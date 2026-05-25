// ============================================================================
// Frankn Transfer Engine — Resume-aware file transfer over WebRTC DCs
// ============================================================================
//
// Binary frame format (upload from client → host):
//   [0x01][36-byte ID][8-byte offset BE][4-byte seq BE][1-byte flags][N bytes data]
//
// Binary frame format (download from host → client):
//   [0x01][36-byte ID][8-byte offset BE][4-byte seq BE][1-byte flags][N bytes data]
//
// Flags bitfield:
//   0x01 = RESUME (host has existing partial, client is resuming)
//   0x02 = FINAL  (last chunk of transfer)
//   0x04 = ACK_REQUESTED (client wants host to send transfer_ack)
// ============================================================================

use crate::{HostMessage, ops::rtc::RTCConn, utils::Status};
use sha2::{Digest, Sha256};
use std::collections::HashMap;
use std::io::SeekFrom;
use std::sync::Arc;
use std::sync::LazyLock;
use tokio::fs::File;
use tokio::io::{AsyncReadExt, AsyncSeekExt, AsyncWriteExt};
use tokio::sync::Mutex;
use tokio_tungstenite::tungstenite::Bytes;

/// Partial transfer state persisted alongside the `.part` file.
#[derive(Debug, serde::Serialize, serde::Deserialize)]
struct TransferState {
    transfer_id: String,
    path: String,
    total_size: u64,
    current_offset: u64,
    expected_hash: Option<String>,
    #[serde(default)]
    last_seq: u32,
}

use std::sync::atomic::{AtomicBool, Ordering};

/// Writable session state for an active upload.
struct UploadSession {
    file: File,
    hasher: Sha256,
    current_offset: u64,
    total_size: u64,
    last_seq: u32,
    path: String,
    client_id: String,
}

/// Global upload session registry.
static UPLOAD_SESSIONS: LazyLock<Mutex<HashMap<String, Arc<Mutex<UploadSession>>>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));

/// Global registry for active download tasks to enable graceful cancellation.
static DOWNLOAD_TASKS: LazyLock<Mutex<HashMap<String, Arc<AtomicBool>>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));

// ── Binary frame constants ─────────────────────────────────────────────────

pub const FRAME_MAGIC: u8 = 0x01;
pub const FRAME_ID_SIZE: usize = 36;
pub const FRAME_OFFSET_SIZE: usize = 8;
pub const FRAME_SEQ_SIZE: usize = 4;
pub const FRAME_FLAGS_SIZE: usize = 1;
pub const FRAME_HEADER_SIZE: usize =
    1 + FRAME_ID_SIZE + FRAME_OFFSET_SIZE + FRAME_SEQ_SIZE + FRAME_FLAGS_SIZE;

const FLAG_FINAL: u8 = 0x02;
const FLAG_ACK_REQUESTED: u8 = 0x04;

// ── Helper: state file path ────────────────────────────────────────────────

fn state_path(file_path: &str) -> String {
    format!("{}.frankn_state", file_path)
}

fn part_path(file_path: &str) -> String {
    format!("{}.part", file_path)
}

// ── Helper: write state file ───────────────────────────────────────────────

async fn write_state(file_path: &str, state: &TransferState) -> std::io::Result<()> {
    let json = serde_json::to_string_pretty(state)?;
    tokio::fs::write(state_path(file_path), json).await?;
    Ok(())
}

// ── Helper: delete state + part files ──────────────────────────────────────

async fn cleanup_partial(file_path: &str) {
    let _ = tokio::fs::remove_file(part_path(file_path)).await;
    let _ = tokio::fs::remove_file(state_path(file_path)).await;
}

// ── TransferInit: start or resume an upload ────────────────────────────────

