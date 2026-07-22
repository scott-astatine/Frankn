use crate::capabilities;
use crate::capabilities::inference::LlmManager;
use crate::config::HostConfig;
use crate::transport::protocol::messages::{HostMessage, Status};
use crate::transport::webrtc::connection::PeerMap;
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tokio::sync::Mutex;

#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(tag = "dc_msg_type")]
pub enum DcMsg {
    // --- System / Power ---
    #[serde(rename = "ping")]
    Ping,
    #[serde(rename = "shutdown")]
    Shutdown { args: String },
    #[serde(rename = "disconnect")]
    Disconnect,
    #[serde(rename = "reboot")]
    Reboot,
    #[serde(rename = "lock_screen")]
    LockScreen,
    #[serde(rename = "unlock_screen")]
    UnlockScreen,
    #[serde(rename = "update")]
    Update,
    #[serde(rename = "restart_host_server")]
    RestartHostServer,
    #[serde(rename = "system_log")]
    SystemLog {
        unit: Option<String>,
        lines: Option<u32>,
        priority: Option<String>,
        since: Option<String>,
        grep: Option<String>,
    },

    // --- Processes ---
    #[serde(rename = "kill")]
    KillProcess { proc: String },
    #[serde(rename = "list_processes")]
    ListProcesses {
        sort_by: Option<String>,
        filter: Option<String>,
    },

    // --- File System ---
    #[serde(rename = "ls")]
    Ls {
        path: String,
        sort_by: Option<String>,
        show_hidden: Option<bool>,
    },
    #[serde(rename = "mkdir")]
    Mkdir { path: String },
    #[serde(rename = "delete_file")]
    DeleteFile { path: String },

    // --- LLM ---
    #[serde(rename = "list_models")]
    ListModels,
    #[serde(rename = "llm_start")]
    LlmStart { model_path: String },
    #[serde(rename = "llm_chat")]
    LlmChat {
        message: String,
        system_prompt: Option<String>,
        chat_id: Option<String>,
    },
    #[serde(rename = "llm_load_chat")]
    LlmLoadChat { chat_id: String },
    #[serde(rename = "llm_delete_chat")]
    LlmDeleteChat { chat_id: String },
    #[serde(rename = "llm_list_chats")]
    LlmListChats,
    #[serde(rename = "llm_stop")]
    LlmStop,
    #[serde(rename = "tool_approval_response")]
    ToolApprovalResponse { approval_id: String, approved: bool },

    // --- SSH ---
    #[serde(rename = "get_audio_devices")]
    GetAudioDevices,
    #[serde(rename = "set_device_volume")]
    SetDeviceVolume { target_id: String, volume: f64 },
    #[serde(rename = "set_default_audio_device")]
    SetDefaultAudioDevice { target_id: String },

    // --- Media Control ---
    #[serde(rename = "toggle_play_pause")]
    TogglePlayPause,
    #[serde(rename = "play_next_track")]
    PlayNextTrack,
    #[serde(rename = "play_previous_track")]
    PlayPreviousTrack,
    #[serde(rename = "set_volume")]
    SetVolume { level: f64 },
    #[serde(rename = "get_media_status")]
    GetMediaStatus,
    #[serde(rename = "list_players")]
    ListPlayers,
    #[serde(rename = "set_active_player")]
    SetActivePlayer { player_name: String },
    #[serde(rename = "seek")]
    Seek { position: u64 },

    // --- SSH ---
    #[serde(rename = "start_ssh")]
    StartSsh,
    #[serde(rename = "stop_ssh")]
    StopSsh,

    // --- Network ---
    #[serde(rename = "get_network_status")]
    GetNetworkStatus,
    #[serde(rename = "toggle_radio")]
    ToggleRadio { radio: String, state: bool },
    #[serde(rename = "list_wifi_networks")]
    ListWifiNetworks,
    #[serde(rename = "connect_wifi")]
    ConnectWifi {
        ssid: String,
        password: Option<String>,
    },
    #[serde(rename = "list_bluetooth_devices")]
    ListBluetoothDevices,
    #[serde(rename = "connect_bluetooth")]
    ConnectBluetooth { mac: String },

