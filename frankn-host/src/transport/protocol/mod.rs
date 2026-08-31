pub mod messages;
pub mod node;
pub mod router;

pub use messages::{ClientMessage, HostMessage, Status};

use crate::auth::AuthManager;
use crate::capabilities::inference::LlmManager;
use crate::config::HostConfig;
use crate::transport::context::CommandContext;
use crate::transport::webrtc::connection::PeerMap;
use crate::utils::get_timestamp;
use std::sync::Arc;
use tokio::sync::Mutex;
use tokio_tungstenite::tungstenite::Bytes;

/// Shared state passed to all protocol message handlers.
pub struct ProtocolContext {
    pub peer_map: PeerMap,
    pub auth_manager: Arc<AuthManager>,
    pub llm_manager: Arc<Mutex<LlmManager>>,
    pub config: Arc<HostConfig>,
    pub node_registry: Arc<Mutex<crate::capabilities::node::registry::NodeRegistry>>,
    pub capability_inventory: Arc<Mutex<crate::capabilities::registry::CapabilityInventory>>,
    pub capability_sessions:
        Arc<Mutex<crate::capabilities::node::registry::CapabilitySessionRegistry>>,
}

/// Decode a text data channel message and route it to the appropriate capability handler.
pub async fn parse_dc_msg(data: &Vec<u8>, ctx: &ProtocolContext, client_id: &str, label: &str) {
    let session = {
        let map = ctx.peer_map.lock().await;
        match map.get(client_id) {
            Some(s) => Arc::clone(s),
            None => {
                crate::elog!("CRITICAL: Link to {} severed.", client_id);
                return;
            }
        }
    };
    let rtc_conn = {
        let s = session.lock().await;
        Arc::clone(&s.conn)
    };

    // Fast-path: check for binary frame magic byte BEFORE allocating a String copy.
    // Binary uploads on frankn_fs use [0x01][36-byte ID][data] framing.
    if data.len() >= 37 && data[0] == 0x01 && label == "frankn_fs" {
        let cmd_ctx = CommandContext::new(
            String::new(),
            client_id.to_string(),
            label.to_string(),
            Arc::clone(&ctx.config),
            Arc::clone(&session),
        );
        parse_binary_msg(data, &cmd_ctx).await;
        return;
    }

    let text = match String::from_utf8(data.clone()) {
        Ok(t) => t,
        Err(_) => {
            crate::elog!("PROTOCOL: Non-UTF8 payload received.");
            return;
        }
    };

    match serde_json::from_str::<ClientMessage>(&text) {
        Ok(msg) => match msg {
            ClientMessage::AuthRequest => {
                let rx_start = std::time::Instant::now();
                crate::log!("[HOST_AUTH_DIAG] auth_request RX from client {}.", client_id);
                let gen_start = std::time::Instant::now();
                let challenge = ctx.auth_manager.generate_challenge();
                let gen_micros = gen_start.elapsed().as_micros();
                {
                    let sess = session.lock().await;
                    let mut current_challenge = sess.current_challenge.lock().await;
                    *current_challenge = Some(challenge.clone());
                }
                let response = HostMessage::Challenge {
                    challenge,
                    salt: ctx.auth_manager.salt.clone(),
                    timestamp: get_timestamp(),
                };
                if let Ok(json) = serde_json::to_string(&response) {
                    let conn = rtc_conn.lock().await;
                    let tx_start = std::time::Instant::now();
                    let _ = conn.send_message(label, &Bytes::from(json)).await;
                    crate::log!(
                        "[HOST_AUTH_DIAG] challenge TX sent to DataChannel (challenge gen: {} µs, send_message: {} µs, total: {} ms)",
                        gen_micros,
                        tx_start.elapsed().as_micros(),
                        rx_start.elapsed().as_millis()
                    );
                }
            }
            ClientMessage::AuthResponse { response, .. } => {
                let rx_start = std::time::Instant::now();
                crate::log!("[HOST_AUTH_DIAG] auth_response RX from client {}.", client_id);
                let expected_challenge = {
                    let sess = session.lock().await;
                    let mut challenge_lock = sess.current_challenge.lock().await;
                    challenge_lock.take()
                };
                if let Some(expected) = expected_challenge {
                    if let Some(token) =
                        ctx.auth_manager.verify_response(&expected, &response).await
                    {
                        crate::log!("AUTH: Success for client {}.", client_id);
                        {
                            let sess = session.lock().await;
                            let mut auth_lock = sess.authenticated.lock().await;
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
                            let tx_start = std::time::Instant::now();
                            let _ = conn.send_message(label, &Bytes::from(json)).await;
                            crate::log!("[HOST_AUTH_DIAG] auth_success TX sent to DataChannel (total host pipeline: {} ms, send_message: {} µs)", rx_start.elapsed().as_millis(), tx_start.elapsed().as_micros());
                        }

                        // Send capability manifest inventory immediately after pairing
                        let mut caps = Vec::new();
                        {
                            let ci = ctx.capability_inventory.lock().await;
                            for entry in ci.list() {
                                caps.push(entry);
                            }
                        }
                        let inventory = HostMessage::CapabilitiesInventory {
                            capabilities: caps,
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
                let cmd_ctx = CommandContext::new(
                    id,
                    client_id.to_string(),
                    label.to_string(),
                    Arc::clone(&ctx.config),
                    Arc::clone(&session),
                );
                crate::capabilities::fs::transfer::handle_transfer_init(
                    &cmd_ctx,
                    &path,
                    hash,
                    total_size,
                    resume_offset,
                )
                .await;
            }

            ClientMessage::TransferCancel { id, .. } => {
                crate::log!("FS: Transfer cancel for {}", id);
                let cmd_ctx = CommandContext::new(
                    id,
                    client_id.to_string(),
                    label.to_string(),
                    Arc::clone(&ctx.config),
                    Arc::clone(&session),
                );
                let resp =
                    crate::capabilities::fs::transfer::handle_transfer_cancel(&cmd_ctx.id).await;
                let _ = cmd_ctx.stream(resp).await;
            }

            ClientMessage::DownloadInit {
                id,
                path,
                resume_offset,
                ..
            } => {
                let cmd_ctx = CommandContext::new(
                    id,
                    client_id.to_string(),
                    label.to_string(),
                    Arc::clone(&ctx.config),
                    Arc::clone(&session),
                );
                crate::capabilities::fs::transfer::handle_download_init(
                    cmd_ctx,
                    &path,
                    resume_offset,
                )
                .await;
            }

            ClientMessage::ClientGenMsg {
                id,
                command,
                auth_token,
            } => {
                let is_auth = {
                    let sess = session.lock().await;
                    let auth_lock = sess.authenticated.lock().await;
                    *auth_lock
                };
                if is_auth && ctx.auth_manager.verify_token(&auth_token).await {
                    if let Some(response) = router::DcMsg::parse_msg(
                        &id,
                        &command,
                        Arc::clone(&ctx.peer_map),
                        client_id,
                        label,
                        Arc::clone(&ctx.llm_manager),
                        Arc::clone(&ctx.config),
                    )
                    .await
                    {
                        if let Ok(json) = serde_json::to_string(&response) {
                            let conn = rtc_conn.lock().await;
                            let _ = conn.send_message(label, &Bytes::from(json)).await;
                        }
                    }
                } else {
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

            // --- Node ↔ Host Control Messages ---
            ClientMessage::NodeRegister {
                node_id,
                display_name,
                capabilities,
                ..
            } => {
                node::handle_register(
                    &node_id,
                    &display_name,
                    &capabilities,
                    &rtc_conn,
                    label,
                    &ctx.config,
                    &ctx.node_registry,
                    &ctx.capability_inventory,
                    &ctx.peer_map,
                )
                .await;
            }

            ClientMessage::NodeHeartbeat { node_id, .. } => {
                node::handle_heartbeat(&node_id, &ctx.node_registry).await;
            }

            ClientMessage::NodeSignal {
                session_id, signal, ..
            } => {
                node::handle_signal(
                    client_id,
                    session_id,
                    signal,
                    &ctx.peer_map,
                    &ctx.node_registry,
                    &ctx.capability_sessions,
                )
                .await;
            }

            ClientMessage::NodeActivationStatus {
                capability_id,
                session_id,
                status,
                error,
                ..
            } => {
                node::handle_activation_status(
                    capability_id,
                    session_id,
                    status,
                    error,
                    &ctx.peer_map,
                    &ctx.capability_sessions,
                )
                .await;
            }

            ClientMessage::ActivateCapability {
                capability_id,
                session_id,
                provider_id,
                properties,
                auth_token,
                ..
            } => {
                node::handle_activate_capability(
                    client_id,
                    capability_id,
                    session_id,
                    provider_id,
                    properties,
                    &auth_token,
                    &rtc_conn,
                    label,
                    &ctx.auth_manager,
                    &ctx.node_registry,
                    &ctx.capability_sessions,
                )
                .await;
            }

            ClientMessage::DeactivateCapability {
                capability_id,
                session_id,
                auth_token,
                ..
            } => {
                node::handle_deactivate_capability(
                    capability_id,
                    session_id,
                    &auth_token,
                    &ctx.auth_manager,
                    &ctx.node_registry,
                    &ctx.capability_sessions,
                )
                .await;
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

pub async fn broadcast_capability_inventory(
    peer_map: &PeerMap,
    capability_inventory: &Arc<Mutex<crate::capabilities::registry::CapabilityInventory>>,
) {
    let mut entries = Vec::new();
    {
        let ci = capability_inventory.lock().await;
        for entry in ci.list() {
            entries.push(entry);
        }
    }
    let inventory = HostMessage::CapabilitiesInventory {
        capabilities: entries,
        timestamp: get_timestamp(),
    };
    if let Ok(json) = serde_json::to_string(&inventory) {
        let peers = peer_map.lock().await;
        for (_, session) in peers.iter() {
            let s = session.lock().await;
            let is_auth = *s.authenticated.lock().await;
            if is_auth {
                let conn = s.conn.lock().await;
                let _ = conn.send_message("frankn_cmd", &Bytes::from(json.clone())).await;
            }
        }
    }
}
