use tokio::process::Command;

pub async fn get_wifi_status() -> bool {
    Command::new("nmcli").args(&["radio", "wifi"]).output().await
        .map(|o| String::from_utf8_lossy(&o.stdout).trim() == "enabled")
        .unwrap_or(false)
}

pub async fn get_bluetooth_status() -> bool {
    Command::new("rfkill").args(&["list", "bluetooth"]).output().await
        .map(|o| !String::from_utf8_lossy(&o.stdout).contains("Soft blocked: yes"))
        .unwrap_or(false)
}

pub async fn toggle_wifi(state: bool) {
    let arg = if state { "on" } else { "off" };
    let _ = Command::new("nmcli").args(&["radio", "wifi", arg]).output().await;
}

pub async fn toggle_bluetooth(state: bool) {
    let arg = if state { "unblock" } else { "block" };
    let _ = Command::new("rfkill").args(&[arg, "bluetooth"]).output().await;
}

pub async fn rescan_wifi() {
    let _ = Command::new("nmcli").args(&["dev", "wifi", "rescan"]).output().await;
}

pub async fn list_wifi_networks() -> Vec<serde_json::Value> {
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
    networks
}

pub async fn connect_wifi(ssid: &str, password: Option<&str>) -> bool {
    let mut cmd = Command::new("nmcli");
    cmd.args(&["dev", "wifi", "connect", ssid]);
    if let Some(pw) = password {
        cmd.args(&["password", pw]);
    }
    let output = cmd.output().await;
    output.map(|o| o.status.success()).unwrap_or(false)
}

pub async fn scan_bluetooth() {
    let _ = Command::new("bluetoothctl").args(&["--timeout", "10", "scan", "on"]).output().await;
}

pub async fn list_bluetooth_devices() -> Vec<serde_json::Value> {
    let mut devices = Vec::new();
    if let Ok(output) = Command::new("bluetoothctl").arg("devices").output().await {
        let out_str = String::from_utf8_lossy(&output.stdout);
        for line in out_str.lines() {
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
    devices
}

pub async fn connect_bluetooth(mac: &str) -> bool {
    let _ = Command::new("bluetoothctl").args(&["pair", mac]).output().await;
    let output = Command::new("bluetoothctl").args(&["connect", mac]).output().await;
    output.map(|o| o.status.success()).unwrap_or(false)
}
