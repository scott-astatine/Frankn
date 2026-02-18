mod utils;
use utils::*;

use std::{
    collections::HashMap,
    sync::Arc,
    time::{SystemTime, UNIX_EPOCH},
};

use futures_util::{SinkExt, StreamExt};
use tokio::{
    net::TcpListener,
    sync::{mpsc::UnboundedSender, RwLock},
};
use tokio_tungstenite::{accept_async, tungstenite::Message};

fn get_timestamp() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs()
}

async fn send_signaling_msg(
    tx: &UnboundedSender<Message>,
    msg: SignalingMessage,
) -> SignalingResult {
    let json_string =
        serde_json::to_string(&msg).map_err(|e| format!("Failed to serialize message: {}", e))?;
    let message = Message::Text(json_string.into());
    tx.send(message)
        .map_err(|e| format!("Failed to send to peer channel: {}", e))?;
    Ok(())
}

async fn handle_signaling_message(
    msg: SignalingMessage,
    current_peer_id: &mut Option<String>,
    tx: &UnboundedSender<Message>,
    peers: &PeerMap,
) -> SignalingResult {
    match msg {
        SignalingMessage::Register {
            peer_id,
            peer_type,
            display_name,
            is_public,
            timestamp,
        } => {
            if current_peer_id.is_some() {
                return send_signaling_msg(
                    tx,
                    SignalingMessage::RegisterFailure {
                        error: format!("{:?} already registered!", peer_type),
                        timestamp,
                    },
                )
                .await
                .map_err(|e| e.to_string());
            }

            let mut peers_map = peers.write().await;

            log!(
                "Registering peer: ID '{:?}', Name: '{}', Type: {:?}, Public: {}",
                peer_id,
                display_name,
                peer_type,
                is_public
            );

            peers_map.insert(
                peer_id.clone(),
                PeerConnection {
                    sender: tx.clone(),
                    peer_type: peer_type,
                    display_name,
                    is_public,
                },
            );

            *current_peer_id = Some(peer_id.clone());

            send_signaling_msg(
                tx,
                SignalingMessage::RegisterSuccess {
                    peer_id: peer_id,
                    timestamp,
                },
            )
            .await
            .map_err(|e| e.to_string())
        }

        SignalingMessage::ListHosts { timestamp } => {
            let hosts: Vec<HostInfo> = peers
                .read()
                .await
                .iter()
                .filter(|(_, conn)| conn.peer_type == PeerType::Host && conn.is_public)
                .map(|(host_id, conn)| HostInfo {
                    host_id: host_id.clone(),
                    display_name: conn.display_name.clone(),
                })
                .collect();

            log!("Listing hosts: Found {} host(s).", hosts.len());
            send_signaling_msg(
                tx,
                SignalingMessage::HostList {
                    hosts: hosts,
                    timestamp,
                },
            )
            .await
            .map_err(|e| e.to_string())
        }

        ref msg @ (SignalingMessage::Offer {
            to: ref target_id,
            timestamp,
            ..
        }
        | SignalingMessage::Answer {
            to: ref target_id,
            timestamp,
            ..
        }
        | SignalingMessage::IceCandidate {
            to: ref target_id,
            timestamp,
            ..
        }) => {
            if current_peer_id.is_none() {
                return Err("Cannot send signaling message before registration.".to_string());
            }

            let peers_map = peers.read().await;

            if let Some(target_conn) = peers_map.get(target_id) {
                log!(
                    "Forwarding message {:?} from {} to {}",
                    match &msg {
                        SignalingMessage::Offer { .. } => "Offer",
                        SignalingMessage::Answer { .. } => "Answer",
                        SignalingMessage::IceCandidate { .. } => "IceCandidate",
                        _ => "Unknown",
                    },
                    current_peer_id.as_ref().unwrap(),
                    target_id
                );
                send_signaling_msg(&target_conn.sender, msg.clone())
                    .await
                    .map_err(|e| e.to_string())
            } else {
                log!("Forwarding failed: Target peer '{}' not found", target_id);

                send_signaling_msg(
                    tx,
                    SignalingMessage::Error {
                        message: format!("Target peer '{}' not found.", target_id),
                        timestamp,
                    },
                )
                .await
                .map_err(|e| e.to_string())
            }
        }

        SignalingMessage::RegisterSuccess { .. }
        | SignalingMessage::RegisterFailure { .. }
        | SignalingMessage::Error { .. }
        | SignalingMessage::HostList { .. } => {
            log!("Received server-only message from client: {:?}", msg);
            Err(format!("Client sent server-only message: {:?}", msg))
        }
    }
}

