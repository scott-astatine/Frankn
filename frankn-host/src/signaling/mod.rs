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
    #[serde(rename = "auth_challenge")]
    AuthChallenge {
        challenge: String,         // Base64URL encoded CSPRNG challenge
    },

    #[serde(rename = "register")]
    Register {
        protocol_version: u8,
        peer_id: String,           // Base64URL encoded Hash(public_key)
        peer_type: PeerType,
        display_name: String,
        is_public: bool,
        public_key: String,        // Hex encoded Ed25519 public key
        signature: String,         // Hex signature of the challenge
        timestamp: u64,
    },

    #[serde(rename = "register_success")]
    RegisterSuccess {
        peer_id: String,
        session_id: String,        // Ephemeral session ID
        timestamp: u64,
    },

    #[serde(rename = "register_failure")]
    RegisterFailure {
        error: String,
        timestamp: u64,
    },

    #[serde(rename = "session_replaced")]
    SessionReplaced {
        reason: String,
        timestamp: u64,
    },

    #[serde(rename = "subscribe_hosts")]
    SubscribeHosts {
        host_ids: Vec<String>,
        timestamp: u64,
    },

    #[serde(rename = "check_hosts_status")]
    CheckHostsStatus {
        host_ids: Vec<String>,
        timestamp: u64,
    },

    #[serde(rename = "hosts_status_response")]
    HostsStatusResponse {
        statuses: std::collections::HashMap<String, bool>,
        timestamp: u64,
    },

    #[serde(rename = "update_host_acl")]
    UpdateHostAcl {
        allowed_peers: Vec<String>,
        timestamp: u64,
        signature: String,
    },

    #[serde(rename = "offer")]
    Offer {
        from: String,
        to: String,
        sdp: String,
        session_id: String,
        sequence: u64,
        signature: String,
        timestamp: u64,
    },

    #[serde(rename = "answer")]
    Answer {
        from: String,
        to: String,
        sdp: String,
        session_id: String,
        sequence: u64,
        signature: String,
        timestamp: u64,
    },

    #[serde(rename = "ice_candidate")]
    IceCandidate {
        from: String,
        to: String,
        candidate: String,
        sdp_mid: Option<String>,
        sdp_m_line_index: Option<u16>,
        session_id: String,
        sequence: u64,
        signature: String,
        timestamp: u64,
    },

    #[serde(rename = "error")]
    Error {
        message: String,
        timestamp: u64,
    },
}

pub struct SignalingClient {
    pub peer_id: String,
    pub session_id: String,
    pub signing_key: ed25519_dalek::SigningKey,
    pub sequence: std::sync::atomic::AtomicU64,
    sender: Arc<RwLock<Option<UnboundedSender<SignalingMessage>>>>,
}

