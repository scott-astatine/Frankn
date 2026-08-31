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
    pub public_key: Vec<u8>,       // 32-byte Ed25519 public key
    pub session_id: String,       // Server-issued active session ID
    pub allowed_peers: Vec<String>, // Whitelist of client peer_ids
    pub last_sequence: std::sync::Arc<std::sync::atomic::AtomicU64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type")]
pub enum SignalingMessage {
    #[serde(rename = "auth_challenge")]
    AuthChallenge {
        challenge: String,         // Base64URL encoded CSPRNG challenge
    },

    #[serde(rename = "register")]
    Register {
        protocol_version: u8,
        peer_id: String,           // Base64URL encoded Hash(public_key)
        peer_type: PeerType,
        display_name: String,
        is_public: bool,
        public_key: String,        // Hex encoded Ed25519 public key
        signature: String,         // Hex signature of the challenge
        timestamp: u64,
    },

    #[serde(rename = "register_success")]
    RegisterSuccess {
        peer_id: String,
        session_id: String,        // Ephemeral session ID
        timestamp: u64,
    },

    #[serde(rename = "register_failure")]
    RegisterFailure {
        error: String,
        timestamp: u64,
    },

    #[serde(rename = "session_replaced")]
    SessionReplaced {
        reason: String,
        timestamp: u64,
    },

    #[serde(rename = "subscribe_hosts")]
    SubscribeHosts {
        host_ids: Vec<String>,
        timestamp: u64,
    },

    #[serde(rename = "ping")]
    Ping {
        #[serde(default)]
        timestamp: u64,
    },

    #[serde(rename = "pong")]
    Pong {
        #[serde(default)]
        timestamp: u64,
    },

    #[serde(rename = "check_hosts_status")]
    CheckHostsStatus {
        host_ids: Vec<String>,
        timestamp: u64,
    },

    #[serde(rename = "hosts_status_response")]
    HostsStatusResponse {
        statuses: HashMap<String, bool>,
        timestamp: u64,
    },

    #[serde(rename = "update_host_acl")]
    UpdateHostAcl {
        allowed_peers: Vec<String>,
        timestamp: u64,
        signature: String,
    },

    #[serde(rename = "list_hosts")]
    ListHosts {
        timestamp: u64,
    },

    #[serde(rename = "host_list")]
    HostList {
        hosts: Vec<HostInfo>,
        timestamp: u64,
    },

    #[serde(rename = "peer_status_update")]
    PeerStatusUpdate {
        peer_id: String,
        online: bool,
        timestamp: u64,
    },

    #[serde(rename = "offer")]
    Offer {
        from: String,
        to: String,
        sdp: String,
        session_id: String,
        sequence: u64,
        signature: String,
        timestamp: u64,
    },

    #[serde(rename = "answer")]
    Answer {
        from: String,
        to: String,
        sdp: String,
        session_id: String,
        sequence: u64,
        signature: String,
        timestamp: u64,
    },

    #[serde(rename = "ice_candidate")]
    IceCandidate {
        from: String,
        to: String,
        candidate: String,
        sdp_mid: Option<String>,
        sdp_m_line_index: Option<u16>,
        session_id: String,
        sequence: u64,
        signature: String,
        timestamp: u64,
    },

    #[serde(rename = "error")]
    Error {
        message: String,
        timestamp: u64,
    },
}
/// Log the output with timestamp
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