    // --- Folder Sync ---
    #[serde(rename = "sync_request")]
    SyncRequest { path: String },
}

impl DcMsg {
    pub async fn parse_msg(
        id: &str,
        command: &DcMsg,
        peer_map: PeerMap,
        client_id: &str,
        label: &str,
        llm_manager: Arc<Mutex<LlmManager>>,
        config: Arc<HostConfig>,
    ) -> Option<HostMessage> {
        let rtc_conn = {
            let map = peer_map.lock().await;
            match map.get(client_id) {
                Some(conn) => Arc::clone(conn),
                None => {
                    return Some(HostMessage::Response {
                        id: id.to_string(),
                        status: Status::Error("Client link lost.".into()),
                        data: None,
                        timestamp: crate::utils::get_timestamp(),
                    });
                }
            }
        };

        let ctx = crate::transport::context::CommandContext::new(
            id.to_string(),
            client_id.to_string(),
            label.to_string(),
            Arc::clone(&config),
            Arc::clone(&rtc_conn),
        );

        match command {
            // --- System & Power ---
            DcMsg::Ping => {
                capabilities::system::ping(&ctx).await;
                None
            }
            DcMsg::Disconnect => {
                capabilities::system::disconnect(&ctx).await;
                None
            }
            DcMsg::Shutdown { args } => {
                capabilities::system::shutdown(&ctx, args).await;
                None
            }
            DcMsg::Reboot => {
                capabilities::system::reboot(&ctx).await;
                None
            }
            DcMsg::LockScreen => {
                capabilities::system::lock_screen(&ctx).await;
                None
            }
            DcMsg::UnlockScreen => Some(HostMessage::Response {
                id: id.to_string(),
                status: Status::Error("Unlock screen not implemented natively".to_string()),
                data: None,
                timestamp: crate::utils::get_timestamp(),
            }),
            DcMsg::Update => Some(HostMessage::Response {
                id: id.to_string(),
                status: Status::Error("System update not implemented natively".to_string()),
                data: None,
                timestamp: crate::utils::get_timestamp(),
            }),
            DcMsg::RestartHostServer => {
                capabilities::system::restart_host(&ctx).await;
                None
            }
            DcMsg::SystemLog {
                unit,
                lines,
                priority,
                since,
                grep,
            } => {
                capabilities::system::system_log(&ctx, unit, lines, priority, since, grep).await;
                None
            }

            // --- Processes ---
            DcMsg::ListProcesses { sort_by, filter } => {
                capabilities::proc_manager::list_processes(&ctx, sort_by, filter).await;
                None
            }
            DcMsg::KillProcess { proc } => {
                capabilities::proc_manager::kill_process(&ctx, proc).await;
                None
            }

            // --- File System ---
            DcMsg::Ls {
                path,
                sort_by,
                show_hidden,
            } => {
                capabilities::fs::ls(&ctx, path, sort_by.clone(), *show_hidden).await;
                None
            }
            DcMsg::Mkdir { path } => {
                capabilities::fs::mkdir(&ctx, path).await;
                None
            }
            DcMsg::DeleteFile { path } => {
                capabilities::fs::delete_file(&ctx, path).await;
                None
            }

            // --- LLM ---
            DcMsg::ListModels => {
                LlmManager::handle_list_models(&ctx).await;
                None
            }
            DcMsg::LlmStart { model_path } => {
                LlmManager::handle_start(&ctx, model_path, Arc::clone(&llm_manager)).await;
                None
            }
            DcMsg::LlmChat {
                message,
                system_prompt,
                chat_id,
            } => {
                LlmManager::handle_chat(
                    &ctx,
                    message,
                    system_prompt,
                    chat_id,
                    Arc::clone(&llm_manager),
                )
                .await;
                None
            }
            DcMsg::LlmLoadChat { chat_id } => {
                LlmManager::handle_load_chat(&ctx, chat_id, Arc::clone(&llm_manager)).await;
                None
            }
            DcMsg::LlmListChats => {
                LlmManager::handle_list_chats(&ctx, Arc::clone(&llm_manager)).await;
                None
            }
            DcMsg::LlmDeleteChat { chat_id } => {
                LlmManager::handle_delete_chat(&ctx, chat_id, Arc::clone(&llm_manager)).await;
                None
            }
            DcMsg::LlmStop => {
                LlmManager::handle_stop(&ctx, Arc::clone(&llm_manager)).await;
                None
            }
            DcMsg::ToolApprovalResponse {
                approval_id,
                approved,
            } => {
                let mut l = llm_manager.lock().await;
                if let Some(tx) = l.approval_registry.remove(approval_id) {
                    let _ = tx.send(*approved);
                }
                Some(HostMessage::Response {
                    id: id.to_string(),
                    status: Status::Success,
                    data: None,
                    timestamp: crate::utils::get_timestamp(),
                })
            }

            // --- Media Control ---
            DcMsg::GetAudioDevices => {
                capabilities::media::get_all_audio_devices(&ctx).await;
                None
            }
            DcMsg::SetDeviceVolume { target_id, volume } => {
                capabilities::media::set_specific_device_volume(&ctx, target_id, volume).await;
                None
            }
            DcMsg::SetDefaultAudioDevice { target_id } => {
                capabilities::media::set_default_audio_device(&ctx, target_id).await;
                None
            }
            DcMsg::TogglePlayPause => {
                capabilities::media::toggle_play_pause(&ctx).await;
                None
            }
            DcMsg::PlayNextTrack => {
                capabilities::media::next_track(&ctx).await;
                None
            }
            DcMsg::PlayPreviousTrack => {
                capabilities::media::previous_track(&ctx).await;
                None
            }
            DcMsg::SetVolume { level } => {
                capabilities::media::set_volume(&ctx, level).await;
                None
            }
            DcMsg::GetMediaStatus => {
                capabilities::media::get_media_status(&ctx).await;
                None
            }
            DcMsg::ListPlayers => {
                capabilities::media::list_players(&ctx).await;
                None
            }
            DcMsg::SetActivePlayer { player_name } => {
                capabilities::media::set_active_player(&ctx, player_name).await;
                None
            }
            DcMsg::Seek { position } => {
                capabilities::media::seek(&ctx, position).await;
                None
            }

            // --- SSH ---
            DcMsg::StartSsh => {
                capabilities::ssh::start_ssh_tunnel(&ctx).await;
                None
            }
            DcMsg::StopSsh => {
                capabilities::ssh::stop_ssh_tunnel(&ctx).await;
                None
            }

            // --- Network ---
            DcMsg::GetNetworkStatus => {
                capabilities::network::get_network_status(&ctx).await;
                None
            }
            DcMsg::ToggleRadio { radio, state } => {
                capabilities::network::toggle_radio(&ctx, radio, *state).await;
                None
            }
            DcMsg::ListWifiNetworks => {
                capabilities::network::list_wifi_networks(&ctx).await;
                None
            }
            DcMsg::ConnectWifi { ssid, password } => {
                capabilities::network::connect_wifi(&ctx, ssid, password).await;
                None
            }
            DcMsg::ListBluetoothDevices => {
                capabilities::network::list_bluetooth_devices(&ctx).await;
                None
            }
            DcMsg::ConnectBluetooth { mac } => {
                capabilities::network::connect_bluetooth(&ctx, mac).await;
                None
            }

            // --- Folder Sync ---
            DcMsg::SyncRequest { path } => {
                capabilities::fs::sync::handle_sync_request(&ctx, path).await;
                None
            }
        }
    }
}
