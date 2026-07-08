use std::io::Error;

pub use crate::ops::dc_message_parser;
use serde::{Deserialize, Serialize};

pub fn get_timestamp() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_secs()
}

pub fn get_cpu_temp() -> Result<f32, Error> {
    // Read the temp file (milli-celsius)
    let temp_str = std::fs::read_to_string("/sys/class/thermal/thermal_zone0/temp")?;
    let temp_milli: f32 = temp_str.trim().parse().unwrap_or(0.0);
    Ok(temp_milli / 1000.0) // Convert to Celsius
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
    ClientGenMsg {
        id: String,
        #[serde(flatten)]
        command: dc_message_parser::DcMsg,
        auth_token: String,
    },

    // ── New resume-aware transfer protocol ──
    /// Initialize a transfer (upload from client → host).
    #[serde(rename = "transfer_init")]
    TransferInit {
        id: String,
        path: String,
        total_size: u64,
        hash: Option<String>,
        /// Byte offset to resume from (0 = fresh start).
        #[serde(default)]
        resume_offset: u64,
    },

    /// Cancel an in-progress transfer and clean up partial state.
    #[serde(rename = "transfer_cancel")]
    TransferCancel { id: String },

    /// Request a file download from the host, optionally resuming.
    #[serde(rename = "download_init")]
    DownloadInit {
        id: String,
        path: String,
        /// Byte offset to resume from (0 = fresh start).
        #[serde(default)]
        resume_offset: u64,
    },
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

    #[serde(rename = "llm_token")]
    LlmToken {
        token: String,
        is_final: bool,
        timestamp: u64,
    },

    #[serde(rename = "tool_approval_request")]
    ToolApprovalRequest {
        approval_id: String,
        tool: String,
        args: String,
        timestamp: u64,
    },

    #[serde(rename = "media_update")]
    MediaUpdate {
        player_name: Option<String>,
        playing: bool,
        metadata: Option<String>,
        art_data: Option<String>,
        position: Option<u64>,
        length: Option<u64>,
        volume: Option<f64>,
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

    #[serde(rename = "telemetry")]
    Telemetry {
        cpu_load: f32,
        used_mem: u64,
        total_mem: u64,
        timestamp: u64,
        cpu_temp: f32,
    },

    // ── New resume-aware transfer protocol ──
    /// ACK for received upload chunks. Tells client how much host has persisted.
    #[serde(rename = "transfer_ack")]
    TransferAck {
        id: String,
        /// Total bytes confirmed written to disk.
        offset: u64,
        /// Highest chunk sequence number received.
        seq: u32,
        timestamp: u64,
    },

    /// Upload completed successfully, hash verified.
    #[serde(rename = "transfer_complete")]
    TransferComplete {
        id: String,
        hash: String,
        timestamp: u64,
    },

    /// Transfer cancelled by client.
    #[serde(rename = "transfer_cancel")]
    TransferCancel { id: String, timestamp: u64 },

    /// Download stream start with metadata.
    #[serde(rename = "download_start")]
    DownloadStart {
        id: String,
        file_name: String,
        total_size: u64,
        /// Offset the host started streaming from.
        offset: u64,
        hash: Option<String>,
        timestamp: u64,
    },

    /// Download stream end.
    #[serde(rename = "download_end")]
    DownloadEnd {
        id: String,
        hash: String,
        timestamp: u64,
    },

    /// Folder sync snapshot metadata.
    #[serde(rename = "sync_snapshot")]
    SyncSnapshot {
        id: String,
        root_path: String,
        files: Vec<serde_json::Value>,
        is_final: bool,
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