pub async fn handle_transfer_init(
    id: &str,
    path: &str,
    hash: Option<String>,
    total_size: u64,
    resume_offset: u64,
    rtc_conn: Arc<Mutex<RTCConn>>,
    channel_label: &str,
    client_id: &str,
) -> HostMessage {
    crate::log!(
        "FS: Transfer init for {} — path={}, size={}, resume_offset={}",
        id,
        path,
        total_size,
        resume_offset
    );

    // Apply strict path sandboxing
    let sandbox_path = match crate::fs_sync::check_sandbox_default(path, false) {
        Ok(p) => p,
        Err(e) => {
            return HostMessage::Response {
                id: id.to_string(),
                status: Status::Error(e),
                data: None,
                timestamp: crate::utils::get_timestamp(),
            };
        }
    };
    let path_str = sandbox_path.to_string_lossy().to_string();

    // Ensure parent directories exist
    if let Some(parent) = sandbox_path.parent() {
        let _ = tokio::fs::create_dir_all(parent).await;
    }

    let part = part_path(&path_str);

    // Check if we're resuming and the partial file is valid
    let mut actual_offset = 0u64;
    let file = if resume_offset > 0 {
        match tokio::fs::metadata(&part).await {
            Ok(meta) => {
                actual_offset = meta.len();
                if actual_offset != resume_offset {
                    crate::elog!(
                        "FS: Resume offset mismatch for {} — expected {}, got {}",
                        id,
                        resume_offset,
                        actual_offset
                    );
                    // Fall through to fresh start
                    actual_offset = 0;
                    match File::create(&part).await {
                        Ok(f) => f,
                        Err(e) => {
                            return HostMessage::Response {
                                id: id.to_string(),
                                status: Status::Error(format!("Failed to create file: {}", e)),
                                data: None,
                                timestamp: crate::utils::get_timestamp(),
                            };
                        }
                    }
                } else {
                    crate::log!("FS: Resuming {} from offset {}", id, actual_offset);
                    match tokio::fs::OpenOptions::new()
                        .write(true)
                        .append(true)
                        .open(&part)
                        .await
                    {
                        Ok(f) => f,
                        Err(e) => {
                            return HostMessage::Response {
                                id: id.to_string(),
                                status: Status::Error(format!("Failed to open partial: {}", e)),
                                data: None,
                                timestamp: crate::utils::get_timestamp(),
                            };
                        }
                    }
                }
            }
            Err(_) => {
                // No partial, start fresh
                match File::create(&part).await {
                    Ok(f) => f,
                    Err(e) => {
                        return HostMessage::Response {
                            id: id.to_string(),
                            status: Status::Error(format!("Failed to create file: {}", e)),
                            data: None,
                            timestamp: crate::utils::get_timestamp(),
                        };
                    }
                }
            }
        }
    } else {
        // Fresh start
        match File::create(&part).await {
            Ok(f) => f,
            Err(e) => {
                return HostMessage::Response {
                    id: id.to_string(),
                    status: Status::Error(format!("Failed to create file: {}", e)),
                    data: None,
                    timestamp: crate::utils::get_timestamp(),
                };
            }
        }
    };

    let session = UploadSession {
        file,
        hasher: Sha256::new(),
        current_offset: actual_offset,
        total_size,
        last_seq: 0,
        path: path_str.clone(),
        client_id: client_id.to_string(),
    };

    // Write initial state file
    let state = TransferState {
        transfer_id: id.to_string(),
        path: path_str.clone(),
        total_size,
        current_offset: actual_offset,
        expected_hash: hash.clone(),
        last_seq: 0,
    };
    if let Err(e) = write_state(&path_str, &state).await {
        crate::elog!("FS: Failed to write state for {}: {}", id, e);
    }

    // Store session
    {
        let mut sessions = UPLOAD_SESSIONS.lock().await;
        sessions.insert(id.to_string(), Arc::new(Mutex::new(session)));
    }

    // Send ready response
    let resp = HostMessage::Response {
        id: id.to_string(),
        status: Status::Success,
        data: Some(serde_json::json!({
            "message": "Transfer ready",
            "offset": actual_offset,
        })),
        timestamp: crate::utils::get_timestamp(),
    };
    if let Ok(json) = serde_json::to_string(&resp) {
        let conn = rtc_conn.lock().await;
        let _ = conn.send_message(channel_label, &Bytes::from(json)).await;
    }

    resp
}

// ── TransferCancel: abort and cleanup ──────────────────────────────────────

pub async fn handle_transfer_cancel(id: &str) -> HostMessage {
    // 1. Clean up uploads
    let session = {
        let mut sessions = UPLOAD_SESSIONS.lock().await;
        sessions.remove(id)
    };

    if let Some(session_arc) = session {
        let session = session_arc.lock().await;
        cleanup_partial(&session.path).await;
        crate::log!("FS: Upload transfer {} cancelled, partial cleaned up", id);
    }

    // 2. Clean up downloads (signal graceful shutdown)
    let cancel_flag = {
        let mut tasks = DOWNLOAD_TASKS.lock().await;
        tasks.remove(id)
    };

    if let Some(flag) = cancel_flag {
        flag.store(true, Ordering::Relaxed);
        crate::log!("FS: Download task {} gracefully cancelled by user", id);
    }

    HostMessage::TransferCancel {
        id: id.to_string(),
        timestamp: crate::utils::get_timestamp(),
    }
}

