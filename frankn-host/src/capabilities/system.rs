use crate::transport::context::CommandContext;
use crate::utils::Status;

pub async fn ping(ctx: &CommandContext) {
    let _ = ctx.reply(Status::Success, Some(serde_json::json!({ "response": "Pong" }))).await;
}

pub async fn shutdown(ctx: &CommandContext, _args: &String) {
    #[cfg(target_os = "linux")]
    let result = crate::platform::linux::systemctl::shutdown().await;
    #[cfg(target_os = "windows")]
    let result = Command::new("shutdown").args(["/s", "/t", "0"]).output().await;
    #[cfg(target_os = "macos")]
    let result = Command::new("sudo")
        .args(["shutdown", "-h", "now"])
        .output().await;

    handle_res(ctx, result).await;
}

pub async fn reboot(ctx: &CommandContext) {
    #[cfg(target_os = "linux")]
    let result = crate::platform::linux::systemctl::reboot().await;
    #[cfg(target_os = "windows")]
    let result = Command::new("shutdown").args(["/r", "/t", "0"]).output().await;
    #[cfg(target_os = "macos")]
    let result = Command::new("sudo")
        .args(["shutdown", "-r", "now"])
        .output().await;

    handle_res(ctx, result).await;
}

pub async fn lock_screen(ctx: &CommandContext) {
    #[cfg(target_os = "linux")]
    {
        let result = crate::platform::linux::systemctl::lock_screen().await;
        handle_spawn_res(ctx, result).await;
    }
    #[cfg(target_os = "windows")]
    {
        let result = Command::new("rundll32.exe")
            .args(["user32.dll,LockWorkStation"])
            .output().await;
        handle_res(ctx, result).await;
    }
    #[cfg(target_os = "macos")]
    {
        let result = Command::new("pmset").args(["displaysleepnow"]).output().await;
        handle_res(ctx, result).await;
    }
}

pub async fn restart_host(ctx: &CommandContext) {
    #[cfg(target_os = "linux")]
    let out = crate::platform::linux::systemctl::restart_host().await;
    handle_res(ctx, out).await;
}

pub async fn disconnect(ctx: &CommandContext) {
    let rtc = ctx.rtc_conn.lock().await;
    let _ = rtc.peer_connection.close().await;
    let _ = ctx.reply(Status::Success, None).await;
}

pub async fn system_log(
    ctx: &CommandContext,
    unit: &Option<String>,
    lines: &Option<u32>,
    priority: &Option<String>,
    since: &Option<String>,
    grep: &Option<String>,
) {
    #[cfg(target_os = "linux")]
    {
        let result = crate::platform::linux::systemctl::get_system_log(unit, lines, priority, since, grep).await;
        match result {
            Ok(output) => {
                let _ = ctx.reply(
                    if output.status.success() {
                        Status::Success
                    } else {
                        Status::Error("Command failed".to_string())
                    },
                    Some(serde_json::json!({
                        "stdout": String::from_utf8_lossy(&output.stdout),
                        "stderr": String::from_utf8_lossy(&output.stderr)
                    })),
                ).await;
            }
            Err(e) => {
                let _ = ctx.reply(Status::Error(e.to_string()), None).await;
            }
        }
    }
    #[cfg(not(target_os = "linux"))]
    {
        let _ = ctx.reply(
            Status::Error("SystemLog only implemented for Linux".to_string()),
            None,
        ).await;
    }
}

async fn handle_res(ctx: &CommandContext, result: std::io::Result<std::process::Output>) {
    match result {
        Ok(output) => {
            let _ = ctx.reply(
                if output.status.success() {
                    Status::Success
                } else {
                    Status::Error(format!(
                        "Action failed: {}",
                        String::from_utf8_lossy(&output.stderr)
                    ))
                },
                Some(serde_json::json!({
                    "stdout": String::from_utf8_lossy(&output.stdout),
                    "stderr": String::from_utf8_lossy(&output.stderr)
                })),
            ).await;
        }
        Err(e) => {
            let _ = ctx.reply(
                Status::Error(format!("Failed to execute process: {}", e)),
                None,
            ).await;
        }
    }
}

async fn handle_spawn_res(ctx: &CommandContext, result: std::io::Result<tokio::process::Child>) {
    match result {
        Ok(_) => {
            let _ = ctx.reply(
                Status::Success,
                Some(serde_json::json!({ "message": "Command successfully spawned in background" })),
            ).await;
        }
        Err(e) => {
            let _ = ctx.reply(
                Status::Error(format!("Failed to spawn process: {}", e)),
                None,
            ).await;
        }
    }
}
