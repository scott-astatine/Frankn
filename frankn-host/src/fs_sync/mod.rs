use crate::{HostMessage, sys::rtc::RTCConn, utils::Status};
use base64::Engine;
use sha2::{Digest, Sha256};
use std::collections::HashMap;
use std::fs;
use std::path::Path;
use std::sync::Arc;
use std::sync::LazyLock;
use tokio::io::AsyncReadExt;
use tokio::io::AsyncWriteExt;
use tokio::sync::Mutex;
use tokio_tungstenite::tungstenite::Bytes;

static UPLOAD_BUFFERS: LazyLock<Mutex<HashMap<String, (String, Vec<u8>, Option<String>, u64)>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));

pub async fn handle_upload_start(
    id: &str,
    path: &str,
    hash: Option<String>,
    total_size: u64,
) -> HostMessage {
    let mut buffers = UPLOAD_BUFFERS.lock().await;
    buffers.insert(
        id.to_string(),
        (path.to_string(), Vec::new(), hash, total_size),
    );

    HostMessage::Response {
        id: id.to_string(),
        status: Status::Success,
        data: Some(serde_json::json!({ "message": "Upload session initialized" })),
        timestamp: crate::utils::get_timestamp(),
    }
}

pub async fn handle_upload_chunk(id: &str, b64_data: &str) {
    let mut buffers = UPLOAD_BUFFERS.lock().await;
    if let Some((_, buffer, _, _)) = buffers.get_mut(id) {
        if let Ok(bytes) = base64::prelude::BASE64_STANDARD.decode(b64_data) {
            buffer.extend(bytes);
        }
    }
}

pub async fn handle_upload_end(id: &str) -> HostMessage {
    let mut buffers = UPLOAD_BUFFERS.lock().await;
    if let Some((path, buffer, expected_hash, total_size)) = buffers.remove(id) {
        if buffer.len() as u64 != total_size {
            return HostMessage::Response {
                id: id.to_string(),
                status: Status::Error("SIZE_MISMATCH".into()),
                data: None,
                timestamp: crate::utils::get_timestamp(),
            };
        }

        if let Some(expected) = expected_hash {
            let mut hasher = Sha256::new();
            hasher.update(&buffer);
            let actual = hex::encode(hasher.finalize());
            if actual != expected {
                return HostMessage::Response {
                    id: id.to_string(),
                    status: Status::Error("INTEGRITY_FAILURE".into()),
                    data: None,
                    timestamp: crate::utils::get_timestamp(),
                };
            }
        }

        let res = async {
            let mut f = tokio::fs::File::create(&path).await?;
            f.write_all(&buffer).await?;
            Ok::<(), std::io::Error>(())
        }
        .await;

        match res {
            Ok(_) => HostMessage::Response {
                id: id.to_string(),
                status: Status::Success,
                data: Some(serde_json::json!({ "message": "Success" })),
                timestamp: crate::utils::get_timestamp(),
            },
            Err(e) => HostMessage::Response {
                id: id.to_string(),
                status: Status::Error(e.to_string()),
                data: None,
                timestamp: crate::utils::get_timestamp(),
            },
        }
    } else {
        HostMessage::Response {
            id: id.to_string(),
            status: Status::Error("Session lost".into()),
            data: None,
            timestamp: 0,
        }
    }
}

pub fn ls(
    id: &str,
    path: &str,
    _sort_by: Option<String>,
    show_hidden: Option<bool>,
) -> HostMessage {
    let entries = fs::read_dir(path);
    match entries {
        Ok(read_dir) => {
            let mut list = Vec::new();
            for entry in read_dir.filter_map(|e| e.ok()) {
                let name = entry.file_name().to_string_lossy().to_string();
                if show_hidden == Some(false) && name.starts_with('.') {
                    continue;
                }
                let metadata = fs::metadata(entry.path()).ok();
                let is_dir = metadata.as_ref().map(|m| m.is_dir()).unwrap_or(false);
                let size = metadata.as_ref().map(|m| m.len()).unwrap_or(0);
                list.push(serde_json::json!({ "name": name, "is_dir": is_dir, "size": size }));
            }
            HostMessage::Response {
                id: id.to_string(),
                status: Status::Success,
                data: Some(serde_json::json!({ "entries": list })),
                timestamp: 0,
            }
        }
        Err(e) => HostMessage::Response {
            id: id.to_string(),
            status: Status::Error(e.to_string()),
            data: None,
            timestamp: 0,
        },
    }
}

