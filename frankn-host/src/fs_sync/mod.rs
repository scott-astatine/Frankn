use crate::{HostMessage, sys::rtc::RTCConn, utils::Status};
use sha2::{Digest, Sha256};
use std::collections::HashMap;
use std::fs;
use std::path::Path;
use std::sync::Arc;
use std::sync::LazyLock;
use tokio::io::AsyncWriteExt;
use tokio::io::BufWriter;
use tokio::sync::Mutex;

// Session ID -> (Writer, Hasher, TotalSize, CurrentSize, Path)
type UploadSession = (BufWriter<tokio::fs::File>, Sha256, u64, u64, String);
static UPLOAD_SESSIONS: LazyLock<Mutex<HashMap<String, UploadSession>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));

pub async fn handle_upload_start(
    id: &str,
    path: &str,
    _hash: Option<String>, // We hash on-the-fly now
    total_size: u64,
) -> HostMessage {
    crate::log!("FS: Starting upload for {} ({} bytes) to {}", id, total_size, path);
    let mut sessions = UPLOAD_SESSIONS.lock().await;
    
    // Ensure parent directories exist
    if let Some(parent) = Path::new(path).parent() {
        let _ = tokio::fs::create_dir_all(parent).await;
    }

    match tokio::fs::File::create(path).await {
        Ok(file) => {
            sessions.insert(
                id.to_string(),
                (BufWriter::new(file), Sha256::new(), total_size, 0, path.to_string()),
            );

            HostMessage::Response {
                id: id.to_string(),
                status: Status::Success,
                data: Some(serde_json::json!({ "message": "Neural stream initialized" })),
                timestamp: crate::utils::get_timestamp(),
            }
        }
        Err(e) => HostMessage::Response {
            id: id.to_string(),
            status: Status::Error(format!("Failed to create file: {}", e)),
            data: None,
            timestamp: crate::utils::get_timestamp(),
        },
    }
}

pub async fn handle_upload_chunk_raw(id: &str, data: &[u8]) {
    let mut sessions = UPLOAD_SESSIONS.lock().await;
    if let Some((writer, hasher, _, current, _)) = sessions.get_mut(id) {
        hasher.update(data);
        if let Err(e) = writer.write_all(data).await {
            eprintln!("FS ERROR: Failed to write chunk for session {}: {}", id, e);
        }
        *current += data.len() as u64;
    }
}

pub async fn handle_upload_end(id: &str, expected_hash: Option<String>) -> HostMessage {
    let mut sessions = UPLOAD_SESSIONS.lock().await;
    if let Some((mut writer, hasher, total, current, path)) = sessions.remove(id) {
        let _ = writer.flush().await;

        if current != total {
            let _ = tokio::fs::remove_file(&path).await;
            return HostMessage::Response {
                id: id.to_string(),
                status: Status::Error("SIZE_MISMATCH".into()),
                data: None,
                timestamp: crate::utils::get_timestamp(),
            };
        }

        if let Some(expected) = expected_hash {
            let actual = hex::encode(hasher.finalize());
            if actual != expected.to_lowercase() {
                let _ = tokio::fs::remove_file(&path).await;
                return HostMessage::Response {
                    id: id.to_string(),
                    status: Status::Error("INTEGRITY_FAILURE".into()),
                    data: None,
                    timestamp: crate::utils::get_timestamp(),
                };
            }
        }

        HostMessage::Response {
            id: id.to_string(),
            status: Status::Success,
            data: Some(serde_json::json!({ "message": "Neural stream finalized" })),
            timestamp: crate::utils::get_timestamp(),
        }
    } else {
        crate::elog!("FS: ERROR - Upload session {} not found at finalization", id);
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

    let file = match tokio::fs::File::open(&path_buf).await {
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

    crate::utils::stream::send_managed_transfer(
        file,
        id.to_string(),
        file_name,
        metadata.len(),
        rtc_conn,
        crate::utils::stream::StreamOptions::default(),
    )
    .await;

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