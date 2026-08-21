use std::sync::Arc;
use std::time::Duration;
use tokio::sync::Mutex;
use tokio_tungstenite::tungstenite::Bytes;
use webrtc::data_channel::data_channel_message::DataChannelMessage;
use webrtc::peer_connection::peer_connection_state::RTCPeerConnectionState;
use webrtc::peer_connection::sdp::session_description::RTCSessionDescription;

use crate::auth::AuthManager;
use crate::capabilities::inference::LlmManager;
use crate::config::HostConfig;
use crate::signaling::{SignalingClient, SignalingMessage};
use crate::transport::protocol::{ProtocolContext, parse_dc_msg};
use crate::transport::webrtc::connection::{PeerMap, RTCConn};

pub struct SessionManager {
    config: Arc<HostConfig>,
    auth_manager: Arc<AuthManager>,
    peer_map: PeerMap,
    llm_manager: Arc<Mutex<LlmManager>>,
    input_manager: Option<Arc<Mutex<crate::capabilities::input::InputManager>>>,
    pub node_registry: Arc<Mutex<crate::capabilities::node::registry::NodeRegistry>>,
    pub capability_inventory: Arc<Mutex<crate::capabilities::registry::CapabilityInventory>>,
    pub capability_sessions:
        Arc<Mutex<crate::capabilities::node::registry::CapabilitySessionRegistry>>,
}

impl SessionManager {
    pub fn new(
        config: Arc<HostConfig>,
        auth_manager: Arc<AuthManager>,
        peer_map: PeerMap,
        llm_manager: Arc<Mutex<LlmManager>>,
        input_manager: Option<Arc<Mutex<crate::capabilities::input::InputManager>>>,
        node_registry: Arc<Mutex<crate::capabilities::node::registry::NodeRegistry>>,
        capability_inventory: Arc<Mutex<crate::capabilities::registry::CapabilityInventory>>,
        capability_sessions: Arc<
            Mutex<crate::capabilities::node::registry::CapabilitySessionRegistry>,
        >,
    ) -> Self {
        Self {
            config,
            auth_manager,
            peer_map,
            llm_manager,
            input_manager,
            node_registry,
            capability_inventory,
            capability_sessions,
        }
    }

    pub async fn run_signaling_loop(self: Arc<Self>) -> Result<(), Box<dyn std::error::Error>> {
        loop {
            let signing_key = match self.config.get_identity_key() {
                Ok(k) => k,
                Err(e) => {
                    crate::elog!("NODE: Failed to load identity key: {e}");
                    tokio::time::sleep(Duration::from_secs(20)).await;
                    continue;
                }
            };

            let (signaling_client, mut signaling_rx) = match SignalingClient::connect(
                &self.config.signaling_url,
                signing_key,
                self.config.host_name.clone(),
                self.config.is_public,
                crate::signaling::PeerType::Host,
            )
            .await
            {
                Ok(c) => c,
                Err(e) => {
                    crate::elog!("NODE: Handshake with signaling server failed: {e}");
                    tokio::time::sleep(Duration::from_secs(20)).await;
                    continue;
                }
            };

            let signaling_client = Arc::new(signaling_client);

            while let Some(msg) = signaling_rx.recv().await {
                match msg {
                    SignalingMessage::RegisterSuccess { .. } => {
                        crate::log!("NODE: Connected to signaling server.");
                    }
                    SignalingMessage::RegisterFailure { error, .. } => {
                        crate::elog!("NODE: Handshake rejected: {}", error);
                        break;
                    }
                    SignalingMessage::Offer {
                        from,
                        sdp,
                        session_id,
                        ..
                    } => {
                        let manager = Arc::clone(&self);
                        let sig = Arc::clone(&signaling_client);
                        tokio::spawn(async move {
                            if let Err(e) = manager
                                .handle_new_connection(from, sdp, session_id, sig)
                                .await
                            {
                                crate::elog!("CORE: Handshake error: {e}");
                            }
                        });
                    }
                    SignalingMessage::IceCandidate {
                        from,
                        candidate,
                        sdp_mid,
                        sdp_m_line_index,
                        session_id,
                        ..
                    } => {
                        crate::log!("ICE_GATHER: Received remote ICE candidate: {}", candidate);
                        let manager = Arc::clone(&self);
                        tokio::spawn(async move {
                            manager
                                .handle_ice_candidate(
                                    from,
                                    candidate,
                                    sdp_mid,
                                    sdp_m_line_index,
                                    session_id,
                                )
                                .await;
                        });
                    }
                    _ => {}
                }
            }
            tokio::time::sleep(Duration::from_secs(5)).await;
        }
    }

