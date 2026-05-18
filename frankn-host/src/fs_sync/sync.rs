use crate::{HostMessage, ops::rtc::RTCConn, utils::{Status, get_timestamp}};
use sha2::{Digest, Sha256};
use std::path::Path;
use walkdir::WalkDir;
use serde_json::json;
use std::fs;
use std::time::UNIX_EPOCH;
use std::sync::Arc;
use tokio::sync::Mutex;
use tokio_tungstenite::tungstenite::Bytes;

/// Handles a request from the client to generate a folder snapshot for synchronization.
pub async fn handle_sync_request(
    id: &str, 
    path: &str,
    rtc_conn: Arc<Mutex<RTCConn>>,
    channel_label: &str
) -> HostMessage {
    // Normalize path: strip trailing slashes to avoid WalkDir/strip_prefix issues
    let normalized_path = path.trim_end_matches('/').to_string();
    crate::log!("SYNC: Received snapshot request [{}] for path: {} (normalized: {})", id, path, normalized_path);
    
    let root = Path::new(&normalized_path);

    if !root.exists() || !root.is_dir() {
        crate::elog!("SYNC ERROR: Path does not exist or is not a directory: {}", normalized_path);
        return HostMessage::Response {
            id: id.into(),
            status: Status::Error("Path does not exist or is not a dir".into()),
            data: None,
            timestamp: get_timestamp(),
        };
    }

    let id_clone = id.to_string();
    let path_clone = normalized_path.clone();
    let path_for_task = normalized_path.clone();

    crate::log!("SYNC: Spawning recursive scan for {}", path_clone);

    // Perform recursive scan in a blocking task to avoid blocking the async executor
    let result = tokio::task::spawn_blocking(move || {
        let mut files = Vec::new();
        let mut count = 0;
        let mut skipped = 0;
        
        crate::log!("SYNC: WalkDir starting for {} (Following symlinks)", path_for_task);
        
        for entry in WalkDir::new(&path_for_task).follow_links(true) {
            let entry = match entry {
                Ok(e) => e,
                Err(e) => {
                    crate::elog!("SYNC ERROR: WalkDir entry error: {}", e);
                    continue;
                }
            };

            let entry_path = entry.path();
            let file_type = entry.file_type();
            
            crate::log!("SYNC: WalkDir yielded: {:?} (is_file: {}, is_dir: {}, is_symlink: {})", 
                entry_path, file_type.is_file(), file_type.is_dir(), file_type.is_symlink());

            if file_type.is_file() || (file_type.is_symlink() && entry_path.is_file()) {
                let metadata = match entry.metadata() {
                    Ok(m) => m,
                    Err(e) => {
                        crate::elog!("SYNC: Failed to read metadata for {:?}: {}", entry_path, e);
                        skipped += 1;
                        continue;
                    }
                };

                let relative_path = entry_path
                    .strip_prefix(&path_for_task)
                    .unwrap_or(entry_path)
                    .to_string_lossy()
                    .to_string();

                // Skip internal frankn state files
                if relative_path.ends_with(".frankn_state") || relative_path.ends_with(".part") {
                    continue;
                }

                // Quick hash (first 1KB + size)
                let hash_fragment = generate_quick_hash(entry_path);

                crate::log!("SYNC: Found file: {} ({} bytes)", relative_path, metadata.len());

                files.push(json!({
                    "path": relative_path,
                    "size": metadata.len(),
                    "mtime": metadata.modified().unwrap_or(UNIX_EPOCH).duration_since(UNIX_EPOCH).unwrap_or_default().as_secs(),
                    "hash": hash_fragment
                }));
                count += 1;
            } else if file_type.is_dir() {
                crate::log!("SYNC: Scanned directory: {:?}", entry_path);
            } else if file_type.is_symlink() {
                crate::log!("SYNC: Found symlink: {:?}", entry_path);
                // Currently skipping symlinks to prevent infinite loops, can be added later if needed
            }
        }
        (files, count, skipped)
    })
    .await;

    match result {
        Ok((files, count, skipped)) => {
            crate::log!("SYNC: Snapshot complete for {}. Found {} files ({} metadata failures).", path_clone, count, skipped);
            
            // Chunk the results to avoid WebRTC Data Channel message size limits (e.g. 64KB)
            const CHUNK_SIZE: usize = 200; 
            let total_chunks = if files.is_empty() { 1 } else { (files.len() as f64 / CHUNK_SIZE as f64).ceil() as usize };
            
            if files.is_empty() {
                crate::log!("SYNC: Sending empty snapshot for {}", path_clone);
                let snapshot = HostMessage::SyncSnapshot {
                    id: id_clone.clone(),
                    root_path: path_clone.clone(),
                    files: Vec::new(),
                    is_final: true,
                    timestamp: get_timestamp(),
                };
                if let Ok(json) = serde_json::to_string(&snapshot) {
                    let conn = rtc_conn.lock().await;
                    let _ = conn.send_message(channel_label, &Bytes::from(json)).await;
                }
            } else {
                for (i, chunk) in files.chunks(CHUNK_SIZE).enumerate() {
                    let is_final = i == total_chunks - 1;
                    let snapshot = HostMessage::SyncSnapshot {
                        id: id_clone.clone(),
                        root_path: path_clone.clone(),
                        files: chunk.to_vec(),
                        is_final,
                        timestamp: get_timestamp(),
                    };

                    if let Ok(json) = serde_json::to_string(&snapshot) {
                        let conn = rtc_conn.lock().await;
                        crate::log!("SYNC: Sending snapshot chunk {}/{} (len: {})", i+1, total_chunks, json.len());
                        if let Err(e) = conn.send_message(channel_label, &Bytes::from(json)).await {
                            crate::elog!("SYNC ERROR: Failed to send chunk: {}", e);
                        }
                    }
                }
            }

            HostMessage::Response {
                id: id_clone,
                status: Status::Success,
                data: Some(json!({"message": format!("Snapshot sent in {} parts", total_chunks)})),
                timestamp: get_timestamp(),
            }
        }
        Err(e) => {
            crate::elog!("SYNC ERROR: Snapshot task failed for {}: {}", path_clone, e);
            HostMessage::Response {
                id: id.into(),
                status: Status::Error(format!("Snapshot task failed: {}", e)),
                data: None,
                timestamp: get_timestamp(),
            }
        }
    }
}

/// Generates a SHA-256 hash of the first 1024 bytes of a file + its total size.
/// This provides a high-confidence "quick check" for file changes without scanning large files entirely.
fn generate_quick_hash(path: &Path) -> Option<String> {
    use std::io::Read;

    let mut file = match fs::File::open(path) {
        Ok(f) => f,
        Err(e) => {
            crate::elog!("SYNC ERROR: Failed to open file for hashing {:?}: {}", path, e);
            return None;
        }
    };
    
    let mut buffer = [0u8; 1024];
    let bytes_read = match file.read(&mut buffer) {
        Ok(n) => n,
        Err(e) => {
            crate::elog!("SYNC ERROR: Failed to read file for hashing {:?}: {}", path, e);
            return None;
        }
    };

    if bytes_read == 0 {
        return Some("empty".into());
    }

    let mut hasher = Sha256::new();
    hasher.update(&buffer[..bytes_read]);
    
    // Include file size to improve collision resistance
    if let Ok(meta) = file.metadata() {
        hasher.update(&meta.len().to_be_bytes());
    }

    Some(hex::encode(hasher.finalize()))
}
