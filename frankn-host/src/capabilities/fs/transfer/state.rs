use std::collections::HashMap;
use std::sync::Arc;
use std::sync::LazyLock;
use std::sync::atomic::AtomicBool;
use tokio::fs::File;
use tokio::sync::Mutex;
use sha2::Sha256;

/// Partial transfer state persisted alongside the `.part` file.
#[derive(Debug, serde::Serialize, serde::Deserialize)]
pub struct TransferState {
    pub transfer_id: String,
    pub path: String,
    pub total_size: u64,
    pub current_offset: u64,
    pub expected_hash: Option<String>,
    #[serde(default)]
    pub last_seq: u32,
}

/// Writable session state for an active upload.
pub struct UploadSession {
    pub file: File,
    pub hasher: Sha256,
    pub current_offset: u64,
    pub total_size: u64,
    pub last_seq: u32,
    pub path: String,
    pub client_id: String,
}

/// Global upload session registry.
pub static UPLOAD_SESSIONS: LazyLock<Mutex<HashMap<String, Arc<Mutex<UploadSession>>>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));

/// Global registry for active download tasks to enable graceful cancellation.
pub static DOWNLOAD_TASKS: LazyLock<Mutex<HashMap<String, Arc<AtomicBool>>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));

pub fn state_path(file_path: &str) -> String {
    format!("{}.frankn_state", file_path)
}

pub fn part_path(file_path: &str) -> String {
    format!("{}.part", file_path)
}

pub async fn write_state(file_path: &str, state: &TransferState) -> std::io::Result<()> {
    let json = serde_json::to_string_pretty(state)?;
    tokio::fs::write(state_path(file_path), json).await?;
    Ok(())
}

pub async fn cleanup_partial(file_path: &str) {
    let _ = tokio::fs::remove_file(part_path(file_path)).await;
    let _ = tokio::fs::remove_file(state_path(file_path)).await;
}
