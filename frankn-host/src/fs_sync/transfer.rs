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
use std::path::Path;
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

/// Writable session state for an active upload.
struct UploadSession {
    file: File,
    hasher: Sha256,
    current_offset: u64,
    total_size: u64,
    last_seq: u32,
    path: String,
}

/// Global upload session registry.
static UPLOAD_SESSIONS: LazyLock<Mutex<HashMap<String, Arc<Mutex<UploadSession>>>>> =
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
) -> HostMessage {
    crate::log!(
        "FS: Transfer init for {} — path={}, size={}, resume_offset={}",
        id,
        path,
        total_size,
        resume_offset
    );

    // Ensure parent directories exist
    if let Some(parent) = Path::new(path).parent() {
        let _ = tokio::fs::create_dir_all(parent).await;
    }

    let part = part_path(path);

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
        path: path.to_string(),
    };

    // Write initial state file
    let state = TransferState {
        transfer_id: id.to_string(),
        path: path.to_string(),
        total_size,
        current_offset: actual_offset,
        expected_hash: hash.clone(),
        last_seq: 0,
    };
    if let Err(e) = write_state(path, &state).await {
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
    let session = {
        let mut sessions = UPLOAD_SESSIONS.lock().await;
        sessions.remove(id)
    };

    if let Some(session_arc) = session {
        let session = session_arc.lock().await;
        cleanup_partial(&session.path).await;
        crate::log!("FS: Transfer {} cancelled, partial cleaned up", id);
    }

    HostMessage::Response {
        id: id.to_string(),
        status: Status::Success,
        data: Some(serde_json::json!({ "message": "Transfer cancelled" })),
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
    let file = match File::open(path).await {
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

    let file_name = Path::new(path)
        .file_name()
        .map(|s| s.to_string_lossy().to_string())
        .unwrap_or_default();

    // Compute hash of the full file (for client-side integrity check)
    let mut hasher = Sha256::new();
    {
        let mut f = file.try_clone().await.unwrap();
        use tokio::io::AsyncReadExt;
        let mut buf = vec![0u8; 65536];
        loop {
            let n = match f.read(&mut buf).await {
                Ok(0) => break,
                Ok(n) => n,
                Err(_) => break,
            };
            hasher.update(&buf[..n]);
        }
    }
    let full_hash = hex::encode(hasher.finalize());

    // Send download_start
    let start_msg = HostMessage::DownloadStart {
        id: id.to_string(),
        file_name,
        total_size,
        offset: actual_offset,
        hash: Some(full_hash.clone()),
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
    let conn_for_download = Arc::clone(&rtc_conn);
    tokio::spawn(async move {
        let _ = stream_download(f, transfer_id, label, full_hash, conn_for_download).await;
    });

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
    channel_label: String,
    full_hash: String,
    rtc_conn: Arc<Mutex<RTCConn>>,
) -> Result<(), std::io::Error> {
    const CHUNK_SIZE: usize = 61440; // 60KB
    let mut buffer = vec![0u8; CHUNK_SIZE];
    let mut seq: u32 = 0;

    // Get starting offset for frame headers
    let start_offset = file.stream_position().await?;
    let mut offset = start_offset;

    loop {
        let n = file.read(&mut buffer).await?;
        if n == 0 {
            break;
        }

        let chunk = &buffer[..n];
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

        // Backpressure check (simple spin wait to avoid blowing up memory)
        loop {
            let buffered = {
                let conn = rtc_conn.lock().await;
                conn.get_buffered_amount(&channel_label).await
            };
            if buffered < 1024 * 1024 {
                // 1MB buffer limit
                break;
            }
            tokio::time::sleep(std::time::Duration::from_millis(10)).await;
        }

        // Send the binary frame
        {
            let conn = rtc_conn.lock().await;
            if let Err(e) = conn
                .send_message(
                    &channel_label,
                    &tokio_tungstenite::tungstenite::Bytes::from(frame),
                )
                .await
            {
                crate::elog!("FS: Failed to send chunk {}: {}", seq, e);
                break;
            }
        }

        offset += n as u64;
    }

    // Send download_end
    let end_msg = HostMessage::DownloadEnd {
        id,
        hash: full_hash,
        timestamp: crate::utils::get_timestamp(),
    };
    if let Ok(json) = serde_json::to_string(&end_msg) {
        let conn = rtc_conn.lock().await;
        let _ = conn.send_message(&channel_label, &Bytes::from(json)).await;
    }

    crate::log!("FS: Download stream finished");

    Ok(())
}
