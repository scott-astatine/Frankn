use crate::auth::AuthManager;
use crate::{elog, log};
use dialoguer::{Confirm, Input, Password};
use rand::{Rng, distr::Alphanumeric};
pub mod tui;

use serde::{Deserialize, Serialize};
use std::path::PathBuf;
use tokio::fs;
use ed25519_dalek::SigningKey;

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct HostConfig {
    pub host_id: String,
    pub host_name: String,
    pub password_hash: String,
    #[serde(default)]
    pub salt: String,
    pub signaling_url: String,
    pub is_public: bool,
    pub restricted_cmds: Vec<String>,
    pub llm_model_dir: Option<String>,
    #[serde(default)]
    pub sync_pairs: Vec<SyncPair>,
    #[serde(default)]
    pub sandbox_home: bool,
    #[serde(skip)]
    pub custom_config_path: Option<PathBuf>,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct SyncPair {
    pub local_path: String,
    pub remote_path: String,
    pub mode: String, // "mirror", "single_source"
    pub client_is_source: bool,
    pub interval_minutes: u32,
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

    pub async fn load_or_init(custom_path: Option<PathBuf>) -> Self {
        let config_path = custom_path.clone().unwrap_or_else(Self::config_file);

        let mut config = if config_path.exists() {
            match fs::read_to_string(&config_path).await {
                Ok(content) => match toml::from_str::<HostConfig>(&content) {
                    Ok(mut config) => {
                        config.custom_config_path = custom_path;
                        // Transparently upgrade old Argon2 PHC formats to the secure double-hashed SHA-256 verifier
                        if config.password_hash.starts_with("$argon2id$") {
                            crate::log!("UPGRADE: Old Argon2 password hash format detected. Upgrading to secure SHA-256 verifier hash...");
                            let old_hash = config.password_hash.clone();
                            // Extract salt from old hash
                            let salt = old_hash.split('$').nth(4).unwrap_or("").to_string();
                            
                            use sha2::Digest;
                            let mut hasher = sha2::Sha256::new();
                            hasher.update(old_hash.as_bytes());
                            let new_hash = format!("{:x}", hasher.finalize());
                            
                            config.password_hash = new_hash;
                            config.salt = salt;
                            // Save config to persist upgraded format
                            config.save().await;
                            crate::log!("UPGRADE: Successful.");
                        }
                        config
                    }
                    Err(e) => {
                        elog!("Failed to parse config: {}. Re-initializing...", e);
                        Self::init_interactive(custom_path).await
                    }
                },
                Err(e) => {
                    elog!("Failed to read config file: {}. Re-initializing...", e);
                    Self::init_interactive(custom_path).await
                }
            }
        } else {
            Self::init_interactive(custom_path).await
        };

        if let Ok(key) = config.get_identity_key() {
            let pub_bytes = key.verifying_key().to_bytes();
            use sha2::Digest;
            let raw_id = sha2::Sha256::digest(&pub_bytes);
            use base64::Engine;
            let peer_id = base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(&raw_id);
            config.host_id = peer_id;
        }

        config
    }

    async fn init_interactive(custom_path: Option<PathBuf>) -> Self {
        // Check if we have a TTY before starting interactive setup
        if !atty::is(atty::Stream::Stdin) {
            elog!("ERROR: Configuration not found and no terminal detected.");
            elog!("Please run 'frankn-host' manually once to complete the initial setup.");
            std::process::exit(1);
        }

        let custom_path_clone = custom_path.clone();
        let config = tokio::task::spawn_blocking(move || {
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

             let llm_model_dir: String = Input::new()
                .with_prompt("Neural Model Directory (e.g., /home/user/Models) [Optional]")
                .default(String::new())
                .interact_text()
                .expect("Failed to get model dir");
            let llm_model_dir = if llm_model_dir.trim().is_empty() { None } else { Some(llm_model_dir.trim().to_string()) };

            let sandbox_home = Confirm::new()
                .with_prompt("Restrict file operations to Home directory (sandbox)?")
                .default(false)
                .interact()
                .expect("Failed to get sandboxing preference");

            // Generate 12-digit alphanumeric ID
            let host_id: String = rand::rng()
                .sample_iter(&Alphanumeric)
                .take(12)
                .map(char::from)
                .collect();

            // Hash the password using existing AuthManager logic
            let auth_manager = AuthManager::new(&password);
            let password_hash = auth_manager.password_hash.clone();
            let salt = auth_manager.salt.clone();

            HostConfig {
                host_id,
                host_name,
                password_hash,
                salt,
                signaling_url,
                is_public,
                restricted_cmds: Vec::new(),
                llm_model_dir,
                sync_pairs: Vec::new(),
                sandbox_home,
                custom_config_path: custom_path_clone,
            }
        })
        .await
        .expect("Interactive setup panicked");

        config.save().await;
        log!("Configuration initialized and saved.");
        config
    }

    pub async fn save(&self) {
        let file_path = self.custom_config_path.clone().unwrap_or_else(Self::config_file);
        
        if let Some(dir) = file_path.parent()
            && !dir.exists()
                && let Err(e) = fs::create_dir_all(dir).await {
                    elog!("Failed to create config directory: {}", e);
                }

        match toml::to_string_pretty(self) {
            Ok(content) => {
                if let Err(e) = fs::write(&file_path, content).await {
                    elog!("Failed to write config file: {}", e);
                }
            }
            Err(e) => {
                elog!("Failed to serialize config: {}", e);
            }
        }
    }

    pub fn identity_file() -> PathBuf {
        let mut path = Self::config_dir();
        path.push("identity.pem");
        path
    }

    pub fn get_identity_key(&self) -> Result<SigningKey, Box<dyn std::error::Error>> {
        let path = Self::identity_file();
        if !path.exists() {
            log!("IDENTITY: No identity file found. Generating new Ed25519 keypair...");
            
            let dir = Self::config_dir();
            if !dir.exists() {
                std::fs::create_dir_all(&dir)?;
                #[cfg(unix)]
                {
                    use std::os::unix::fs::PermissionsExt;
                    std::fs::set_permissions(&dir, std::fs::Permissions::from_mode(0o700))?;
                }
            }

            use rand_core::OsRng;
            let mut csprng = OsRng;
            let signing_key = SigningKey::generate(&mut csprng);

            use base64::Engine;
            let pem = format!(
                "-----BEGIN ED25519 PRIVATE KEY-----\n{}\n-----END ED25519 PRIVATE KEY-----\n",
                base64::engine::general_purpose::STANDARD.encode(signing_key.to_bytes())
            );

            std::fs::write(&path, pem)?;
            #[cfg(unix)]
            {
                use std::os::unix::fs::PermissionsExt;
                std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o600))?;
            }

            log!("IDENTITY: Keypair generated and saved to {:?}", path);
            Ok(signing_key)
        } else {
            let content = std::fs::read_to_string(&path)?;
            let b64 = content
                .lines()
                .filter(|line| !line.starts_with("-----"))
                .collect::<Vec<_>>()
                .concat();
            
            use base64::Engine;
            let bytes = base64::engine::general_purpose::STANDARD.decode(b64.trim())?;
            let raw: [u8; 32] = bytes.as_slice().try_into().map_err(|_| "Invalid Ed25519 private key length")?;
            let signing_key = SigningKey::from_bytes(&raw);
            Ok(signing_key)
        }
    }
}
