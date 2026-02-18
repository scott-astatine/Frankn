use std::sync::Arc;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpStream;
use tokio::sync::Mutex;
use tokio_tungstenite::tungstenite::Bytes;
use webrtc::data_channel::RTCDataChannel;
use webrtc::data_channel::data_channel_message::DataChannelMessage;

use crate::sys::rtc::RTCConn;
use crate::{HostMessage, Status, elog, log};

pub async fn start_ssh_tunnel(id: &str, rtc_conn: Arc<Mutex<RTCConn>>) -> HostMessage {
    let _ = stop_ssh_tunnel(id, Arc::clone(&rtc_conn)).await;

    log!("[SSH] Starting bridge for request: {}", id);

    // Retry loop to wait for the data channel to be registered in the map
    let mut dc = None;
    for _ in 0..20 {
        // Wait up to 2 seconds
        let conn = rtc_conn.lock().await;
        let map = conn.data_channels.lock().await;
        if let Some(found_dc) = map.get("frankn_ssh").cloned() {
            dc = Some(found_dc);
            break;
        }
        drop(map);
        drop(conn);
        tokio::time::sleep(tokio::time::Duration::from_millis(100)).await;
    }

    if let Some(dc) = dc {
        match TcpStream::connect("127.0.0.1:22").await {
            Ok(_) => {
                let (stop_tx, stop_rx) = tokio::sync::oneshot::channel();
                {
                    let conn = rtc_conn.lock().await;
                    let mut bridge_stop = conn.ssh_bridge_stop.lock().await;
                    *bridge_stop = Some(stop_tx);
                }

                tokio::spawn(async move {
                    handle_ssh_channel(dc, stop_rx).await;
                });
                HostMessage::Response {
                    id: id.to_string(),
                    status: Status::Success,
                    data: Some(serde_json::json!({ "message": "SSH reachable. Bridge active." })),
                    timestamp: crate::utils::get_timestamp(),
                }
            }
            Err(e) => {
                elog!("[SSH] Local connection failed: {}", e);
                HostMessage::Response {
                    id: id.to_string(),
                    status: Status::Error(format!("Local SSH unreachable: {}", e)),
                    data: None,
                    timestamp: crate::utils::get_timestamp(),
                }
            }
        }
    } else {
        elog!("[SSH] Data channel 'frankn_ssh' never appeared.");
        HostMessage::Response {
            id: id.to_string(),
            status: Status::Error("Uplink 'frankn_ssh' missing. Re-open terminal.".to_string()),
            data: None,
            timestamp: crate::utils::get_timestamp(),
        }
    }
}

pub async fn stop_ssh_tunnel(id: &str, rtc_conn: Arc<Mutex<RTCConn>>) -> HostMessage {
    let bridge_stop = {
        let conn = rtc_conn.lock().await;
        let mut stop_lock = conn.ssh_bridge_stop.lock().await;
        stop_lock.take()
    };

    if let Some(tx) = bridge_stop {
        let _ = tx.send(());
        log!("[SSH] Bridge stop signal sent.");
    }

    HostMessage::Response {
        id: id.to_string(),
        status: Status::Success,
        data: Some(serde_json::json!({ "message": "Bridge terminated." })),
        timestamp: crate::utils::get_timestamp(),
    }
}

pub async fn handle_ssh_channel(
    dc: Arc<RTCDataChannel>,
    stop_rx: tokio::sync::oneshot::Receiver<()>,
) {
    log!("[SSH] Spawning IO bridge for channel: {}", dc.label());

    let stream = match TcpStream::connect("127.0.0.1:22").await {
        Ok(s) => {
            log!("[SSH] Internal bridge established.");
            s
        }
        Err(e) => {
            let err_msg = format!("Error: Local SSH unreachable: {}\n", e);
            let _ = dc.send(&Bytes::from(err_msg)).await;
            return;
        }
    };

    let (mut ri, mut wi) = stream.into_split();
    let (tx, mut rx) = tokio::sync::mpsc::unbounded_channel::<Vec<u8>>();
    let notify_close = Arc::new(tokio::sync::Notify::new());

    dc.on_message(Box::new(move |msg: DataChannelMessage| {
        let _ = tx.send(msg.data.to_vec());
        Box::pin(async { {} })
    }));

    let n_close_event = Arc::clone(&notify_close);
    dc.on_close(Box::new(move || {
        log!("[SSH] DataChannel closure detected.");
        n_close_event.notify_waiters();
        Box::pin(async { {} })
    }));

    let dc_label = dc.label().to_owned();

    let mut t1 = tokio::spawn(async move {
        while let Some(data) = rx.recv().await {
            if let Err(e) = wi.write_all(&data).await {
                elog!("[SSH] Socket write error: {}", e);
                break;
            }
        }
    });

    let dc_write = Arc::clone(&dc);
    let mut t2 = tokio::spawn(async move {
        let mut buf = vec![0u8; 16384]; // 16KB buffer
        loop {
            match ri.read(&mut buf).await {
                Ok(0) => break,
                Ok(n) => {
                    if dc_write
                        .send(&Bytes::from(buf[..n].to_vec()))
                        .await
                        .is_err()
                    {
                        break;
                    }
                }
                Err(e) => {
                    elog!("[SSH] Socket read error: {}", e);
                    break;
                }
            }
        }
    });

    tokio::select! {
        _ = &mut t1 => { log!("[SSH] Inbound task finished."); },
        _ = &mut t2 => { log!("[SSH] Outbound task finished."); },
        _ = notify_close.notified() => { log!("[SSH] DataChannel closed."); },
        _ = stop_rx => { log!("[SSH] Shutdown requested."); },
    }

    t1.abort();
    t2.abort();

    log!("[SSH] Bridge cleanup complete for {}", dc_label);
}