pub async fn get_file(id: &str, path: &str, rtc_conn: Arc<Mutex<RTCConn>>) -> HostMessage {
    let path_buf = Path::new(path).to_path_buf();
    let file_name = path_buf
        .file_name()
        .map(|s| s.to_string_lossy().to_string())
        .unwrap_or_default();
    let transfer_id = id.to_string();

    let mut file = match tokio::fs::File::open(&path_buf).await {
        Ok(f) => f,
        Err(e) => {
            return HostMessage::Response {
                id: id.into(),
                status: Status::Error(format!("File open failed: {}", e)),
                data: None,
                timestamp: 0,
            };
        }
    };

    let metadata = match file.metadata().await {
        Ok(m) => m,
        Err(e) => {
            return HostMessage::Response {
                id: id.into(),
                status: Status::Error(format!("Metadata failed: {}", e)),
                data: None,
                timestamp: 0,
            };
        }
    };
    let total_size = metadata.len();

    tokio::spawn(async move {
        let mut hasher = Sha256::new();

        let start_msg = serde_json::to_string(&HostMessage::FileTransferStart {
            id: transfer_id.clone(),
            file_name,
            total_size,
            timestamp: crate::utils::get_timestamp(),
        });

        {
            let conn = rtc_conn.lock().await;
            if let Ok(json) = start_msg {
                let _ = conn.send_message("frankn_fs", &Bytes::from(json)).await;
            }
        }

        loop {
            let mut buffer = [0u8; 16384];
            let n = match file.read(&mut buffer).await {
                Ok(0) => break,
                Ok(n) => n,
                Err(e) => {
                    eprintln!("Error reading file: {}", e);
                    break;
                }
            };

            let chunk = &buffer[0..n];
            hasher.update(chunk);

            let mut frame = Vec::with_capacity(36 + n);
            let mut id_bytes = transfer_id.as_bytes().to_vec();
            id_bytes.resize(36, 0);
            frame.extend_from_slice(&id_bytes);
            frame.extend_from_slice(chunk);

            let conn = rtc_conn.lock().await;
            let buffered = conn.get_buffered_amount("frankn_fs").await;

            if buffered > 1024 * 1024 {
                drop(conn);
                tokio::time::sleep(tokio::time::Duration::from_millis(10)).await;
                continue;
            }

            if let Err(e) = conn.send_message("frankn_fs", &Bytes::from(frame)).await {
                eprintln!("Failed to send chunk: {}", e);
                return;
            }
            drop(conn);
        }

        let hash = hex::encode(hasher.finalize());
        let end_msg = HostMessage::FileTransferEnd {
            id: transfer_id,
            timestamp: crate::utils::get_timestamp(),
            hash: Some(hash),
        };

        if let Ok(json) = serde_json::to_string(&end_msg) {
            let conn = rtc_conn.lock().await;
            let _ = conn.send_message("frankn_fs", &Bytes::from(json)).await;
        }
    });

    HostMessage::Response {
        id: id.into(),
        status: Status::Success,
        data: None,
        timestamp: 0,
    }
}

pub fn delete_file(id: &str, path: &str) -> HostMessage {
    match fs::remove_file(path) {
        Ok(_) => HostMessage::Response {
            id: id.into(),
            status: Status::Success,
            data: None,
            timestamp: 0,
        },
        Err(e) => HostMessage::Response {
            id: id.into(),
            status: Status::Error(e.to_string()),
            data: None,
            timestamp: 0,
        },
    }
}
