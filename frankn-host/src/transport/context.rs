use std::sync::Arc;
use tokio::sync::Mutex;
use tokio_tungstenite::tungstenite::Bytes;
use crate::config::HostConfig;
use crate::transport::webrtc::connection::PeerSession;
use crate::transport::protocol::messages::{HostMessage, Status};
use crate::utils::get_timestamp;

#[allow(dead_code)]
#[derive(Clone)]
pub struct CommandContext {
    pub id: String,
    pub client_id: String,
    pub label: String,
    pub config: Arc<HostConfig>,
    pub session: Arc<Mutex<PeerSession>>,
}

impl CommandContext {
    pub fn new(
        id: String,
        client_id: String,
        label: String,
        config: Arc<HostConfig>,
        session: Arc<Mutex<PeerSession>>,
    ) -> Self {
        Self {
            id,
            client_id,
            label,
            config,
            session,
        }
    }

    /// Send a final success/error reply for this command.
    pub async fn reply(&self, status: Status, data: Option<serde_json::Value>) -> Result<(), String> {
        let resp = HostMessage::Response {
            id: self.id.clone(),
            status,
            data,
            timestamp: get_timestamp(),
        };
        self.send(resp).await
    }

    /// Stream a partial update message (e.g., LLM tokens or progress updates).
    #[allow(dead_code)]
    pub async fn stream(&self, msg: HostMessage) -> Result<(), String> {
        self.send(msg).await
    }

    /// Check if a capability action is authorized under current policy.
    pub fn require_grant(&self, _action: &str) -> Result<(), String> {
        // Policy hooks for future authorization checks
        Ok(())
    }

    async fn send(&self, msg: HostMessage) -> Result<(), String> {
        let json = serde_json::to_string(&msg).map_err(|e| e.to_string())?;
        let session = self.session.lock().await;
        let conn = session.conn.lock().await;
        conn.send_message(&self.label, &Bytes::from(json))
            .await
            .map_err(|e| e.to_string())
    }

    /// Send a raw binary frame directly over the data channel.
    pub async fn send_binary(&self, bytes: Vec<u8>) -> Result<(), String> {
        let session = self.session.lock().await;
        let conn = session.conn.lock().await;
        let channels = conn.data_channels.lock().await;
        if let Some(dc) = channels.get(&self.label) {
            dc.send(&Bytes::from(bytes))
                .await
                .map(|_| ())
                .map_err(|e| e.to_string())
        } else {
            Err(format!("Data channel {} not found", self.label))
        }
    }

    /// Retrieve the current buffered amount of the data channel.
    pub async fn buffered_amount(&self) -> usize {
        let session = self.session.lock().await;
        let conn = session.conn.lock().await;
        let channels = conn.data_channels.lock().await;
        if let Some(dc) = channels.get(&self.label) {
            dc.buffered_amount().await
        } else {
            0
        }
    }
}
