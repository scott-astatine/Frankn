use crate::{
    HostMessage, elog, log,
    sys::rtc::{PeerMap, RTCConn},
    utils::Status,
};
use std::collections::HashMap;
use std::ops::Deref;
use std::sync::Arc;
use std::sync::LazyLock;
use tokio::process::Command;
use tokio::sync::Mutex;
use tokio_tungstenite::tungstenite::Bytes;
use zbus::zvariant::{OwnedValue, Value};
use zbus::{Connection, names::BusName, proxy};

static LAST_ACTIVE_PLAYER: LazyLock<Mutex<Option<String>>> = LazyLock::new(|| Mutex::new(None));

#[proxy(
    interface = "org.mpris.MediaPlayer2.Player",
    default_path = "/org/mpris/MediaPlayer2"
)]
trait MediaPlayer {
    fn next(&self) -> zbus::Result<()>;
    fn previous(&self) -> zbus::Result<()>;
    fn pause(&self) -> zbus::Result<()>;
    fn play_pause(&self) -> zbus::Result<()>;
    fn stop(&self) -> zbus::Result<()>;
    fn play(&self) -> zbus::Result<()>;
    fn seek(&self, offset: i64) -> zbus::Result<()>;
    fn set_position(
        &self,
        track_id: zbus::zvariant::ObjectPath<'_>,
        position: i64,
    ) -> zbus::Result<()>;
    fn open_uri(&self, uri: &str) -> zbus::Result<()>;

    #[zbus(property)]
    fn playback_status(&self) -> zbus::Result<String>;
    #[zbus(property)]
    fn metadata(&self) -> zbus::Result<HashMap<String, OwnedValue>>;
    #[zbus(property)]
    fn volume(&self) -> zbus::Result<f64>;
    #[zbus(property)]
    fn set_volume(&self, value: f64) -> zbus::Result<()>;
    #[zbus(property, name = "Position")]
    fn position(&self) -> zbus::Result<i64>;
    #[zbus(property)]
    fn rate(&self) -> zbus::Result<f64>;
}

struct MprisData {
    player_name: String,
    status: String,
    title: String,
    artist: String,
    position: u64,
    length: u64,
    art_data: Option<String>,
    volume: f64,
    track_id: String,
}

pub async fn handle_start_media_sync(id: &str, _rtc: Arc<Mutex<RTCConn>>) -> HostMessage {
    HostMessage::Response {
        id: id.to_string(),
        status: Status::Success,
        data: Some(serde_json::json!({ "message": "Neural link synchronized with Media Core." })),
        timestamp: crate::utils::get_timestamp(),
    }
}

pub async fn toggle_play_pause(id: &str, _rtc: Arc<Mutex<RTCConn>>) -> HostMessage {
    let _ = call_mpris(|p| Box::pin(async move { p.play_pause().await })).await;
    get_media_status(id, _rtc).await
}

pub async fn next_track(id: &str, _rtc: Arc<Mutex<RTCConn>>) -> HostMessage {
    let _ = call_mpris(|p| Box::pin(async move { p.next().await })).await;
    get_media_status(id, _rtc).await
}

pub async fn previous_track(id: &str, _rtc: Arc<Mutex<RTCConn>>) -> HostMessage {
    let _ = call_mpris(|p| Box::pin(async move { p.previous().await })).await;
    get_media_status(id, _rtc).await
}

pub async fn seek(id: &str, position: &u64, _rtc: Arc<Mutex<RTCConn>>) -> HostMessage {
    let pos = *position;
    let res = async {
        let conn = Connection::session().await?;
        let data = fetch_mpris_data_with_conn(&conn).await?;
        let bus_name = BusName::try_from(data.player_name.as_str())
            .map_err(|e| zbus::Error::Address(e.to_string()))?;
        let proxy = MediaPlayerProxy::builder(&conn)
            .destination(bus_name)?
            .build()
            .await?;

        let track_obj_path = zbus::zvariant::ObjectPath::try_from(data.track_id.as_str())
            .unwrap_or_else(|_| zbus::zvariant::ObjectPath::from_static_str_unchecked("/"));

        proxy.set_position(track_obj_path, pos as i64).await?;
        Ok::<(), zbus::Error>(())
    }
    .await;

    if let Err(e) = res {
        elog!("MEDIA: Seek operation failed: {}", e);
    }

    get_media_status(id, _rtc).await
}

