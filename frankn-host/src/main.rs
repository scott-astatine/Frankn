use std::collections::HashMap;
use std::sync::Arc;
use std::time::Duration;

use crate::signaling::SignalingClient;
use crate::utils::ClientMessage;
use crate::utils::{HostMessage, Status, get_timestamp};
use auth::AuthManager;
use base64::Engine;
use clap::{Parser, Subcommand};
use signaling::SignalingMessage;
use sys::rtc::{PeerMap, RTCConn};
use tokio::sync::Mutex;
use tokio_tungstenite::tungstenite::Bytes;
use webrtc::data_channel::data_channel_message::DataChannelMessage;
use webrtc::peer_connection::peer_connection_state::RTCPeerConnectionState;
use webrtc::peer_connection::sdp::session_description::RTCSessionDescription;

mod auth;
mod config;
mod fs_sync;
mod signaling;
mod sys;
mod utils;

#[derive(Parser)]
#[command(name = "frankn-host")]
#[command(about = "Frankn Personal Remote Ops Center Host", long_about = None)]
struct Cli {
    #[command(subcommand)]
    command: Option<Commands>,
}

#[derive(Subcommand)]
enum Commands {
    /// Manage host configuration
    Config,
    /// Display pairing ID and QR code
    Pair,
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let cli = Cli::parse();

    // Load config or initialize on first run
    let config = config::HostConfig::load_or_init().await;

    match cli.command {
        Some(Commands::Config) => {
            config::tui::run_tui(config).await?;
            Ok(())
        }
        Some(Commands::Pair) => {
            println!("=== NEURAL LINK PAIRING ===");
            println!("\nHost ID: {}", config.host_id);
            println!("Display Name: {}", config.host_name);

            use qr2term::print_qr;
            println!("\nScan this code from the Frankn App:");
            let qr_payload = format!("{}|{}", config.host_id, config.host_name);
            print_qr(&qr_payload).expect("Failed to print QR code");
            println!("\nKeep this ID secure.\n");
            Ok(())
        }
        Some(_) => Ok(()),
        None => run_service(config).await,
    }
}

async fn run_service(config: config::HostConfig) -> Result<(), Box<dyn std::error::Error>> {
    crate::log!("Neural Link Host Server initialized.");
    crate::log!("ID: {}", config.host_id);
    crate::log!("Display Name: {}", config.host_name);

    // =============================================================================
    // CORE SERVICES INITIALIZATION
    // =============================================================================
    let auth_manager = Arc::new(AuthManager::from_hash(&config.password_hash));
    let peer_map: PeerMap = Arc::new(Mutex::new(HashMap::new()));

    // =============================================================================
    // BACKGROUND SERVICES
    // =============================================================================
    let pm_notif = Arc::clone(&peer_map);
    tokio::spawn(async move {
        sys::notifications::start_notification_listener(pm_notif).await;
    });

    let pm_media = Arc::clone(&peer_map);
    tokio::spawn(async move {
        sys::media::start_media_sync(pm_media).await;
    });

    // =============================================================================
    // SIGNALING CONNECTION LOOP
    // =============================================================================
    loop {
        let (signaling_client, mut signaling_rx) = match SignalingClient::connect(
            &config.signaling_url,
            config.host_id.clone(),
            config.host_name.clone(),
            config.is_public,
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
                    crate::log!("NODE: Neural Link established.");
                }
                SignalingMessage::RegisterFailure { error, .. } => {
                    crate::elog!("NODE: Handshake rejected: {}", error);
                }
                SignalingMessage::Offer { from, sdp, .. } => {
                    let sig = Arc::clone(&signaling_client);
                    let auth = Arc::clone(&auth_manager);
                    let pm = Arc::clone(&peer_map);
                    tokio::spawn(async move {
                        if let Err(e) = handle_new_connection(from, sdp, sig, auth, pm).await {
                            crate::elog!("CORE: Handshake error: {e}");
                        }
                    });
                }
                SignalingMessage::IceCandidate {
                    from,
                    candidate,
                    sdp_mid,
                    sdp_m_line_index,
                    ..
                } => {
                    let pm = Arc::clone(&peer_map);
                    tokio::spawn(async move {
                        let map = pm.lock().await;
                        if let Some(rtc_conn) = map.get(&from) {
                            let conn = rtc_conn.lock().await;
                            if let Err(e) = conn
                                .add_remote_candidate(candidate, sdp_mid, sdp_m_line_index)
                                .await
                            {
                                crate::elog!("Failed to add remote candidate: {}", e);
                            }
                        }
                    });
                }
                _ => {}
            }
        }
        tokio::time::sleep(Duration::from_millis(5000)).await;
    }
}

