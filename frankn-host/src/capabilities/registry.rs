use serde::{Deserialize, Serialize};
use std::collections::HashMap;

#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct CapabilityDescriptor {
    pub id: String,
    pub name: String,
    pub version: String,
    pub actions: Vec<String>,
    pub properties: HashMap<String, serde_json::Value>,
    pub events: Vec<String>,
    pub schemas: HashMap<String, serde_json::Value>,
    pub permissions: Vec<String>,
    pub platform_support: Vec<String>,
    pub health: String,
}

pub struct CapabilityRegistry {
    capabilities: HashMap<String, CapabilityDescriptor>,
}

impl CapabilityRegistry {
    pub fn new() -> Self {
        let mut registry = Self {
            capabilities: HashMap::new(),
        };
        registry.register_builtins();
        registry
    }

    pub fn register(&mut self, descriptor: CapabilityDescriptor) {
        self.capabilities.insert(descriptor.id.clone(), descriptor);
    }

    pub fn get(&self, id: &str) -> Option<&CapabilityDescriptor> {
        self.capabilities.get(id)
    }

    pub fn list(&self) -> Vec<CapabilityDescriptor> {
        self.capabilities.values().cloned().collect()
    }

    fn register_builtins(&mut self) {
        // 1. System
        self.register(CapabilityDescriptor {
            id: "system".to_string(),
            name: "System Utilities".to_string(),
            version: "1.0.0".to_string(),
            actions: vec![
                "ping".to_string(),
                "shutdown".to_string(),
                "disconnect".to_string(),
                "reboot".to_string(),
                "lock_screen".to_string(),
                "unlock_screen".to_string(),
                "update".to_string(),
                "restart_host_server".to_string(),
                "system_log".to_string(),
            ],
            properties: HashMap::new(),
            events: Vec::new(),
            schemas: HashMap::new(),
            permissions: Vec::new(),
            platform_support: vec!["linux".to_string()],
            health: "healthy".to_string(),
        });

        // 2. Process Manager
        self.register(CapabilityDescriptor {
            id: "process".to_string(),
            name: "Process Manager".to_string(),
            version: "1.0.0".to_string(),
            actions: vec!["list_processes".to_string(), "kill".to_string()],
            properties: HashMap::new(),
            events: Vec::new(),
            schemas: HashMap::new(),
            permissions: Vec::new(),
            platform_support: vec!["linux".to_string()],
            health: "healthy".to_string(),
        });

        // 3. File System
        self.register(CapabilityDescriptor {
            id: "filesystem".to_string(),
            name: "File System".to_string(),
            version: "1.0.0".to_string(),
            actions: vec![
                "ls".to_string(),
                "mkdir".to_string(),
                "delete_file".to_string(),
            ],
            properties: HashMap::new(),
            events: Vec::new(),
            schemas: HashMap::new(),
            permissions: vec!["sandbox_home".to_string()],
            platform_support: vec!["linux".to_string()],
            health: "healthy".to_string(),
        });

        // 4. Media Control
        self.register(CapabilityDescriptor {
            id: "media".to_string(),
            name: "Media Control".to_string(),
            version: "1.0.0".to_string(),
            actions: vec![
                "toggle_play_pause".to_string(),
                "play_next_track".to_string(),
                "play_previous_track".to_string(),
                "set_volume".to_string(),
                "get_media_status".to_string(),
                "list_players".to_string(),
                "set_active_player".to_string(),
                "seek".to_string(),
                "get_audio_devices".to_string(),
                "set_device_volume".to_string(),
                "set_default_audio_device".to_string(),
            ],
            properties: HashMap::new(),
            events: vec!["media_update".to_string()],
            schemas: HashMap::new(),
            permissions: Vec::new(),
            platform_support: vec!["linux".to_string()],
            health: "healthy".to_string(),
        });

        // 5. SSH Terminal
        self.register(CapabilityDescriptor {
            id: "ssh".to_string(),
            name: "SSH Terminal".to_string(),
            version: "1.0.0".to_string(),
            actions: vec!["start_ssh".to_string(), "stop_ssh".to_string()],
            properties: HashMap::new(),
            events: Vec::new(),
            schemas: HashMap::new(),
            permissions: Vec::new(),
            platform_support: vec!["linux".to_string()],
            health: "healthy".to_string(),
        });

        // 6. Network Configuration
        self.register(CapabilityDescriptor {
            id: "network".to_string(),
            name: "Network Configuration".to_string(),
            version: "1.0.0".to_string(),
            actions: vec![
                "get_network_status".to_string(),
                "toggle_radio".to_string(),
                "list_wifi_networks".to_string(),
                "connect_wifi".to_string(),
                "list_bluetooth_devices".to_string(),
                "connect_bluetooth".to_string(),
            ],
            properties: HashMap::new(),
            events: Vec::new(),
            schemas: HashMap::new(),
            permissions: Vec::new(),
            platform_support: vec!["linux".to_string()],
            health: "healthy".to_string(),
        });

        // 7. AI Inference
        self.register(CapabilityDescriptor {
            id: "inference".to_string(),
            name: "AI Inference".to_string(),
            version: "1.0.0".to_string(),
            actions: vec![
                "list_models".to_string(),
                "llm_start".to_string(),
                "llm_chat".to_string(),
                "llm_load_chat".to_string(),
                "llm_delete_chat".to_string(),
                "llm_list_chats".to_string(),
                "llm_stop".to_string(),
                "tool_approval_response".to_string(),
            ],
            properties: HashMap::new(),
            events: vec!["llm_token".to_string(), "tool_approval_request".to_string()],
            schemas: HashMap::new(),
            permissions: Vec::new(),
            platform_support: vec!["linux".to_string()],
            health: "healthy".to_string(),
        });

        // 8. Folder Sync
        self.register(CapabilityDescriptor {
            id: "sync".to_string(),
            name: "Folder Sync".to_string(),
            version: "1.0.0".to_string(),
            actions: vec!["sync_request".to_string()],
            properties: HashMap::new(),
            events: Vec::new(),
            schemas: HashMap::new(),
            permissions: Vec::new(),
            platform_support: vec!["linux".to_string()],
            health: "healthy".to_string(),
        });

        // 9. Input Control
        let input_health = if std::path::Path::new("/dev/uinput").exists() {
            "healthy"
        } else {
            "unsupported"
        };
        self.register(CapabilityDescriptor {
            id: "input".to_string(),
            name: "Input Control".to_string(),
            version: "1.0.0".to_string(),
            actions: Vec::new(),
            properties: HashMap::new(),
            events: Vec::new(),
            schemas: HashMap::new(),
            permissions: Vec::new(),
            platform_support: vec!["linux".to_string()],
            health: input_health.to_string(),
        });
    }
}

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq, Eq)]
pub struct CapabilityProvider {
    pub kind: String, // "host" or "node"
    pub provider_id: String,
}

