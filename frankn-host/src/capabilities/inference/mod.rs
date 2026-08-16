use crate::transport::context::CommandContext;
use crate::utils::Status;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::Mutex;

pub mod engine;
pub mod store;
pub mod tools;

#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct ChatMessage {
    pub role: String,
    pub content: String,
}

#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct ChatSession {
    pub id: String,
    pub title: String,
    pub messages: Vec<ChatMessage>,
    pub updated_at: u64,
}

pub struct LlmManager {
    pub active_model: Option<String>,
    pub client: reqwest::Client,
    pub chats: Arc<Mutex<HashMap<String, ChatSession>>>,
    pub chats_loaded: bool,
    pub approval_registry: HashMap<String, tokio::sync::oneshot::Sender<bool>>,
    pub dohee_child: Option<tokio::process::Child>,
    pub use_in_process_engine: bool,
}

impl LlmManager {
    pub fn new() -> Self {
        Self {
            active_model: None,
            client: reqwest::Client::new(),
            chats: Arc::new(Mutex::new(HashMap::new())),
            chats_loaded: false,
            approval_registry: HashMap::new(),
            dohee_child: None,
            use_in_process_engine: true,
        }
    }
    pub async fn handle_list_models(ctx: &CommandContext) {
        let model_dir = ctx.config.llm_model_dir.clone().unwrap_or_else(|| {
            dirs::home_dir()
                .map(|mut p| {
                    p.push("Models");
                    p.to_string_lossy().to_string()
                })
                .unwrap_or_else(|| "~/.config/frankn/llms/".to_string())
        });

        match Self::scan_models(&model_dir).await {
            Ok(data) => {
                let _ = ctx.reply(Status::Success, Some(data)).await;
            }
            Err(e) => {
                let _ = ctx.reply(Status::Error(e), None).await;
            }
        }
    }

    pub async fn handle_start(
        ctx: &CommandContext,
        model_path: &str,
        llm_manager: Arc<Mutex<LlmManager>>,
    ) {
        let resolved = Self::resolve_model_path(model_path, &ctx.config.llm_model_dir);
        let resolved_str = resolved.to_string_lossy().to_string();

        crate::log!("Resolved model path: {}", resolved_str);

        match llm_manager
            .lock()
            .await
            .start_server(&resolved_str, &ctx.config)
            .await
        {
            Ok(_) => {
                let _ = ctx.reply(Status::Success, None).await;
            }
            Err(e) => {
                let _ = ctx.reply(Status::Error(e), None).await;
            }
        }
    }

fn resolve_model_path(model_path: &str, config_model_dir: &Option<String>) -> std::path::PathBuf {
    let path = std::path::Path::new(model_path);
    if path.is_absolute() || path.exists() {
        return path.to_path_buf();
    }

    let model_dir = config_model_dir.clone().unwrap_or_else(|| {
        dirs::home_dir()
            .map(|mut p| {
                p.push("Models");
                p.to_string_lossy().to_string()
            })
            .unwrap_or_else(|| "~/.config/frankn/llms/".to_string())
    });

    let dir_path = if model_dir.starts_with("~/") {
        if let Some(home) = dirs::home_dir() {
            home.join(&model_dir[2..])
        } else {
            std::path::PathBuf::from(&model_dir)
        }
    } else {
        std::path::PathBuf::from(&model_dir)
    };

    dir_path.join(path)
}

    pub async fn handle_chat(
        ctx: &CommandContext,
        message: &str,
        system_prompt: &Option<String>,
        chat_id: &Option<String>,
        llm_manager: Arc<Mutex<LlmManager>>,
    ) {
        let msg = message.to_string();
        let sys_prompt = system_prompt.clone();
        let cid = chat_id.clone();
        let ctx_clone = ctx.clone();

        let llm_m = Arc::clone(&llm_manager);
        tokio::spawn(async move {
            let model = {
                let mut l = llm_m.lock().await;
                l.ensure_chats_loaded().await;
                l.active_model
                    .clone()
                    .unwrap_or_else(|| "gemma2:9b".to_string())
            };
            engine::chat_stream_detached(ctx_clone, llm_m, model, msg, sys_prompt, cid).await;
        });
    }

    pub async fn handle_load_chat(
        ctx: &CommandContext,
        chat_id: &str,
        llm_manager: Arc<Mutex<LlmManager>>,
    ) {
        let mut l = llm_manager.lock().await;
        let data = l.load_chat(chat_id).await;
        let status = match data {
            Some(_) => Status::Success,
            None => Status::Error("Chat not found".to_string()),
        };
        let _ = ctx.reply(status, data).await;
    }

    pub async fn handle_list_chats(ctx: &CommandContext, llm_manager: Arc<Mutex<LlmManager>>) {
        let mut l = llm_manager.lock().await;
        let data = l.list_chats().await;
        let _ = ctx.reply(Status::Success, Some(data)).await;
    }

    pub async fn handle_delete_chat(
        ctx: &CommandContext,
        chat_id: &str,
        llm_manager: Arc<Mutex<LlmManager>>,
    ) {
        let mut l = llm_manager.lock().await;
        let deleted = l.delete_chat(chat_id).await;
        let status = if deleted {
            Status::Success
        } else {
            Status::Error("Chat not found".to_string())
        };
        let _ = ctx.reply(status, None).await;
    }

    pub async fn handle_stop(ctx: &CommandContext, llm_manager: Arc<Mutex<LlmManager>>) {
        llm_manager.lock().await.stop_server().await;
        let _ = ctx.reply(Status::Success, None).await;
    }
}

impl LlmManager {
    pub async fn scan_models(model_dir: &str) -> Result<serde_json::Value, String> {
        let path = std::path::Path::new(model_dir);
        if !path.exists() {
            return Ok(serde_json::json!({ "models": [] }));
        }

        let mut models = Vec::new();
        let mut dir = tokio::fs::read_dir(path)
            .await
            .map_err(|e| format!("Failed to read models directory: {}", e))?;

        while let Ok(Some(entry)) = dir.next_entry().await {
            let entry_path = entry.path();
            if entry_path.is_file() {
                if let Some(ext) = entry_path.extension() {
                    let ext_str = ext.to_string_lossy().to_lowercase();
                    if ext_str == "gguf" || ext_str == "bin" {
                        let name = entry_path
                            .file_name()
                            .map(|f| f.to_string_lossy().to_string())
                            .unwrap_or_default();
                        let size = entry.metadata().await.map(|m| m.len()).unwrap_or(0);
                        models.push(serde_json::json!({
                            "name": name,
                            "path": entry_path.to_string_lossy().to_string(),
                            "size": size,
                        }));
                    }
                }
            }
        }

        Ok(serde_json::json!({ "models": models }))
    }
}