pub async fn set_volume(id: &str, level: &f64, _rtc: Arc<Mutex<RTCConn>>) -> HostMessage {
    let vol_str = format!("{:.2}", level);
    #[cfg(target_os = "linux")]
    let _ = Command::new("wpctl")
        .args(["set-volume", "@DEFAULT_AUDIO_SINK@", &vol_str])
        .output()
        .await;
    get_media_status(id, _rtc).await
}

async fn call_mpris<F>(f: F) -> zbus::Result<()>
where
    F: for<'a> FnOnce(
        &'a MediaPlayerProxy<'a>,
    ) -> std::pin::Pin<
        Box<dyn std::future::Future<Output = zbus::Result<()>> + Send + 'a>,
    >,
{
    let conn = Connection::session().await?;
    if let Some(player) = find_active_player(&conn).await {
        if let Ok(bus_name) = BusName::try_from(player.as_str()) {
            if let Ok(builder) = MediaPlayerProxy::builder(&conn).destination(bus_name) {
                if let Ok(proxy) = builder.build().await {
                    f(&proxy).await?;
                }
            }
        }
    }
    Ok(())
}

async fn find_active_player(conn: &Connection) -> Option<String> {
    let dbus = zbus::fdo::DBusProxy::new(conn).await.ok()?;
    let names = dbus.list_names().await.ok()?;

    let players: Vec<String> = names
        .into_iter()
        .filter(|n| n.as_str().starts_with("org.mpris.MediaPlayer2."))
        .map(|n| n.to_string())
        .collect();

    if players.is_empty() {
        *LAST_ACTIVE_PLAYER.lock().await = None;
        return None;
    }

    for player in &players {
        if let Ok(bus_name) = BusName::try_from(player.as_str()) {
            if let Ok(builder) = MediaPlayerProxy::builder(conn).destination(bus_name) {
                if let Ok(proxy) = builder.build().await {
                    if let Ok(status) = proxy.playback_status().await {
                        if status == "Playing" {
                            *LAST_ACTIVE_PLAYER.lock().await = Some(player.clone());
                            return Some(player.clone());
                        }
                    }
                }
            }
        }
    }

    let mut last_active = LAST_ACTIVE_PLAYER.lock().await;
    if let Some(ref name) = *last_active {
        if players.contains(name) {
            return Some(name.clone());
        }
    }

    let fallback = players.first().cloned();
    *last_active = fallback.clone();
    fallback
}

pub async fn list_players(req_id: &str, _rtc: Arc<Mutex<RTCConn>>) -> HostMessage {
    let conn_res = Connection::session().await;
    let mut players_list = Vec::new();

    if let Ok(conn) = conn_res {
        if let Ok(dbus) = zbus::fdo::DBusProxy::new(&conn).await {
            if let Ok(names) = dbus.list_names().await {
                for name in names {
                    if name.as_str().starts_with("org.mpris.MediaPlayer2.") {
                        players_list.push(name.to_string());
                    }
                }
            }
        }
    }

    let current = LAST_ACTIVE_PLAYER.lock().await.clone();

    HostMessage::Response {
        id: req_id.to_string(),
        status: Status::Success,
        data: Some(serde_json::json!({
            "players": players_list,
            "active_player": current
        })),
        timestamp: crate::utils::get_timestamp(),
    }
}

