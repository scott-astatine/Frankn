use crate::auth::AuthManager;
use crate::{elog, log};
use dialoguer::{Confirm, Input, Password};
use rand::{Rng, distr::Alphanumeric};
pub mod tui;

use serde::{Deserialize, Serialize};
use std::path::PathBuf;
use tokio::fs;

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct HostConfig {
    pub host_id: String,
    pub host_name: String,
    pub password_hash: String,
    pub signaling_url: String,
    pub is_public: bool,
    pub restricted_cmds: Vec<String>,
}

impl HostConfig {
    fn config_dir() -> PathBuf {
        let mut path = dirs::home_dir().expect("Could not find home directory");
        path.push(".config/frankn");
        path
    }

    fn config_file() -> PathBuf {
        let mut path = Self::config_dir();
        path.push("config.toml");
        path
    }

    pub async fn load_or_init() -> Self {
        let config_path = Self::config_file();

        if config_path.exists() {
            match fs::read_to_string(&config_path).await {
                Ok(content) => match toml::from_str::<HostConfig>(&content) {
                    Ok(config) => return config,
                    Err(e) => {
                        elog!("Failed to parse config: {}. Re-initializing...", e);
                    }
                },
                Err(e) => {
                    elog!("Failed to read config file: {}. Re-initializing...", e);
                }
            }
        }

        // First run or corrupted config
        Self::init_interactive().await
    }

    async fn init_interactive() -> Self {
        // Check if we have a TTY before starting interactive setup
        if !atty::is(atty::Stream::Stdin) {
            elog!("ERROR: Configuration not found and no terminal detected.");
            elog!("Please run 'frankn-host' manually once to complete the initial setup.");
            std::process::exit(1);
        }

        let config = tokio::task::spawn_blocking(|| {
            println!(
                "
⚡ Welcome to Frankn Host Setup
"
            );

            let host_name: String = Input::new()
                .with_prompt("Host Display Name")
                .default(
                    hostname::get()
                        .map(|h| h.to_string_lossy().to_string())
                        .unwrap_or_else(|_| "My Host".to_string()),
                )
                .interact_text()
                .expect("Failed to get host name");

            let password = Password::new()
                .with_prompt("Set Host Passcode")
                .with_confirmation("Confirm Passcode", "Passwords do not match")
                .interact()
                .expect("Failed to get password");

            let is_public = Confirm::new()
                .with_prompt("List host publicly on signaling server?")
                .default(false)
                .interact()
                .expect("Failed to get public preference");

            let signaling_url: String = Input::new()
                .with_prompt("Signaling Server URL")
                .default("ws://152.67.19.202:8037".to_string())
                .interact_text()
                .expect("Failed to get signaling URL");

            // Generate 12-digit alphanumeric ID
            let host_id: String = rand::rng()
                .sample_iter(&Alphanumeric)
                .take(12)
                .map(char::from)
                .collect();

            // Hash the password using existing AuthManager logic
            let auth_manager = AuthManager::new(&password);
            let password_hash = auth_manager.password_hash.clone();

            HostConfig {
                host_id,
                host_name,
                password_hash,
                signaling_url,
                is_public,
                restricted_cmds: Vec::new(),
            }
        })
        .await
        .expect("Interactive setup panicked");

        config.save().await;
        log!("Configuration initialized and saved.");
        config
    }

    pub async fn save(&self) {
        let dir = Self::config_dir();
        if !dir.exists() {
            if let Err(e) = fs::create_dir_all(&dir).await {
                elog!("Failed to create config directory: {}", e);
            }
        }

        match toml::to_string_pretty(self) {
            Ok(content) => {
                if let Err(e) = fs::write(Self::config_file(), content).await {
                    elog!("Failed to write config file: {}", e);
                }
            }
            Err(e) => {
                elog!("Failed to serialize config: {}", e);
            }
        }
    }
}
