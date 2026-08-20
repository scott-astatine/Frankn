use std::sync::Arc;
use std::time::Duration;
use tokio::sync::Mutex;
use tokio_tungstenite::tungstenite::Bytes;
use webrtc::data_channel::data_channel_message::DataChannelMessage;
use webrtc::peer_connection::peer_connection_state::RTCPeerConnectionState;

use crate::config::HostConfig;
use crate::transport::webrtc::connection::{RTCConn, RtcRole};
use crate::signaling::{SignalingClient, SignalingMessage, PeerType};
use crate::transport::protocol::{ClientMessage, HostMessage, Status};
use crate::utils::get_timestamp;

pub struct NodeRuntime {
    config: Arc<HostConfig>,
    active_sessions: Arc<Mutex<std::collections::HashMap<String, Arc<Mutex<RTCConn>>>>>,
}

impl NodeRuntime {
    pub fn new(config: HostConfig) -> Self {
        Self {
            config: Arc::new(config),
            active_sessions: Arc::new(Mutex::new(std::collections::HashMap::new())),
        }
    }

    pub async fn run(self) -> Result<(), Box<dyn std::error::Error>> {
        crate::log!("Neural Link Node Server starting...");
        crate::log!("ID: {}", self.config.host_id);
        
        let node_cfg = match self.config.node.as_ref() {
            Some(cfg) => cfg,
            None => {
                crate::elog!("ERROR: Node configuration section [node] missing in node.toml!");
                std::process::exit(1);
            }
        };

        loop {
            let host_peer_id = node_cfg.host_peer_id.clone();
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
                PeerType::Client,
            )
            .await
            {
                Ok(c) => c,
                Err(e) => {
                    crate::elog!("NODE: Signaling connection failed: {e}. Retrying in 10s...");
                    tokio::time::sleep(Duration::from_secs(10)).await;
                    continue;
                }
            };

            let signaling_client = Arc::new(signaling_client);
            crate::log!("NODE: Connected to signaling server as Client. Registering WebRTC control link...");

            // Create client RTC connection
            let rtc_conn = match RTCConn::new(RtcRole::Answerer).await {
                Ok(c) => Arc::new(Mutex::new(c)),
                Err(e) => {
                    crate::elog!("NODE: Failed to create WebRTC connection: {e}");
                    tokio::time::sleep(Duration::from_secs(10)).await;
                    continue;
                }
            };

            // Set up data channel "frankn_node_control"
            let control_dc = match {
                let conn = rtc_conn.lock().await;
                conn.create_data_channel("frankn_node_control").await
            } {
                Ok(dc) => dc,
                Err(e) => {
                    crate::elog!("NODE: Failed to create frankn_node_control channel: {e}");
                    tokio::time::sleep(Duration::from_secs(10)).await;
                    continue;
                }
            };

            // Monitor data channel lifecycle
            let node_id_clone = self.config.host_id.clone();
            let display_name_clone = self.config.host_name.clone();
            let capabilities_raw = node_cfg.capabilities.clone();
            
            // Build capability descriptors
            let mut capabilities = Vec::new();
            for cap in capabilities_raw {
                capabilities.push(crate::capabilities::registry::CapabilityDescriptor {
                    id: cap.clone(),
                    name: cap.clone(),
                    version: "1.0.0".to_string(),
                    actions: vec![],
                    properties: std::collections::HashMap::new(),
                    events: vec![],
                    schemas: std::collections::HashMap::new(),
                    permissions: vec![],
                    platform_support: vec![],
                    health: "healthy".to_string(),
                });
            }

            let control_dc_clone = Arc::clone(&control_dc);
            let node_id_heartbeat = node_id_clone.clone();
            let heartbeat_handle = Arc::new(Mutex::new(None));
            let heartbeat_handle_clone = Arc::clone(&heartbeat_handle);

            control_dc.on_open(Box::new(move || {
                crate::log!("NODE: WebRTC control data channel opened. Sending RegisterRequest...");
                let dc = Arc::clone(&control_dc_clone);
                let nid = node_id_clone.clone();
                let name = display_name_clone.clone();
                let caps = capabilities.clone();

                let h_handle = Arc::clone(&heartbeat_handle_clone);
                let nid_hb = node_id_heartbeat.clone();

                Box::pin(async move {
                    let reg_msg = ClientMessage::NodeRegister {
                        node_id: nid,
                        display_name: name,
                        capabilities: caps,
                        timestamp: get_timestamp(),
                    };

                    if let Ok(json) = serde_json::to_string(&reg_msg) {
                        let _ = dc.send(&Bytes::from(json)).await;
                    }

                    // Spawn heartbeat sender
                    let hb_dc = Arc::clone(&dc);
                    let mut lock = h_handle.lock().await;
                    *lock = Some(tokio::spawn(async move {
                        loop {
                            tokio::time::sleep(Duration::from_secs(10)).await;
                            let hb_msg = ClientMessage::NodeHeartbeat {
                                node_id: nid_hb.clone(),
                                timestamp: get_timestamp(),
                                status: "healthy".to_string(),
                            };
                            if let Ok(json) = serde_json::to_string(&hb_msg) {
                                if hb_dc.send(&Bytes::from(json)).await.is_err() {
                                    crate::elog!("NODE: Heartbeat send failed.");
                                    break;
                                }
                            }
                        }
                    }));
                })
            }));            // Message handler
            let rtc_conn_msg = Arc::clone(&rtc_conn);
            let active_sessions_clone = Arc::clone(&self.active_sessions);
            let sig_client_clone = Arc::clone(&signaling_client);
            control_dc.on_message(Box::new(move |msg: DataChannelMessage| {
                let rtc = Arc::clone(&rtc_conn_msg);
                let active_sessions = Arc::clone(&active_sessions_clone);
                let sig_client = Arc::clone(&sig_client_clone);
                Box::pin(async move {
                    if let Ok(text) = String::from_utf8(msg.data.to_vec()) {
                        match serde_json::from_str::<HostMessage>(&text) {
                            Ok(HostMessage::NodeRegisterAck { status, .. }) => {
                                match status {
                                    Status::Success => {
                                        crate::log!("NODE: Registered successfully with Host!");
                                    }
                                    Status::Error(e) => {
                                        crate::elog!("NODE: Registration failed: {}", e);
                                        let conn = rtc.lock().await;
                                        let _ = conn.close().await;
                                    }
                                }
                            }
                            Ok(HostMessage::NodeActivateCapability { capability_id, session_id, client_id, .. }) => {
                                crate::log!("NODE: Received activation command for '{}' (session: '{}', client: '{}')",
                                    &capability_id, &session_id, &client_id);
                                
                                let active_sessions_inner = Arc::clone(&active_sessions);
                                let rtc_ctrl = Arc::clone(&rtc);
                                let cap_id = capability_id.clone();
                                let sess_id = session_id.clone();
                                let cli_id = client_id.clone();
                                let sig_client_inner = Arc::clone(&sig_client);

                                tokio::spawn(async move {
                                    // Create a new direct RTCConn for this capability session
                                    let node_cap_conn = match RTCConn::new(RtcRole::Offerer).await {
                                        Ok(c) => Arc::new(Mutex::new(c)),
                                        Err(e) => {
                                            crate::elog!("NODE: Failed to create capability connection: {e}");
                                            return;
                                        }
                                    };

                                    // Store it
                                    active_sessions_inner.lock().await.insert(sess_id.clone(), Arc::clone(&node_cap_conn));

                                    // Set up peer connection state change callback to handle failure/disconnection/close
                                    {
                                        let nc = node_cap_conn.lock().await;
                                        let rtc_ctrl_inner = Arc::clone(&rtc_ctrl);
                                        let active_sessions_inner_c = Arc::clone(&active_sessions_inner);
                                        let sess_id_inner = sess_id.clone();
                                        let cap_id_inner = cap_id.clone();
                                        
                                        nc.on_peer_connection_state_change(move |state| {
                                            use webrtc::peer_connection::peer_connection_state::RTCPeerConnectionState;
                                            match state {
                                                RTCPeerConnectionState::Failed |
                                                RTCPeerConnectionState::Disconnected |
                                                RTCPeerConnectionState::Closed => {
                                                    crate::log!("NODE: Capability session '{}' connection state changed to {:?}. Cleaning up.",
                                                        sess_id_inner, state);
                                                    
                                                    let active_sessions_inner_2 = Arc::clone(&active_sessions_inner_c);
                                                    let rtc_ctrl_inner_2 = Arc::clone(&rtc_ctrl_inner);
                                                    let sess_id_inner_2 = sess_id_inner.clone();
                                                    let cap_id_inner_2 = cap_id_inner.clone();
                                                    
                                                    tokio::spawn(async move {
                                                        let old_conn = {
                                                            let mut map = active_sessions_inner_2.lock().await;
                                                            map.remove(&sess_id_inner_2)
                                                        };
                                                        if let Some(c) = old_conn {
                                                            let conn_lock = c.lock().await;
                                                            let _ = conn_lock.close().await;
                                                        }
                                                        
                                                        let status_msg = ClientMessage::NodeActivationStatus {
                                                            capability_id: cap_id_inner_2,
                                                            session_id: sess_id_inner_2,
                                                            status: crate::capabilities::node::registry::CapabilitySessionStatus::Closed,
                                                            error: None,
                                                        };
                                                        if let Ok(json) = serde_json::to_string(&status_msg) {
                                                            let conn = rtc_ctrl_inner_2.lock().await;
                                                            let _ = conn.send_message("frankn_node_control", &Bytes::from(json)).await;
                                                        }
                                                    });
                                                }
                                                _ => {}
                                            }
                                        });
                                    }

                                    // Set up ICE candidate forwarder
                                    {
                                        let nc = node_cap_conn.lock().await;
                                        let rtc_ctrl_inner = Arc::clone(&rtc_ctrl);
                                        let cli_id_inner = cli_id.clone();
                                        let sess_id_inner = sess_id.clone();
                                        let sig_client_send = Arc::clone(&sig_client_inner);
                                        nc.on_ice_candidate(move |candidate| {
                                            if let Some(c) = candidate {
                                                let rtc_ctrl_send = Arc::clone(&rtc_ctrl_inner);
                                                let cli_id_send = cli_id_inner.clone();
                                                let sess_id_send = sess_id_inner.clone();
                                                let sig_client_inner_send = Arc::clone(&sig_client_send);
                                                tokio::spawn(async move {
                                                    let init = match c.to_json() {
                                                        Ok(init) => init,
                                                        Err(e) => {
                                                            crate::elog!("NODE: Failed to convert ICE candidate: {e}");
                                                            return;
                                                        }
                                                    };
                                                    use std::sync::atomic::Ordering;
                                                    let sequence = sig_client_inner_send.sequence.fetch_add(1, Ordering::SeqCst);
                                                    let timestamp = std::time::SystemTime::now()
                                                        .duration_since(std::time::UNIX_EPOCH)
                                                        .unwrap()
                                                        .as_millis() as u64;
                                                    let signature = match sig_client_inner_send.sign_envelope(
                                                        0x03,
                                                        &cli_id_send,
                                                        &init.candidate,
                                                        sequence,
                                                        timestamp,
                                                    ) {
                                                        Ok(s) => s,
                                                        Err(e) => {
                                                            crate::elog!("NODE: Failed to sign ICE candidate: {e}");
                                                            return;
                                                        }
                                                    };
                                                    let signal_msg = ClientMessage::NodeSignal {
                                                        client_id: cli_id_send.clone(),
                                                        session_id: sess_id_send.clone(),
                                                        signal: crate::signaling::SignalingMessage::IceCandidate {
                                                            from: sig_client_inner_send.peer_id.clone(),
                                                            to: cli_id_send.clone(),
                                                            candidate: init.candidate,
                                                            sdp_mid: init.sdp_mid,
                                                            sdp_m_line_index: init.sdp_mline_index,
                                                            session_id: sess_id_send.clone(),
                                                            sequence,
                                                            signature,
                                                            timestamp,
                                                        },
                                                    };
                                                    if let Ok(json) = serde_json::to_string(&signal_msg) {
                                                        let conn = rtc_ctrl_send.lock().await;
                                                        let _ = conn.send_message("frankn_node_control", &Bytes::from(json)).await;
                                                    }
                                                });
                                            }
                                        });
                                    }

                                    // Pre-create the frankn_media data channel on capability connection
                                    {
                                        let nc = node_cap_conn.lock().await;
                                        match nc.create_data_channel("frankn_media").await {
                                            Ok(dc) => {
                                                let dc_clone = Arc::clone(&dc);
                                                tokio::spawn(async move {
                                                    let mut counter = 0;
                                                    loop {
                                                        tokio::time::sleep(tokio::time::Duration::from_millis(500)).await;
                                                        let mock_frame = format!("MOCK_FRAME_{}", counter);
                                                        if dc_clone.send(&Bytes::from(mock_frame)).await.is_err() {
                                                            break;
                                                        }
                                                        counter += 1;
                                                    }
                                                });
                                            }
                                            Err(e) => {
                                                crate::elog!("NODE: Failed to create frankn_media data channel: {e}");
                                            }
                                        }
                                    }

                                    // Add the direct VP8 video track to the capability connection!
                                    let video_track = match node_cap_conn.lock().await.add_video_track("video-stream", "mock-camera").await {
                                        Ok(track) => Some(track),
                                        Err(e) => {
                                            crate::elog!("NODE: Failed to add video track: {e}");
                                            None
                                        }
                                    };

                                    if let Some(track) = video_track {
                                        let runner = crate::capabilities::camera::CameraRunner::new(track, None);
                                        runner.start().await;
                                    }

                                    // Respond with positive status
                                     let status_msg = ClientMessage::NodeActivationStatus {
                                         capability_id: cap_id,
                                         session_id: sess_id,
                                         status: crate::capabilities::node::registry::CapabilitySessionStatus::Active,
                                         error: None,
                                     };
                                    if let Ok(json) = serde_json::to_string(&status_msg) {
                                        let conn = rtc_ctrl.lock().await;
                                        let _ = conn.send_message("frankn_node_control", &Bytes::from(json)).await;
                                    }
                                });
                            }
                            Ok(HostMessage::NodeDeactivateCapability { capability_id, session_id, .. }) => {
                                crate::log!("NODE: Received deactivation command for '{}' (session: '{}')",
                                    &capability_id, &session_id);
                                let active_sessions_inner = Arc::clone(&active_sessions);
                                let rtc_ctrl = Arc::clone(&rtc);
                                let cap_id = capability_id.clone();
                                let sess_id = session_id.clone();
                                tokio::spawn(async move {
                                    let conn_opt = {
                                        let mut map = active_sessions_inner.lock().await;
                                        map.remove(&sess_id)
                                    };
                                    if let Some(nc) = conn_opt {
                                        let conn = nc.lock().await;
                                        let _ = conn.close().await;
                                    }
                                     let status_msg = ClientMessage::NodeActivationStatus {
                                         capability_id: cap_id,
                                         session_id: sess_id,
                                         status: crate::capabilities::node::registry::CapabilitySessionStatus::Closed,
                                         error: None,
                                     };
                                    if let Ok(json) = serde_json::to_string(&status_msg) {
                                        let conn = rtc_ctrl.lock().await;
                                        let _ = conn.send_message("frankn_node_control", &Bytes::from(json)).await;
                                    }
                                });
                            }
                            Ok(HostMessage::HostSignal { client_id, session_id, signal }) => {
                                crate::log!("NODE: Forwarded signal from client '{}' for session '{}': {:?}",
                                    &client_id, &session_id, &signal);
                                let active_sessions_inner = Arc::clone(&active_sessions);
                                let rtc_ctrl = Arc::clone(&rtc);
                                let target_cli = client_id.clone();
                                let sess_id = session_id.clone();
                                let sig_client_inner = Arc::clone(&sig_client);
                                tokio::spawn(async move {
                                    let conn_opt = {
                                        let map = active_sessions_inner.lock().await;
                                        map.get(&sess_id).cloned()
                                    };
                                    if let Some(nc) = conn_opt {
                                        match signal {
                                            crate::signaling::SignalingMessage::Offer { sdp, .. } => {
                                                let c = nc.lock().await;
                                                let desc = webrtc::peer_connection::sdp::session_description::RTCSessionDescription::offer(sdp).unwrap();
                                                if let Err(e) = c.peer_connection.set_remote_description(desc).await {
                                                    crate::elog!("NODE: Failed to set remote description: {e}");
                                                    return;
                                                }
                                                let _ = c.flush_candidates().await;

                                                match c.peer_connection.create_answer(None).await {
                                                    Ok(answer) => {
                                                        if let Err(e) = c.peer_connection.set_local_description(answer.clone()).await {
                                                            crate::elog!("NODE: Failed to set local description: {e}");
                                                        } else {
                                                            use std::sync::atomic::Ordering;
                                                            let sequence = sig_client_inner.sequence.fetch_add(1, Ordering::SeqCst);
                                                            let timestamp = std::time::SystemTime::now()
                                                                .duration_since(std::time::UNIX_EPOCH)
                                                                .unwrap()
                                                                .as_millis() as u64;
                                                            let signature = match sig_client_inner.sign_envelope(
                                                                0x02,
                                                                &target_cli,
                                                                &answer.sdp,
                                                                sequence,
                                                                timestamp,
                                                            ) {
                                                                Ok(s) => s,
                                                                Err(e) => {
                                                                    crate::elog!("NODE: Failed to sign answer: {e}");
                                                                    return;
                                                                }
                                                            };
                                                            let signal_msg = ClientMessage::NodeSignal {
                                                                client_id: target_cli.clone(),
                                                                session_id: sess_id.clone(),
                                                                signal: crate::signaling::SignalingMessage::Answer {
                                                                    from: sig_client_inner.peer_id.clone(),
                                                                    to: target_cli.clone(),
                                                                    sdp: answer.sdp,
                                                                    session_id: sess_id.clone(),
                                                                    sequence,
                                                                    signature,
                                                                    timestamp,
                                                                },
                                                            };
                                                            if let Ok(json) = serde_json::to_string(&signal_msg) {
                                                                let rtc_ctrl_inner = rtc_ctrl.lock().await;
                                                                let _ = rtc_ctrl_inner.send_message("frankn_node_control", &Bytes::from(json)).await;
                                                            }
                                                        }
                                                    }
                                                    Err(e) => {
                                                        crate::elog!("NODE: Failed to create answer: {e}");
                                                    }
                                                }
                                            }
                                            crate::signaling::SignalingMessage::IceCandidate { candidate, sdp_mid, sdp_m_line_index, .. } => {
                                                let c = nc.lock().await;
                                                let _ = c.add_remote_candidate(candidate, sdp_mid, sdp_m_line_index).await;
                                            }
                                            _ => {}
                                        }
                                    }
                                });
                            }
                            _ => {}
                        }
                    }
                })
            }));
            // Generate SDP Offer
            let sdp_offer = {
                let conn = rtc_conn.lock().await;
                match conn.peer_connection.create_offer(None).await {
                    Ok(offer) => {
                        if let Err(e) = conn.peer_connection.set_local_description(offer.clone()).await {
                            crate::elog!("NODE: Failed to set local description: {e}");
                            None
                        } else {
                            Some(offer.sdp)
                        }
                    }
                    Err(e) => {
                        crate::elog!("NODE: Failed to create SDP offer: {e}");
                        None
                    }
                }
            };

            let sdp_offer = match sdp_offer {
                Some(o) => o,
                None => {
                    tokio::time::sleep(Duration::from_secs(10)).await;
                    continue;
                }
            };

            // Set up local ICE candidate forwarder
            {
                let conn = rtc_conn.lock().await;
                let sig = Arc::clone(&signaling_client);
                let hid = host_peer_id.clone();
                conn.on_ice_candidate(move |candidate| {
                    if let Some(c) = candidate {
                        let sig_cl = Arc::clone(&sig);
                        let hid_cl = hid.clone();
                        tokio::spawn(async move {
                            if let Ok(init) = c.to_json() {
                                let _ = sig_cl
                                    .send_ice_candidate(
                                        &hid_cl,
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

            // Send Offer via signaling server
            if let Err(e) = signaling_client.send_offer(&host_peer_id, sdp_offer).await {
                crate::elog!("NODE: Failed to send SDP offer to Host: {e}");
                tokio::time::sleep(Duration::from_secs(10)).await;
                continue;
            }
            crate::log!("NODE: SDP offer successfully sent to Host. Awaiting answer...");

            // Listen for Answer and candidates from Signaling Client
            let rtc_conn_recv = Arc::clone(&rtc_conn);
            let (tx_close, mut rx_close) = tokio::sync::mpsc::channel(1);

            // WebRTC connection state monitoring
            {
                let conn = rtc_conn_recv.lock().await;
                let tx_c = tx_close.clone();
                conn.on_peer_connection_state_change(move |state| {
                    if state == RTCPeerConnectionState::Closed || state == RTCPeerConnectionState::Failed {
                        let _ = tx_c.try_send(());
                    }
                });
            }

            let host_peer_id_clone = host_peer_id.clone();
            let recv_loop = tokio::spawn(async move {
                while let Some(msg) = signaling_rx.recv().await {
                    match msg {
                        SignalingMessage::Answer { sdp, from, .. } => {
                            if from == host_peer_id_clone {
                                crate::log!("NODE: Received Answer from Host. Setting remote description...");
                                let desc = webrtc::peer_connection::sdp::session_description::RTCSessionDescription::answer(sdp).unwrap();
                                let conn = rtc_conn_recv.lock().await;
                                if let Err(e) = conn.peer_connection.set_remote_description(desc).await {
                                    crate::elog!("NODE: Failed to set remote description: {e}");
                                } else {
                                    let _ = conn.flush_candidates().await;
                                }
                            }
                        }
                        SignalingMessage::IceCandidate { candidate, sdp_mid, sdp_m_line_index, from, .. } => {
                            if from == host_peer_id_clone {
                                let conn = rtc_conn_recv.lock().await;
                                let _ = conn.add_remote_candidate(candidate, sdp_mid, sdp_m_line_index).await;
                            }
                        }
                        _ => {}
                    }
                }
            });

            // Block until connection is closed or signaling terminates
            tokio::select! {
                _ = rx_close.recv() => {
                    crate::log!("NODE: Control link disconnected.");
                }
                _ = recv_loop => {
                    crate::log!("NODE: Signaling receiver closed.");
                }
            }

            // Cleanup heartbeat sender
            if let Some(handle) = heartbeat_handle.lock().await.take() {
                handle.abort();
            }

            crate::log!("NODE: Restarting control link handshake in 5s...");
            tokio::time::sleep(Duration::from_secs(5)).await;
        }
    }
}
