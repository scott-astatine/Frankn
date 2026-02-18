pub use crate::sys::dc_message_parser::DcMsg;
use serde::{Deserialize, Serialize};
use std::fs;

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

pub fn generate_host_id() -> String {
    let id_file = "/home/scott/.config/frankn/.host_id";
    if let Ok(id) = fs::read_to_string(id_file) {
        return id.trim().to_string();
    }
    use rand::Rng;
    let mut id: String = rand::rng()
        .sample_iter(&rand::distr::Alphanumeric)
        .take(16)
        .map(char::from)
        .collect();
    id = format!("frank-host-{}", id);
    let _ = fs::write(id_file, &id);
    id
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
    UploadEnd { id: String, timestamp: u64 },
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

    #[serde(rename = "file_transfer_start")]
    FileTransferStart {
        id: String,
        file_name: String,
        total_size: u64,
        timestamp: u64,
    },

    #[serde(rename = "file_transfer_end")]
    FileTransferEnd {
        id: String,
        timestamp: u64,

        hash: Option<String>,
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
