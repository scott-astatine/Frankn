use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::Mutex;
use tokio_tungstenite::tungstenite::Bytes;

use crate::auth::AuthManager;
use crate::config::HostConfig;
use crate::capabilities::node::registry::{
    NodeRegistry, CapabilitySessionRegistry, CapabilitySession, CapabilitySessionStatus, NodeInfo,
};
use crate::capabilities::registry::{
    CapabilityDescriptor, CapabilityInventory, CapabilityInventoryEntry, CapabilityProvider,
};
use crate::signaling::SignalingMessage;
use crate::transport::webrtc::connection::{PeerMap, RTCConn};
use crate::transport::protocol::{HostMessage, Status};
use crate::utils::get_timestamp;

/// Handle a NodeRegister message: verify the node is allowed, store it in the
/// NodeRegistry, register its capabilities in the inventory, and ack.
pub async fn handle_register(
    node_id: &str,
    display_name: &str,
    capabilities: &[CapabilityDescriptor],
    rtc_conn: &Arc<Mutex<RTCConn>>,
    label: &str,
    config: &Arc<HostConfig>,
    node_registry: &Arc<Mutex<NodeRegistry>>,
    capability_inventory: &Arc<Mutex<CapabilityInventory>>,
) {
    let is_allowed = config.allowed_nodes.contains(&node_id.to_string());
    if is_allowed {
        let node_info = NodeInfo {
            node_id: node_id.to_string(),
            display_name: display_name.to_string(),
            capabilities: capabilities.to_vec(),
            authenticated: true,
            rtc_conn: Arc::clone(rtc_conn),
            last_seen: std::time::Instant::now(),
        };
        {
            let mut nr = node_registry.lock().await;
            nr.register(node_info);
        }
        {
            let mut ci = capability_inventory.lock().await;
            for cap in capabilities {
                ci.register(CapabilityInventoryEntry {
                    descriptor: cap.clone(),
                    provider: CapabilityProvider {
                        kind: "node".to_string(),
                        provider_id: node_id.to_string(),
                    },
                    availability: "available".to_string(),
                });
            }
        }
        let response = HostMessage::NodeRegisterAck {
            status: Status::Success,
            timestamp: get_timestamp(),
        };
        if let Ok(json) = serde_json::to_string(&response) {
            let conn = rtc_conn.lock().await;
            let _ = conn.send_message(label, &Bytes::from(json)).await;
        }
        crate::log!("NODE: Node '{}' ({}) successfully registered.", display_name, node_id);
    } else {
        let response = HostMessage::NodeRegisterAck {
            status: Status::Error("Unauthorized Node ID.".into()),
            timestamp: get_timestamp(),
        };
        if let Ok(json) = serde_json::to_string(&response) {
            let conn = rtc_conn.lock().await;
            let _ = conn.send_message(label, &Bytes::from(json)).await;
        }
        crate::elog!("NODE: Node '{}' ({}) pairing failed: unauthorized.", display_name, node_id);
    }
}

/// Handle a NodeHeartbeat message: update the node's last_seen timestamp.
pub async fn handle_heartbeat(
    node_id: &str,
    node_registry: &Arc<Mutex<NodeRegistry>>,
) {
    let mut nr = node_registry.lock().await;
    nr.update_heartbeat(node_id);
}

/// Handle a NodeSignal message: validate ownership, then forward the signal
/// between the correct Client and Node via the Host.
pub async fn handle_signal(
    sender_id: &str,
    session_id: String,
    signal: SignalingMessage,
    peer_map: &PeerMap,
    node_registry: &Arc<Mutex<NodeRegistry>>,
    capability_sessions: &Arc<Mutex<CapabilitySessionRegistry>>,
) {
    let session_info = {
        let cs = capability_sessions.lock().await;
        cs.get(&session_id).cloned()
    };

    if let Some(sess) = session_info {
        let is_node = {
            let nr = node_registry.lock().await;
            nr.get(sender_id).is_some()
        };

        if is_node {
            // Node -> Host (forward to Client)
            if sess.node_id != sender_id {
                crate::elog!("SECURITY: Node '{}' tried to signal session '{}' owned by Node '{}'",
                    sender_id, session_id, sess.node_id);
                return;
            }

            let client_conn = {
                let map = peer_map.lock().await;
                map.get(&sess.client_id).cloned()
            };

            if let Some(conn) = client_conn {
                let response = HostMessage::HostSignal {
                    client_id: sender_id.to_string(),
                    session_id,
                    signal,
                };
                if let Ok(json) = serde_json::to_string(&response) {
                    let sess_lock = conn.lock().await;
                    let r_conn = sess_lock.conn.lock().await;
                    let _ = r_conn.send_message("frankn_cmd", &Bytes::from(json)).await;
                }
            }
        } else {
            // Client -> Host (forward to Node)
            if sess.client_id != sender_id {
                crate::elog!("SECURITY: Client '{}' tried to signal session '{}' owned by Client '{}'",
                    sender_id, session_id, sess.client_id);
                return;
            }

            let node_conn = {
                let nr = node_registry.lock().await;
                nr.get(&sess.node_id).map(|n| Arc::clone(&n.rtc_conn))
            };

            if let Some(nc) = node_conn {
                let response = HostMessage::HostSignal {
                    client_id: sender_id.to_string(),
                    session_id,
                    signal,
                };
                if let Ok(json) = serde_json::to_string(&response) {
                    let conn = nc.lock().await;
                    let _ = conn.send_message("frankn_node_control", &Bytes::from(json)).await;
                }
            }
        }
    } else {
        crate::elog!("NODE: Signaling received for unknown session '{}'", session_id);
    }
}

