use crate::{
    HostMessage,
    ops::rtc::RTCConn,
    utils::{Status, get_timestamp},
};
use std::sync::Arc;
use tokio::process::Command;
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
    let result = Command::new("shutdown").args(["/s", "/t", "0"]).output().await;
    #[cfg(target_os = "macos")]
    let result = Command::new("sudo")
        .args(["shutdown", "-h", "now"])
        .output().await;

    handle_res(id, result)
}

pub async fn reboot(id: &str, _rtc: Arc<Mutex<RTCConn>>) -> HostMessage {
    #[cfg(target_os = "linux")]
    let result = Command::new("systemctl").arg("reboot").output().await;
    #[cfg(target_os = "windows")]
    let result = Command::new("shutdown").args(["/r", "/t", "0"]).output().await;
    #[cfg(target_os = "macos")]
    let result = Command::new("sudo")
        .args(["shutdown", "-r", "now"])
        .output().await;

    handle_res(id, result)
}

pub async fn lock_screen(id: &str, _rtc: Arc<Mutex<RTCConn>>) -> HostMessage {
    #[cfg(target_os = "linux")]
    {
        let _ = Command::new("loginctl").arg("lock-session").output().await;
        // Spawn screen locker detached (do not await) to prevent event loop blocking
        let result = Command::new("hyprlock").spawn();
        handle_spawn_res(id, result)
    }
    #[cfg(target_os = "windows")]
    {
        let result = Command::new("rundll32.exe")
            .args(["user32.dll,LockWorkStation"])
            .output().await;
        handle_res(id, result)
    }
    #[cfg(target_os = "macos")]
    {
        let result = Command::new("pmset").args(["displaysleepnow"]).output().await;
        handle_res(id, result)
    }
}

pub async fn restart_host(id: &str, _rtc: Arc<Mutex<RTCConn>>) -> HostMessage {
    #[cfg(target_os = "linux")]
    let out = Command::new("systemctl")
        .args(["--user", "restart", "frankn-host"])
        .output()
        .await;
    handle_res(id, out)
}

pub async fn disconnect(id: &str, rtc: Arc<Mutex<RTCConn>>) -> HostMessage {
    let rtc = rtc.lock().await;
    let _ = rtc.peer_connection.close().await;
    HostMessage::Response {
        id: id.to_string(),
        status: Status::Success,
        data: None,
        timestamp: get_timestamp(),
    }
}

pub async fn system_log(
    id: &str,
    unit: &Option<String>,
    lines: &Option<u32>,
    priority: &Option<String>,
    since: &Option<String>,
    grep: &Option<String>,
    _rtc: Arc<Mutex<RTCConn>>,
) -> HostMessage {
    #[cfg(target_os = "linux")]
    {
        let mut cmd = Command::new("journalctl");
        cmd.arg("--no-pager");

        // Time window (default: last 5 minutes)
        let since_val = since
            .as_deref()
            .filter(|s| !s.trim().is_empty())
            .unwrap_or("-5m");
        cmd.args(["--since", since_val]);

        // Line cap (default: 200) to prevent massive payloads
        let n = lines.unwrap_or(200);
        cmd.args(["--lines", &n.to_string()]);

        // Unit filter (e.g. "sshd", "frankn-host", "NetworkManager")
        if let Some(u) = unit
            && !u.trim().is_empty()
        {
            cmd.arg(format!("--unit={}", u.trim()));
        }

        // Priority filter (e.g. "err", "warning", "info")
        if let Some(p) = priority
            && !p.trim().is_empty()
        {
            cmd.arg(format!("--priority={}", p.trim()));
        }

        // Keyword/grep filter (case-insensitive)
        if let Some(g) = grep
            && !g.trim().is_empty()
        {
            cmd.arg(format!("--grep={}", g.trim()));
            cmd.arg("--case-sensitive=false");
        }

        match cmd.output().await {
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
                timestamp: get_timestamp(),
            },
            Err(e) => HostMessage::Response {
                id: id.to_string(),
                status: Status::Error(e.to_string()),
                data: None,
                timestamp: get_timestamp(),
            },
        }
    }
    #[cfg(not(target_os = "linux"))]
    HostMessage::Response {
        id: id.to_string(),
        status: Status::Error("SystemLog only implemented for Linux".to_string()),
        data: None,
        timestamp: get_timestamp(),
    }
}

fn handle_res(id: &str, result: std::io::Result<std::process::Output>) -> HostMessage {

    match result {
        Ok(output) => HostMessage::Response {
            id: id.to_string(),
            status: if output.status.success() {
                Status::Success
            } else {
                Status::Error(format!(
                    "Action failed: {}",
                    String::from_utf8_lossy(&output.stderr)
                ))
            },
            data: Some(serde_json::json!({
                "stdout": String::from_utf8_lossy(&output.stdout),
                "stderr": String::from_utf8_lossy(&output.stderr)
            })),
            timestamp: get_timestamp(),
        },
        Err(e) => HostMessage::Response {
            id: id.to_string(),
            status: Status::Error(format!("Failed to execute process: {}", e)),
            data: None,
            timestamp: get_timestamp(),
        },
    }
}

fn handle_spawn_res(id: &str, result: std::io::Result<tokio::process::Child>) -> HostMessage {
    match result {
        Ok(_) => HostMessage::Response {
            id: id.to_string(),
            status: Status::Success,
            data: Some(serde_json::json!({ "message": "Command successfully spawned in background" })),
            timestamp: get_timestamp(),
        },
        Err(e) => HostMessage::Response {
            id: id.to_string(),
            status: Status::Error(format!("Failed to spawn process: {}", e)),
            data: None,
            timestamp: get_timestamp(),
        },
    }
}