    pub async fn handle_ice_candidate(
        &self,
        from: String,
        candidate: String,
        sdp_mid: Option<String>,
        sdp_m_line_index: Option<u16>,
        session_id: String,
    ) {
        let map = self.peer_map.lock().await;
        if let Some(rtc_conn) = map.get(&from) {
            let sess = rtc_conn.lock().await;
            let active_sid = sess.session_id.clone();
            if active_sid != session_id {
                crate::log!(
                    "ICE_GATHER: Discarding stale remote candidate due to mismatched session ID ({:?} vs {:?})",
                    session_id,
                    active_sid
                );
                return;
            }
            let conn = sess.conn.lock().await;
            if let Err(e) = conn
                .add_remote_candidate(candidate, sdp_mid, sdp_m_line_index)
                .await
            {
                crate::elog!("Failed to add remote candidate: {}", e);
            }
        }
    }

    pub async fn handle_new_connection(
        &self,
        client_id: String,
        sdp_offer: String,
        session_id: String,
        signaling_client: Arc<SignalingClient>,
    ) -> Result<(), String> {
        let _peer_type = if self.config.allowed_nodes.contains(&client_id) {
            crate::transport::webrtc::connection::PeerRole::Node
        } else {
            crate::transport::webrtc::connection::PeerRole::Client
        };
        let rtc_conn = Arc::new(Mutex::new(
            RTCConn::new(crate::transport::webrtc::connection::RtcRole::Answerer)
                .await
                .map_err(|e| e.to_string())?,
        ));

        // Store the handshake session ID on the connection object
        {
            let conn = rtc_conn.lock().await;
            let mut active_sid = conn.session_id.lock().await;
            *active_sid = Some(session_id.clone());
        }

        let session = Arc::new(Mutex::new(
            crate::transport::webrtc::connection::PeerSession::new(
                client_id.clone(),
                session_id.clone(),
                Arc::clone(&rtc_conn),
            ),
        ));

        // Manage sessions
        {
            let mut map = self.peer_map.lock().await;
            if let Some(existing) = map.remove(&client_id) {
                crate::log!("UPLINK: Replacing active session for {}.", client_id);

                // If the reconnecting peer is a known Node, clean up its old state
                {
                    let mut nr = self.node_registry.lock().await;
                    if nr.get(&client_id).is_some() {
                        crate::log!(
                            "NODE: Node '{}' is reconnecting. Cleaning up old state.",
                            client_id
                        );

                        // Close all capability sessions belonging to this node
                        let mut cs = self.capability_sessions.lock().await;
                        let sessions_to_close: Vec<_> = cs
                            .list()
                            .into_iter()
                            .filter(|s| s.node_id == client_id)
                            .collect();
                        for mut sess in sessions_to_close {
                            crate::log!(
                                "NODE: Closing stale capability session '{}' for reconnecting node.",
                                sess.session_id
                            );
                            sess.status = crate::capabilities::node::registry::CapabilitySessionStatus::Closed;
                            cs.register(sess);
                        }

                        // Remove old provider entries from capability inventory
                        let mut ci = self.capability_inventory.lock().await;
                        ci.unregister_by_provider("node", &client_id);

                        // Unregister the old node entry
                        nr.unregister(&client_id);
                    }
                }

                let sess = existing.lock().await;
                let _ = sess.close().await;
            }
            map.insert(client_id.clone(), Arc::clone(&session));
            crate::log!("UPLINK: Session established for {}.", client_id);
        }

        // Send ICE to Client
        {
            let r_conn = rtc_conn.lock().await;
            let sig = Arc::clone(&signaling_client);
            let cid = client_id.clone();
            r_conn.on_ice_candidate(move |candidate| {
                if let Some(c) = candidate {
                    let sig_cl = Arc::clone(&sig);
                    let cid_cl = cid.clone();
                    tokio::spawn(async move {
                        if let Ok(init) = c.to_json() {
                            crate::log!(
                                "ICE_GATHER: Generated local ICE candidate: {}",
                                init.candidate
                            );
                            let _ = sig_cl
                                .send_ice_candidate(
                                    &cid_cl,
                                    init.candidate,
                                    init.sdp_mid,
                                    init.sdp_mline_index,
                                )
                                .await;
                        }
                    });
                }
            });
        }

        let auth_manager_clone = Arc::clone(&self.auth_manager);
        let peer_map_clone = Arc::clone(&self.peer_map);
        let client_id_clone = client_id.clone();
        let llm_manager_clone = Arc::clone(&self.llm_manager);
        let input_manager_clone = self.input_manager.clone();
        let config_clone = Arc::clone(&self.config);
        let node_registry_clone = Arc::clone(&self.node_registry);
        let capability_inventory_clone = Arc::clone(&self.capability_inventory);
        let capability_sessions_clone = Arc::clone(&self.capability_sessions);

        {
            let conn = rtc_conn.lock().await;
            conn.set_remote_data_channel_handler(move |dc| {
                let label = dc.label().to_owned();
                let pm = Arc::clone(&peer_map_clone);
                let auth = Arc::clone(&auth_manager_clone);
                let cid = client_id_clone.clone();
                let llm = Arc::clone(&llm_manager_clone);
                let im = input_manager_clone.clone();
                let cfg = Arc::clone(&config_clone);
                let nr = Arc::clone(&node_registry_clone);
                let ci = Arc::clone(&capability_inventory_clone);
                let cs = Arc::clone(&capability_sessions_clone);

                match label.as_str() {
                    "frankn_ssh" => {
                        crate::log!("LINK: Data channel 'frankn_ssh' initialized.");
                    }
                    "frankn_input" => {
                        let im_c = im.clone();
                        dc.on_message(Box::new(move |msg| {
                            let im_c2 = im_c.clone();
                            Box::pin(async move {
                                if let Ok(input_msg) = serde_json::from_slice::<
                                    crate::capabilities::input::InputMsg,
                                >(&msg.data)
                                    && let Some(manager) = im_c2
                                {
                                    let mut m = manager.lock().await;
                                    m.handle_msg(input_msg);
                                }
                            })
                        }));
                    }
                    "frankn_cmd"
                    | "frankn_fs"
                    | "frankn_media"
                    | "dohee_x"
                    | "frankn_node_control" => {
                        let channel_label = label.clone();
                        let proto_ctx = Arc::new(ProtocolContext {
                            peer_map: Arc::clone(&pm),
                            auth_manager: Arc::clone(&auth),
                            llm_manager: Arc::clone(&llm),
                            config: Arc::clone(&cfg),
                            node_registry: Arc::clone(&nr),
                            capability_inventory: Arc::clone(&ci),
                            capability_sessions: Arc::clone(&cs),
                        });
                        dc.on_message(Box::new(move |msg: DataChannelMessage| {
                            let d = msg.data.to_vec();
                            let l = channel_label.clone();
                            let c = cid.clone();
                            let pctx = Arc::clone(&proto_ctx);
                            Box::pin(async move { parse_dc_msg(&d, &pctx, &c, &l).await })
                        }));
                    }
                    _ => {}
                };
            })
            .await;
        }

        let handshake_res = async {
            let offer = RTCSessionDescription::offer(sdp_offer).map_err(|e| e.to_string())?;
            let answer = {
                let conn = rtc_conn.lock().await;
                conn.set_remote_description(offer)
                    .await
                    .map_err(|e| e.to_string())?;
                conn.create_answer().await.map_err(|e| e.to_string())?
            };

            signaling_client
                .send_answer(&client_id, answer.sdp)
                .await
                .map_err(|e| e.to_string())?;
            Ok::<(), String>(())
        }
        .await;

        if let Err(e) = handshake_res {
            crate::elog!("CORE: Handshake failed for client {}: {}", client_id, e);
            {
                let mut map = self.peer_map.lock().await;
                if let Some(current) = map.get(&client_id) {
                    let current_conn = {
                        let s = current.lock().await;
                        Arc::clone(&s.conn)
                    };
                    if Arc::ptr_eq(&current_conn, &rtc_conn) {
                        map.remove(&client_id);
                    }
                }
            }
            let conn = rtc_conn.lock().await;
            let _ = conn.close().await;
            return Err(e);
        }

        let (tx, mut rx) = tokio::sync::mpsc::channel(1);
        {
            let conn = rtc_conn.lock().await;
            conn.on_peer_connection_state_change(move |state| {
                if state == RTCPeerConnectionState::Closed
                    || state == RTCPeerConnectionState::Failed
                {
                    let _ = tx.try_send(());
                }
            });
        }

        let current_state = {
            let conn = rtc_conn.lock().await;
            conn.peer_connection.connection_state()
        };
        if current_state != RTCPeerConnectionState::Closed
            && current_state != RTCPeerConnectionState::Failed
        {
            let _ = rx.recv().await;
        }

        {
            let mut map = self.peer_map.lock().await;
            if let Some(current) = map.get(&client_id) {
                let current_conn = {
                    let s = current.lock().await;
                    Arc::clone(&s.conn)
                };
                if Arc::ptr_eq(&current_conn, &rtc_conn) {
                    map.remove(&client_id);
                }
            }
        }

        {
            let conn = rtc_conn.lock().await;
            let _ = conn.close().await;
        }

        {
            let mut nr = self.node_registry.lock().await;
            if nr.get(&client_id).is_some() {
                nr.unregister(&client_id);
                crate::log!("NODE: Node '{}' disconnected.", client_id);

                let mut ci = self.capability_inventory.lock().await;
                ci.unregister_by_provider("node", &client_id);
            }
        }

        // Cleanup active capability sessions associated with the disconnected peer
        {
            let mut cs = self.capability_sessions.lock().await;
            let peer_map_lock = self.peer_map.lock().await;
            let node_registry_lock = self.node_registry.lock().await;

            // Collect sessions to clean up
            let mut sessions_to_close = Vec::new();
            for sess in cs.list() {
                if sess.node_id == client_id || sess.client_id == client_id {
                    sessions_to_close.push(sess);
                }
            }

            for mut sess in sessions_to_close {
                crate::log!(
                    "CORE: Closing capability session '{}' due to peer disconnect.",
                    sess.session_id
                );
                sess.status = crate::capabilities::node::registry::CapabilitySessionStatus::Closed;
                cs.register(sess.clone()); // Update status in registry

                if sess.node_id == client_id {
                    // Node disconnected, notify the Client
                    if let Some(client_session) = peer_map_lock.get(&sess.client_id) {
                        let response = crate::transport::protocol::messages::HostMessage::CapabilityActivationStatus {
                            capability_id: sess.capability_id.clone(),
                            session_id: sess.session_id.clone(),
                            status: crate::capabilities::node::registry::CapabilitySessionStatus::Closed,
                            error: Some("Provider node disconnected".to_string()),
                            timestamp: crate::utils::get_timestamp(),
                        };
                        if let Ok(json) = serde_json::to_string(&response) {
                            let s = client_session.lock().await;
                            let conn = s.conn.lock().await;
                            let _ = conn.send_message("frankn_cmd", &Bytes::from(json)).await;
                        }
                    }
                } else if sess.client_id == client_id {
                    // Client disconnected, notify the Node
                    if let Some(node_entry) = node_registry_lock.get(&sess.node_id) {
                        let response = crate::transport::protocol::messages::HostMessage::NodeDeactivateCapability {
                            capability_id: sess.capability_id.clone(),
                            session_id: sess.session_id.clone(),
                            timestamp: crate::utils::get_timestamp(),
                        };
                        if let Ok(json) = serde_json::to_string(&response) {
                            let conn = node_entry.rtc_conn.lock().await;
                            let _ = conn
                                .send_message("frankn_node_control", &Bytes::from(json))
                                .await;
                        }
                    }
                }
            }
        }

        // Clean up active upload sessions for this client to prevent file descriptor leaks
        crate::capabilities::fs::transfer::cleanup_client_uploads(&client_id).await;

        crate::log!("UPLINK: Session terminated for {}.", client_id);
        Ok(())
    }
}
