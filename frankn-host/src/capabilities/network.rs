use crate::transport::context::CommandContext;
use crate::utils::Status;
use tokio::process::Command;

pub async fn get_network_status(ctx: &CommandContext) {
    let wifi_on = Command::new("nmcli").args(&["radio", "wifi"]).output().await
        .map(|o| String::from_utf8_lossy(&o.stdout).trim() == "enabled")
        .unwrap_or(false);

    let bt_on = Command::new("rfkill").args(&["list", "bluetooth"]).output().await
        .map(|o| !String::from_utf8_lossy(&o.stdout).contains("Soft blocked: yes"))
        .unwrap_or(false);

    let _ = ctx.reply(
        Status::Success,
        Some(serde_json::json!({
            "wifi_enabled": wifi_on,
            "bluetooth_enabled": bt_on
        })),
    ).await;
}

pub async fn toggle_radio(ctx: &CommandContext, radio: &str, state: bool) {
    if radio == "wifi" {
        let arg = if state { "on" } else { "off" };
        let _ = Command::new("nmcli").args(&["radio", "wifi", arg]).output().await;
    } else if radio == "bluetooth" {
        let arg = if state { "unblock" } else { "block" };
        let _ = Command::new("rfkill").args(&[arg, "bluetooth"]).output().await;
    }
    let _ = ctx.reply(
        Status::Success,
        Some(serde_json::json!({ "message": format!("{} turned {}", radio, state) })),
    ).await;
}

pub async fn list_wifi_networks(ctx: &CommandContext) {
    // Rescan in the background so we don't block the WebRTC response
    tokio::spawn(async {
        let _ = Command::new("nmcli").args(&["dev", "wifi", "rescan"]).output().await;
    });
    
    // Output format: IN-USE:SSID:SIGNAL:SECURITY
    let mut networks = Vec::new();
    if let Ok(output) = Command::new("nmcli").args(&["-t", "-f", "IN-USE,SSID,SIGNAL,SECURITY", "dev", "wifi", "list"]).output().await {
        let out_str = String::from_utf8_lossy(&output.stdout);
        for line in out_str.lines() {
            let parts: Vec<&str> = line.split(':').collect();
            if parts.len() >= 4 && !parts[1].is_empty() {
                networks.push(serde_json::json!({
                    "in_use": parts[0] == "*",
                    "ssid": parts[1],
                    "signal": parts[2].parse::<i32>().unwrap_or(0),
                    "security": parts[3]
                }));
            }
        }
    }
    
    let _ = ctx.reply(
        Status::Success,
        Some(serde_json::json!({ "networks": networks })),
    ).await;
}

pub async fn connect_wifi(ctx: &CommandContext, ssid: &str, password: &Option<String>) {
    let mut cmd = Command::new("nmcli");
    cmd.args(&["dev", "wifi", "connect", ssid]);
    if let Some(pw) = password {
        cmd.args(&["password", pw]);
    }
    
    let output = cmd.output().await;
    let success = output.map(|o| o.status.success()).unwrap_or(false);
    
    let _ = ctx.reply(
        if success { Status::Success } else { Status::Error("Failed".to_string()) },
        Some(serde_json::json!({ "success": success })),
    ).await;
}

pub async fn list_bluetooth_devices(ctx: &CommandContext) {
    // Scan for new devices in the background
    tokio::spawn(async {
        let _ = Command::new("bluetoothctl").args(&["--timeout", "10", "scan", "on"]).output().await;
    });

    let mut devices = Vec::new();
    if let Ok(output) = Command::new("bluetoothctl").arg("devices").output().await {
        let out_str = String::from_utf8_lossy(&output.stdout);
        for line in out_str.lines() {
            // Line format: Device MAC_ADDRESS Name
            if line.starts_with("Device ") {
                let parts: Vec<&str> = line.splitn(3, ' ').collect();
                if parts.len() == 3 {
                    let mac = parts[1];
                    let name = parts[2];
                    
                    let connected = if let Ok(info) = Command::new("bluetoothctl").args(&["info", mac]).output().await {
                        String::from_utf8_lossy(&info.stdout).contains("Connected: yes")
                    } else {
                        false
                    };

                    devices.push(serde_json::json!({
                        "mac": mac,
                        "name": name,
                        "connected": connected
                    }));
                }
            }
        }
    }
    
    let _ = ctx.reply(
        Status::Success,
        Some(serde_json::json!({ "devices": devices })),
    ).await;
}

pub async fn connect_bluetooth(ctx: &CommandContext, mac: &str) {
    // Attempt pair then connect
    let _ = Command::new("bluetoothctl").args(&["pair", mac]).output().await;
    let output = Command::new("bluetoothctl").args(&["connect", mac]).output().await;
    let success = output.map(|o| o.status.success()).unwrap_or(false);
    
    let _ = ctx.reply(
        if success { Status::Success } else { Status::Error("Failed".to_string()) },
        Some(serde_json::json!({ "success": success })),
    ).await;
}