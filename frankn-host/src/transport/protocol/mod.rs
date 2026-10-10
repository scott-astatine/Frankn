pub mod messages;
pub mod node;
pub mod router;

pub use messages::{ClientMessage, HostMessage, Status};

use crate::auth::AuthManager;
use crate::capabilities::inference::LlmManager;
use crate::config::HostConfig;
use crate::signaling::SignalingClient;
use crate::transport::context::CommandContext;
use crate::transport::webrtc::connection::{PeerMap, RTCConn};
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
    pub allowed_clients: Arc<Mutex<Vec<String>>>,
    pub signaling_client: Arc<SignalingClient>,
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
    let role = {
        let peer = session.lock().await;
        *peer.role.lock().await
    };

    // Fast-path: check for binary frame magic byte BEFORE allocating a String copy.
    // Binary uploads on frankn_fs use [0x01][36-byte ID][data] framing.
    if data.len() >= 37 && data[0] == 0x01 && label == "frankn_fs" {
        if role != crate::transport::webrtc::connection::PeerRole::AuthenticatedClient {
            crate::elog!(
                "SECURITY: Rejected file-transfer frame from peer {}",
                client_id
            );
            return;
        }
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
        Ok(msg) => {
            if !message_allowed_for_role(role, &msg) {
                crate::elog!(
                    "SECURITY: Rejected {} from peer {} with role {:?}",
                    client_message_kind(&msg),
                    client_id,
                    role
                );
                return;
            }
            match msg {
                ClientMessage::AuthRequest | ClientMessage::AuthResponse { .. } => {
                    send_auth_failed(
                        &rtc_conn,
                        label,
                        "Client update required for OPAQUE authentication.",
                    )
                    .await;
                }
                ClientMessage::AuthOpaqueStart {
                    attempt_id,
                    request,
                } => {
                    let decoded = base64::Engine::decode(
                        &base64::engine::general_purpose::URL_SAFE_NO_PAD,
                        request,
                    );
                    let owner_scope = session.lock().await.session_id.clone();
                    let result = match decoded {
                        Ok(request) => {
                            ctx.auth_manager
                                .begin_opaque_login(
                                    &owner_scope,
                                    &attempt_id,
                                    client_id,
                                    &ctx.config.host_id,
                                    &request,
                                )
                                .await
                        }
                        Err(_) => Err("Authentication failed".to_string()),
                    };
                    match result {
                        Ok(response) => {
                            let message = HostMessage::AuthOpaqueResponse {
                                attempt_id,
                                response: base64::Engine::encode(
                                    &base64::engine::general_purpose::URL_SAFE_NO_PAD,
                                    response,
                                ),
                                timestamp: get_timestamp(),
                            };
                            send_host_message(&rtc_conn, label, &message).await;
                            crate::log!("[AUTH] OPAQUE exchange started for client {}.", client_id);
                        }
                        Err(_) => {
                            send_auth_failed(&rtc_conn, label, "Authentication failed.").await;
                            crate::elog!(
                                "[AUTH] OPAQUE exchange could not start for client {}.",
                                client_id
                            );
                        }
                    }
                }
                ClientMessage::AuthOpaqueFinish {
                    attempt_id,
                    finalization,
                } => {
                    let decoded = base64::Engine::decode(
                        &base64::engine::general_purpose::URL_SAFE_NO_PAD,
                        finalization,
                    );
                    let owner_scope = session.lock().await.session_id.clone();
                    let result = match decoded {
                        Ok(finalization) => {
                            ctx.auth_manager
                                .finish_opaque_login(
                                    &owner_scope,
                                    &attempt_id,
                                    client_id,
                                    &ctx.config.host_id,
                                    &finalization,
                                )
                                .await
                        }
                        Err(_) => Err("Authentication failed".to_string()),
                    };
                    match result {
                        Ok(token) => {
                            complete_authenticated_client(
                                &ctx,
                                &session,
                                &rtc_conn,
                                label,
                                client_id,
                                &attempt_id,
                                token,
                            )
                            .await;
                        }
                        Err(_) => {
                            send_auth_failed(&rtc_conn, label, "Authentication failed.").await;
                            crate::elog!("[AUTH] OPAQUE proof rejected for client {}.", client_id);
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
                        crate::capabilities::fs::transfer::handle_transfer_cancel(&cmd_ctx.id)
                            .await;
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
                    let is_auth =
                        role == crate::transport::webrtc::connection::PeerRole::AuthenticatedClient;
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
                        client_id,
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
                    node::handle_heartbeat(client_id, &node_id, &ctx.node_registry).await;
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
                        client_id,
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
                        client_id,
                        capability_id,
                        session_id,
                        &auth_token,
                        &ctx.auth_manager,
                        &ctx.node_registry,
                        &ctx.capability_sessions,
                    )
                    .await;
                }
            }
        }
        Err(e) => {
            crate::elog!("NODE: Protocol Error - Failed to parse DC message: {e}");
        }
    }
}

