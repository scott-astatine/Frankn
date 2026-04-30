use crate::{HostMessage, ops::rtc::RTCConn, utils::Status};
use sha2::{Digest, Sha256};
use std::collections::HashMap;
use std::fs;
use std::path::Path;
use std::sync::Arc;
use std::sync::LazyLock;
use tokio::io::AsyncWriteExt;
use tokio::io::BufWriter;
use tokio::sync::Mutex;

pub mod transfer;

/// Writable state of an upload session, wrapped in Arc<Mutex<>> so the global
/// session map lock can be released before performing I/O.
struct UploadSessionInner {
    writer: BufWriter<tokio::fs::File>,
    hasher: Sha256,
    current_size: u64,
}

/// Session ID -> (inner, total_size, target_path)
type UploadSession = (Arc<Mutex<UploadSessionInner>>, u64, String);
static UPLOAD_SESSIONS: LazyLock<Mutex<HashMap<String, UploadSession>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));

pub async fn handle_upload_start(
    id: &str,
    path: &str,
    _hash: Option<String>, // We hash on-the-fly now
    total_size: u64,
) -> HostMessage {
    crate::log!(
        "FS: Starting upload for {} ({} bytes) to {}",
        id,
        total_size,
        path
    );

    // Ensure parent directories exist
    if let Some(parent) = Path::new(path).parent() {
        let _ = tokio::fs::create_dir_all(parent).await;
    }

    match tokio::fs::File::create(path).await {
        Ok(file) => {
            let inner = UploadSessionInner {
                writer: BufWriter::new(file),
                hasher: Sha256::new(),
                current_size: 0,
            };
            let session = (Arc::new(Mutex::new(inner)), total_size, path.to_string());

            let mut sessions = UPLOAD_SESSIONS.lock().await;
            sessions.insert(id.to_string(), session);

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
    // Lock the global map only long enough to clone the Arc.
    let session = {
        let sessions = UPLOAD_SESSIONS.lock().await;
        sessions.get(id).map(|(inner, _, _)| Arc::clone(inner))
    };

    if let Some(inner) = session {
        let mut guard = inner.lock().await;
        guard.hasher.update(data);
        if let Err(e) = guard.writer.write_all(data).await {
            eprintln!("FS ERROR: Failed to write chunk for session {}: {}", id, e);
        }
        guard.current_size += data.len() as u64;
    }
}

pub async fn handle_upload_end(id: &str, expected_hash: Option<String>) -> HostMessage {
    let session = {
        let mut sessions = UPLOAD_SESSIONS.lock().await;
        sessions.remove(id)
    };

    if let Some((inner, total, path)) = session {
        let mut guard = inner.lock().await;
        let _ = guard.writer.flush().await;

        if guard.current_size != total {
            let _ = tokio::fs::remove_file(&path).await;
            return HostMessage::Response {
                id: id.to_string(),
                status: Status::Error("SIZE_MISMATCH".into()),
                data: None,
                timestamp: crate::utils::get_timestamp(),
            };
        }

        if let Some(expected) = expected_hash {
            let actual = hex::encode(guard.hasher.clone().finalize());
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
        crate::elog!(
            "FS: ERROR - Upload session {} not found at finalization",
            id
        );
        HostMessage::Response {
            id: id.to_string(),
            status: Status::Error("Session lost".into()),
            data: None,
            timestamp: 0,
        }
    }
}

pub fn ls(id: &str, path: &str, sort_by: Option<String>, show_hidden: Option<bool>) -> HostMessage {
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

                let modified_time = metadata
                    .as_ref()
                    .and_then(|m| m.modified().ok())
                    .unwrap_or(std::time::SystemTime::UNIX_EPOCH);
                let dt: chrono::DateTime<chrono::Local> = modified_time.into();
                let modified_str = dt.format("%Y-%m-%d %H:%M:%S").to_string();
                let timestamp = dt.timestamp();

                list.push(serde_json::json!({
                    "name": name,
                    "is_dir": is_dir,
                    "size": size,
                    "modified": modified_str,
                    "timestamp": timestamp,
                }));
            }

            // Sorting logic
            let sort_by_field = sort_by.as_deref().unwrap_or("name");
            list.sort_by(|a, b| {
                let is_dir_a = a["is_dir"].as_bool().unwrap_or(false);
                let is_dir_b = b["is_dir"].as_bool().unwrap_or(false);

                // Always put directories first
                if is_dir_a && !is_dir_b {
                    return std::cmp::Ordering::Less;
                } else if !is_dir_a && is_dir_b {
                    return std::cmp::Ordering::Greater;
                }

                match sort_by_field {
                    "size" => {
                        let size_a = a["size"].as_u64().unwrap_or(0);
                        let size_b = b["size"].as_u64().unwrap_or(0);
                        size_b.cmp(&size_a) // Descending size
                    }
                    "modified" => {
                        let time_a = a["timestamp"].as_i64().unwrap_or(0);
                        let time_b = b["timestamp"].as_i64().unwrap_or(0);
                        time_b.cmp(&time_a) // Descending modified time
                    }
                    _ => {
                        // Default to name sorting
                        let name_a = a["name"].as_str().unwrap_or("").to_lowercase();
                        let name_b = b["name"].as_str().unwrap_or("").to_lowercase();
                        name_a.cmp(&name_b)
                    }
                }
            });

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

    // The actual transfer is driven by StreamStart/StreamEnd messages spawned
    // in a background task. We don't send a separate Response here — the
    // StreamEnd serves as the completion signal for the client.
    crate::utils::stream::send_managed_transfer(
        file,
        id.to_string(),
        file_name,
        metadata.len(),
        rtc_conn,
        crate::utils::stream::StreamOptions::default(),
    )
    .await;

    // Send an informational "transfer started" response so the client knows
    // the request was accepted. The StreamEnd that arrives later signals
    // actual completion.
    HostMessage::Response {
        id: id.into(),
        status: Status::Success,
        data: Some(serde_json::json!({ "message": "Transfer started" })),
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