// ── Binary chunk handler (resume-aware) ────────────────────────────────────

/// Parse and process a binary upload chunk frame.
///
/// Frame format: [magic][id][offset BE][seq BE][flags][data]
pub async fn handle_transfer_chunk_raw(
    data: &[u8],
    rtc_conn: Arc<Mutex<RTCConn>>,
    channel_label: &str,
) {
    if data.len() < FRAME_HEADER_SIZE || data[0] != FRAME_MAGIC {
        crate::elog!(
            "FS: Invalid binary frame (len={}, magic={})",
            data.len(),
            data[0]
        );
        return;
    }

    let id_bytes = &data[1..1 + FRAME_ID_SIZE];
    let transfer_id = String::from_utf8_lossy(id_bytes)
        .trim_matches(char::from(0))
        .to_string();

    let offset = u64::from_be_bytes(
        data[1 + FRAME_ID_SIZE..1 + FRAME_ID_SIZE + FRAME_OFFSET_SIZE]
            .try_into()
            .unwrap_or([0u8; 8]),
    );

    let seq = u32::from_be_bytes(
        data[1 + FRAME_ID_SIZE + FRAME_OFFSET_SIZE
            ..1 + FRAME_ID_SIZE + FRAME_OFFSET_SIZE + FRAME_SEQ_SIZE]
            .try_into()
            .unwrap_or([0u8; 4]),
    );

    let flags = data[1 + FRAME_ID_SIZE + FRAME_OFFSET_SIZE + FRAME_SEQ_SIZE];
    let is_final = (flags & FLAG_FINAL) != 0;
    let ack_requested = (flags & FLAG_ACK_REQUESTED) != 0;

    let chunk_data = &data[FRAME_HEADER_SIZE..];

    // Look up session
    let session = {
        let sessions = UPLOAD_SESSIONS.lock().await;
        sessions.get(&transfer_id).map(Arc::clone)
    };

    let Some(session_arc) = session else {
        crate::elog!("FS: No session for chunk seq={} offset={}", seq, offset);
        return;
    };

    let mut session = session_arc.lock().await;

    // Verify offset matches expected (catch reordering)
    if offset != session.current_offset {
        crate::elog!(
            "FS: Offset mismatch for {} — expected {}, got {}",
            transfer_id,
            session.current_offset,
            offset
        );
        return;
    }

    // Write chunk
    if let Err(e) = session.file.write_all(chunk_data).await {
        crate::elog!("FS: Write error for {}: {}", transfer_id, e);
        return;
    }

    session.hasher.update(chunk_data);
    session.current_offset += chunk_data.len() as u64;
    session.last_seq = seq;

    // Flush periodically (every 1MB or on final)
    if is_final || session.current_offset % (1024 * 1024) < chunk_data.len() as u64 {
        let _ = session.file.flush().await;
    }

    // Update state file
    let state = TransferState {
        transfer_id: transfer_id.clone(),
        path: session.path.clone(),
        total_size: session.total_size,
        current_offset: session.current_offset,
        expected_hash: None, // Don't persist hash in state for privacy
        last_seq: seq,
    };
    // Best-effort state persistence
    let _ = write_state(&session.path, &state).await;

    let offset_now = session.current_offset;
    let seq_now = seq;
    let transfer_id_clone = transfer_id.clone();

    // Drop session lock before sending ACK
    drop(session);

    // Send ACK if requested or periodically
    if ack_requested || seq % 50 == 0 {
        let ack = HostMessage::TransferAck {
            id: transfer_id,
            offset: offset_now,
            seq: seq_now,
            timestamp: crate::utils::get_timestamp(),
        };
        if let Ok(json) = serde_json::to_string(&ack) {
            let conn = rtc_conn.lock().await;
            let _ = conn.send_message(channel_label, &Bytes::from(json)).await;
        }
    }

    // If final, finalize the transfer
    if is_final {
        finalize_upload(&transfer_id_clone, rtc_conn, channel_label).await;
    }
}

// ── Upload finalization ────────────────────────────────────────────────────

