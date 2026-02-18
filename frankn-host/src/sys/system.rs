use tokio::process::Command;
use crate::{HostMessage, utils::{Status, get_timestamp}, sys::rtc::RTCConn};
use std::sync::Arc;
use tokio::sync::Mutex;

pub async fn ping(id: &str, _rtc: Arc<Mutex<RTCConn>>) -> HostMessage {
    HostMessage::Response {
        id: id.to_string(),
        status: Status::Success,
        data: Some(serde_json::json!({ "response": "Pong" })),
        timestamp: get_timestamp(),
    }
}

pub async fn shutdown(id: &str, _args: &String, _rtc: Arc<Mutex<RTCConn>>) -> HostMessage {
    #[cfg(target_os = "linux")]
    let result = Command::new("systemctl").arg("poweroff").output().await;
    #[cfg(target_os = "windows")]
    let result = Command::new("shutdown").args(["/s", "/t", "0"]).output();
    #[cfg(target_os = "macos")]
    let result = Command::new("sudo").args(["shutdown", "-h", "now"]).output();

    handle_res(id, result)
}

pub async fn reboot(id: &str, _rtc: Arc<Mutex<RTCConn>>) -> HostMessage {
    #[cfg(target_os = "linux")]
    let result = Command::new("systemctl").arg("reboot").output().await;
    #[cfg(target_os = "windows")]
    let result = Command::new("shutdown").args(["/r", "/t", "0"]).output();
    #[cfg(target_os = "macos")]
    let result = Command::new("sudo").args(["shutdown", "-r", "now"]).output();

    handle_res(id, result)
}

pub async fn lock_screen(id: &str, _rtc: Arc<Mutex<RTCConn>>) -> HostMessage {
    #[cfg(target_os = "linux")]
    {
        let _ = Command::new("loginctl").arg("lock-session").output().await;
        let result = Command::new("hyprlock").output().await;
        handle_res(id, result)
    }
    #[cfg(target_os = "windows")]
    {
        let result = Command::new("rundll32.exe").args(["user32.dll,LockWorkStation"]).output();
        handle_res(id, result)
    }
    #[cfg(target_os = "macos")]
    {
        let result = Command::new("pmset").args(["displaysleepnow"]).output();
        handle_res(id, result)
    }
}

fn handle_res(id: &str, result: std::io::Result<std::process::Output>) -> HostMessage {
    match result {
        Ok(output) => {
            HostMessage::Response {
                id: id.to_string(),
                status: if output.status.success() { Status::Success } else { Status::Error(format!("Action failed: {}", String::from_utf8_lossy(&output.stderr))) },
                data: Some(serde_json::json!({
                    "stdout": String::from_utf8_lossy(&output.stdout),
                    "stderr": String::from_utf8_lossy(&output.stderr)
                })),
                timestamp: get_timestamp(),
            }
        }
        Err(e) => HostMessage::Response {
            id: id.to_string(),
            status: Status::Error(format!("Failed to execute process: {}", e)),
            data: None,
            timestamp: get_timestamp(),
        },
    }
}
