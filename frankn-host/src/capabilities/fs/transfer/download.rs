use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};
use std::io::SeekFrom;
use tokio::fs::File;
use tokio::io::{AsyncReadExt, AsyncSeekExt};
use tokio::sync::Mutex;
use tokio_tungstenite::tungstenite::Bytes;
use sha2::{Digest, Sha256};

use crate::{HostMessage, transport::webrtc::connection::RTCConn, utils::Status};
use super::framing::{FRAME_HEADER_SIZE, FRAME_MAGIC, FLAG_FINAL};
use super::state::DOWNLOAD_TASKS;

pub async fn handle_download_init(
    id: &str,
    path: &str,
    resume_offset: u64,
    rtc_conn: Arc<Mutex<RTCConn>>,
    channel_label: &str,
) -> HostMessage {
    let sandbox_path = match crate::capabilities::fs::check_sandbox_default(path, false) {
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

    let start_msg = HostMessage::DownloadStart {
        id: id.to_string(),
        file_name,
        total_size,
        offset: actual_offset,
        hash: None,
        timestamp: crate::utils::get_timestamp(),
    };

    if let Ok(json) = serde_json::to_string(&start_msg) {
        let conn = rtc_conn.lock().await;
        if let Err(e) = conn.send_message(channel_label, &Bytes::from(json)).await {
            crate::elog!("FS ERROR: Failed to send download_start: {}", e);
        }
    }

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
            if let Err(e) = conn
                .send_message(
                    channel_label,
                    &tokio_tungstenite::tungstenite::Bytes::from(json),
                )
                .await
            {
                crate::elog!("FS ERROR: Failed to send download_end seek error: {}", e);
            }
        }
        return HostMessage::Response {
            id: id.to_string(),
            status: Status::Success,
            data: None,
            timestamp: 0,
        };
    }

    let transfer_id = id.to_string();
    let label = channel_label.to_string();

    let cancel_flag = Arc::new(AtomicBool::new(false));
    let cancel_flag_clone = Arc::clone(&cancel_flag);

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

async fn stream_download(
    mut file: File,
    id: String,
    dc: Arc<webrtc::data_channel::RTCDataChannel>,
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
            crate::log!("FS: Download task {} exited gracefully.", id);
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

        let id_bytes = id.as_bytes();
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
                crate::log!("FS: Download task {} exited gracefully.", id);
                return Ok(());
            }

            let buffered = dc.buffered_amount().await;
            if buffered < 1024 * 1024 {
                break;
            }
            tokio::time::sleep(std::time::Duration::from_millis(10)).await;
        }

        if let Err(e) = dc
            .send(&tokio_tungstenite::tungstenite::Bytes::from(frame))
            .await
        {
            crate::elog!("FS: Failed to send chunk {}: {}", seq, e);
            break;
        }

        offset += n as u64;
    }

    let full_hash = hex::encode(hasher.finalize());

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
