use crate::ops::rtc::PeerMap;
use crate::{HostMessage, ops, utils::Status};
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
        llm_manager: Arc<Mutex<crate::ops::llm::LlmManager>>,
        config: Arc<crate::config::HostConfig>,
    ) -> HostMessage {
        let rtc_conn = {
            let map = peer_map.lock().await;
            match map.get(client_id) {
                Some(conn) => Arc::clone(conn),
                None => {
                    return HostMessage::Response {
                        id: id.to_string(),
                        status: Status::Error("Client link lost.".into()),
                        data: None,
                        timestamp: crate::utils::get_timestamp(),
                    };
                }
            }
        };

        match command {
            // --- System & Power ---
            DcMsg::Ping => ops::system::ping(id, rtc_conn).await,
            DcMsg::Disconnect => ops::system::disconnect(id, rtc_conn).await,
            DcMsg::Shutdown { args } => ops::system::shutdown(id, args, rtc_conn).await,
            DcMsg::Reboot => ops::system::reboot(id, rtc_conn).await,
            DcMsg::LockScreen => ops::system::lock_screen(id, rtc_conn).await,
            DcMsg::UnlockScreen => HostMessage::Response {
                id: id.to_string(),
                status: Status::Error("Unlock screen not implemented natively".to_string()),
                data: None,
                timestamp: crate::utils::get_timestamp(),
            },
            DcMsg::Update => HostMessage::Response {
                id: id.to_string(),
                status: Status::Error("System update not implemented natively".to_string()),
                data: None,
                timestamp: crate::utils::get_timestamp(),
            },
            DcMsg::RestartHostServer => ops::system::restart_host(id, rtc_conn).await,
            DcMsg::SystemLog { unit, lines, priority, since, grep } => {
                ops::system::system_log(id, unit, lines, priority, since, grep, rtc_conn).await
            }

            // --- Processes ---
            DcMsg::ListProcesses { sort_by, filter } => {
                ops::proc_manager::list_processes(id, sort_by, filter, rtc_conn).await
            }
            DcMsg::KillProcess { proc } => {
                ops::proc_manager::kill_process(id, proc, rtc_conn).await
            }

            // --- File System ---
            DcMsg::Ls {
                path,
                sort_by,
                show_hidden,
            } => crate::fs_sync::ls(id, path, sort_by.clone(), *show_hidden),
            DcMsg::Mkdir { path } => crate::fs_sync::mkdir(id, path),
            DcMsg::DeleteFile { path } => crate::fs_sync::delete_file(id, path),

            // --- LLM ---
            DcMsg::ListModels => ops::llm::LlmManager::handle_list_models(id, &config).await,
            DcMsg::LlmStart { model_path } => {
                ops::llm::LlmManager::handle_start(
                    id,
                    model_path,
                    Arc::clone(&llm_manager),
                    &config,
                )
                .await
            }
            DcMsg::LlmChat {
                message,
                system_prompt,
                chat_id,
            } => {
                ops::llm::LlmManager::handle_chat(
                    id,
                    message,
                    system_prompt,
                    chat_id,
                    Arc::clone(&llm_manager),
                    Arc::clone(&rtc_conn),
                    label,
                )
                .await
            }
            DcMsg::LlmLoadChat { chat_id } => {
                ops::llm::LlmManager::handle_load_chat(id, chat_id, Arc::clone(&llm_manager)).await
            }
            DcMsg::LlmListChats => {
                ops::llm::LlmManager::handle_list_chats(id, Arc::clone(&llm_manager)).await
            }
            DcMsg::LlmDeleteChat { chat_id } => {
                ops::llm::LlmManager::handle_delete_chat(id, chat_id, Arc::clone(&llm_manager))
                    .await
            }
            DcMsg::LlmStop => ops::llm::LlmManager::handle_stop(id, Arc::clone(&llm_manager)).await,

            // --- Media Control ---
            DcMsg::GetAudioDevices => ops::media::get_all_audio_devices(id, rtc_conn).await,
            DcMsg::SetDeviceVolume { target_id, volume } => {
                ops::media::set_specific_device_volume(id, target_id, volume, rtc_conn).await
            }
            DcMsg::SetDefaultAudioDevice { target_id } => {
                ops::media::set_default_audio_device(id, target_id, rtc_conn).await
            }
            DcMsg::TogglePlayPause => ops::media::toggle_play_pause(id, rtc_conn).await,
            DcMsg::PlayNextTrack => ops::media::next_track(id, rtc_conn).await,
            DcMsg::PlayPreviousTrack => ops::media::previous_track(id, rtc_conn).await,
            DcMsg::SetVolume { level } => ops::media::set_volume(id, level, rtc_conn).await,
            DcMsg::GetMediaStatus => ops::media::get_media_status(id, rtc_conn).await,
            DcMsg::ListPlayers => ops::media::list_players(id, rtc_conn).await,
            DcMsg::SetActivePlayer { player_name } => {
                ops::media::set_active_player(id, player_name, rtc_conn).await
            }
            DcMsg::Seek { position } => ops::media::seek(id, position, rtc_conn).await,

            // --- SSH ---
            DcMsg::StartSsh => ops::ssh::start_ssh_tunnel(id, rtc_conn).await,
            DcMsg::StopSsh => ops::ssh::stop_ssh_tunnel(id, rtc_conn).await,

            // --- Network ---
            DcMsg::GetNetworkStatus => ops::network::get_network_status(id, rtc_conn).await,
            DcMsg::ToggleRadio { radio, state } => {
                ops::network::toggle_radio(id, radio, *state, rtc_conn).await
            }
            DcMsg::ListWifiNetworks => ops::network::list_wifi_networks(id, rtc_conn).await,
            DcMsg::ConnectWifi { ssid, password } => {
                ops::network::connect_wifi(id, ssid, password, rtc_conn).await
            }
            DcMsg::ListBluetoothDevices => ops::network::list_bluetooth_devices(id, rtc_conn).await,
            DcMsg::ConnectBluetooth { mac } => {
                ops::network::connect_bluetooth(id, mac, rtc_conn).await
            }

            // --- Folder Sync ---
            DcMsg::SyncRequest { path } => {
                crate::fs_sync::sync::handle_sync_request(id, path, rtc_conn, "frankn_cmd").await
            }
        }
    }
}