async fn handle_peer_connection(stream: tokio::net::TcpStream, peers: PeerMap) {
    let ws_stream = match accept_async(stream).await {
        Ok(ws) => ws,
        Err(e) => {
            elog!("WebSocket handshake failed: {}", e);
            return;
        }
    };

    log!("WebSocket connection established!");

    let (mut ws_write, mut ws_read) = ws_stream.split();
    // Channel for sending message to the peer
    let (tx, mut rx) = tokio::sync::mpsc::unbounded_channel::<Message>();

    let mut peer_id: Option<String> = None;
    let mut interval = tokio::time::interval(std::time::Duration::from_secs(5));

    // Clone tx for the heartbeat loop (conceptually, though we use it in select)
    // Actually, we can use tx.send inside the loop.

    loop {
        tokio::select! {
            // 1. Handle incoming messages
            msg_result = ws_read.next() => {
                match msg_result {
                    Some(Ok(Message::Text(text))) => {
                        match serde_json::from_str::<SignalingMessage>(&text) {
                            Ok(signal_msg) => {
                                if let Err(e) =
                                    handle_signaling_message(signal_msg, &mut peer_id, &tx, &peers).await
                                {
                                    elog!("Failed to handle message: {}, Payload: {}", e, text);
                                    let error_msg = SignalingMessage::Error {
                                        message: format!("Error handling message: {}", e),
                                        timestamp: get_timestamp(),
                                    };
                                    let _ = send_signaling_msg(&tx, error_msg).await;
                                }
                            }
                            Err(e) => {
                                elog!("Failed to parse message: {}, Payload: {}", e, text);
                                let error_msg = SignalingMessage::Error {
                                    message: format!("Invalid message format: {}", e),
                                    timestamp: get_timestamp(),
                                };
                                let _ = send_signaling_msg(&tx, error_msg).await;
                            }
                        }
                    }
                    Some(Ok(Message::Ping(data))) => {
                        let _ = tx.send(Message::Pong(data));
                    }
                    Some(Ok(Message::Pong(_))) => {
                    }
                    Some(Ok(Message::Close(_))) => {
                        log!("Client initiated close.");
                        break;
                    }
                    Some(Ok(_)) => {
                    }
                    Some(Err(e)) => {
                        elog!("WebSocket read error: {}", e);
                        break;
                    }
                    None => {
                        log!("WebSocket stream ended.");
                        break;
                    }
                }
            }

            // 2. Handle outgoing messages
            Some(msg) = rx.recv() => {
                if let Err(e) = ws_write.send(msg).await {
                    elog!("Failed to send message (client disconnected?): {}", e);
                    break;
                }
            }

            _ = interval.tick() => {
                // Send a ping to check connection health
                if let Err(_) = tx.send(Message::Ping(vec![].into())) {
                    break;
                }
            }
        }
    }

    // --- Cleanup on disconnect ---
    if let Some(id) = peer_id {
        log!("Peer {} disconnected. Removing from map.", id);
        peers.write().await.remove(&id);
    }
    log!("Connection handling closed.");
}

#[tokio::main]
async fn main() {
    log!("🚀 Starting Frankn Signaling Server...");
    let peers: PeerMap = Arc::new(RwLock::new(HashMap::new()));

    let listener = TcpListener::bind("0.0.0.0:8037")
        .await
        .expect("Failed to bind to the port");

    log!("Signaling server listening on 0.0.0.0:8037");
    while let Ok((stream, addr)) = listener.accept().await {
        log!("New connection from: {}", addr);
        let peers = peers.clone();
        tokio::spawn(handle_peer_connection(stream, peers));
    }
}