async fn finalize_upload(id: &str, rtc_conn: Arc<Mutex<RTCConn>>, channel_label: &str) {
    let session = {
        let mut sessions = UPLOAD_SESSIONS.lock().await;
        sessions.remove(id)
    };

    let Some(session_arc) = session else {
        crate::elog!("FS: Finalize called but session {} not found", id);
        return;
    };

    let mut session = session_arc.lock().await;

    // Flush everything
    if let Err(e) = session.file.flush().await {
        crate::elog!("FS: Flush error during finalize for {}: {}", id, e);
        return;
    }

    let hash_hex = hex::encode(session.hasher.clone().finalize());

    // Rename .part → final
    let part = part_path(&session.path);
    if let Err(e) = tokio::fs::rename(&part, &session.path).await {
        crate::elog!("FS: Rename error for {}: {}", id, e);
        return;
    }

    // Clean up state file
    let _ = tokio::fs::remove_file(state_path(&session.path)).await;

    // Send completion message
    let complete = HostMessage::TransferComplete {
        id: id.to_string(),
        hash: hash_hex,
        timestamp: crate::utils::get_timestamp(),
    };
    if let Ok(json) = serde_json::to_string(&complete) {
        let conn = rtc_conn.lock().await;
        let _ = conn.send_message(channel_label, &Bytes::from(json)).await;
    }

    crate::log!("FS: Transfer {} completed", id);
}

// ── DownloadInit: start a download (host → client) with resume ─────────────

pub async fn handle_download_init(
    id: &str,
    path: &str,
    resume_offset: u64,
    rtc_conn: Arc<Mutex<RTCConn>>,
    channel_label: &str,
) -> HostMessage {
    // Apply strict path sandboxing
    let sandbox_path = match crate::fs_sync::check_sandbox_default(path, false) {
        Ok(p) => p,
        Err(e) => {
            return HostMessage::Response {
                id: id.to_string(),
                status: Status::Error(e),
                data: None,
                timestamp: crate::utils::get_timestamp(),
            };
        }
    };

    let file = match File::open(&sandbox_path).await {
        Ok(f) => f,
        Err(e) => {
            return HostMessage::Response {
                id: id.to_string(),
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
                id: id.to_string(),
                status: Status::Error(format!("Metadata failed: {}", e)),
                data: None,
                timestamp: 0,
            };
        }
    };

    let total_size = metadata.len();
    let actual_offset = resume_offset.min(total_size);

    let file_name = sandbox_path
        .file_name()
        .map(|s| s.to_string_lossy().to_string())
        .unwrap_or_default();

    // Send download_start without pre-computing the hash
    let start_msg = HostMessage::DownloadStart {
        id: id.to_string(),
        file_name,
        total_size,
        offset: actual_offset,
        hash: None, // Will be computed on the fly and sent in DownloadEnd
        timestamp: crate::utils::get_timestamp(),
    };

    if let Ok(json) = serde_json::to_string(&start_msg) {
        let conn = rtc_conn.lock().await;
        let _ = conn.send_message(channel_label, &Bytes::from(json)).await;
    }

    // Stream the file from the resume offset
    let mut f = file;
    if let Err(e) = f.seek(SeekFrom::Start(actual_offset)).await {
        crate::elog!("FS: Seek error for download {}: {}", id, e);
        let end_msg = HostMessage::DownloadEnd {
            id: id.to_string(),
            hash: String::new(),
            timestamp: crate::utils::get_timestamp(),
        };
        if let Ok(json) = serde_json::to_string(&end_msg) {
            let conn = rtc_conn.lock().await;
            let _ = conn
                .send_message(
                    channel_label,
                    &tokio_tungstenite::tungstenite::Bytes::from(json),
                )
                .await;
        }
        return HostMessage::Response {
            id: id.to_string(),
            status: Status::Success,
            data: None,
            timestamp: 0,
        };
    }

    // Spawn the actual streaming in a background task
    let transfer_id = id.to_string();
    let label = channel_label.to_string();

    let cancel_flag = Arc::new(AtomicBool::new(false));
    let cancel_flag_clone = Arc::clone(&cancel_flag);

    // Retrieve specific RTCDataChannel directly to bypass global connection Mutex locks in streaming loop
    let dc = {
        let conn = rtc_conn.lock().await;
        let channels = conn.data_channels.lock().await;
        channels.get(&label).cloned()
    };

    if let Some(dc_arc) = dc {
        tokio::spawn(async move {
            let _ = stream_download(
                f,
                transfer_id,
                dc_arc,
                cancel_flag_clone,
            )
            .await;
        });
    } else {
        crate::elog!("FS: Data channel {} not found for download!", label);
    }

    DOWNLOAD_TASKS
        .lock()
        .await
        .insert(id.to_string(), cancel_flag);

    HostMessage::Response {
        id: id.to_string(),
        status: Status::Success,
        data: Some(serde_json::json!({
            "message": "Download started",
            "total_size": total_size,
            "offset": actual_offset,
        })),
        timestamp: 0,
    }
}

