use std::sync::Arc;
use tokio::io::{AsyncRead, AsyncReadExt};
use tokio::sync::Mutex;
use tokio_tungstenite::tungstenite::Bytes;
use sha2::{Digest, Sha256};
use crate::sys::rtc::RTCConn;
use crate::HostMessage;

/// Options for the data streamer
pub struct StreamOptions {
    pub chunk_size: usize,
    pub buffer_threshold: usize,
    pub channel_label: String,
}

impl Default for StreamOptions {
    fn default() -> Self {
        Self {
            chunk_size: 61440,           // 60KB chunks (max safe density)
            buffer_threshold: 1024 * 1024, // 1MB backpressure limit
            channel_label: "frankn_fs".to_string(),
        }
    }
}

/// Streams data from an AsyncRead source over a WebRTC DataChannel.
/// Handles framing (36-byte ID), backpressure, and SHA-256 hashing.
pub async fn stream_data<R: AsyncRead + Unpin>(
    mut reader: R,
    id: String,
    rtc_conn: Arc<Mutex<RTCConn>>,
    options: StreamOptions,
) -> Result<String, std::io::Error> {
    let mut hasher = Sha256::new();
    let mut buffer = vec![0u8; options.chunk_size];
    let id_bytes = {
        let mut b = id.as_bytes().to_vec();
        b.resize(36, 0); // UUID padding
        b
    };

    loop {
        let n = reader.read(&mut buffer).await?;
        if n == 0 {
            break;
        }

        let chunk = &buffer[0..n];
        hasher.update(chunk);

        // Frame the data: [Magic Byte 0x01][36 bytes ID][Data]
        let mut frame = Vec::with_capacity(1 + 36 + n);
        frame.push(0x01); // Magic byte for BINARY
        frame.extend_from_slice(&id_bytes);
        frame.extend_from_slice(chunk);

        // Backpressure management
        let mut wait_count = 0;
        loop {
            let conn = rtc_conn.lock().await;
            let buffered = conn.get_buffered_amount(&options.channel_label).await;
            
            if buffered < options.buffer_threshold {
                if let Err(e) = conn.send_message(&options.channel_label, &Bytes::from(frame)).await {
                    return Err(std::io::Error::new(std::io::ErrorKind::BrokenPipe, e.to_string()));
                }
                crate::log!("FS: Sent chunk for {}. Length: {} bytes", id, n);
                break; // Move to next chunk
            }
            
            drop(conn);
            wait_count += 1;
            if wait_count % 100 == 0 {
                crate::log!("FS: Backpressure stall for session {}. Current Buffer: {} bytes", id, buffered);
            }
            tokio::time::sleep(tokio::time::Duration::from_millis(10)).await;
        }
    }

    Ok(hex::encode(hasher.finalize()))
}

/// Sends the start and end control messages for a transfer, wrapping the binary stream.
pub async fn send_managed_transfer<R: AsyncRead + Unpin + Send + 'static>(
    reader: R,
    id: String,
    file_name: String,
    total_size: u64,
    rtc_conn: Arc<Mutex<RTCConn>>,
    options: StreamOptions,
) {
    let transfer_id = id.clone();
    let label = options.channel_label.clone();
    let conn_for_stream = Arc::clone(&rtc_conn);

    tokio::spawn(async move {
        // 1. Send Transfer Start
        let start_msg = HostMessage::StreamStart {
            id: transfer_id.clone(),
            file_name,
            total_size,
            timestamp: crate::utils::get_timestamp(),
        };

        if let Ok(json) = serde_json::to_string(&start_msg) {
            let conn = conn_for_stream.lock().await;
            let _ = conn.send_message(&label, &Bytes::from(json)).await;
        }

        // 2. Stream the binary data
        let hash_result = stream_data(reader, transfer_id.clone(), Arc::clone(&conn_for_stream), options).await;

        // 3. Send Transfer End
        match hash_result {
            Ok(hash) => {
                let end_msg = HostMessage::StreamEnd {
                    id: transfer_id,
                    timestamp: crate::utils::get_timestamp(),
                    hash: Some(hash),
                };
                if let Ok(json) = serde_json::to_string(&end_msg) {
                    let conn = conn_for_stream.lock().await;
                    let _ = conn.send_message(&label, &Bytes::from(json)).await;
                }
            }
            Err(e) => {
                eprintln!("Transfer stream failed for {}: {}", transfer_id, e);
            }
        }
    });
}
