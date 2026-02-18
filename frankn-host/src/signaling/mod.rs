use std::sync::Arc;

use futures_util::{SinkExt, StreamExt};
use serde::{Deserialize, Serialize};
use tokio::sync::mpsc::{UnboundedReceiver, UnboundedSender};
use tokio_tungstenite::{connect_async, tungstenite::Message};
use webrtc::util::sync::RwLock;

use crate::{elog, log};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub enum PeerType {
    Host,
    Client,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type")]
pub enum SignalingMessage {
    #[serde(rename = "register")]
    Register {
        peer_id: String,
        peer_type: PeerType,
        display_name: String,
        is_public: bool,
        timestamp: u64,
    },

    #[serde(rename = "register_success")]
    RegisterSuccess { peer_id: String, timestamp: u64 },

    #[serde(rename = "register_failure")]
    RegisterFailure { error: String, timestamp: u64 },

    #[serde(rename = "offer")]
    Offer {
        from: String,
        to: String,
        sdp: String,
        timestamp: u64,
    },

    #[serde(rename = "answer")]
    Answer {
        from: String,
        to: String,
        sdp: String,
        timestamp: u64,
    },

    #[serde(rename = "ice_candidate")]
    IceCandidate {
        from: String,
        to: String,
        candidate: String,
        sdp_mid: Option<String>,
        sdp_m_line_index: Option<u16>,
        timestamp: u64,
    },

    #[serde(rename = "error")]
    Error { message: String, timestamp: u64 },
}

pub struct SignalingClient {
    peer_id: String,
    sender: Arc<RwLock<Option<UnboundedSender<SignalingMessage>>>>,
    is_dummy: bool,
}

impl SignalingClient {
    pub fn dummy() -> Self {
        Self {
            peer_id: String::new(),
            sender: Arc::new(RwLock::new(None)),
            is_dummy: true,
        }
    }

    pub fn is_dummy(&self) -> bool {
        self.is_dummy
    }

    /// Connect to a signaling server
    pub async fn connect(
        signaling_server_url: &str,
        peer_id: String,
        display_name: String,
        is_public: bool,
    ) -> Result<(Self, UnboundedReceiver<SignalingMessage>), Box<dyn std::error::Error>> {
        log!("Connecting to signaling server: {}", signaling_server_url);

        let (ws_stream, _) = connect_async(signaling_server_url).await?;
        let (mut write, mut read) = ws_stream.split();
        let (tx, mut rx) = tokio::sync::mpsc::unbounded_channel();
        let (incoming_tx, incoming_rx) = tokio::sync::mpsc::unbounded_channel();

        let sender = Arc::new(RwLock::new(Some(tx.clone())));

        tokio::spawn(async move {
            let mut interval = tokio::time::interval(std::time::Duration::from_secs(10));
            loop {
                tokio::select! {
                    // 1. Handle outgoing messages from the app
                    Some(msg) = rx.recv() => {
                        let text = serde_json::to_string(&msg).unwrap();
                        if write.send(Message::Text(text.into())).await.is_err() {
                            elog!("NODE: Failed to send message to signaling server.");
                            break;
                        }
                    }
                    // 2. Handle incoming messages from the server
                    msg_result = read.next() => {
                        match msg_result {
                            Some(Ok(Message::Text(text))) => {
                                match serde_json::from_str::<SignalingMessage>(&text) {
                                    Ok(signal_msg) => {
                                        if incoming_tx.send(signal_msg).is_err() {
                                            break;
                                        }
                                    }
                                    Err(e) => {
                                        elog!("NODE: Failed to parse signaling message: {}", e);
                                    }
                                }
                            }
                            Some(Ok(Message::Ping(_))) => {
                                // Tungstenite handles Pong automatically in most cases
                            }
                            Some(Ok(Message::Pong(_))) => {
                                // Heartbeat acknowledged
                            }
                            Some(Ok(Message::Close(_))) => {
                                log!("NODE: Signaling server closed connection.");
                                break;
                            }
                            Some(Err(e)) => {
                                elog!("NODE: Signaling WebSocket error: {}", e);
                                break;
                            }
                            None => {
                                log!("NODE: Signaling stream ended.");
                                break;
                            }
                            _ => {}
                        }
                    }
                    // 3. Heartbeat
                    _ = interval.tick() => {
                        if write.send(Message::Ping(vec![].into())).await.is_err() {
                            elog!("NODE: Signaling heartbeat failed.");
                            break;
                        }
                    }
                }
            }
            log!("NODE: Signaling connection task terminated.");
        });

        let client = Self {
            peer_id: peer_id.clone(),
            sender,
            is_dummy: false,
        };

        client
            .send_message(SignalingMessage::Register {
                peer_id,
                peer_type: PeerType::Host,
                display_name,
                is_public,
                timestamp: std::time::SystemTime::now()
                    .duration_since(std::time::UNIX_EPOCH)
                    .unwrap()
                    .as_secs(),
            })
            .await?;

        Ok((client, incoming_rx))
    }

    /// Send msg of type `SignalingMessage`
    pub async fn send_message(
        &self,
        msg: SignalingMessage,
    ) -> Result<(), Box<dyn std::error::Error>> {
        let sender_lock = self.sender.read();
        if let Some(sender) = sender_lock.as_ref() {
            sender.send(msg).map_err(|_| "Failed to send message")?;
            Ok(())
        } else {
            Err("Sender not available".into())
        }
    }

    pub async fn send_offer(
        &self,
        to: &str,
        sdp: String,
    ) -> Result<(), Box<dyn std::error::Error>> {
        self.send_message(SignalingMessage::Offer {
            from: self.peer_id.clone(),
            to: to.to_string(),
            sdp,
            timestamp: std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_secs(),
        })
        .await
    }

    /// Send Answer to Client
    pub async fn send_answer(
        &self,
        to: &str,
        sdp: String,
    ) -> Result<(), Box<dyn std::error::Error>> {
        self.send_message(SignalingMessage::Answer {
            from: self.peer_id.clone(),
            to: to.to_string(),
            sdp,
            timestamp: std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_secs(),
        })
        .await
    }

    /// Send IceCandidate
    pub async fn send_ice_candidate(
        &self,
        to: &str,
        candidate: String,
        sdp_mid: Option<String>,
        sdp_m_line_index: Option<u16>,
    ) -> Result<(), Box<dyn std::error::Error>> {
        self.send_message(SignalingMessage::IceCandidate {
            from: self.peer_id.clone(),
            to: to.to_string(),
            candidate,
            sdp_mid,
            sdp_m_line_index,
            timestamp: std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_secs(),
        })
        .await
    }
}
