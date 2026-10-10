use crate::auth::AuthManager;
use crate::{elog, log};
use dialoguer::{Confirm, Input, Password};
use rand::{Rng, distr::Alphanumeric};
pub mod tui;

use ed25519_dalek::SigningKey;
use serde::{Deserialize, Serialize};
use std::path::PathBuf;
use tokio::fs;

static CONFIG_TEMP_SEQUENCE: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);

fn write_config_atomically(
    file_path: &std::path::Path,
    content: String,
    secure_parent: bool,
) -> std::io::Result<()> {
    use std::io::Write;

    let parent = file_path
        .parent()
        .unwrap_or_else(|| std::path::Path::new("."));
    std::fs::create_dir_all(parent)?;
    #[cfg(unix)]
    if secure_parent {
        use std::os::unix::fs::PermissionsExt;
        std::fs::set_permissions(parent, std::fs::Permissions::from_mode(0o700))?;
    }

    let sequence = CONFIG_TEMP_SEQUENCE.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
    let file_name = file_path.file_name().unwrap_or_default().to_string_lossy();
    let temporary = parent.join(format!(
        ".{file_name}.{}.{}.tmp",
        std::process::id(),
        sequence
    ));
    let mut options = std::fs::OpenOptions::new();
    options.create_new(true).write(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        options.mode(0o600);
    }
    let result = (|| {
        let mut file = options.open(&temporary)?;
        file.write_all(content.as_bytes())?;
        file.sync_all()?;
        std::fs::rename(&temporary, file_path)?;
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            std::fs::set_permissions(file_path, std::fs::Permissions::from_mode(0o600))?;
        }
        Ok(())
    })();
    if result.is_err() {
        let _ = std::fs::remove_file(&temporary);
    }
    result
}

#[derive(Debug, Serialize, Deserialize, Clone, Copy, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum RuntimeMode {
    Host,
    Node,
}

