use crate::ops::rtc::{PeerMap, RTCConn};
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
    SystemLog { args: Option<String> },

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

macro_rules! dispatch {
    ($id:ident, $rtc:ident, $cmd:expr, {
        $($variant:ident $( { $($arg:ident),* } )? => $func:path),* $(,)?
    }) => {
        match $cmd {
            $(
                DcMsg::$variant { $($($arg,)*)? .. } => {
                    $func($id, $($($arg,)*)? $rtc).await
                }
            )*
            _ => HostMessage::Response {
                id: $id.to_string(),
                status: Status::Error("Command not dispatched".into()),
                data: None,
                timestamp: crate::utils::get_timestamp(),
            }
        }
    };
}

impl DcMsg {
    pub async fn parse_msg(
        id: &str,
        command: &DcMsg,
        _params: Option<serde_json::Value>,
        peer_map: PeerMap,
        client_id: &str,
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

        dispatch!(id, rtc_conn, command, {
            // System & Power
            Ping => ops::system::ping,
            Disconnect => ops::system::disconnect,
            Shutdown { args } => ops::system::shutdown,
            Reboot => ops::system::reboot,
            LockScreen => ops::system::lock_screen,
            RestartHostServer => ops::system::restart_host,

            // Media
            TogglePlayPause => ops::media::toggle_play_pause,
            PlayNextTrack => ops::media::next_track,
            PlayPreviousTrack => ops::media::previous_track,
            SetVolume { level } => ops::media::set_volume,
            Seek { position } => ops::media::seek,
            GetMediaStatus => ops::media::get_media_status,
            ListPlayers => ops::media::list_players,
            SetActivePlayer { player_name } => ops::media::set_active_player,

            // Audio Mixer
            GetAudioDevices => ops::media::get_all_audio_devices,
            SetDeviceVolume { target_id, volume } => ops::media::set_specific_device_volume,
            SetDefaultAudioDevice { target_id } => ops::media::set_default_audio_device,

            // Processes
            ListProcesses { sort_by, filter } => ops::proc_manager::list_processes,
            KillProcess { proc } => ops::proc_manager::kill_process,

            // File System
            Ls { path, sort_by, show_hidden } => _async_ls,
            DeleteFile { path } => _async_delete_file,

            // System Logs
            SystemLog { args } => _handle_system_log,

            // SSH
            StartSsh => ops::ssh::start_ssh_tunnel,
            StopSsh => ops::ssh::stop_ssh_tunnel,

            // Network
            GetNetworkStatus => ops::network::get_network_status,
            ToggleRadio { radio, state } => _async_toggle_radio,
            ListWifiNetworks => ops::network::list_wifi_networks,
            ConnectWifi { ssid, password } => _async_connect_wifi,
            ListBluetoothDevices => ops::network::list_bluetooth_devices,
            ConnectBluetooth { mac } => _async_connect_bluetooth,

            // Folder Sync
            SyncRequest { path } => _async_sync_request,
        })
    }
}

// --- Adapters ---

async fn _async_sync_request(
    id: &str,
    path: &String,
    _rtc: Arc<Mutex<RTCConn>>,
) -> HostMessage {
    // To be implemented in ops/sync.rs or fs_sync
    HostMessage::Response {
        id: id.to_string(),
        status: Status::Error("SyncRequest not yet implemented".into()),
        data: None,
        timestamp: crate::utils::get_timestamp(),
    }
}

async fn _async_ls(
    id: &str,
    path: &String,
    sort_by: &Option<String>,
    show_hidden: &Option<bool>,
    _rtc: Arc<Mutex<RTCConn>>,
) -> HostMessage {
    crate::fs_sync::ls(id, path, sort_by.clone(), *show_hidden)
}

async fn _async_delete_file(id: &str, path: &String, _rtc: Arc<Mutex<RTCConn>>) -> HostMessage {
    crate::fs_sync::delete_file(id, path)
}

async fn _handle_system_log(
    id: &str,
    args: &Option<String>,
    _rtc: Arc<Mutex<RTCConn>>,
) -> HostMessage {
    #[cfg(target_os = "linux")]
    {
        use tokio::process::Command;
        let mut cmd = Command::new("journalctl");
        cmd.args(["--no-pager", "--since", "-1m"]);
        if let Some(service) = args
            && !service.trim().is_empty()
        {
            cmd.arg(service);
        }
        let result = cmd.output().await;
        _handle_cmd_output(id, result)
    }
    #[cfg(not(target_os = "linux"))]
    HostMessage::Response {
        id: id.to_string(),
        status: Status::Error("SystemLog only implemented for Linux".to_string()),
        data: None,
        timestamp: crate::utils::get_timestamp(),
    }
}

fn _handle_cmd_output(id: &str, result: std::io::Result<std::process::Output>) -> HostMessage {
    match result {
        Ok(output) => HostMessage::Response {
            id: id.to_string(),
            status: if output.status.success() {
                Status::Success
            } else {
                Status::Error("Command failed".to_string())
            },
            data: Some(serde_json::json!({
                "stdout": String::from_utf8_lossy(&output.stdout),
                "stderr": String::from_utf8_lossy(&output.stderr)
            })),
            timestamp: crate::utils::get_timestamp(),
        },
        Err(e) => HostMessage::Response {
            id: id.to_string(),
            status: Status::Error(e.to_string()),
            data: None,
            timestamp: crate::utils::get_timestamp(),
        },
    }
}

async fn _async_toggle_radio(
    id: &str,
    radio: &String,
    state: &bool,
    rtc: Arc<Mutex<RTCConn>>,
) -> HostMessage {
    ops::network::toggle_radio(id, radio, *state, rtc).await
}

async fn _async_connect_wifi(
    id: &str,
    ssid: &String,
    password: &Option<String>,
    rtc: Arc<Mutex<RTCConn>>,
) -> HostMessage {
    ops::network::connect_wifi(id, ssid, password, rtc).await
}

async fn _async_connect_bluetooth(id: &str, mac: &String, rtc: Arc<Mutex<RTCConn>>) -> HostMessage {
    ops::network::connect_bluetooth(id, mac, rtc).await
}
