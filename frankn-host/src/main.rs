use std::collections::HashMap;
use std::sync::Arc;
use std::time::Duration;

use crate::ops::llm::LlmManager;
use crate::signaling::SignalingClient;
use crate::utils::{ClientMessage, get_cpu_temp};
use crate::utils::{HostMessage, Status, get_timestamp};
use auth::AuthManager;
use clap::{Parser, Subcommand};
use ops::rtc::{PeerMap, RTCConn};
use signaling::SignalingMessage;
use tokio::sync::Mutex;
use tokio_tungstenite::tungstenite::Bytes;
use webrtc::data_channel::data_channel_message::DataChannelMessage;
use webrtc::peer_connection::peer_connection_state::RTCPeerConnectionState;
use webrtc::peer_connection::sdp::session_description::RTCSessionDescription;

mod auth;
mod config;
mod fs_sync;
mod ops;
mod signaling;
mod utils;

#[derive(Parser)]
#[command(name = "frankn-host")]
#[command(about = "Frankn Personal Remote Ops Center Host", long_about = None)]
struct Cli {
    /// Path to a custom configuration file
    #[arg(short, long, value_name = "FILE")]
    config: Option<String>,

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
    // Explicitly install the rustls crypto provider to prevent panics when
    // multiple tokio tasks attempt to use cryptography (WebRTC Signaling + Reqwest LLM).
    let _ = rustls::crypto::ring::default_provider().install_default();

    let cli = Cli::parse();
    let custom_path = cli.config.map(std::path::PathBuf::from);

    // Load config or initialize on first run
    let config = config::HostConfig::load_or_init(custom_path).await;

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
        None => run_service(config).await,
    }
}