async fn handle_new_connection(
    client_id: String,
    sdp_offer: String,
    signaling_client: Arc<SignalingClient>,
    auth_manager: Arc<AuthManager>,
    peer_map: PeerMap,
) -> Result<(), Box<dyn std::error::Error>> {
    let rtc_conn = Arc::new(Mutex::new(RTCConn::new().await?));

    // Manage sessions
    {
        let mut map = peer_map.lock().await;
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
        r_conn.on_ice_candidate(move |candidate| {
            if let Some(c) = candidate {
                let sig_cl = Arc::clone(&sig);
                let cid_cl = cid.clone();
                tokio::spawn(async move {
                    if let Ok(init) = c.to_json() {
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

    let auth_manager_clone = Arc::clone(&auth_manager);
    let peer_map_clone = Arc::clone(&peer_map);
    let client_id_clone = client_id.clone();

    {
        let conn = rtc_conn.lock().await;
        conn.set_remote_data_channel_handler(move |dc| {
            let label = dc.label().to_owned();
            let pm = Arc::clone(&peer_map_clone);
            let auth = Arc::clone(&auth_manager_clone);
            let cid = client_id_clone.clone();

            match label.as_str() {
                "frankn_ssh" => {
                    crate::log!("LINK: Data channel 'frankn_ssh' initialized.");
                }
                "frankn_cmd" | "frankn_fs" | "frankn_media" => {
                    let channel_label = label.clone();
                    dc.on_message(Box::new(move |msg: DataChannelMessage| {
                        let p = Arc::clone(&pm);
                        let a = Arc::clone(&auth);
                        let d = msg.data.to_vec();
                        let l = channel_label.clone();
                        let c = cid.clone();
                        Box::pin(async move { parse_dc_msg(&d, p, a, &c, &l).await })
                    }));
                }
                _ => {}
            };
        })
        .await;
    }

    let offer = RTCSessionDescription::offer(sdp_offer)?;
    let answer = {
        let conn = rtc_conn.lock().await;
        conn.set_remote_description(offer).await?;
        conn.create_answer().await?
    };

    signaling_client.send_answer(&client_id, answer.sdp).await?;

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
        let mut map = peer_map.lock().await;
        if let Some(current) = map.get(&client_id) {
            if Arc::ptr_eq(current, &rtc_conn) {
                map.remove(&client_id);
            }
        }
    }

    {
        let conn = rtc_conn.lock().await;
        let _ = conn.close().await;
    }

    crate::log!("UPLINK: Session terminated for {}.", client_id);
    Ok(())
}

async fn parse_dc_msg(
    data: &Vec<u8>,
    peer_map: PeerMap,
    auth_manager: Arc<AuthManager>,
    client_id: &str,
    label: &str,
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

    let text = match String::from_utf8(data.clone()) {
        Ok(t) => t,
        Err(_) => {
            parse_binary_msg(data, rtc_conn, label).await;
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
                        let res = HostMessage::AuthSuccess {
                            token,
                            timestamp: get_timestamp(),
                        };
                        if let Ok(json) = serde_json::to_string(&res) {
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
            ClientMessage::UploadStart {
                id,
                path,
                hash,
                total_size,
                ..
            } => {
                crate::log!("FS: Upload session {} initialized.", id);
                let response =
                    crate::fs_sync::handle_upload_start(&id, &path, hash, total_size).await;
                if let Ok(json) = serde_json::to_string(&response) {
                    let conn = rtc_conn.lock().await;
                    let _ = conn.send_message(label, &Bytes::from(json)).await;
                }
            }
            ClientMessage::UploadChunk { id, data, .. } => {
                crate::fs_sync::handle_upload_chunk(&id, &data).await;
            }
            ClientMessage::UploadEnd { id, .. } => {
                crate::log!("FS: Upload session {} finalized.", id);
                let response = crate::fs_sync::handle_upload_end(&id).await;
                if let Ok(json) = serde_json::to_string(&response) {
                    let conn = rtc_conn.lock().await;
                    let _ = conn.send_message(label, &Bytes::from(json)).await;
                }
            }
            ClientMessage::XDcMsg {
                id,
                command,
                params,
                auth_token,
                ..
            } => {
                let is_auth = {
                    let conn = rtc_conn.lock().await;
                    let auth_lock = conn.authenticated.lock().await;
                    *auth_lock
                };
                if is_auth && auth_manager.verify_token(&auth_token).await {
                    let response = crate::sys::dc_message_parser::DcMsg::parse_msg(
                        &id,
                        &command,
                        params,
                        Arc::clone(&peer_map),
                        client_id,
                    )
                    .await;
                    if let Ok(json) = serde_json::to_string(&response) {
                        let conn = rtc_conn.lock().await;
                        let _ = conn.send_message(label, &Bytes::from(json)).await;
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
        Err(_) => {
            if !text.trim().starts_with('{') {
                parse_binary_msg(data, rtc_conn, label).await;
            }
        }
    }
}

async fn parse_binary_msg(data: &Vec<u8>, _rtc_conn: Arc<Mutex<RTCConn>>, label: &str) {
    if label == "frankn_fs" && data.len() >= 36 {
        let id_bytes = &data[0..36];
        let transfer_id = String::from_utf8_lossy(id_bytes)
            .trim_matches(char::from(0))
            .to_string();
        let b64_data = base64::prelude::BASE64_STANDARD.encode(&data[36..]);
        crate::fs_sync::handle_upload_chunk(&transfer_id, &b64_data).await;
    }
}
