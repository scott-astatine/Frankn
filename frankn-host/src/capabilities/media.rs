use crate::{
    HostMessage,
    transport::context::CommandContext,
    transport::webrtc::connection::PeerMap,
    utils::Status,
};
use std::sync::Arc;
use tokio_tungstenite::tungstenite::Bytes;

pub async fn toggle_play_pause(ctx: &CommandContext) {
    #[cfg(target_os = "linux")]
    let _ = crate::platform::linux::mpris::toggle_play_pause().await;
    get_media_status(ctx).await;
}

pub async fn next_track(ctx: &CommandContext) {
    #[cfg(target_os = "linux")]
    let _ = crate::platform::linux::mpris::next_track().await;
    get_media_status(ctx).await;
}

pub async fn previous_track(ctx: &CommandContext) {
    #[cfg(target_os = "linux")]
    let _ = crate::platform::linux::mpris::previous_track().await;
    get_media_status(ctx).await;
}

pub async fn seek(ctx: &CommandContext, position: &u64) {
    #[cfg(target_os = "linux")]
    {
        let _ = crate::platform::linux::mpris::seek(*position).await;
    }
    get_media_status(ctx).await;
}

pub async fn set_volume(ctx: &CommandContext, level: &f64) {
    let clamped_level = level.clamp(0.0, 1.5);
    let vol_str = format!("{:.2}", clamped_level);
    #[cfg(target_os = "linux")]
    let _ = tokio::process::Command::new("wpctl")
        .args(["set-volume", "@DEFAULT_AUDIO_SINK@", &vol_str])
        .output()
        .await;
    get_media_status(ctx).await;
}

pub async fn list_players(ctx: &CommandContext) {
    #[cfg(target_os = "linux")]
    {
        let (players_list, current) = crate::platform::linux::mpris::list_players().await;
        let _ = ctx.reply(Status::Success, Some(serde_json::json!({
            "players": players_list,
            "active_player": current
        }))).await;
    }
    #[cfg(not(target_os = "linux"))]
    {
        let _ = ctx.reply(Status::Success, Some(serde_json::json!({
            "players": Vec::<String>::new(),
            "active_player": None::<String>
        }))).await;
    }
}

pub async fn set_active_player(ctx: &CommandContext, player_name: &String) {
    #[cfg(target_os = "linux")]
    {
        crate::platform::linux::mpris::set_active_player(player_name).await;
    }
    let _ = ctx.reply(Status::Success, Some(serde_json::json!({
        "message": format!("Active player set to {}", player_name)
    }))).await;
}

pub async fn get_media_status(ctx: &CommandContext) {
    #[cfg(target_os = "linux")]
    {
        match crate::platform::linux::mpris::get_media_status().await {
            Ok(d) => {
                let _ = ctx.reply(Status::Success, Some(serde_json::json!({
                    "player_name": Some(d.player_name.clone()),
                    "playing": d.status.to_lowercase().contains("playing"),
                    "art_data": d.art_data,
                    "position": Some(d.position),
                    "length": Some(d.length),
                    "volume": Some(d.volume),
                    "metadata": Some(format!("{} - {}", d.title, d.artist)),
                }))).await;
            }
            Err(_) => {
                let _ = ctx.reply(Status::Success, Some(serde_json::json!({
                    "player_name": None::<String>,
                    "playing": false,
                    "metadata": Some("No Media".to_string()),
                    "art_data": None::<String>,
                    "position": None::<u64>,
                    "length": None::<u64>,
                    "volume": None::<f64>,
                }))).await;
            }
        }
    }
    #[cfg(not(target_os = "linux"))]
    {
        let _ = ctx.reply(
            Status::Success,
            Some(serde_json::json!({ "media_status": "unknown" })),
        ).await;
    }
}

