use sha2::{Digest, Sha256};
use std::io::SeekFrom;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};
use tokio::fs::File;
use tokio::io::{AsyncReadExt, AsyncSeekExt};

use super::framing::{FLAG_FINAL, FRAME_HEADER_SIZE, FRAME_MAGIC};
use super::state::DOWNLOAD_TASKS;
use crate::{HostMessage, transport::context::CommandContext, utils::Status};

pub async fn handle_download_init(
    ctx: CommandContext,
    path: &str,
    resume_offset: u64,
) -> HostMessage {
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

    let file = match File::open(&sandbox_path).await {
        Ok(f) => f,
        Err(e) => {
            return HostMessage::Response {
                id: ctx.id.clone(),
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
                id: ctx.id.clone(),
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

    let start_msg = HostMessage::DownloadStart {
        id: ctx.id.clone(),
        file_name,
        total_size,
        offset: actual_offset,
        hash: None,
        timestamp: crate::utils::get_timestamp(),
    };

    let _ = ctx.stream(start_msg).await;

    let mut f = file;
    if let Err(e) = f.seek(SeekFrom::Start(actual_offset)).await {
        crate::elog!("FS: Seek error for download {}: {}", ctx.id, e);
        let end_msg = HostMessage::DownloadEnd {
            id: ctx.id.clone(),
            hash: String::new(),
            timestamp: crate::utils::get_timestamp(),
        };
        let _ = ctx.stream(end_msg).await;
        return HostMessage::Response {
            id: ctx.id.clone(),
            status: Status::Success,
            data: None,
            timestamp: 0,
        };
    }

    let cancel_flag = Arc::new(AtomicBool::new(false));
    let cancel_flag_clone = Arc::clone(&cancel_flag);
    let ctx_clone = ctx.clone();

    tokio::spawn(async move {
        let _ = stream_download(f, ctx_clone, cancel_flag_clone).await;
    });

    DOWNLOAD_TASKS
        .lock()
        .await
        .insert(ctx.id.clone(), cancel_flag);

    HostMessage::Response {
        id: ctx.id.clone(),
        status: Status::Success,
        data: Some(serde_json::json!({
            "message": "Download started",
            "total_size": total_size,
            "offset": actual_offset,
        })),
        timestamp: 0,
    }
}

async fn stream_download(
    mut file: File,
    ctx: CommandContext,
    cancel_flag: Arc<AtomicBool>,
) -> Result<(), std::io::Error> {
    const CHUNK_SIZE: usize = 61440;
    let mut buffer = vec![0u8; CHUNK_SIZE];
    let mut seq: u32 = 0;

    let mut hasher = Sha256::new();

    let start_offset = file.stream_position().await?;
    let mut offset = start_offset;

    loop {
        if cancel_flag.load(Ordering::Relaxed) {
            crate::log!("FS: Download task {} exited gracefully.", ctx.id);
            return Ok(());
        }

        let n = file.read(&mut buffer).await?;
        if n == 0 {
            break;
        }

        let chunk = &buffer[..n];
        hasher.update(chunk);
        seq += 1;

        let mut frame = Vec::with_capacity(FRAME_HEADER_SIZE + n);
        frame.push(FRAME_MAGIC);

        let id_bytes = ctx.id.as_bytes();
        frame.extend_from_slice(id_bytes);
        for _ in id_bytes.len()..36 {
            frame.push(0);
        }

        frame.extend_from_slice(&offset.to_be_bytes());
        frame.extend_from_slice(&seq.to_be_bytes());

        let is_last = n < CHUNK_SIZE;
        let flags = if is_last { FLAG_FINAL } else { 0 };
        frame.push(flags);
        frame.extend_from_slice(chunk);

        loop {
            if cancel_flag.load(Ordering::Relaxed) {
                crate::log!("FS: Download task {} exited gracefully.", ctx.id);
                return Ok(());
            }

            let buffered = ctx.buffered_amount().await;
            if buffered < 1024 * 1024 {
                break;
            }
            tokio::time::sleep(std::time::Duration::from_millis(10)).await;
        }

        if let Err(e) = ctx.send_binary(frame).await {
            crate::elog!("FS: Failed to send chunk {}: {}", seq, e);
            break;
        }

        offset += n as u64;
    }

    let full_hash = hex::encode(hasher.finalize());

    let end_msg = HostMessage::DownloadEnd {
        id: ctx.id.clone(),
        hash: full_hash,
        timestamp: crate::utils::get_timestamp(),
    };
    let _ = ctx.stream(end_msg).await;

    crate::log!("FS: Download stream finished");
    Ok(())
}
