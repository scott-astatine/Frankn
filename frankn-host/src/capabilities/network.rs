use crate::transport::context::CommandContext;
use crate::utils::Status;
use crate::platform::linux::network as linux_net;

pub async fn get_network_status(ctx: &CommandContext) {
    let wifi_on = linux_net::get_wifi_status().await;
    let bt_on = linux_net::get_bluetooth_status().await;

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
        linux_net::toggle_wifi(state).await;
    } else if radio == "bluetooth" {
        linux_net::toggle_bluetooth(state).await;
    }
    let _ = ctx.reply(
        Status::Success,
        Some(serde_json::json!({ "message": format!("{} turned {}", radio, state) })),
    ).await;
}

pub async fn list_wifi_networks(ctx: &CommandContext) {
    // Rescan in the background so we don't block the WebRTC response
    tokio::spawn(async {
        linux_net::rescan_wifi().await;
    });
    
    let networks = linux_net::list_wifi_networks().await;
    
    let _ = ctx.reply(
        Status::Success,
        Some(serde_json::json!({ "networks": networks })),
    ).await;
}

pub async fn connect_wifi(ctx: &CommandContext, ssid: &str, password: &Option<String>) {
    let success = linux_net::connect_wifi(ssid, password.as_deref()).await;
    
    let _ = ctx.reply(
        if success { Status::Success } else { Status::Error("Failed".to_string()) },
        Some(serde_json::json!({ "success": success })),
    ).await;
}

pub async fn list_bluetooth_devices(ctx: &CommandContext) {
    // Scan for new devices in the background
    tokio::spawn(async {
        linux_net::scan_bluetooth().await;
    });

    let devices = linux_net::list_bluetooth_devices().await;
    
    let _ = ctx.reply(
        Status::Success,
        Some(serde_json::json!({ "devices": devices })),
    ).await;
}

pub async fn connect_bluetooth(ctx: &CommandContext, mac: &str) {
    let success = linux_net::connect_bluetooth(mac).await;
    
    let _ = ctx.reply(
        if success { Status::Success } else { Status::Error("Failed".to_string()) },
        Some(serde_json::json!({ "success": success })),
    ).await;
}