pub async fn set_active_player(
    req_id: &str,
    player_name: &String,
    _rtc: Arc<Mutex<RTCConn>>,
) -> HostMessage {
    let mut current = LAST_ACTIVE_PLAYER.lock().await;
    *current = Some(player_name.clone());

    HostMessage::Response {
        id: req_id.to_string(),
        status: Status::Success,
        data: Some(
            serde_json::json!({ "message": format!("Active player set to {}", player_name) }),
        ),
        timestamp: crate::utils::get_timestamp(),
    }
}

pub async fn get_media_status(id: &str, _rtc: Arc<Mutex<RTCConn>>) -> HostMessage {
    #[cfg(target_os = "linux")]
    {
        match async {
            let conn = Connection::session().await?;
            fetch_mpris_data_with_conn(&conn).await
        }
        .await
        {
            Ok(d) => HostMessage::Response {
                id: id.to_string(),
                status: Status::Success,
                data: Some(serde_json::json!({
                    "player_name": d.player_name,
                    "media_status": d.status,
                    "volume": d.volume,
                    "metadata": format!("{} - {}", d.title, d.artist),
                    "position": d.position,
                    "length": d.length,
                    "art_data": d.art_data,
                    "track_id": d.track_id
                })),
                timestamp: crate::utils::get_timestamp(),
            },
            Err(_) => HostMessage::Response {
                id: id.to_string(),
                status: Status::Success,
                data: Some(
                    serde_json::json!({ "media_status": "Stopped", "metadata": "No Media", "volume": 0.0 }),
                ),
                timestamp: crate::utils::get_timestamp(),
            },
        }
    }
    #[cfg(not(target_os = "linux"))]
    HostMessage::Response {
        id: id.to_string(),
        status: Status::Success,
        data: Some(serde_json::json!({ "media_status": "unknown" })),
        timestamp: crate::utils::get_timestamp(),
    }
}

fn get_numeric_metadata(metadata: &HashMap<String, OwnedValue>, key: &str) -> u64 {
    let keys = [key.to_string(), key.replace("mpris:", "mpris:L")];

    for k in keys {
        if let Some(v) = metadata.get(&k) {
            match v.deref() {
                Value::I64(i) => return *i as u64,
                Value::U64(u) => return *u,
                Value::I32(i) => return *i as u64,
                Value::U32(u) => return *u as u64,
                Value::F64(f) => return *f as u64,
                Value::Str(s) => {
                    if let Ok(n) = s.parse::<u64>() {
                        return n;
                    }
                }
                _ => {}
            }
        }
    }
    0
}

