use std::collections::HashMap;
use std::sync::Arc;
use std::time::Duration;

use crate::auth::AuthManager;
use crate::capabilities;
use crate::capabilities::inference::LlmManager;
use crate::config::HostConfig;
use crate::transport::webrtc::connection::PeerMap;
use crate::utils::{HostMessage, get_cpu_temp, get_timestamp};
use tokio::sync::Mutex;
use tokio_tungstenite::tungstenite::Bytes;

use super::sessions::SessionManager;

pub struct HostRuntime {
    config: Arc<HostConfig>,
    auth_manager: Arc<AuthManager>,
    peer_map: PeerMap,
    llm_manager: Arc<Mutex<LlmManager>>,
    input_manager: Option<Arc<Mutex<capabilities::input::InputManager>>>,
    node_registry: Arc<Mutex<capabilities::node::registry::NodeRegistry>>,
    capability_inventory: Arc<Mutex<capabilities::registry::CapabilityInventory>>,
    capability_sessions: Arc<Mutex<capabilities::node::registry::CapabilitySessionRegistry>>,
}

impl HostRuntime {
    pub fn new(config: HostConfig) -> Self {
        let config = Arc::new(config);
        let auth_manager = Arc::new(AuthManager::from_hash(&config.password_hash, &config.salt));
        let peer_map: PeerMap = Arc::new(Mutex::new(HashMap::new()));
        let llm_manager = Arc::new(Mutex::new(LlmManager::new()));
        let input_manager = match capabilities::input::InputManager::new() {
            Ok(im) => Some(Arc::new(Mutex::new(im))),
            Err(e) => {
                crate::elog!("CRITICAL: Failed to initialize virtual input devices (uinput).");
                crate::elog!("  ↳ Error: {}", e);
                crate::elog!("  ↳ The trackpad and keyboard features will NOT work.");
                crate::elog!(
                    "  ↳ Fix 1: Ensure the kernel module is loaded: 'sudo modprobe uinput'"
                );
                crate::elog!("  ↳ Fix 2: Ensure your user has permissions to /dev/uinput");
                None
            }
        };

        let node_registry = Arc::new(Mutex::new(capabilities::node::registry::NodeRegistry::new()));

        let mut capability_inventory = capabilities::registry::CapabilityInventory::new();
        let registry = capabilities::registry::CapabilityRegistry::new();
        for cap in registry.list() {
            capability_inventory.register(capabilities::registry::CapabilityInventoryEntry {
                descriptor: cap,
                provider: capabilities::registry::CapabilityProvider {
                    kind: "host".to_string(),
                    provider_id: config.host_id.clone(),
                },
                availability: "available".to_string(),
            });
        }
        let capability_inventory = Arc::new(Mutex::new(capability_inventory));
        let capability_sessions = Arc::new(Mutex::new(
            capabilities::node::registry::CapabilitySessionRegistry::new(),
        ));

        Self {
            config,
            auth_manager,
            peer_map,
            llm_manager,
            input_manager,
            node_registry,
            capability_inventory,
            capability_sessions,
        }
    }

    pub async fn run(self) -> Result<(), Box<dyn std::error::Error>> {
        crate::log!("Neural Link Host Server initialized.");
        crate::log!("ID: {}", self.config.host_id);
        crate::log!("Display Name: {}", self.config.host_name);

        // =============================================================================
        // BACKGROUND SERVICES
        // =============================================================================
        let pm_notif = Arc::clone(&self.peer_map);
        tokio::spawn(async move {
            capabilities::notifications::start_notification_listener(pm_notif).await;
        });

        let pm_media = Arc::clone(&self.peer_map);
        tokio::spawn(async move {
            capabilities::media::start_media_sync(pm_media).await;
        });

        // =============================================================================
        // NODE LIVENESS MONITOR
        // =============================================================================
        let nr_liveness = Arc::clone(&self.node_registry);
        let ci_liveness = Arc::clone(&self.capability_inventory);
        let cs_liveness = Arc::clone(&self.capability_sessions);
        let pm_liveness = Arc::clone(&self.peer_map);
        tokio::spawn(async move {
            let timeout = Duration::from_secs(60);
            loop {
                tokio::time::sleep(Duration::from_secs(15)).await;

                let timed_out = {
                    let nr = nr_liveness.lock().await;
                    nr.collect_timed_out(timeout)
                };

                for node_id in timed_out {
                    crate::log!("NODE: Liveness timeout for '{}'. Cleaning up.", node_id);

                    // Close all capability sessions belonging to this node
                    {
                        let mut cs = cs_liveness.lock().await;
                        let sessions_to_close: Vec<_> = cs.list().into_iter()
                            .filter(|s| s.node_id == node_id)
                            .collect();
                        for mut sess in sessions_to_close {
                            sess.status = capabilities::node::registry::CapabilitySessionStatus::Closed;
                            cs.register(sess);
                        }
                    }

                    // Remove provider entries
                    {
                        let mut ci = ci_liveness.lock().await;
                        ci.unregister_by_provider("node", &node_id);
                    }

                    // Unregister the node
                    {
                        let mut nr = nr_liveness.lock().await;
                        nr.unregister(&node_id);
                    }

                    // Close the peer session if it still exists
                    {
                        let mut map = pm_liveness.lock().await;
                        if let Some(existing) = map.remove(&node_id) {
                            let sess = existing.lock().await;
                            let _ = sess.close().await;
                        }
                    }

                    crate::log!("NODE: '{}' removed due to liveness timeout.", node_id);
                }
            }
        });

        // =============================================================================
        // TELEMETRY BROADCAST
        // =============================================================================
        let pm_telemetry = Arc::clone(&self.peer_map);
        tokio::spawn(async move {
            use sysinfo::{CpuRefreshKind, MemoryRefreshKind, RefreshKind, System};
            let mut sys = System::new_with_specifics(
                RefreshKind::nothing()
                    .with_cpu(CpuRefreshKind::everything())
                    .with_memory(MemoryRefreshKind::everything()),
            );

            loop {
                let has_clients = {
                    let map = pm_telemetry.lock().await;
                    !map.is_empty()
                };

                if has_clients {
                    sys.refresh_cpu_all();
                    sys.refresh_memory();

                    let msg = HostMessage::Telemetry {
                        cpu_load: sys.global_cpu_usage(),
                        cpu_temp: get_cpu_temp().unwrap_or(0.0),
                        used_mem: sys.used_memory(),
                        total_mem: sys.total_memory(),
                        timestamp: get_timestamp(),
                    };

                    if let Ok(json) = serde_json::to_string(&msg) {
                        let map = pm_telemetry.lock().await;
                        for conn in map.values() {
                            let sess = conn.lock().await;
                            let r_conn = sess.conn.lock().await;
                            let _ = r_conn
                                .send_message("frankn_cmd", &Bytes::from(json.clone()))
                                .await;
                        }
                    }
                }
                tokio::time::sleep(Duration::from_secs(2)).await;
            }
        });

        // Instantiate SessionManager to run the signaling and session lifecycle
        let session_manager = Arc::new(SessionManager::new(
            Arc::clone(&self.config),
            Arc::clone(&self.auth_manager),
            Arc::clone(&self.peer_map),
            Arc::clone(&self.llm_manager),
            self.input_manager.clone(),
            Arc::clone(&self.node_registry),
            Arc::clone(&self.capability_inventory),
            Arc::clone(&self.capability_sessions),
        ));

        session_manager.run_signaling_loop().await
    }
}
