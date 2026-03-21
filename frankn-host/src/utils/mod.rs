pub mod stream;
pub use crate::sys::dc_message_parser::DcMsg;
use serde::{Deserialize, Serialize};

pub fn get_timestamp() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_secs()
}

#[derive(Debug, Serialize)]
pub enum Status {
    Success,
    Error(String),
}

#[derive(Debug, Deserialize)]
#[serde(tag = "type")]
pub enum ClientMessage {
    #[serde(rename = "auth_request")]
    AuthRequest,

    #[serde(rename = "auth_response")]
    AuthResponse { response: String },

    #[serde(rename = "dc_msg")]
    XDcMsg {
        id: String,
        #[serde(flatten)]
        command: DcMsg,
        params: Option<serde_json::Value>,
        auth_token: String,
    },

    #[serde(rename = "upload_start")]
    UploadStart {
        id: String,
        path: String,
        total_size: u64,
        hash: Option<String>,
        timestamp: u64,
    },

    #[serde(rename = "upload_chunk")]
    UploadChunk { id: String, data: String },

    #[serde(rename = "upload_end")]
    UploadEnd { id: String, hash: Option<String>, timestamp: u64 },
}

#[derive(Debug, Serialize)]
#[serde(tag = "type")]
pub enum HostMessage {
    #[serde(rename = "challenge")]
    Challenge {
        challenge: String,
        salt: String,
        timestamp: u64,
    },

    #[serde(rename = "auth_success")]
    AuthSuccess { token: String, timestamp: u64 },

    #[serde(rename = "auth_failed")]
    AuthFailed { error: String, timestamp: u64 },

    #[serde(rename = "media_update")]
    MediaUpdate {
        player_name: Option<String>,
        status: String,
        metadata: Option<String>,
        art_data: Option<String>,
        position: Option<u64>,
        length: Option<u64>,
        timestamp: u64,
    },

    #[serde(rename = "media_position_update")]
    MediaPositionUpdate {
        position: u64,
        length: Option<u64>,
        timestamp: u64,
    },

    #[serde(rename = "response")]
    Response {
        id: String,
        status: Status,
        data: Option<serde_json::Value>,
        timestamp: u64,
    },

    #[serde(rename = "notification")]
    Notification {
        id: u32,
        app_name: String,
        title: String,
        body: String,
        timestamp: u64,
    },

    #[serde(rename = "stream_start")]
    StreamStart {
        id: String,
        file_name: String,
        total_size: u64,
        timestamp: u64,
    },

    #[serde(rename = "stream_end")]
    StreamEnd {
        id: String,
        timestamp: u64,

        hash: Option<String>,
    },

    #[serde(rename = "telemetry")]
    Telemetry {
        cpu_load: f32,
        used_mem: u64,
        total_mem: u64,
        timestamp: u64,
    },
}

#[macro_export]
macro_rules! log {
    ($($arg:tt)*) => {
        println!("[{}] {}", chrono::Local::now().format("%H:%M:%S"), format!($($arg)*))
    };
}

#[macro_export]
macro_rules! elog {
    ($($arg:tt)*) => {
        eprintln!("[{}] {}", chrono::Local::now().format("%H:%M:%S"), format!($($arg)*))
    };
}