fn message_allowed_for_role(
    role: crate::transport::webrtc::connection::PeerRole,
    message: &ClientMessage,
) -> bool {
    use crate::transport::webrtc::connection::PeerRole;
    match role {
        PeerRole::UnauthenticatedClient => matches!(
            message,
            ClientMessage::AuthRequest
                | ClientMessage::AuthResponse { .. }
                | ClientMessage::AuthOpaqueStart { .. }
                | ClientMessage::AuthOpaqueFinish { .. }
        ),
        PeerRole::AuthenticatedClient => matches!(
            message,
            ClientMessage::ClientGenMsg { .. }
                | ClientMessage::TransferInit { .. }
                | ClientMessage::TransferCancel { .. }
                | ClientMessage::DownloadInit { .. }
                | ClientMessage::ActivateCapability { .. }
                | ClientMessage::DeactivateCapability { .. }
        ),
        PeerRole::Node => matches!(
            message,
            ClientMessage::NodeRegister { .. }
                | ClientMessage::NodeHeartbeat { .. }
                | ClientMessage::NodeSignal { .. }
                | ClientMessage::NodeActivationStatus { .. }
        ),
        PeerRole::TrustedHostInternal => false,
    }
}

fn client_message_kind(message: &ClientMessage) -> &'static str {
    match message {
        ClientMessage::AuthRequest => "auth_request",
        ClientMessage::AuthResponse { .. } => "auth_response",
        ClientMessage::AuthOpaqueStart { .. } => "auth_opaque_start",
        ClientMessage::AuthOpaqueFinish { .. } => "auth_opaque_finish",
        ClientMessage::ClientGenMsg { .. } => "dc_msg",
        ClientMessage::TransferInit { .. } => "transfer_init",
        ClientMessage::TransferCancel { .. } => "transfer_cancel",
        ClientMessage::DownloadInit { .. } => "download_init",
        ClientMessage::NodeRegister { .. } => "node_register",
        ClientMessage::NodeHeartbeat { .. } => "node_heartbeat",
        ClientMessage::NodeSignal { .. } => "node_signal",
        ClientMessage::NodeActivationStatus { .. } => "node_activation_status",
        ClientMessage::ActivateCapability { .. } => "activate_capability",
        ClientMessage::DeactivateCapability { .. } => "deactivate_capability",
    }
}

async fn send_host_message(rtc_conn: &Arc<Mutex<RTCConn>>, label: &str, message: &HostMessage) {
    if let Ok(json) = serde_json::to_string(message) {
        let conn = rtc_conn.lock().await;
        let _ = conn.send_message(label, &Bytes::from(json)).await;
    }
}

async fn send_auth_failed(rtc_conn: &Arc<Mutex<RTCConn>>, label: &str, error: &str) {
    send_host_message(
        rtc_conn,
        label,
        &HostMessage::AuthFailed {
            error: error.to_string(),
            timestamp: get_timestamp(),
        },
    )
    .await;
}

async fn complete_authenticated_client(
    ctx: &ProtocolContext,
    session: &Arc<Mutex<crate::transport::webrtc::connection::PeerSession>>,
    rtc_conn: &Arc<Mutex<RTCConn>>,
    label: &str,
    client_id: &str,
    attempt_id: &str,
    token: String,
) {
    if !ctx.config.is_public {
        let mut acl = ctx.allowed_clients.lock().await;
        if !acl.iter().any(|id| id == client_id) {
            let mut updated_acl = acl.clone();
            updated_acl.push(client_id.to_string());
            if let Err(error) = ctx.config.persist_allowed_clients(&updated_acl).await {
                crate::elog!(
                    "PAIR: Could not persist client ACL for {}: {}",
                    client_id,
                    error
                );
                send_auth_failed(rtc_conn, label, "Could not save paired client.").await;
                ctx.auth_manager.revoke_token(&token).await;
                return;
            }
            if let Err(error) = ctx
                .signaling_client
                .update_host_acl(updated_acl.clone())
                .await
            {
                crate::elog!(
                    "PAIR: ACL saved locally; signaling update will retry after reconnect: {}",
                    error
                );
            }
            *acl = updated_acl;
            crate::log!("PAIR: Client {} added to private Host ACL.", client_id);
        }
    }

    {
        let sess = session.lock().await;
        *sess.role.lock().await =
            crate::transport::webrtc::connection::PeerRole::AuthenticatedClient;
    }
    crate::log!("AUTH: OPAQUE success for client {}.", client_id);
    let home_dir = dirs::home_dir()
        .map(|path| path.to_string_lossy().to_string())
        .unwrap_or_else(|| "/home/".to_string());
    send_host_message(
        rtc_conn,
        label,
        &HostMessage::AuthSuccess {
            attempt_id: attempt_id.to_string(),
            home_dir,
            timestamp: get_timestamp(),
        },
    )
    .await;

    let capabilities = ctx.capability_inventory.lock().await.list();
    send_host_message(
        rtc_conn,
        label,
        &HostMessage::CapabilitiesInventory {
            capabilities,
            timestamp: get_timestamp(),
        },
    )
    .await;
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
            let role = *s.role.lock().await;
            if role == crate::transport::webrtc::connection::PeerRole::AuthenticatedClient {
                let conn = s.conn.lock().await;
                let _ = conn
                    .send_message("frankn_cmd", &Bytes::from(json.clone()))
                    .await;
            }
        }
    }
}
