use std::collections::HashMap;

use serde::{Deserialize, Serialize};
use tokio::sync::RwLock;
use tokio_tungstenite::tungstenite::Message;

type PeerId = String;
pub type PeerMap = std::sync::Arc<RwLock<HashMap<PeerId, PeerConnection>>>;
pub type SignalingResult = Result<(), String>;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub enum PeerType {
    Host,
    Client,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct HostInfo {
    pub host_id: String,
    pub display_name: String,
}

pub struct PeerConnection {
    pub sender: tokio::sync::mpsc::UnboundedSender<Message>,
    pub peer_type: PeerType,
    pub display_name: String,
    pub is_public: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type")]
pub enum SignalingMessage {
    #[serde(rename = "register")]
    Register {
        peer_id: String,
        peer_type: PeerType,
        display_name: String,
        is_public: bool,
        timestamp: u64,
    },

    #[serde(rename = "register_success")]
    RegisterSuccess { peer_id: String, timestamp: u64 },

    #[serde(rename = "register_failure")]
    RegisterFailure { error: String, timestamp: u64 },

    #[serde(rename = "list_hosts")]
    ListHosts { timestamp: u64 },

    #[serde(rename = "host_list")]
    HostList {
        hosts: Vec<HostInfo>,
        timestamp: u64,
    },

    #[serde(rename = "offer")]
    Offer {
        from: String,
        to: String,
        sdp: String,
        timestamp: u64,
    },

    #[serde(rename = "answer")]
    Answer {
        from: String,
        to: String,
        sdp: String,
        timestamp: u64,
    },

    #[serde(rename = "ice_candidate")]
    IceCandidate {
        from: String,
        to: String,
        candidate: String,
        sdp_mid: Option<String>,
        sdp_m_line_index: Option<u16>,
        timestamp: u64,
    },

    #[serde(rename = "error")]
    Error { message: String, timestamp: u64 },
}

#[macro_export]
macro_rules! log {
    ($($arg:tt)*) => {
        println!("[{}] {}", chrono::Local::now().format("%H:%M:%S"), format!($($arg)*));
    };
}

#[macro_export]
macro_rules! elog {
    ($($arg:tt)*) => {
        eprintln!("[{}] {}", chrono::Local::now().format("%H:%M:%S"), format!($($arg)*));
    };
}