async fn run_service(config: config::HostConfig) -> Result<(), Box<dyn std::error::Error>> {
    let config = Arc::new(config);
    crate::log!("Neural Link Host Server initialized.");
    crate::log!("ID: {}", config.host_id);
    crate::log!("Display Name: {}", config.host_name);

    // =============================================================================
    // CORE SERVICES INITIALIZATION
    // =============================================================================
    let auth_manager = Arc::new(AuthManager::from_hash(&config.password_hash, &config.salt));
    let peer_map: PeerMap = Arc::new(Mutex::new(HashMap::new()));
    let llm_manager = Arc::new(Mutex::new(LlmManager::new()));
    let input_manager = match crate::ops::input::InputManager::new() {
        Ok(im) => Some(Arc::new(Mutex::new(im))),
        Err(e) => {
            crate::elog!("CRITICAL: Failed to initialize virtual input devices (uinput).");
            crate::elog!("  ↳ Error: {}", e);
            crate::elog!("  ↳ The trackpad and keyboard features will NOT work.");
            crate::elog!("  ↳ Fix 1: Ensure the kernel module is loaded: 'sudo modprobe uinput'");
            crate::elog!("  ↳ Fix 2: Ensure your user has permissions to /dev/uinput");
            None
        }
    };

    // =============================================================================
    // BACKGROUND SERVICES
    // =============================================================================
    let pm_notif = Arc::clone(&peer_map);
    tokio::spawn(async move {
        ops::notifications::start_notification_listener(pm_notif).await;
    });

    let pm_media = Arc::clone(&peer_map);
    tokio::spawn(async move {
        ops::media::start_media_sync(pm_media).await;
    });

    // =============================================================================
    // TELEMETRY BROADCAST
    // =============================================================================
    let pm_telemetry = Arc::clone(&peer_map);
    tokio::spawn(async move {
        use sysinfo::{CpuRefreshKind, MemoryRefreshKind, RefreshKind, System};
        let mut sys = System::new_with_specifics(
            RefreshKind::nothing()
                .with_cpu(CpuRefreshKind::everything())
                .with_memory(MemoryRefreshKind::everything()),
        );

        loop {
            let has_clients = {
                let map = pm_telemetry.lock().await;
                !map.is_empty()
            };

            if has_clients {
                sys.refresh_cpu_all();
                sys.refresh_memory();

                let msg = HostMessage::Telemetry {
                    cpu_load: sys.global_cpu_usage(),
                    cpu_temp: get_cpu_temp().unwrap_or(0.0),
                    used_mem: sys.used_memory(),
                    total_mem: sys.total_memory(),
                    timestamp: get_timestamp(),
                };

                if let Ok(json) = serde_json::to_string(&msg) {
                    let map = pm_telemetry.lock().await;
                    for conn in map.values() {
                        let r_conn = conn.lock().await;
                        let _ = r_conn
                            .send_message(
                                "frankn_cmd",
                                &tokio_tungstenite::tungstenite::Bytes::from(json.clone()),
                            )
                            .await;
                    }
                }
            }
            tokio::time::sleep(Duration::from_secs(2)).await;
        }
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
                    crate::log!("NODE: Connected to signaling server.");
                }
                SignalingMessage::RegisterFailure { error, .. } => {
                    crate::elog!("NODE: Handshake rejected: {}", error);
                    break; // Break the while loop to close the channel and trigger a reconnect
                }
                SignalingMessage::Offer { from, sdp, .. } => {
                    let sig = Arc::clone(&signaling_client);
                    let auth = Arc::clone(&auth_manager);
                    let pm = Arc::clone(&peer_map);
                    let llm = Arc::clone(&llm_manager);
                    let im = input_manager.clone();
                    let cfg = Arc::clone(&config);
                    tokio::spawn(async move {
                        if let Err(e) =
                            handle_new_connection(from, sdp, sig, auth, pm, llm, im, cfg).await
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
    llm_manager: Arc<Mutex<LlmManager>>,
    input_manager: Option<Arc<Mutex<crate::ops::input::InputManager>>>,
    config: Arc<config::HostConfig>,
) -> Result<(), String> {
    let rtc_conn = Arc::new(Mutex::new(RTCConn::new().await.map_err(|e| e.to_string())?));

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
    let llm_manager_clone = Arc::clone(&llm_manager);
    let input_manager_clone = input_manager.clone();
    let config_clone = Arc::clone(&config);

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
                                serde_json::from_slice::<crate::ops::input::InputMsg>(&msg.data)
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
            conn.set_remote_description(offer).await.map_err(|e| e.to_string())?;
            conn.create_answer().await.map_err(|e| e.to_string())?
        };

        signaling_client.send_answer(&client_id, answer.sdp).await.map_err(|e| e.to_string())?;
        Ok::<(), String>(())
    }.await;

    if let Err(e) = handshake_res {
        crate::elog!("CORE: Handshake failed for client {}: {}", client_id, e);
        {
            let mut map = peer_map.lock().await;
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
        let mut map = peer_map.lock().await;
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
    crate::fs_sync::transfer::cleanup_client_uploads(&client_id).await;

    crate::log!("UPLINK: Session terminated for {}.", client_id);
    Ok(())
}

async fn parse_dc_msg(
    data: &Vec<u8>,
    peer_map: PeerMap,
    auth_manager: Arc<AuthManager>,
    client_id: &str,
    label: &str,
    llm_manager: Arc<Mutex<LlmManager>>,
    config: Arc<config::HostConfig>,
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
        parse_binary_msg(data, rtc_conn, label).await;
        return;
    }

    let text = match String::from_utf8(data.clone()) {
        Ok(t) => t,
        Err(_) => {
            // Not valid UTF-8 and not a binary frame — drop silently.
            return;
        }
    };

    // log!("{text}");

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

            // ── New resume-aware transfer protocol ──
            ClientMessage::TransferInit {
                id,
                path,
                hash,
                total_size,
                resume_offset,
                ..
            } => {
                crate::log!("FS: Transfer init for {} → {}", id, path);
                crate::fs_sync::transfer::handle_transfer_init(
                    &id,
                    &path,
                    hash,
                    total_size,
                    resume_offset,
                    Arc::clone(&rtc_conn),
                    label,
                    client_id,
                )
                .await;
            }

            ClientMessage::TransferCancel { id, .. } => {
                crate::log!("FS: Transfer cancel for {}", id);
                let resp = crate::fs_sync::transfer::handle_transfer_cancel(&id).await;
                if let Ok(json) = serde_json::to_string(&resp) {
                    let rtc_clone = Arc::clone(&rtc_conn);
                    let label_clone = label.to_string();
                    tokio::spawn(async move {
                        let conn = rtc_clone.lock().await;
                        let _ = conn.send_message(&label_clone, &Bytes::from(json)).await;
                    });
                }
            }

            ClientMessage::DownloadInit {
                id,
                path,
                resume_offset,
                ..
            } => {
                crate::log!(
                    "FS: Download init for {} ← {} (offset={})",
                    id,
                    path,
                    resume_offset
                );
                crate::fs_sync::transfer::handle_download_init(
                    &id,
                    &path,
                    resume_offset,
                    Arc::clone(&rtc_conn),
                    label,
                )
                .await;
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
                    match &command {
                        crate::ops::dc_message_parser::DcMsg::ListModels => {
                            let rtc = Arc::clone(&rtc_conn);
                            let lbl = label.to_string();
                            let msg_id = id.clone();

                            // Retrieve model directory from config or default
                            let model_dir = config.llm_model_dir.clone().unwrap_or_else(|| {
                                dirs::home_dir()
                                    .map(|mut p| {
                                        p.push("Models");
                                        p.to_string_lossy().to_string()
                                    })
                                    .unwrap_or_else(|| "~/.config/frankn/llms/".to_string())
                            });

                            tokio::spawn(async move {
                                let res = match crate::ops::llm::LlmManager::scan_models(&model_dir)
                                    .await
                                {
                                    Ok(_models) => Status::Success,
                                    Err(e) => Status::Error(e),
                                };

                                let data = crate::ops::llm::LlmManager::scan_models(&model_dir)
                                    .await
                                    .ok();

                                let response = HostMessage::Response {
                                    id: msg_id,
                                    status: res,
                                    data,
                                    timestamp: crate::utils::get_timestamp(),
                                };
                                if let Ok(json) = serde_json::to_string(&response) {
                                    let conn = rtc.lock().await;
                                    let _ = conn.send_message(&lbl, &Bytes::from(json)).await;
                                }
                            });
                        }
                        crate::ops::dc_message_parser::DcMsg::LlmStart { model_path } => {
                            let path = model_path.clone();
                            let llm = Arc::clone(&llm_manager);
                            let rtc = Arc::clone(&rtc_conn);
                            let lbl = label.to_string();
                            let msg_id = id.clone();
                            let cfg = Arc::clone(&config);
                            tokio::spawn(async move {
                                let res = match llm.lock().await.start_server(&path, &cfg).await {
                                    Ok(_) => Status::Success,
                                    Err(e) => Status::Error(e),
                                };
                                let response = HostMessage::Response {
                                    id: msg_id,
                                    status: res,
                                    data: None,
                                    timestamp: crate::utils::get_timestamp(),
                                };
                                if let Ok(json) = serde_json::to_string(&response) {
                                    let conn = rtc.lock().await;
                                    let _ = conn.send_message(&lbl, &Bytes::from(json)).await;
                                }
                            });
                        }
                        crate::ops::dc_message_parser::DcMsg::LlmChat {
                            message,
                            system_prompt,
                            chat_id,
                        } => {
                            let msg = message.clone();
                            let sys_prompt = system_prompt.clone();
                            let cid = chat_id.clone();
                            let llm = Arc::clone(&llm_manager);
                            let rtc = Arc::clone(&rtc_conn);
                            let lbl = label.to_string();
                            let msg_id = id.clone();
                            tokio::spawn(async move {
                                let (client, chats) = {
                                    let mut l = llm.lock().await;
                                    l.ensure_chats_loaded().await;
                                    (l.get_client(), l.get_chats())
                                };
                                crate::ops::llm::LlmManager::chat_stream_detached(
                                    client, chats, msg, sys_prompt, cid, msg_id, rtc, lbl,
                                )
                                .await;
                            });
                        }
                        crate::ops::dc_message_parser::DcMsg::LlmLoadChat { chat_id } => {
                            let cid = chat_id.clone();
                            let llm = Arc::clone(&llm_manager);
                            let rtc = Arc::clone(&rtc_conn);
                            let lbl = label.to_string();
                            let msg_id = id.clone();
                            tokio::spawn(async move {
                                let mut l = llm.lock().await;
                                let data = l.load_chat(&cid).await;
                                let res = match data {
                                    Some(ref _d) => Status::Success,
                                    None => Status::Error("Chat not found".to_string()),
                                };
                                let response = HostMessage::Response {
                                    id: msg_id,
                                    status: res,
                                    data,
                                    timestamp: crate::utils::get_timestamp(),
                                };
                                if let Ok(json) = serde_json::to_string(&response) {
                                    let conn = rtc.lock().await;
                                    let _ = conn.send_message(&lbl, &Bytes::from(json)).await;
                                }
                            });
                        }
                        crate::ops::dc_message_parser::DcMsg::LlmListChats => {
                            let llm = Arc::clone(&llm_manager);
                            let rtc = Arc::clone(&rtc_conn);
                            let lbl = label.to_string();
                            let msg_id = id.clone();
                            tokio::spawn(async move {
                                let mut l = llm.lock().await;
                                let data = l.list_chats().await;
                                let response = HostMessage::Response {
                                    id: msg_id,
                                    status: Status::Success,
                                    data: Some(data),
                                    timestamp: crate::utils::get_timestamp(),
                                };
                                if let Ok(json) = serde_json::to_string(&response) {
                                    let conn = rtc.lock().await;
                                    let _ = conn.send_message(&lbl, &Bytes::from(json)).await;
                                }
                            });
                        }
                        crate::ops::dc_message_parser::DcMsg::LlmDeleteChat { chat_id } => {
                            let cid = chat_id.clone();
                            let llm = Arc::clone(&llm_manager);
                            let rtc = Arc::clone(&rtc_conn);
                            let lbl = label.to_string();
                            let msg_id = id.clone();
                            tokio::spawn(async move {
                                let mut l = llm.lock().await;
                                let deleted = l.delete_chat(&cid).await;
                                let res = if deleted {
                                    Status::Success
                                } else {
                                    Status::Error("Chat not found".to_string())
                                };
                                let response = HostMessage::Response {
                                    id: msg_id,
                                    status: res,
                                    data: None,
                                    timestamp: crate::utils::get_timestamp(),
                                };
                                if let Ok(json) = serde_json::to_string(&response) {
                                    let conn = rtc.lock().await;
                                    let _ = conn.send_message(&lbl, &Bytes::from(json)).await;
                                }
                            });
                        }
                        crate::ops::dc_message_parser::DcMsg::LlmStop => {
                            let llm = Arc::clone(&llm_manager);
                            tokio::spawn(async move {
                                llm.lock().await.stop_server().await;
                            });
                        }
                        _ => {
                            let response = crate::ops::dc_message_parser::DcMsg::parse_msg(
                                &id,
                                &command,
                                params,
                                Arc::clone(&peer_map),
                                client_id,
                            )
                            .await;
                            if let Ok(json) = serde_json::to_string(&response) {
                                let rtc_clone = Arc::clone(&rtc_conn);
                                let label_clone = label.to_string();
                                tokio::spawn(async move {
                                    let conn = rtc_clone.lock().await;
                                    let _ = conn.send_message(&label_clone, &Bytes::from(json)).await;
                                });
                            }
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
async fn parse_binary_msg(data: &Vec<u8>, rtc_conn: Arc<Mutex<RTCConn>>, label: &str) {
    if label == "frankn_fs"
        && data.len() >= crate::fs_sync::transfer::FRAME_HEADER_SIZE
        && data[0] == 0x01
    {
        crate::fs_sync::transfer::handle_transfer_chunk_raw(data, rtc_conn, label).await;
    }
}
