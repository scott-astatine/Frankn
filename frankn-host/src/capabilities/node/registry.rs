use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::Mutex;
use crate::transport::webrtc::connection::RTCConn;
use crate::capabilities::registry::CapabilityDescriptor;

#[derive(Clone)]
pub struct NodeInfo {
    pub node_id: String,
    pub display_name: String,
    pub capabilities: Vec<CapabilityDescriptor>,
    pub authenticated: bool,
    pub rtc_conn: Arc<Mutex<RTCConn>>,
    pub last_seen: std::time::Instant,
}

impl std::fmt::Debug for NodeInfo {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("NodeInfo")
            .field("node_id", &self.node_id)
            .field("display_name", &self.display_name)
            .field("capabilities", &self.capabilities)
            .field("authenticated", &self.authenticated)
            .field("last_seen", &self.last_seen)
            .finish()
    }
}

pub struct NodeRegistry {
    pub nodes: HashMap<String, NodeInfo>,
}

impl NodeRegistry {
    pub fn new() -> Self {
        Self {
            nodes: HashMap::new(),
        }
    }

    pub fn register(&mut self, node: NodeInfo) {
        self.nodes.insert(node.node_id.clone(), node);
    }

    pub fn unregister(&mut self, node_id: &str) {
        self.nodes.remove(node_id);
    }

    pub fn get(&self, node_id: &str) -> Option<&NodeInfo> {
        self.nodes.get(node_id)
    }

    pub fn update_heartbeat(&mut self, node_id: &str) {
        if let Some(node) = self.nodes.get_mut(node_id) {
            node.last_seen = std::time::Instant::now();
        }
    }

    pub fn list(&self) -> Vec<NodeInfo> {
        self.nodes.values().cloned().collect()
    }

    pub fn collect_timed_out(&self, timeout: std::time::Duration) -> Vec<String> {
        self.nodes.iter()
            .filter(|(_, node)| node.last_seen.elapsed() > timeout)
            .map(|(id, _)| id.clone())
            .collect()
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub enum CapabilitySessionStatus {
    #[serde(rename = "pending")]
    Pending,
    #[serde(rename = "active")]
    Active,
    #[serde(rename = "failed")]
    Failed,
    #[serde(rename = "closed")]
    Closed,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct CapabilitySession {
    pub session_id: String,
    pub client_id: String,
    pub capability_id: String,
    pub node_id: String,
    pub status: CapabilitySessionStatus,
    pub error: Option<String>,
}

pub struct CapabilitySessionRegistry {
    pub sessions: HashMap<String, CapabilitySession>,
}

impl CapabilitySessionRegistry {
    pub fn new() -> Self {
        Self {
            sessions: HashMap::new(),
        }
    }

    pub fn register(&mut self, session: CapabilitySession) {
        self.sessions.insert(session.session_id.clone(), session);
    }

    pub fn get(&self, session_id: &str) -> Option<&CapabilitySession> {
        self.sessions.get(session_id)
    }

    pub fn get_mut(&mut self, session_id: &str) -> Option<&mut CapabilitySession> {
        self.sessions.get_mut(session_id)
    }

    pub fn remove(&mut self, session_id: &str) -> Option<CapabilitySession> {
        self.sessions.remove(session_id)
    }

    pub fn list(&self) -> Vec<CapabilitySession> {
        self.sessions.values().cloned().collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_capability_session_registry() {
        let mut registry = CapabilitySessionRegistry::new();
        
        let session = CapabilitySession {
            session_id: "sess-01".to_string(),
            client_id: "client-01".to_string(),
            capability_id: "camera".to_string(),
            node_id: "node-01".to_string(),
            status: CapabilitySessionStatus::Pending,
            error: None,
        };

        registry.register(session.clone());

        assert!(registry.get("sess-01").is_some());
        assert_eq!(registry.get("sess-01").unwrap().status, CapabilitySessionStatus::Pending);

        // Update status
        if let Some(s) = registry.get_mut("sess-01") {
            s.status = CapabilitySessionStatus::Active;
        }
        assert_eq!(registry.get("sess-01").unwrap().status, CapabilitySessionStatus::Active);

        assert_eq!(registry.list().len(), 1);

        registry.remove("sess-01");
        assert!(registry.get("sess-01").is_none());
        assert_eq!(registry.list().len(), 0);
    }
}