async fn fetch_mpris_data_with_conn(conn: &Connection) -> zbus::Result<MprisData> {
    let player = find_active_player(conn)
        .await
        .ok_or_else(|| zbus::Error::Address("No player found".into()))?;
    let bus_name =
        BusName::try_from(player.as_str()).map_err(|e| zbus::Error::Address(e.to_string()))?;
    let proxy = MediaPlayerProxy::builder(&conn)
        .destination(bus_name)?
        .build()
        .await?;

    let status = proxy
        .playback_status()
        .await
        .unwrap_or_else(|_| "Stopped".into());
    let metadata = proxy.metadata().await.unwrap_or_default();
    let pos = proxy.position().await.unwrap_or(0) as u64;

    let volume = match Command::new("wpctl")
        .args(["get-volume", "@DEFAULT_AUDIO_SINK@"])
        .output()
        .await
    {
        Ok(out) => {
            let out_str = String::from_utf8_lossy(&out.stdout);
            out_str
                .split("Volume: ")
                .nth(1)
                .and_then(|s| s.split_whitespace().next())
                .and_then(|s| s.parse::<f64>().ok())
                .unwrap_or(0.0)
        }
        Err(_) => 0.0,
    };

    let title = metadata
        .get("xesam:title")
        .and_then(|v| {
            if let Value::Str(s) = v.deref() {
                Some(s.as_str().to_string())
            } else {
                None
            }
        })
        .unwrap_or_else(|| "Unknown Title".to_string());

    let artist = metadata
        .get("xesam:artist")
        .and_then(|v| {
            if let Value::Array(arr) = v.deref() {
                arr.iter().next().and_then(|v| {
                    if let Value::Str(s) = v {
                        Some(s.as_str().to_string())
                    } else {
                        None
                    }
                })
            } else {
                None
            }
        })
        .unwrap_or_else(|| "Unknown Artist".to_string());

    let length = get_numeric_metadata(&metadata, "mpris:length");

    let track_id = metadata
        .get("mpris:trackid")
        .and_then(|v| {
            if let Value::ObjectPath(p) = v.deref() {
                Some(p.as_str().to_string())
            } else if let Value::Str(s) = v.deref() {
                Some(s.as_str().to_string())
            } else {
                None
            }
        })
        .unwrap_or_else(|| "/".to_string());

    let mut art_data: Option<String> = None;
    let art_url_val = metadata
        .get("mpris:artUrl")
        .or_else(|| metadata.get("xesam:artUrl"));

    if let Some(v) = art_url_val {
        if let Value::Str(url) = v.deref() {
            let url_str = url.as_str();

            // Log the URL we found to help debug
            // log!("MEDIA: Found art URL: {}", url_str);

            if url_str.starts_with("file://") {
                let path = url_str.trim_start_matches("file://");
                // Use tokio::fs for non-blocking read
                if let Ok(bytes) = tokio::fs::read(path).await {
                    use base64::Engine;
                    art_data = Some(base64::prelude::BASE64_STANDARD.encode(bytes));
                } else {
                    elog!("MEDIA: Failed to read local art file: {}", path);
                }
            } else if url_str.starts_with("http") {
                // Pass the HTTP URL directly to the client.
                // The client (Flutter) has built-in image caching and networking logic.
                // Sending the URL instead of the base64 data:
                // 1. Saves host bandwidth (sending small string vs large encoded blob).
                // 2. Removes the runtime dependency on 'curl'.
                // 3. Reduces latency for the metadata update.
                art_data = Some(url_str.to_string());
            } else if url_str.starts_with('/') {
                // Raw absolute path
                if let Ok(bytes) = tokio::fs::read(url_str).await {
                    use base64::Engine;
                    art_data = Some(base64::prelude::BASE64_STANDARD.encode(bytes));
                }
            }
        }
    }

    Ok(MprisData {
        player_name: player,
        status,
        title,
        artist,
        position: pos,
        length,
        art_data,
        volume,
        track_id,
    })
}

