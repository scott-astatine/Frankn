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

        Self {
            config,
            auth_manager,
            peer_map,
            llm_manager,
            input_manager,
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
                            let r_conn = conn.lock().await;
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
        ));

        session_manager.run_signaling_loop().await
    }
}