/// Handle a NodeActivationStatus message: update the session state and forward
/// the status to the requesting client.
pub async fn handle_activation_status(
    capability_id: String,
    session_id: String,
    status: CapabilitySessionStatus,
    error: Option<String>,
    peer_map: &PeerMap,
    capability_sessions: &Arc<Mutex<CapabilitySessionRegistry>>,
) {
    crate::log!("NODE: Activation status for capability '{}' in session '{}': {:?} (error: {:?})",
        capability_id, session_id, status, error);

    let client_id = {
        let mut cs = capability_sessions.lock().await;
        if let Some(sess) = cs.get_mut(&session_id) {
            sess.status = status;
            sess.error = error.clone();
            Some(sess.client_id.clone())
        } else {
            None
        }
    };

    // Forward the activation status to the client
    if let Some(cid) = client_id {
        let client_session = {
            let map = peer_map.lock().await;
            map.get(&cid).cloned()
        };

        if let Some(csess) = client_session {
            let response = HostMessage::CapabilityActivationStatus {
                capability_id,
                session_id,
                status,
                error,
                timestamp: get_timestamp(),
            };
            if let Ok(json) = serde_json::to_string(&response) {
                let sess = csess.lock().await;
                let conn = sess.conn.lock().await;
                let _ = conn.send_message("frankn_cmd", &Bytes::from(json)).await;
            }
        }
    }
}

/// Handle an ActivateCapability message from a Client: resolve the provider,
/// create a session record, and forward the activation request to the Node.
pub async fn handle_activate_capability(
    client_id: &str,
    capability_id: String,
    session_id: String,
    provider_id: Option<String>,
    properties: HashMap<String, serde_json::Value>,
    auth_token: &str,
    rtc_conn: &Arc<Mutex<RTCConn>>,
    label: &str,
    auth_manager: &Arc<AuthManager>,
    node_registry: &Arc<Mutex<NodeRegistry>>,
    capability_sessions: &Arc<Mutex<CapabilitySessionRegistry>>,
) {
    if auth_manager.verify_token(auth_token).await {
        let target_node_id = if let Some(pid) = provider_id {
            pid
        } else {
            let nr = node_registry.lock().await;
            if let Some(node) = nr.list().iter().find(|n| {
                n.capabilities.iter().any(|c| c.id == capability_id)
            }) {
                node.node_id.clone()
            } else {
                String::new()
            }
        };

        if target_node_id.is_empty() {
            let response = HostMessage::CapabilityActivationStatus {
                capability_id,
                session_id,
                status: CapabilitySessionStatus::Failed,
                error: Some("No online provider found for capability".to_string()),
                timestamp: get_timestamp(),
            };
            if let Ok(json) = serde_json::to_string(&response) {
                let conn = rtc_conn.lock().await;
                let _ = conn.send_message(label, &Bytes::from(json)).await;
            }
            return;
        }

        let node_conn = {
            let nr = node_registry.lock().await;
            nr.get(&target_node_id).map(|n| Arc::clone(&n.rtc_conn))
        };

        if let Some(nc) = node_conn {
            {
                let mut cs = capability_sessions.lock().await;
                cs.register(CapabilitySession {
                    session_id: session_id.clone(),
                    client_id: client_id.to_string(),
                    capability_id: capability_id.clone(),
                    node_id: target_node_id.clone(),
                    status: CapabilitySessionStatus::Pending,
                    error: None,
                });
            }

            let msg = HostMessage::NodeActivateCapability {
                capability_id,
                session_id,
                client_id: client_id.to_string(),
                properties,
                timestamp: get_timestamp(),
            };
            if let Ok(json) = serde_json::to_string(&msg) {
                let conn = nc.lock().await;
                let _ = conn.send_message("frankn_node_control", &Bytes::from(json)).await;
            }
        } else {
            let response = HostMessage::CapabilityActivationStatus {
                capability_id,
                session_id,
                status: CapabilitySessionStatus::Failed,
                error: Some("Provider offline".to_string()),
                timestamp: get_timestamp(),
            };
            if let Ok(json) = serde_json::to_string(&response) {
                let conn = rtc_conn.lock().await;
                let _ = conn.send_message(label, &Bytes::from(json)).await;
            }
        }
    } else {
        let response = HostMessage::CapabilityActivationStatus {
            capability_id,
            session_id,
            status: CapabilitySessionStatus::Failed,
            error: Some("Access Denied.".to_string()),
            timestamp: get_timestamp(),
        };
        if let Ok(json) = serde_json::to_string(&response) {
            let conn = rtc_conn.lock().await;
            let _ = conn.send_message(label, &Bytes::from(json)).await;
        }
    }
}

/// Handle a DeactivateCapability message from a Client: look up the session,
/// find the node, and forward the deactivation request.
pub async fn handle_deactivate_capability(
    capability_id: String,
    session_id: String,
    auth_token: &str,
    auth_manager: &Arc<AuthManager>,
    node_registry: &Arc<Mutex<NodeRegistry>>,
    capability_sessions: &Arc<Mutex<CapabilitySessionRegistry>>,
) {
    if auth_manager.verify_token(auth_token).await {
        let sess_info = {
            let cs = capability_sessions.lock().await;
            cs.get(&session_id).cloned()
        };

        if let Some(sess) = sess_info {
            let node_conn = {
                let nr = node_registry.lock().await;
                nr.get(&sess.node_id).map(|n| Arc::clone(&n.rtc_conn))
            };

            if let Some(nc) = node_conn {
                let msg = HostMessage::NodeDeactivateCapability {
                    capability_id,
                    session_id,
                    timestamp: get_timestamp(),
                };
                if let Ok(json) = serde_json::to_string(&msg) {
                    let conn = nc.lock().await;
                    let _ = conn.send_message("frankn_node_control", &Bytes::from(json)).await;
                }
            }
        }
    }
}