#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct CapabilityInventoryEntry {
    pub descriptor: CapabilityDescriptor,
    pub provider: CapabilityProvider,
    pub availability: String, // "available", "unavailable"
}

pub struct CapabilityInventory {
    pub entries: Vec<CapabilityInventoryEntry>,
}

impl CapabilityInventory {
    pub fn new() -> Self {
        Self {
            entries: Vec::new(),
        }
    }

    pub fn register(&mut self, entry: CapabilityInventoryEntry) {
        self.entries
            .retain(|e| !(e.descriptor.id == entry.descriptor.id && e.provider == entry.provider));
        self.entries.push(entry);
    }

    pub fn unregister_by_provider(&mut self, kind: &str, provider_id: &str) {
        self.entries
            .retain(|e| !(e.provider.kind == kind && e.provider.provider_id == provider_id));
    }

    pub fn list(&self) -> Vec<CapabilityInventoryEntry> {
        self.entries.clone()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_capability_inventory_duplication_and_provider() {
        let mut inventory = CapabilityInventory::new();

        let descriptor = CapabilityDescriptor {
            id: "camera".to_string(),
            name: "Camera".to_string(),
            version: "1.0.0".to_string(),
            actions: vec![],
            properties: HashMap::new(),
            events: vec![],
            schemas: HashMap::new(),
            permissions: vec![],
            platform_support: vec![],
            health: "healthy".to_string(),
        };

        let provider_node1 = CapabilityProvider {
            kind: "node".to_string(),
            provider_id: "node-01".to_string(),
        };

        let provider_node2 = CapabilityProvider {
            kind: "node".to_string(),
            provider_id: "node-02".to_string(),
        };

        // Register camera under node-01
        inventory.register(CapabilityInventoryEntry {
            descriptor: descriptor.clone(),
            provider: provider_node1.clone(),
            availability: "available".to_string(),
        });

        // Register camera under node-02
        inventory.register(CapabilityInventoryEntry {
            descriptor: descriptor.clone(),
            provider: provider_node2.clone(),
            availability: "available".to_string(),
        });

        // We should have 2 entries in inventory
        assert_eq!(inventory.list().len(), 2);

        // Register camera under node-01 again (updating it)
        inventory.register(CapabilityInventoryEntry {
            descriptor: descriptor.clone(),
            provider: provider_node1.clone(),
            availability: "available".to_string(),
        });

        // We should still have 2 entries in inventory (no duplicates)
        assert_eq!(inventory.list().len(), 2);

        // Unregister node-01
        inventory.unregister_by_provider("node", "node-01");

        // We should have 1 entry left (node-02)
        assert_eq!(inventory.list().len(), 1);
        assert_eq!(inventory.list()[0].provider.provider_id, "node-02");
    }
}