impl SignalingClient {
    /// Connect to a signaling server
    pub async fn connect(
        signaling_server_url: &str,
        signing_key: ed25519_dalek::SigningKey,
        display_name: String,
        is_public: bool,
        peer_type: PeerType,
    ) -> Result<(Self, UnboundedReceiver<SignalingMessage>), Box<dyn std::error::Error>> {
        log!("Connecting to signaling server: {}", signaling_server_url);

        let (ws_stream, _) = connect_async(signaling_server_url).await?;
        let (mut write, mut read) = ws_stream.split();
        let (tx, mut rx) = tokio::sync::mpsc::unbounded_channel();
        let (incoming_tx, incoming_rx) = tokio::sync::mpsc::unbounded_channel();

        // 1. Wait for AuthChallenge from server
        let challenge = match read.next().await {
            Some(Ok(Message::Text(text))) => {
                let msg: SignalingMessage = serde_json::from_str(&text)?;
                if let SignalingMessage::AuthChallenge { challenge } = msg {
                    challenge
                } else {
                    return Err("Expected AuthChallenge from server".into());
                }
            }
            _ => return Err("Failed to receive AuthChallenge".into()),
        };

        // 2. Decode challenge and sign
        use base64::Engine;
        let challenge_bytes = base64::engine::general_purpose::URL_SAFE_NO_PAD.decode(&challenge)?;

        use ed25519_dalek::Signer;
        let signature = signing_key.sign(&challenge_bytes);
        let signature_hex = hex::encode(signature.to_bytes());

        // 3. Derive Peer ID and Public Key
        let public_key_bytes = signing_key.verifying_key().to_bytes();
        let public_key_hex = hex::encode(public_key_bytes);

        use sha2::Digest;
        let raw_peer_id = sha2::Sha256::digest(&public_key_bytes);
        let peer_id = base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(&raw_peer_id);

        // 4. Send Register payload
        let register_msg = SignalingMessage::Register {
            protocol_version: 1,
            peer_id: peer_id.clone(),
            peer_type: peer_type.clone(),
            display_name,
            is_public,
            public_key: public_key_hex,
            signature: signature_hex,
            timestamp: std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_millis() as u64,
        };
        let text = serde_json::to_string(&register_msg)?;
        write.send(Message::Text(text.into())).await?;

        // 5. Wait for RegisterSuccess
        let session_id = match read.next().await {
            Some(Ok(Message::Text(text))) => {
                let msg: SignalingMessage = serde_json::from_str(&text)?;
                if let SignalingMessage::RegisterSuccess { session_id, .. } = msg {
                    session_id
                } else if let SignalingMessage::RegisterFailure { error, .. } = msg {
                    return Err(format!("Registration failed: {}", error).into());
                } else {
                    return Err("Expected RegisterSuccess".into());
                }
            }
            _ => return Err("Failed to receive RegisterSuccess".into()),
        };

        let sender = Arc::new(RwLock::new(Some(tx.clone())));

        tokio::spawn(async move {
            let mut interval = tokio::time::interval(std::time::Duration::from_secs(10));
            let mut last_seen = std::time::Instant::now();
            loop {
                tokio::select! {
                    Some(msg) = rx.recv() => {
                        let text = serde_json::to_string(&msg).unwrap();
                        if write.send(Message::Text(text.into())).await.is_err() {
                            elog!("NODE: Failed to send message to signaling server.");
                            break;
                        }
                    }
                    msg_result = read.next() => {
                        last_seen = std::time::Instant::now();
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
                            Some(Ok(Message::Ping(_))) => {}
                            Some(Ok(Message::Pong(_))) => {}
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
                    _ = interval.tick() => {
                        if last_seen.elapsed().as_secs() > 30 {
                            elog!("NODE: Signaling server timeout (no response). Terminating connection.");
                            break;
                        }
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
            peer_id,
            session_id,
            signing_key,
            sequence: std::sync::atomic::AtomicU64::new(1),
            sender,
        };

        Ok((client, incoming_rx))
    }

    /// Sign data-plane message using the 160-byte canonical binary structure
    pub fn sign_envelope(
        &self,
        msg_type: u8,
        to_peer_id_str: &str,
        payload_str: &str,
        sequence: u64,
        timestamp: u64,
    ) -> Result<String, Box<dyn std::error::Error>> {
        let mut buf = [0u8; 160];
        
        // Domain Separator (14 bytes)
        buf[0..14].copy_from_slice(b"FRANKN-SIG-V1\0");
        
        // Version (1 byte)
        buf[14] = 0x01;
        
        // Message Type ID (1 byte)
        buf[15] = msg_type;
        
        // Session ID (32 bytes)
        use base64::Engine;
        let session_bytes = base64::engine::general_purpose::URL_SAFE_NO_PAD.decode(&self.session_id)?;
        buf[16..48].copy_from_slice(&session_bytes);
        
        // Sequence (8 bytes BE)
        buf[48..56].copy_from_slice(&sequence.to_be_bytes());
        
        // Timestamp (8 bytes BE ms)
        buf[56..64].copy_from_slice(&timestamp.to_be_bytes());
        
        // From Peer ID (32 bytes)
        let from_bytes = base64::engine::general_purpose::URL_SAFE_NO_PAD.decode(&self.peer_id)?;
        buf[64..96].copy_from_slice(&from_bytes);
        
        // To Peer ID (32 bytes)
        let to_bytes = base64::engine::general_purpose::URL_SAFE_NO_PAD.decode(to_peer_id_str)?;
        buf[96..128].copy_from_slice(&to_bytes);
        
        // Payload Hash (32 bytes)
        use sha2::{Sha256, Digest};
        let payload_hash = Sha256::digest(payload_str.as_bytes());
        buf[128..160].copy_from_slice(&payload_hash);
        
        use ed25519_dalek::Signer;
        let signature = self.signing_key.sign(&buf);
        
        Ok(hex::encode(signature.to_bytes()))
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

    /// Send Offer to Target Peer
    pub async fn send_offer(
        &self,
        to: &str,
        sdp: String,
    ) -> Result<(), Box<dyn std::error::Error>> {
        use std::sync::atomic::Ordering;
        let sequence = self.sequence.fetch_add(1, Ordering::SeqCst);
        let timestamp = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_millis() as u64;

        let signature = self.sign_envelope(0x01, to, &sdp, sequence, timestamp)?;

        self.send_message(SignalingMessage::Offer {
            from: self.peer_id.clone(),
            to: to.to_string(),
            sdp,
            session_id: self.session_id.clone(),
            sequence,
            signature,
            timestamp,
        })
        .await
    }

    /// Send Answer to Client
    pub async fn send_answer(
        &self,
        to: &str,
        sdp: String,
    ) -> Result<(), Box<dyn std::error::Error>> {
        use std::sync::atomic::Ordering;
        let sequence = self.sequence.fetch_add(1, Ordering::SeqCst);
        let timestamp = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_millis() as u64;

        let signature = self.sign_envelope(0x02, to, &sdp, sequence, timestamp)?;

        self.send_message(SignalingMessage::Answer {
            from: self.peer_id.clone(),
            to: to.to_string(),
            sdp,
            session_id: self.session_id.clone(),
            sequence,
            signature,
            timestamp,
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
        use std::sync::atomic::Ordering;
        let sequence = self.sequence.fetch_add(1, Ordering::SeqCst);
        let timestamp = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_millis() as u64;

        let signature = self.sign_envelope(0x03, to, &candidate, sequence, timestamp)?;

        self.send_message(SignalingMessage::IceCandidate {
            from: self.peer_id.clone(),
            to: to.to_string(),
            candidate,
            sdp_mid,
            sdp_m_line_index,
            session_id: self.session_id.clone(),
            sequence,
            signature,
            timestamp,
        })
        .await
    }
}
