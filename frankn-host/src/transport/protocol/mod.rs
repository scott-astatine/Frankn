pub mod messages;
pub mod router;

pub use messages::{ClientMessage, HostMessage, Status};

use std::sync::Arc;
use tokio::sync::Mutex;
use tokio_tungstenite::tungstenite::Bytes;
use crate::auth::AuthManager;
use crate::config::HostConfig;
use crate::capabilities::inference::LlmManager;
use crate::transport::webrtc::connection::PeerMap;
use crate::utils::get_timestamp;
use crate::transport::context::CommandContext;

/// Decode a text data channel message and route it to the appropriate capability handler.
pub async fn parse_dc_msg(
    data: &Vec<u8>,
    peer_map: PeerMap,
    auth_manager: Arc<AuthManager>,
    client_id: &str,
    label: &str,
    llm_manager: Arc<Mutex<LlmManager>>,
    config: Arc<HostConfig>,
) {
    let rtc_conn = {
        let map = peer_map.lock().await;
        match map.get(client_id) {
            Some(conn) => Arc::clone(conn),
            None => {
                crate::elog!("CRITICAL: Link to {} severed.", client_id);
                return;
            }
        }
    };

    // Fast-path: check for binary frame magic byte BEFORE allocating a String copy.
    // Binary uploads on frankn_fs use [0x01][36-byte ID][data] framing.
    if data.len() >= 37 && data[0] == 0x01 && label == "frankn_fs" {
        let ctx = CommandContext::new(
            String::new(),
            client_id.to_string(),
            label.to_string(),
            Arc::clone(&config),
            Arc::clone(&rtc_conn),
        );
        parse_binary_msg(data, &ctx).await;
        return;
    }

    let text = match String::from_utf8(data.clone()) {
        Ok(t) => t,
        Err(_) => {
            // Not valid UTF-8 and not a binary frame — drop silently.
            return;
        }
    };

    match serde_json::from_str::<ClientMessage>(&text) {
        Ok(msg) => match msg {
            ClientMessage::AuthRequest => {
                crate::log!("CHALLENGE: Generating for client...");
                let challenge = auth_manager.generate_challenge();
                {
                    let conn = rtc_conn.lock().await;
                    let mut current_challenge = conn.current_challenge.lock().await;
                    *current_challenge = Some(challenge.clone());
                }
                let response = HostMessage::Challenge {
                    challenge,
                    salt: auth_manager.salt.clone(),
                    timestamp: get_timestamp(),
                };
                if let Ok(json) = serde_json::to_string(&response) {
                    let conn = rtc_conn.lock().await;
                    let _ = conn.send_message(label, &Bytes::from(json)).await;
                }
            }
            ClientMessage::AuthResponse { response, .. } => {
                let expected_challenge = {
                    let conn = rtc_conn.lock().await;
                    let mut challenge_lock = conn.current_challenge.lock().await;
                    challenge_lock.take()
                };
                if let Some(expected) = expected_challenge {
                    if let Some(token) = auth_manager.verify_response(&expected, &response).await {
                        crate::log!("AUTH: Success for client {}.", client_id);
                        {
                            let conn = rtc_conn.lock().await;
                            let mut auth_lock = conn.authenticated.lock().await;
                            *auth_lock = true;
                        }
                        let home_dir = dirs::home_dir()
                            .map(|p| p.to_string_lossy().to_string())
                            .unwrap_or_else(|| "/home/".to_string());
                        let res = HostMessage::AuthSuccess {
                            token,
                            home_dir,
                            timestamp: get_timestamp(),
                        };
                        if let Ok(json) = serde_json::to_string(&res) {
                            let conn = rtc_conn.lock().await;
                            let _ = conn.send_message(label, &Bytes::from(json)).await;
                        }

                        // Send capability manifest inventory immediately after pairing
                        let registry = crate::capabilities::registry::CapabilityRegistry::new();
                        let inventory = HostMessage::CapabilitiesInventory {
                            capabilities: registry.list(),
                            timestamp: get_timestamp(),
                        };
                        if let Ok(json) = serde_json::to_string(&inventory) {
                            let conn = rtc_conn.lock().await;
                            let _ = conn.send_message(label, &Bytes::from(json)).await;
                        }
                    } else {
                        crate::elog!("AUTH: Failure for client {}.", client_id);
                        let res = HostMessage::AuthFailed {
                            error: "Credentials rejected.".to_string(),
                            timestamp: get_timestamp(),
                        };
                        if let Ok(json) = serde_json::to_string(&res) {
                            let conn = rtc_conn.lock().await;
                            let _ = conn.send_message(label, &Bytes::from(json)).await;
                        }
                    }
                }
            }

            // ── New resume-aware transfer protocol ──
            ClientMessage::TransferInit {
                id,
                path,
                hash,
                total_size,
                resume_offset,
                ..
            } => {
                let ctx = CommandContext::new(
                    id,
                    client_id.to_string(),
                    label.to_string(),
                    Arc::clone(&config),
                    Arc::clone(&rtc_conn),
                );
                crate::capabilities::fs::transfer::handle_transfer_init(
                    &ctx,
                    &path,
                    hash,
                    total_size,
                    resume_offset,
                )
                .await;
            }

            ClientMessage::TransferCancel { id, .. } => {
                crate::log!("FS: Transfer cancel for {}", id);
                let ctx = CommandContext::new(
                    id,
                    client_id.to_string(),
                    label.to_string(),
                    Arc::clone(&config),
                    Arc::clone(&rtc_conn),
                );
                let resp = crate::capabilities::fs::transfer::handle_transfer_cancel(&ctx.id).await;
                let _ = ctx.stream(resp).await;
            }

            ClientMessage::DownloadInit {
                id,
                path,
                resume_offset,
                ..
            } => {
                let ctx = CommandContext::new(
                    id,
                    client_id.to_string(),
                    label.to_string(),
                    Arc::clone(&config),
                    Arc::clone(&rtc_conn),
                );
                crate::capabilities::fs::transfer::handle_download_init(
                    ctx,
                    &path,
                    resume_offset,
                )
                .await;
            }

            ClientMessage::ClientGenMsg {
                id,
                command,
                auth_token,
                ..
            } => {
                let is_auth = {
                    let conn = rtc_conn.lock().await;
                    let auth_lock = conn.authenticated.lock().await;
                    *auth_lock
                };
                if is_auth && auth_manager.verify_token(&auth_token).await {
                    if let Some(response) = router::DcMsg::parse_msg(
                        &id,
                        &command,
                        Arc::clone(&peer_map),
                        client_id,
                        label,
                        Arc::clone(&llm_manager),
                        Arc::clone(&config),
                    )
                    .await {
                        if let Ok(json) = serde_json::to_string(&response) {
                            let rtc_clone = Arc::clone(&rtc_conn);
                            let label_clone = label.to_string();
                            tokio::spawn(async move {
                                let conn = rtc_clone.lock().await;
                                let _ = conn.send_message(&label_clone, &Bytes::from(json)).await;
                            });
                        }
                    }
                } else {
                    crate::elog!("EXEC: Permission denied for command {} (ID: {})", id, id);
                    let res = HostMessage::Response {
                        id,
                        status: Status::Error("Access Denied.".into()),
                        data: None,
                        timestamp: get_timestamp(),
                    };
                    if let Ok(json) = serde_json::to_string(&res) {
                        let conn = rtc_conn.lock().await;
                        let _ = conn.send_message(label, &Bytes::from(json)).await;
                    }
                }
            }
        },
        Err(e) => {
            crate::elog!("NODE: Protocol Error - Failed to parse DC message: {e}");
            crate::elog!("NODE: Raw payload was: {text}");
        }
    }
}

pub async fn parse_binary_msg(data: &Vec<u8>, ctx: &CommandContext) {
    if ctx.label == "frankn_fs"
        && data.len() >= crate::capabilities::fs::transfer::FRAME_HEADER_SIZE
        && data[0] == 0x01
    {
        crate::capabilities::fs::transfer::handle_transfer_chunk_raw(data, ctx).await;
    }
}
