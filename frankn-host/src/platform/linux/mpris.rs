use std::collections::HashMap;
use std::ops::Deref;
use std::sync::LazyLock;
use tokio::process::Command;
use tokio::sync::Mutex;
use zbus::zvariant::{OwnedValue, Value};
use zbus::{Connection, names::BusName, proxy};

pub static LAST_ACTIVE_PLAYER: LazyLock<Mutex<Option<String>>> = LazyLock::new(|| Mutex::new(None));

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

pub struct MprisData {
    pub player_name: String,
    pub status: String,
    pub title: String,
    pub artist: String,
    pub position: u64,
    pub length: u64,
    pub art_data: Option<String>,
    pub volume: f64,
    pub track_id: String,
}

pub async fn toggle_play_pause() -> zbus::Result<()> {
    call_mpris(|p| Box::pin(async move { p.play_pause().await })).await
}

pub async fn next_track() -> zbus::Result<()> {
    call_mpris(|p| Box::pin(async move { p.next().await })).await
}

pub async fn previous_track() -> zbus::Result<()> {
    call_mpris(|p| Box::pin(async move { p.previous().await })).await
}

pub async fn seek(position: u64) -> zbus::Result<()> {
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

    proxy.set_position(track_obj_path, position as i64).await?;
    Ok(())
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
    if let Some(player) = find_active_player(&conn).await
        && let Ok(bus_name) = BusName::try_from(player.as_str())
        && let Ok(builder) = MediaPlayerProxy::builder(&conn).destination(bus_name)
        && let Ok(proxy) = builder.build().await
    {
        f(&proxy).await?;
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
        if let Ok(bus_name) = BusName::try_from(player.as_str())
            && let Ok(builder) = MediaPlayerProxy::builder(conn).destination(bus_name)
            && let Ok(proxy) = builder.build().await
            && let Ok(status) = proxy.playback_status().await
            && status == "Playing"
        {
            *LAST_ACTIVE_PLAYER.lock().await = Some(player.clone());
            return Some(player.clone());
        }
    }

    let mut last_active = LAST_ACTIVE_PLAYER.lock().await;
    if let Some(ref name) = *last_active
        && players.contains(name)
    {
        return Some(name.clone());
    }

    let fallback = players.first().cloned();
    *last_active = fallback.clone();
    fallback
}

pub async fn list_players() -> (Vec<String>, Option<String>) {
    let conn_res = Connection::session().await;
    let mut players_list = Vec::new();

    if let Ok(conn) = conn_res
        && let Ok(dbus) = zbus::fdo::DBusProxy::new(&conn).await
        && let Ok(names) = dbus.list_names().await
    {
        for name in names {
            if name.as_str().starts_with("org.mpris.MediaPlayer2.") {
                players_list.push(name.to_string());
            }
        }
    }

    let current = LAST_ACTIVE_PLAYER.lock().await.clone();
    (players_list, current)
}

pub async fn get_media_status() -> zbus::Result<MprisData> {
    let conn = Connection::session().await?;
    fetch_mpris_data_with_conn(&conn).await
}

pub async fn set_active_player(player_name: &str) {
    *LAST_ACTIVE_PLAYER.lock().await = Some(player_name.to_string());
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
    let proxy = MediaPlayerProxy::builder(conn)
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

    if let Some(v) = art_url_val
        && let Value::Str(url) = v.deref()
    {
        let url_str = url.as_str();

        if url_str.starts_with("file://") {
            let path = url_str.trim_start_matches("file://");
            art_data = Some(format!("frankn-fs://{}", path));
        } else if url_str.starts_with("http") {
            art_data = Some(url_str.to_string());
        } else if url_str.starts_with('/') {
            art_data = Some(format!("frankn-fs://{}", url_str));
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
