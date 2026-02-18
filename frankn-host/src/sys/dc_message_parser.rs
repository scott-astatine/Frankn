use crate::sys::rtc::{PeerMap, RTCConn};
use crate::{HostMessage, sys, utils::Status};
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
    ListProcesses,

    // --- File System ---
    #[serde(rename = "ls")]
    Ls {
        path: String,
        sort_by: Option<String>,
        show_hidden: Option<bool>,
    },
    #[serde(rename = "get_file")]
    GetFile { path: String },
    #[serde(rename = "delete_file")]
    DeleteFile { path: String },

    // --- Audio Mixer ---
    #[serde(rename = "get_audio_devices")]
    GetAudioDevices,
    #[serde(rename = "set_device_volume")]
    SetDeviceVolume { target_id: String, volume: f64 },
    #[serde(rename = "set_default_audio_device")]
    SetDefaultAudioDevice { target_id: String },

    // --- Media Control ---
    #[serde(rename = "start_media_sync")]
    StartMediaSync,
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
            Ping => sys::system::ping,
            Shutdown { args } => sys::system::shutdown,
            Reboot => sys::system::reboot,
            LockScreen => sys::system::lock_screen,

            // Media
            StartMediaSync => sys::media::handle_start_media_sync,
            TogglePlayPause => sys::media::toggle_play_pause,
            PlayNextTrack => sys::media::next_track,
            PlayPreviousTrack => sys::media::previous_track,
            SetVolume { level } => sys::media::set_volume,
            Seek { position } => sys::media::seek,
            GetMediaStatus => sys::media::get_media_status,
            ListPlayers => sys::media::list_players,
            SetActivePlayer { player_name } => sys::media::set_active_player,

            // Audio Mixer
            GetAudioDevices => sys::media::get_all_audio_devices,
            SetDeviceVolume { target_id, volume } => sys::media::set_specific_device_volume,
            SetDefaultAudioDevice { target_id } => sys::media::set_default_audio_device,

            // Processes
            ListProcesses => sys::proc_manager::list_processes,
            KillProcess { proc } => sys::proc_manager::kill_process,

            // File System
            Ls { path, sort_by, show_hidden } => _async_ls,
            GetFile { path } => _async_get_file,
            DeleteFile { path } => _async_delete_file,

            // System Logs
            SystemLog { args } => _handle_system_log,

            // SSH
            StartSsh => sys::ssh::start_ssh_tunnel,
            StopSsh => sys::ssh::stop_ssh_tunnel,
        })
    }
}

// --- Adapters ---

async fn _async_ls(
    id: &str,
    path: &String,
    sort_by: &Option<String>,
    show_hidden: &Option<bool>,
    _rtc: Arc<Mutex<RTCConn>>,
) -> HostMessage {
    crate::fs_sync::ls(id, path, sort_by.clone(), show_hidden.clone())
}

async fn _async_get_file(id: &str, path: &String, rtc: Arc<Mutex<RTCConn>>) -> HostMessage {
    crate::fs_sync::get_file(id, path, rtc).await
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
        cmd.args(["-n", "50", "--no-pager"]);
        if let Some(service) = args {
            if !service.trim().is_empty() {
                cmd.arg("-u").arg(service);
            }
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
