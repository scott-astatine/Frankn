use std::sync::Arc;
use std::time::Duration;
use tokio::sync::Mutex;
use webrtc::data_channel::data_channel_message::DataChannelMessage;
use webrtc::peer_connection::peer_connection_state::RTCPeerConnectionState;
use webrtc::peer_connection::sdp::session_description::RTCSessionDescription;

use crate::config::HostConfig;
use crate::auth::AuthManager;
use crate::capabilities::inference::LlmManager;
use crate::transport::webrtc::connection::{PeerMap, RTCConn};
use crate::signaling::{SignalingClient, SignalingMessage};
use crate::transport::protocol::parse_dc_msg;

pub struct SessionManager {
    config: Arc<HostConfig>,
    auth_manager: Arc<AuthManager>,
    peer_map: PeerMap,
    llm_manager: Arc<Mutex<LlmManager>>,
    input_manager: Option<Arc<Mutex<crate::capabilities::input::InputManager>>>,
}

impl SessionManager {
    pub fn new(
        config: Arc<HostConfig>,
        auth_manager: Arc<AuthManager>,
        peer_map: PeerMap,
        llm_manager: Arc<Mutex<LlmManager>>,
        input_manager: Option<Arc<Mutex<crate::capabilities::input::InputManager>>>,
    ) -> Self {
        Self {
            config,
            auth_manager,
            peer_map,
            llm_manager,
            input_manager,
        }
    }

    pub async fn run_signaling_loop(self: Arc<Self>) -> Result<(), Box<dyn std::error::Error>> {
        loop {
            let (signaling_client, mut signaling_rx) = match SignalingClient::connect(
                &self.config.signaling_url,
                self.config.host_id.clone(),
                self.config.host_name.clone(),
                self.config.is_public,
            )
            .await
            {
                Ok(c) => c,
                Err(e) => {
                    crate::elog!("NODE: Handshake with signaling server failed: {e}");
                    tokio::time::sleep(Duration::from_millis(20000)).await;
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
                        break; // Break the while loop to close the channel and trigger a reconnect
                    }
                    SignalingMessage::Offer { from, sdp, session_id, .. } => {
                        let manager = Arc::clone(&self);
                        let sig = Arc::clone(&signaling_client);
                        tokio::spawn(async move {
                            if let Err(e) = manager.handle_new_connection(from, sdp, session_id, sig).await {
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
                            manager.handle_ice_candidate(from, candidate, sdp_mid, sdp_m_line_index, session_id).await;
                        });
                    }
                    _ => {}
                }
            }
            tokio::time::sleep(Duration::from_millis(5000)).await;
        }
    }

    pub async fn handle_ice_candidate(
        &self,
        from: String,
        candidate: String,
        sdp_mid: Option<String>,
        sdp_m_line_index: Option<u16>,
        session_id: Option<String>,
    ) {
        let map = self.peer_map.lock().await;
        if let Some(rtc_conn) = map.get(&from) {
            let conn = rtc_conn.lock().await;
            let active_sid = conn.session_id.lock().await;
            if active_sid.is_some() && active_sid.as_ref() != session_id.as_ref() {
                crate::log!("ICE_GATHER: Discarding stale remote candidate due to mismatched session ID ({:?} vs {:?})", session_id, active_sid);
                return;
            }
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
        session_id: Option<String>,
        signaling_client: Arc<SignalingClient>,
    ) -> Result<(), String> {
        let rtc_conn = Arc::new(Mutex::new(RTCConn::new().await.map_err(|e| e.to_string())?));

        // Store the handshake session ID on the connection object
        {
            let conn = rtc_conn.lock().await;
            let mut active_sid = conn.session_id.lock().await;
            *active_sid = session_id.clone();
        }

        // Manage sessions
        {
            let mut map = self.peer_map.lock().await;
            if let Some(existing) = map.remove(&client_id) {
                crate::log!("UPLINK: Replacing active session for {}.", client_id);
                let conn = existing.lock().await;
                let _ = conn.close().await;
            }
            map.insert(client_id.clone(), Arc::clone(&rtc_conn));
            crate::log!("UPLINK: Session established for {}.", client_id);
        }

        // Send ICE to Client
        {
            let r_conn = rtc_conn.lock().await;
            let sig = Arc::clone(&signaling_client);
            let cid = client_id.clone();
            let sid = session_id.clone();
            r_conn.on_ice_candidate(move |candidate| {
                if let Some(c) = candidate {
                    let sig_cl = Arc::clone(&sig);
                    let cid_cl = cid.clone();
                    let sid_cl = sid.clone();
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
                                    sid_cl,
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

                match label.as_str() {
                    "frankn_ssh" => {
                        crate::log!("LINK: Data channel 'frankn_ssh' initialized.");
                    }
                    "frankn_input" => {
                        let im_c = im.clone();
                        dc.on_message(Box::new(move |msg| {
                            let im_c2 = im_c.clone();
                            Box::pin(async move {
                                if let Ok(input_msg) =
                                    serde_json::from_slice::<crate::capabilities::input::InputMsg>(&msg.data)
                                    && let Some(manager) = im_c2
                                {
                                    let mut m = manager.lock().await;
                                    m.handle_msg(input_msg);
                                }
                            })
                        }));
                    }
                    "frankn_cmd" | "frankn_fs" | "frankn_media" | "dohee_x" => {
                        let channel_label = label.clone();
                        dc.on_message(Box::new(move |msg: DataChannelMessage| {
                            let p = Arc::clone(&pm);
                            let a = Arc::clone(&auth);
                            let d = msg.data.to_vec();
                            let l = channel_label.clone();
                            let c = cid.clone();
                            let llm_m = Arc::clone(&llm);
                            let cfg_inner = Arc::clone(&cfg);
                            Box::pin(
                                async move { parse_dc_msg(&d, p, a, &c, &l, llm_m, cfg_inner).await },
                            )
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
                .send_answer(&client_id, answer.sdp, session_id.clone())
                .await
                .map_err(|e| e.to_string())?;
            Ok::<(), String>(())
        }
        .await;

        if let Err(e) = handshake_res {
            crate::elog!("CORE: Handshake failed for client {}: {}", client_id, e);
            {
                let mut map = self.peer_map.lock().await;
                if let Some(current) = map.get(&client_id)
                    && Arc::ptr_eq(current, &rtc_conn)
                {
                    map.remove(&client_id);
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
                if state == RTCPeerConnectionState::Closed || state == RTCPeerConnectionState::Failed {
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
            if let Some(current) = map.get(&client_id)
                && Arc::ptr_eq(current, &rtc_conn)
            {
                map.remove(&client_id);
            }
        }

        {
            let conn = rtc_conn.lock().await;
            let _ = conn.close().await;
        }

        // Clean up active upload sessions for this client to prevent file descriptor leaks
        crate::capabilities::fs::transfer::cleanup_client_uploads(&client_id).await;

        crate::log!("UPLINK: Session terminated for {}.", client_id);
        Ok(())
    }
}
