use tokio::process::Command;

pub async fn shutdown() -> std::io::Result<std::process::Output> {
    Command::new("systemctl").arg("poweroff").output().await
}

pub async fn reboot() -> std::io::Result<std::process::Output> {
    Command::new("systemctl").arg("reboot").output().await
}

pub async fn lock_screen() -> std::io::Result<tokio::process::Child> {
    let _ = Command::new("loginctl").arg("lock-session").output().await;
    // Spawn screen locker detached (do not await) to prevent event loop blocking
    Command::new("hyprlock").spawn()
}

pub async fn restart_host() -> std::io::Result<std::process::Output> {
    Command::new("systemctl")
        .args(["--user", "restart", "frankn-host"])
        .output()
        .await
}

pub async fn get_system_log(
    unit: &Option<String>,
    lines: &Option<u32>,
    priority: &Option<String>,
    since: &Option<String>,
    grep: &Option<String>,
) -> std::io::Result<std::process::Output> {
    let mut cmd = Command::new("journalctl");
    cmd.arg("--no-pager");

    let since_val = since
        .as_deref()
        .filter(|s| !s.trim().is_empty())
        .unwrap_or("-5m");
    cmd.args(["--since", since_val]);

    let n = lines.unwrap_or(200);
    cmd.args(["--lines", &n.to_string()]);

    if let Some(u) = unit
        && !u.trim().is_empty()
    {
        cmd.arg(format!("--unit={}", u.trim()));
    }

    if let Some(p) = priority
        && !p.trim().is_empty()
    {
        cmd.arg(format!("--priority={}", p.trim()));
    }

    if let Some(g) = grep
        && !g.trim().is_empty()
    {
        cmd.arg(format!("--grep={}", g.trim()));
        cmd.arg("--case-sensitive=false");
    }

    cmd.output().await
}
