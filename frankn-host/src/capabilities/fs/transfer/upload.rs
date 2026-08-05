use std::sync::Arc;
use std::sync::atomic::Ordering;
use tokio::fs::File;
use tokio::io::AsyncWriteExt;
use tokio::sync::Mutex;
use sha2::{Digest, Sha256};

use crate::{HostMessage, transport::context::CommandContext, utils::Status};
use super::framing::{parse_frame_header, TransferFrameHeader, FRAME_HEADER_SIZE, FLAG_FINAL, FLAG_ACK_REQUESTED};
use super::state::{
    TransferState, UploadSession, UPLOAD_SESSIONS, DOWNLOAD_TASKS,
    write_state, part_path, state_path, cleanup_partial,
};

pub async fn handle_transfer_init(
    ctx: &CommandContext,
    path: &str,
    hash: Option<String>,
    total_size: u64,
    resume_offset: u64,
) -> HostMessage {
    crate::log!(
        "FS: Transfer init for {} — path={}, size={}, resume_offset={}",
        ctx.id,
        path,
        total_size,
        resume_offset
    );

    let sandbox_path = match crate::capabilities::fs::check_sandbox_default(path, false) {
        Ok(p) => p,
        Err(e) => {
            return HostMessage::Response {
                id: ctx.id.clone(),
                status: Status::Error(e),
                data: None,
                timestamp: crate::utils::get_timestamp(),
            };
        }
    };
    let path_str = sandbox_path.to_string_lossy().to_string();

    if let Some(parent) = sandbox_path.parent() {
        let _ = tokio::fs::create_dir_all(parent).await;
    }

    let part = part_path(&path_str);

    let mut actual_offset = 0u64;
    let file = if resume_offset > 0 {
        match tokio::fs::metadata(&part).await {
            Ok(meta) => {
                actual_offset = meta.len();
                if actual_offset != resume_offset {
                    crate::elog!(
                        "FS: Resume offset mismatch for {} — expected {}, got {}",
                        ctx.id,
                        resume_offset,
                        actual_offset
                    );
                    actual_offset = 0;
                    match File::create(&part).await {
                        Ok(f) => f,
                        Err(e) => {
                            return HostMessage::Response {
                                id: ctx.id.clone(),
                                status: Status::Error(format!("Failed to create file: {}", e)),
                                data: None,
                                timestamp: crate::utils::get_timestamp(),
                            };
                        }
                    }
                } else {
                    crate::log!("FS: Resuming {} from offset {}", ctx.id, actual_offset);
                    match tokio::fs::OpenOptions::new()
                        .write(true)
                        .append(true)
                        .open(&part)
                        .await
                    {
                        Ok(f) => f,
                        Err(e) => {
                            return HostMessage::Response {
                                id: ctx.id.clone(),
                                status: Status::Error(format!("Failed to open partial: {}", e)),
                                data: None,
                                timestamp: crate::utils::get_timestamp(),
                            };
                        }
                    }
                }
            }
            Err(_) => {
                match File::create(&part).await {
                    Ok(f) => f,
                    Err(e) => {
                        return HostMessage::Response {
                            id: ctx.id.clone(),
                            status: Status::Error(format!("Failed to create file: {}", e)),
                            data: None,
                            timestamp: crate::utils::get_timestamp(),
                        };
                    }
                }
            }
        }
    } else {
        match File::create(&part).await {
            Ok(f) => f,
            Err(e) => {
                return HostMessage::Response {
                    id: ctx.id.clone(),
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
        client_id: ctx.client_id.clone(),
    };

    let state = TransferState {
        transfer_id: ctx.id.clone(),
        path: path_str.clone(),
        total_size,
        current_offset: actual_offset,
        expected_hash: hash.clone(),
        last_seq: 0,
    };
    if let Err(e) = write_state(&path_str, &state).await {
        crate::elog!("FS: Failed to write state for {}: {}", ctx.id, e);
    }

    {
        let mut sessions = UPLOAD_SESSIONS.lock().await;
        sessions.insert(ctx.id.clone(), Arc::new(Mutex::new(session)));
    }

    let resp = HostMessage::Response {
        id: ctx.id.clone(),
        status: Status::Success,
        data: Some(serde_json::json!({
            "message": "Transfer ready",
            "offset": actual_offset,
        })),
        timestamp: crate::utils::get_timestamp(),
    };
    let _ = ctx.stream(resp.clone()).await;

    resp
}

pub async fn handle_transfer_cancel(id: &str) -> HostMessage {
    let session = {
        let mut sessions = UPLOAD_SESSIONS.lock().await;
        sessions.remove(id)
    };

    if let Some(session_arc) = session {
        let session = session_arc.lock().await;
        cleanup_partial(&session.path).await;
        crate::log!("FS: Upload transfer {} cancelled, partial cleaned up", id);
    }

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

pub async fn handle_transfer_chunk_raw(
    data: &[u8],
    ctx: &CommandContext,
) {
    let Some(header) = parse_frame_header(data) else {
        crate::elog!(
            "FS: Invalid binary frame (len={}, magic={})",
            data.len(),
            data.first().copied().unwrap_or_default()
        );
        return;
    };

    let TransferFrameHeader {
        transfer_id,
        offset,
        seq,
        flags,
    } = header;
    let is_final = (flags & FLAG_FINAL) != 0;
    let ack_requested = (flags & FLAG_ACK_REQUESTED) != 0;

    let chunk_data = &data[FRAME_HEADER_SIZE..];

    let session = {
        let sessions = UPLOAD_SESSIONS.lock().await;
        sessions.get(&transfer_id).map(Arc::clone)
    };

    let Some(session_arc) = session else {
        crate::elog!("FS: No session for chunk seq={} offset={}", seq, offset);
        return;
    };

    let mut session = session_arc.lock().await;

    if offset != session.current_offset {
        crate::elog!(
            "FS: Offset mismatch for {} — expected {}, got {}",
            transfer_id,
            session.current_offset,
            offset
        );
        return;
    }

    if let Err(e) = session.file.write_all(chunk_data).await {
        crate::elog!("FS: Write error for {}: {}", transfer_id, e);
        return;
    }

    session.hasher.update(chunk_data);
    session.current_offset += chunk_data.len() as u64;
    session.last_seq = seq;

    if is_final || session.current_offset % (1024 * 1024) < chunk_data.len() as u64 {
        let _ = session.file.flush().await;
    }

    let state = TransferState {
        transfer_id: transfer_id.clone(),
        path: session.path.clone(),
        total_size: session.total_size,
        current_offset: session.current_offset,
        expected_hash: None,
        last_seq: seq,
    };
    let _ = write_state(&session.path, &state).await;

    let offset_now = session.current_offset;
    let seq_now = seq;
    let transfer_id_clone = transfer_id.clone();

    drop(session);

    if ack_requested || seq % 50 == 0 {
        let ack = HostMessage::TransferAck {
            id: transfer_id,
            offset: offset_now,
            seq: seq_now,
            timestamp: crate::utils::get_timestamp(),
        };
        let _ = ctx.stream(ack).await;
    }

    if is_final {
        finalize_upload(&transfer_id_clone, ctx).await;
    }
}

async fn finalize_upload(id: &str, ctx: &CommandContext) {
    let session = {
        let mut sessions = UPLOAD_SESSIONS.lock().await;
        sessions.remove(id)
    };

    let Some(session_arc) = session else {
        crate::elog!("FS: Finalize called but session {} not found", id);
        return;
    };

    let mut session = session_arc.lock().await;

    if let Err(e) = session.file.flush().await {
        crate::elog!("FS: Flush error during finalize for {}: {}", id, e);
        return;
    }

    let hash_hex = hex::encode(session.hasher.clone().finalize());

    let part = part_path(&session.path);
    if let Err(e) = tokio::fs::rename(&part, &session.path).await {
        crate::elog!("FS: Rename error for {}: {}", id, e);
        return;
    }

    let _ = tokio::fs::remove_file(state_path(&session.path)).await;

    let complete = HostMessage::TransferComplete {
        id: id.to_string(),
        hash: hash_hex,
        timestamp: crate::utils::get_timestamp(),
    };
    let _ = ctx.stream(complete).await;

    crate::log!("FS: Transfer {} completed", id);
}

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
        }
    }
}