impl Default for RuntimeMode {
    fn default() -> Self {
        Self::Host
    }
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct NodeConfig {
    pub host_peer_id: String,
    #[serde(default)]
    pub capabilities: Vec<String>,
}

fn default_true() -> bool {
    true
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct HostConfig {
    #[serde(default)]
    pub mode: RuntimeMode,
    pub host_id: String,
    pub host_name: String,
    pub password_hash: String,
    #[serde(default)]
    pub salt: String,
    /// RFC 9807 Host setup and password file. Missing means local migration is required.
    #[serde(default)]
    pub opaque_auth: Option<frankn_opaque::OpaqueEnrollment>,
    pub signaling_url: String,
    pub is_public: bool,
    pub restricted_cmds: Vec<String>,
    pub llm_model_dir: Option<String>,
    #[serde(default)]
    pub sync_pairs: Vec<SyncPair>,
    #[serde(default)]
    pub sandbox_home: bool,
    #[serde(default)]
    pub lock_cmd: Option<String>,
    #[serde(default)]
    pub unlock_cmd: Option<String>,
    #[serde(default = "default_true")]
    pub enable_notifications: bool,

    // Node-Specific Configuration
    #[serde(default)]
    pub node: Option<NodeConfig>,
    #[serde(default)]
    pub allowed_nodes: Vec<String>,
    /// Client peer IDs permitted by a private signaling host.
    #[serde(default)]
    pub allowed_clients: Vec<String>,

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
                            crate::log!(
                                "UPGRADE: Old Argon2 password hash format detected. Upgrading to secure SHA-256 verifier hash..."
                            );
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
            if let Some(ref path) = custom_path {
                elog!("ERROR: Configuration file '{:?}' not found!", path);
                std::process::exit(1);
            }
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

        if let Some(secure_url) = config.signaling_url.strip_prefix("ws://") {
            config.signaling_url = format!("wss://{secure_url}");
            config.save().await;
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
物理 / Virtual Pairing: Setup Host Profile
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
                .default("wss://152.67.19.202:8037".to_string())
                .interact_text()
                .expect("Failed to get signaling URL");

            let llm_model_dir: String = Input::new()
                .with_prompt("Neural Model Directory (e.g., /home/user/Models) [Optional]")
                .default(String::new())
                .interact_text()
                .expect("Failed to get model dir");
            let llm_model_dir = if llm_model_dir.trim().is_empty() {
                None
            } else {
                Some(llm_model_dir.trim().to_string())
            };

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

            let auth_manager =
                AuthManager::new(&password).expect("Failed to enroll Host passcode with OPAQUE");
            let opaque_auth = auth_manager.opaque_enrollment.clone();

            HostConfig {
                mode: RuntimeMode::Host,
                host_id,
                host_name,
                password_hash: String::new(),
                salt: String::new(),
                opaque_auth,
                signaling_url,
                is_public,
                restricted_cmds: Vec::new(),
                llm_model_dir,
                sync_pairs: Vec::new(),
                sandbox_home,
                lock_cmd: None,
                unlock_cmd: None,
                enable_notifications: true,
                node: None,
                allowed_nodes: Vec::new(),
                allowed_clients: Vec::new(),
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
        if let Err(e) = self.save_checked().await {
            elog!("Failed to write config file: {}", e);
        }
    }

    pub async fn save_checked(&self) -> Result<(), String> {
        let file_path = self
            .custom_config_path
            .clone()
            .unwrap_or_else(Self::config_file);

        if let Some(dir) = file_path.parent()
            && !dir.exists()
            && let Err(e) = fs::create_dir_all(dir).await
        {
            return Err(format!("create config directory: {e}"));
        }

        let content = toml::to_string_pretty(self).map_err(|e| format!("serialize config: {e}"))?;
        let secure_parent = self.custom_config_path.is_none();
        tokio::task::spawn_blocking(move || {
            write_config_atomically(&file_path, content, secure_parent)
        })
        .await
        .map_err(|e| format!("config writer task: {e}"))?
        .map_err(|e| format!("write config: {e}"))
    }

    /// Persist the current client ACL and fail pairing if the update cannot be saved.
    pub async fn persist_allowed_clients(&self, allowed_clients: &[String]) -> Result<(), String> {
        let file_path = self
            .custom_config_path
            .clone()
            .unwrap_or_else(Self::config_file);
        if let Some(dir) = file_path.parent() {
            fs::create_dir_all(dir)
                .await
                .map_err(|e| format!("create config directory: {e}"))?;
        }
        let mut updated = self.clone();
        updated.allowed_clients = allowed_clients.to_vec();
        let content =
            toml::to_string_pretty(&updated).map_err(|e| format!("serialize config: {e}"))?;
        tokio::task::spawn_blocking(move || write_config_atomically(&file_path, content, false))
            .await
            .map_err(|e| format!("config writer task: {e}"))?
            .map_err(|e| format!("write config: {e}"))
    }

    pub async fn migrate_opaque_auth(&self) -> Result<(), String> {
        if self.opaque_auth.is_some() {
            return Err("Host authentication is already migrated to OPAQUE".into());
        }
        if !atty::is(atty::Stream::Stdin) {
            return Err("OPAQUE migration requires a local interactive terminal".into());
        }

        let old_hash = self.password_hash.clone();
        let old_salt = self.salt.clone();
        let opaque_auth = tokio::task::spawn_blocking(move || {
            let password = Password::new()
                .with_prompt("Enter the current Host passcode to migrate authentication")
                .interact()
                .map_err(|_| "Could not read the current passcode".to_string())?;
            if !AuthManager::verify_password(&password, &old_hash, &old_salt) {
                return Err("Current passcode verification failed".to_string());
            }
            let auth = AuthManager::new(&password)?;
            Ok::<_, String>(auth.opaque_enrollment)
        })
        .await
        .map_err(|e| format!("migration task failed: {e}"))??;

        let mut migrated = self.clone();
        migrated.password_hash.clear();
        migrated.salt.clear();
        migrated.opaque_auth = opaque_auth;
        migrated.save_checked().await?;
        Ok(())
    }

    pub fn identity_file(&self) -> PathBuf {
        if let Some(ref custom_path) = self.custom_config_path {
            let mut path = custom_path.clone();
            path.set_extension("pem");
            path
        } else {
            let mut path = Self::config_dir();
            path.push("identity.pem");
            path
        }
    }

    pub fn get_identity_key(&self) -> Result<SigningKey, Box<dyn std::error::Error>> {
        let path = self.identity_file();
        if !path.exists() {
            log!("IDENTITY: No identity file found. Generating new Ed25519 keypair...");

            let dir = path.parent().unwrap();
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
            let raw: [u8; 32] = bytes
                .as_slice()
                .try_into()
                .map_err(|_| "Invalid Ed25519 private key length")?;
            let signing_key = SigningKey::from_bytes(&raw);
            Ok(signing_key)
        }
    }
}