// ── Stream download chunks to client ───────────────────────────────────────

async fn stream_download(
    mut file: File,
    id: String,
    dc: Arc<webrtc::data_channel::RTCDataChannel>,
    cancel_flag: Arc<AtomicBool>,
) -> Result<(), std::io::Error> {
    const CHUNK_SIZE: usize = 61440; // 60KB
    let mut buffer = vec![0u8; CHUNK_SIZE];
    let mut seq: u32 = 0;

    let mut hasher = Sha256::new(); // On-the-fly SHA-256 hasher

    // Get starting offset for frame headers
    let start_offset = file.stream_position().await?;
    let mut offset = start_offset;

    loop {
        // Check for graceful cancellation
        if cancel_flag.load(Ordering::Relaxed) {
            crate::log!("FS: Download task {} exited gracefully.", id);
            return Ok(());
        }

        let n = file.read(&mut buffer).await?;
        if n == 0 {
            break;
        }

        let chunk = &buffer[..n];
        hasher.update(chunk); // Update hash chunk by chunk
        seq += 1;

        // Build binary frame: [magic][id][offset][seq][flags][data]
        let mut frame = Vec::with_capacity(FRAME_HEADER_SIZE + n);
        frame.push(FRAME_MAGIC);

        // ID (36 bytes, null-padded)
        let id_bytes = id.as_bytes();
        frame.extend_from_slice(id_bytes);
        for _ in id_bytes.len()..FRAME_ID_SIZE {
            frame.push(0);
        }

        // Offset (8 bytes, big-endian)
        frame.extend_from_slice(&offset.to_be_bytes());

        // Seq (4 bytes, big-endian)
        frame.extend_from_slice(&seq.to_be_bytes());

        // Flags
        let is_last = n < CHUNK_SIZE;
        let flags = if is_last { FLAG_FINAL } else { 0 };
        frame.push(flags);

        // Data
        frame.extend_from_slice(chunk);

        // Backpressure check (no Mutex locks on the global connection!)
        loop {
            // Check for graceful cancellation inside loop
            if cancel_flag.load(Ordering::Relaxed) {
                crate::log!("FS: Download task {} exited gracefully.", id);
                return Ok(());
            }

            let buffered = dc.buffered_amount().await;
            if buffered < 1024 * 1024 {
                // 1MB buffer limit
                break;
            }
            tokio::time::sleep(std::time::Duration::from_millis(10)).await;
        }

        // Send the binary frame directly
        if let Err(e) = dc
            .send(&tokio_tungstenite::tungstenite::Bytes::from(frame))
            .await
        {
            crate::elog!("FS: Failed to send chunk {}: {}", seq, e);
            break;
        }

        offset += n as u64;
    }

    let full_hash = hex::encode(hasher.finalize()); // Finalize SHA-256 hash

    // Send download_end with the finalized hash
    let end_msg = HostMessage::DownloadEnd {
        id,
        hash: full_hash,
        timestamp: crate::utils::get_timestamp(),
    };
    if let Ok(json) = serde_json::to_string(&end_msg) {
        let _ = dc.send(&Bytes::from(json)).await;
    }

    crate::log!("FS: Download stream finished");
    Ok(())
}

/// Clean up any active upload sessions for a specific client to prevent leaks.
pub async fn cleanup_client_uploads(client_id: &str) {
    let mut sessions = UPLOAD_SESSIONS.lock().await;
    let mut to_remove = Vec::new();
    for (id, session_arc) in sessions.iter() {
        let session = session_arc.lock().await;
        if session.client_id == client_id {
            to_remove.push(id.clone());
        }
    }
    for id in to_remove {
        if let Some(session_arc) = sessions.remove(&id) {
            let _session = session_arc.lock().await;
            crate::log!("FS: Cleaned up orphaned upload session {} for client {}", id, client_id);
            // file and hasher drop here, releasing resources
        }
    }
}