pub async fn start_media_sync(peer_map: PeerMap) {
    #[cfg(target_os = "linux")]
    {
        let pm_metadata = Arc::clone(&peer_map);

        tokio::spawn(async move {
            crate::log!("Neural Media Engine: Initializing event loop...");
            let mut last_metadata_sig = String::new();
            let mut last_client_count = 0;

            loop {
                let current_clients = {
                    let map = pm_metadata.lock().await;
                    map.len()
                };

                if current_clients == 0 {
                    last_client_count = 0;
                    tokio::time::sleep(tokio::time::Duration::from_secs(2)).await;
                    continue;
                }

                match crate::platform::linux::mpris::get_media_status().await {
                    Ok(mut d) => {
                        if d.player_name.as_str().to_lowercase().contains("firef") {
                            d.player_name = "Zen".to_string();
                        }

                        let art_len = d.art_data.as_ref().map(|s| s.len()).unwrap_or(0);
                        let sig = format!(
                            "{} {} {} {} {} pos: {} art_len: {}",
                            d.player_name,
                            d.status,
                            d.title,
                            d.length,
                            d.volume,
                            d.position,
                            art_len
                        );

                        let force_update = current_clients > last_client_count;
                        last_client_count = current_clients;

                        if sig != last_metadata_sig || force_update {
                            last_metadata_sig = sig.clone();

                            let msg = HostMessage::MediaUpdate {
                                player_name: Some(d.player_name.clone()),
                                playing: d.status.to_lowercase().contains("playing"),
                                metadata: Some(format!("{} - {}", d.title, d.artist)),
                                art_data: d.art_data,
                                position: Some(d.position),
                                length: Some(d.length),
                                timestamp: crate::utils::get_timestamp(),
                                volume: Some(d.volume),
                            };

                            if let Ok(json) = serde_json::to_string(&msg) {
                                let map = pm_metadata.lock().await;
                                for conn in map.values() {
                                    let r_conn = conn.lock().await;
                                    let _ = r_conn
                                        .send_message("frankn_media", &Bytes::from(json.clone()))
                                        .await;
                                }
                            }
                        }
                    }
                    Err(_) => {
                        if !last_metadata_sig.is_empty() {
                            last_metadata_sig = String::new();
                            let msg = HostMessage::MediaUpdate {
                                player_name: None,
                                playing: false,
                                metadata: Some("No Media".into()),
                                art_data: None,
                                position: None,
                                length: None,
                                volume: None,
                                timestamp: crate::utils::get_timestamp(),
                            };
                            if let Ok(json) = serde_json::to_string(&msg) {
                                let map = pm_metadata.lock().await;
                                for conn in map.values() {
                                    let r_conn = conn.lock().await;
                                    let _ = r_conn
                                        .send_message("frankn_media", &Bytes::from(json.clone()))
                                        .await;
                                }
                            }
                        }
                    }
                }
                tokio::time::sleep(tokio::time::Duration::from_millis(1000)).await;
            }
        });
    }
}

pub async fn get_all_audio_devices(ctx: &CommandContext) {
    #[cfg(target_os = "linux")]
    {
        use serde_json::json;

        let mut devices = Vec::new();

        let default_sink = if let Ok(output) = tokio::process::Command::new("pactl")
            .args(["get-default-sink"])
            .output()
            .await
        {
            String::from_utf8_lossy(&output.stdout).trim().to_string()
        } else {
            String::new()
        };

        if let Ok(output) = tokio::process::Command::new("pactl")
            .args(["-f", "json", "list", "sinks"])
            .output()
            .await
            && let Ok(json_str) = String::from_utf8(output.stdout)
            && let Ok(sinks) = serde_json::from_str::<serde_json::Value>(&json_str)
            && let Some(arr) = sinks.as_array()
        {
            for sink in arr {
                let id = sink["name"].as_str().unwrap_or("0").to_string();
                let name = sink["description"]
                    .as_str()
                    .unwrap_or("Unknown Output")
                    .to_string();
                let is_default = id == default_sink;

                let vol = sink["volume"]["front-left"]["value_percent"]
                    .as_str()
                    .unwrap_or("0%")
                    .trim_end_matches('%')
                    .parse::<f64>()
                    .unwrap_or(0.0)
                    / 100.0;
                devices.push(json!({
                    "id": id,
                    "name": name,
                    "type": "sink",
                    "volume": vol,
                    "is_active": is_default
                }));
            }
        }
        let _ = ctx.reply(Status::Success, Some(json!({ "devices": devices }))).await;
    }
    #[cfg(not(target_os = "linux"))]
    {
        let _ = ctx.reply(
            Status::Error("Not supported".into()),
            None,
        ).await;
    }
}

pub async fn set_default_audio_device(ctx: &CommandContext, target_id: &String) {
    #[cfg(target_os = "linux")]
    {
        let _ = tokio::process::Command::new("pactl")
            .args(["set-default-sink", target_id])
            .output()
            .await;
    }
    get_all_audio_devices(ctx).await;
}

pub async fn set_specific_device_volume(ctx: &CommandContext, target_id: &str, volume: &f64) {
    let clamped_volume = volume.clamp(0.0, 1.5);
    let vol_percent = format!("{}%", (clamped_volume * 100.0).round() as i64);
    #[cfg(target_os = "linux")]
    {
        let _ = tokio::process::Command::new("pactl")
            .args(["set-sink-volume", target_id, &vol_percent])
            .output()
            .await;
    }
    get_all_audio_devices(ctx).await;
}