pub async fn start_media_sync(peer_map: PeerMap) {
    #[cfg(target_os = "linux")]
    {
        let pm_metadata = Arc::clone(&peer_map);
        let pm_position = Arc::clone(&peer_map);

        tokio::spawn(async move {
            log!("Neural Media Engine: Initializing event loop...");
            let conn = match Connection::session().await {
                Ok(c) => c,
                Err(e) => {
                    elog!("D-Bus: Session connection failed: {}", e);
                    return;
                }
            };

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

                match fetch_mpris_data_with_conn(&conn).await {
                    Ok(d) => {
                        // Include art data length in signature to detect changes
                        let art_len = d.art_data.as_ref().map(|s| s.len()).unwrap_or(0);
                        let sig = format!(
                            "{} {} {} {} {} art_len: {}",
                            d.player_name, d.status, d.title, d.length, d.volume, art_len
                        );

                        let force_update = current_clients > last_client_count;
                        last_client_count = current_clients;

                        if sig != last_metadata_sig || force_update {
                            last_metadata_sig = sig.clone();

                            let msg = HostMessage::MediaUpdate {
                                player_name: Some(d.player_name.clone()),
                                status: d.status,
                                metadata: Some(format!("{} - {}", d.title, d.artist)),
                                art_data: d.art_data,
                                position: Some(d.position),
                                length: Some(d.length),
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
                                for c in map.keys() {
                                    log!("Media Update sent to Client({c}): {:?}", sig);
                                }
                            }
                        }
                    }
                    Err(_) => {
                        if !last_metadata_sig.is_empty() {
                            last_metadata_sig = String::new();
                            let msg = HostMessage::MediaUpdate {
                                player_name: None,
                                status: "Stopped".into(),
                                metadata: Some("No Media".into()),
                                art_data: None,
                                position: None,
                                length: None,
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

        tokio::spawn(async move {
            let conn = match Connection::session().await {
                Ok(c) => c,
                Err(_) => return,
            };

            loop {
                let has_clients = {
                    let map = pm_position.lock().await;
                    !map.is_empty()
                };

                if !has_clients {
                    tokio::time::sleep(tokio::time::Duration::from_secs(5)).await;
                    continue;
                }

                if let Ok(d) = fetch_mpris_data_with_conn(&conn).await {
                    if d.status.to_lowercase().contains("playing") {
                        let msg = HostMessage::MediaPositionUpdate {
                            position: d.position,
                            length: Some(d.length),
                            timestamp: crate::utils::get_timestamp(),
                        };

                        if let Ok(json) = serde_json::to_string(&msg) {
                            let map = pm_position.lock().await;
                            for conn in map.values() {
                                let r_conn = conn.lock().await;
                                let _ = r_conn
                                    .send_message("frankn_media", &Bytes::from(json.clone()))
                                    .await;
                            }
                        }
                    }
                }
                tokio::time::sleep(tokio::time::Duration::from_secs(5)).await;
            }
        });
    }
}

pub async fn get_all_audio_devices(req_id: &str, _rtc: Arc<Mutex<RTCConn>>) -> HostMessage {
    #[cfg(target_os = "linux")]
    {
        let mut devices = Vec::new();

        let default_sink = if let Ok(output) = Command::new("pactl")
            .args(["get-default-sink"])
            .output()
            .await
        {
            String::from_utf8_lossy(&output.stdout).trim().to_string()
        } else {
            String::new()
        };

        if let Ok(output) = Command::new("pactl")
            .args(["-f", "json", "list", "sinks"])
            .output()
            .await
        {
            if let Ok(json_str) = String::from_utf8(output.stdout) {
                if let Ok(sinks) = serde_json::from_str::<serde_json::Value>(&json_str) {
                    if let Some(arr) = sinks.as_array() {
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
                            devices.push(serde_json::json!({
                                "id": id,
                                "name": name,
                                "type": "sink",
                                "volume": vol,
                                "is_active": is_default
                            }));
                        }
                    }
                }
            }
        }
        HostMessage::Response {
            id: req_id.to_string(),
            status: Status::Success,
            data: Some(serde_json::json!({ "devices": devices })),
            timestamp: crate::utils::get_timestamp(),
        }
    }
    #[cfg(not(target_os = "linux"))]
    HostMessage::Response {
        id: req_id.to_string(),
        status: Status::Error("Not supported".into()),
        data: None,
        timestamp: crate::utils::get_timestamp(),
    }
}

pub async fn set_default_audio_device(
    req_id: &str,
    target_id: &String,
    _rtc: Arc<Mutex<RTCConn>>,
) -> HostMessage {
    #[cfg(target_os = "linux")]
    {
        let _ = Command::new("pactl")
            .args(["set-default-sink", target_id])
            .output()
            .await;
    }
    get_all_audio_devices(req_id, _rtc).await
}

pub async fn set_specific_device_volume(
    req_id: &str,
    target_id: &str,
    volume: &f64,
    _rtc: Arc<Mutex<RTCConn>>,
) -> HostMessage {
    let vol_percent = format!("{}%", (volume * 100.0).round() as i64);
    #[cfg(target_os = "linux")]
    {
        let _ = Command::new("pactl")
            .args(["set-sink-volume", target_id, &vol_percent])
            .output()
            .await;
    }
    get_all_audio_devices(req_id, _rtc).await
}

fn mpris_error(id: &str, e: impl std::fmt::Display) -> HostMessage {
    HostMessage::Response {
        id: id.to_string(),
        status: Status::Error(format!("D-Bus Error: {}", e)),
        data: None,
        timestamp: crate::utils::get_timestamp(),
    }
}
