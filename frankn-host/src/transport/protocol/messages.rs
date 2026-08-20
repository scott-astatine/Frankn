use serde::{Deserialize, Serialize};
use super::router::DcMsg;

#[derive(Debug, Serialize, Deserialize, Clone, PartialEq)]
pub enum Status {
    Success,
    Error(String),
}

#[derive(Debug, Serialize, Deserialize, Clone)]
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
        command: DcMsg,
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

    // --- Node ↔ Host Control Messages ---
    #[serde(rename = "node_register")]
    NodeRegister {
        node_id: String,
        display_name: String,
        capabilities: Vec<crate::capabilities::registry::CapabilityDescriptor>,
        timestamp: u64,
    },

    #[serde(rename = "node_heartbeat")]
    NodeHeartbeat {
        node_id: String,
        timestamp: u64,
        status: String,
    },

    #[serde(rename = "node_signal")]
    NodeSignal {
        client_id: String,
        session_id: String,
        signal: crate::signaling::SignalingMessage,
    },

    #[serde(rename = "node_activation_status")]
    NodeActivationStatus {
        capability_id: String,
        session_id: String,
        status: crate::capabilities::node::registry::CapabilitySessionStatus,
        error: Option<String>,
    },

    #[serde(rename = "activate_capability")]
    ActivateCapability {
        capability_id: String,
        session_id: String,
        provider_id: Option<String>,
        properties: std::collections::HashMap<String, serde_json::Value>,
        timestamp: u64,
        auth_token: String,
    },

    #[serde(rename = "deactivate_capability")]
    DeactivateCapability {
        capability_id: String,
        session_id: String,
        timestamp: u64,
        auth_token: String,
    },
}

#[derive(Debug, Serialize, Deserialize, Clone)]
#[serde(tag = "type")]
pub enum HostMessage {
    #[serde(rename = "challenge")]
    Challenge {
        challenge: String,
        salt: String,
        timestamp: u64,
    },

    #[serde(rename = "auth_success")]
    AuthSuccess {
        token: String,
        home_dir: String,
        timestamp: u64,
    },

    #[serde(rename = "capabilities_inventory")]
    CapabilitiesInventory {
        capabilities: Vec<crate::capabilities::registry::CapabilityDescriptor>,
        timestamp: u64,
    },

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

    /// Transfer failed or was aborted.
    #[serde(rename = "transfer_failed")]
    TransferFailed {
        id: String,
        error: String,
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

    // --- Host ↔ Node Control Messages ---
    #[serde(rename = "node_register_ack")]
    NodeRegisterAck {
        status: Status,
        timestamp: u64,
    },

    #[serde(rename = "node_activate_capability")]
    NodeActivateCapability {
        capability_id: String,
        session_id: String,
        client_id: String,
        properties: std::collections::HashMap<String, serde_json::Value>,
        timestamp: u64,
    },

    #[serde(rename = "node_deactivate_capability")]
    NodeDeactivateCapability {
        capability_id: String,
        session_id: String,
        timestamp: u64,
    },

    #[serde(rename = "host_signal")]
    HostSignal {
        client_id: String,
        session_id: String,
        signal: crate::signaling::SignalingMessage,
    },

    #[serde(rename = "capability_activation_status")]
    CapabilityActivationStatus {
        capability_id: String,
        session_id: String,
        status: crate::capabilities::node::registry::CapabilitySessionStatus,
        error: Option<String>,
        timestamp: u64,
    },
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn transfer_init_message_deserializes_with_resume_metadata() {
        let message: ClientMessage = serde_json::from_value(serde_json::json!({
            "type": "transfer_init",
            "id": "transfer-1",
            "path": "/tmp/example.txt",
            "total_size": 123,
            "hash": "abc",
            "resume_offset": 32
        }))
        .unwrap();

        match message {
            ClientMessage::TransferInit {
                id,
                path,
                total_size,
                hash,
                resume_offset,
            } => {
                assert_eq!(id, "transfer-1");
                assert_eq!(path, "/tmp/example.txt");
                assert_eq!(total_size, 123);
                assert_eq!(hash.as_deref(), Some("abc"));
                assert_eq!(resume_offset, 32);
            }
            _ => panic!("transfer_init should decode to ClientMessage::TransferInit"),
        }
    }

    #[test]
    fn transfer_ack_message_preserves_the_wire_contract() {
        let message = HostMessage::TransferAck {
            id: "transfer-1".to_string(),
            offset: 1024,
            seq: 7,
            timestamp: 99,
        };

        let value = serde_json::to_value(message).unwrap();
        assert_eq!(value["type"], "transfer_ack");
        assert_eq!(value["id"], "transfer-1");
        assert_eq!(value["offset"], 1024);
        assert_eq!(value["seq"], 7);
        assert_eq!(value["timestamp"], 99);
    }
}
