use crate::HostMessage;
use crate::ops::rtc::RTCConn;
use eventsource_stream::Eventsource;
use futures_util::StreamExt;
use reqwest::Client;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::Mutex;
use tokio_tungstenite::tungstenite::Bytes;

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
    active_model: Option<String>,
    client: Client,
    chats: Arc<Mutex<HashMap<String, ChatSession>>>,
    chats_loaded: bool,
    pub approval_registry: HashMap<String, tokio::sync::oneshot::Sender<bool>>,
}

impl LlmManager {
    pub fn new() -> Self {
        Self {
            active_model: None,
            client: Client::new(),
            chats: Arc::new(Mutex::new(HashMap::new())),
            chats_loaded: false,
            approval_registry: HashMap::new(),
        }
    }

    async fn get_chats_path() -> std::path::PathBuf {
        let mut path = dirs::home_dir().unwrap_or_default();
        path.push(".config/frankn/chats.json");
        path
    }

    pub async fn ensure_chats_loaded(&mut self) {
        if self.chats_loaded {
            return;
        }
        let path = Self::get_chats_path().await;
        if let Ok(data) = tokio::fs::read_to_string(&path).await
            && let Ok(loaded) = serde_json::from_str::<HashMap<String, ChatSession>>(&data)
        {
            let mut c = self.chats.lock().await;
            *c = loaded;
        }
        self.chats_loaded = true;
    }

    pub async fn save_chats(chats: &HashMap<String, ChatSession>) {
        let path = Self::get_chats_path().await;
        if let Ok(data) = serde_json::to_string_pretty(chats) {
            let _ = tokio::fs::write(&path, data).await;
        }
    }

    pub async fn list_chats(&mut self) -> serde_json::Value {
        self.ensure_chats_loaded().await;
        let c = self.chats.lock().await;
        let mut list: Vec<serde_json::Value> = c
            .values()
            .map(|s| {
                serde_json::json!({
                    "id": s.id,
                    "title": s.title,
                    "updated_at": s.updated_at
                })
            })
            .collect();
        list.sort_by(|a, b| {
            let t_a = a["updated_at"].as_u64().unwrap_or(0);
            let t_b = b["updated_at"].as_u64().unwrap_or(0);
            t_b.cmp(&t_a) // desc
        });
        serde_json::json!({ "chats": list })
    }

    pub async fn load_chat(&mut self, chat_id: &str) -> Option<serde_json::Value> {
        self.ensure_chats_loaded().await;
        let c = self.chats.lock().await;
        c.get(chat_id).map(|s| serde_json::to_value(s).unwrap())
    }

    pub async fn delete_chat(&mut self, chat_id: &str) -> bool {
        self.ensure_chats_loaded().await;
        let mut c = self.chats.lock().await;
        let removed = c.remove(chat_id).is_some();
        if removed {
            Self::save_chats(&c).await;
        }
        removed
    }

    pub async fn start_server(
        &mut self,
        model_name_or_path: &str,
        config: &crate::config::HostConfig,
    ) -> Result<(), String> {
        // 1. Verify Ollama is running
        let health_res = self.client.get("http://localhost:11434/").send().await;
        if health_res.is_err() {
            return Err(
                "Ollama service is not running on http://localhost:11434. Please start Ollama."
                    .to_string(),
            );
        }

        // 2. Determine if it is a local GGUF path
        if model_name_or_path.ends_with(".gguf") || model_name_or_path.ends_with(".ggff") {
            let path = std::path::Path::new(model_name_or_path);
            let final_path = if path.is_absolute() {
                path.to_path_buf()
            } else {
                let model_dir = config.llm_model_dir.clone().unwrap_or_else(|| {
                    dirs::home_dir()
                        .map(|mut p| {
                            p.push(".config/frankn/models");
                            p.to_path_buf()
                        })
                        .unwrap_or_else(|| std::path::PathBuf::from("/home/user/Models"))
                        .to_string_lossy()
                        .into_owned()
                });
                std::path::Path::new(&model_dir).join(model_name_or_path)
            };

            if !final_path.exists() {
                return Err(format!(
                    "Local model file does not exist: {}",
                    final_path.display()
                ));
            }

            // Extract a clean model name for Ollama registration, e.g., local_model_name
            let stem = final_path
                .file_stem()
                .ok_or_else(|| "Invalid model file name".to_string())?
                .to_string_lossy()
                .to_string();
            let ollama_model_name = format!("local_{}", stem.replace('.', "_").replace(' ', "_"));

            crate::log!(
                "Registering local GGUF model with Ollama: {} -> {}",
                final_path.display(),
                ollama_model_name
            );

            // Call Ollama create API
            let create_payload = serde_json::json!({
                "name": &ollama_model_name,
                "modelfile": format!("FROM {}", final_path.to_string_lossy())
            });

            let res = self
                .client
                .post("http://localhost:11434/api/create")
                .json(&create_payload)
                .send()
                .await
                .map_err(|e| format!("Failed to call Ollama create API: {}", e))?;

            if !res.status().is_success() {
                let err_text = res.text().await.unwrap_or_default();
                return Err(format!("Ollama failed to create model: {}", err_text));
            }

            self.active_model = Some(ollama_model_name);
        } else {
            // It's a standard pulled model name
            self.active_model = Some(model_name_or_path.to_string());
        }

        Ok(())
    }

    pub async fn stop_server(&mut self) {
        self.active_model = None;
    }

    pub async fn scan_models(dir_path: &str) -> Result<serde_json::Value, String> {
        let mut models = Vec::new();
        let client = reqwest::Client::new();

        // 1. Fetch official Ollama models
        if let Ok(res) = client.get("http://localhost:11434/api/tags").send().await {
            #[derive(Deserialize)]
            struct OllamaModel {
                name: String,
                size: u64,
            }
            #[derive(Deserialize)]
            struct OllamaTagsResponse {
                models: Vec<OllamaModel>,
            }
            if let Ok(parsed) = res.json::<OllamaTagsResponse>().await {
                for m in parsed.models {
                    models.push(serde_json::json!({
                        "name": m.name,
                        "size": m.size,
                    }));
                }
            }
        }

        // 2. Scan local custom model directory (if it exists)
        if let Ok(mut entries) = tokio::fs::read_dir(dir_path).await {
            while let Ok(Some(entry)) = entries.next_entry().await {
                let path = entry.path();
                if path.is_file()
                    && let Some(ext) = path.extension()
                    && (ext == "gguf" || ext == "ggff")
                {
                    let name = path
                        .file_name()
                        .unwrap_or_default()
                        .to_string_lossy()
                        .into_owned();
                    let size = match entry.metadata().await {
                        Ok(meta) => meta.len(),
                        Err(_) => 0,
                    };

                    // Avoid duplicate entries if user registered the GGUF in Ollama already
                    if !models.iter().any(|m| m["name"] == name) {
                        models.push(serde_json::json!({
                            "name": name,
                            "size": size,
                        }));
                    }
                }
            }
        }

        Ok(serde_json::json!({ "models": models }))
    }

    pub async fn chat_stream_detached(
        llm_manager: Arc<Mutex<Self>>,
        model: String,
        message: String,
        system_prompt: Option<String>,
        chat_id: Option<String>,
        msg_id: String,
        rtc_conn: Arc<Mutex<RTCConn>>,
        label: String,
    ) {
        let (client, chats) = {
            let l = llm_manager.lock().await;
            (l.client.clone(), l.chats.clone())
        };

        // 1. Send the initial success response to unblock the Flutter client
        let response = HostMessage::Response {
            id: msg_id,
            status: crate::utils::Status::Success,
            data: None,
            timestamp: crate::utils::get_timestamp(),
        };
        Self::send_msg(response, &rtc_conn, &label).await;

        let cid = chat_id.unwrap_or_else(|| uuid::Uuid::new_v4().to_string());

        // We load the existing chat history and append the user message
        let mut req_messages = {
            let mut c = chats.lock().await;
            let session = c.entry(cid.clone()).or_insert_with(|| ChatSession {
                id: cid.clone(),
                title: message.chars().take(30).collect::<String>(),
                messages: Vec::new(),
                updated_at: crate::utils::get_timestamp(),
            });

            // Set system prompt if new session
            if let Some(sp) = system_prompt {
                // To support agent skills, we append a strict instructions suffix to the system prompt
                let full_sp = format!(
                    "{}\n\n[SYSTEM INSTRUCTION: Workstation Agent Skills]\nYou have access to local workstation tools. You can view directories, read/write files, and run commands. To execute a tool, use XML tags format:\n<call:tool_name>\n{{\"param\": \"value\"}}\n</call:tool_name>\n\nAvailable Tools:\n1. list_dir: {{\"path\": \"/path\"}}\n2. read_file: {{\"path\": \"/path\"}}\n3. write_file: {{\"path\": \"/path\", \"content\": \"...\"}}\n4. run_command: {{\"command\": \"command string\"}}\n\nFollow ReAct pattern: Thought -> Action -> Observation. Output thought reasoning inside <think> tags first.",
                    sp
                );

                if session.messages.is_empty() || session.messages[0].role != "system" {
                    session.messages.insert(
                        0,
                        ChatMessage {
                            role: "system".to_string(),
                            content: full_sp,
                        },
                    );
                } else {
                    session.messages[0].content = full_sp;
                }
            }

            session.messages.push(ChatMessage {
                role: "user".to_string(),
                content: message.clone(),
            });
            session.updated_at = crate::utils::get_timestamp();

            let msgs = session.messages.clone();
            Self::save_chats(&c).await;
            msgs
        };

        // ReAct Loop - max 6 turns per conversation turn to prevent infinite loops
        for turn in 0..6 {
            crate::log!("AGENT LOOP: Starting turn {}", turn);
            let req_body_messages = req_messages
                .iter()
                .map(|m| {
                    serde_json::json!({
                        "role": m.role,
                        "content": m.content
                    })
                })
                .collect::<Vec<serde_json::Value>>();

            let request_body = serde_json::json!({
                "model": model,
                "messages": req_body_messages,
                "stream": true
            });

            let res = match client
                .post("http://localhost:11434/v1/chat/completions")
                .json(&request_body)
                .send()
                .await
            {
                Ok(r) => r,
                Err(e) => {
                    crate::elog!("LLM ERROR: failed to send request: {}", e);
                    break;
                }
            };

            let mut stream = res.bytes_stream().eventsource();
            let mut assistant_content = String::new();

            while let Some(event) = stream.next().await {
                match event {
                    Ok(event) => {
                        let data = event.data;
                        if data == "[DONE]" {
                            break;
                        }

                        if let Ok(parsed) = serde_json::from_str::<serde_json::Value>(&data)
                            && let Some(choices) = parsed.get("choices")
                            && let Some(first_choice) = choices.get(0)
                            && let Some(delta) = first_choice.get("delta")
                            && let Some(content) = delta.get("content")
                            && let Some(content_str) = content.as_str()
                        {
                            assistant_content.push_str(content_str);
                            let msg = HostMessage::LlmToken {
                                token: content_str.to_string(),
                                is_final: false,
                                timestamp: crate::utils::get_timestamp(),
                            };
                            Self::send_msg(msg, &rtc_conn, &label).await;
                        }
                    }
                    Err(e) => {
                        crate::elog!("LLM ERROR: event stream error: {}", e);
                        break;
                    }
                }
            }

            // Save this turn's assistant response
            req_messages.push(ChatMessage {
                role: "assistant".to_string(),
                content: assistant_content.clone(),
            });

            // Parse if the assistant requested a tool call
            if let Some(tool) = crate::ops::llm_tools::parse_tool_call(&assistant_content) {
                crate::log!("AGENT LOOP: Tool call detected: {}", tool.name);

                // Notify UI of tool execution start
                let status_msg = format!("\n\n⚙️ [Harness: Running tool `{}`...]\n\n", tool.name);
                Self::send_msg(
                    HostMessage::LlmToken {
                        token: status_msg,
                        is_final: false,
                        timestamp: crate::utils::get_timestamp(),
                    },
                    &rtc_conn,
                    &label,
                )
                .await;

                // Execute workstation tool
                let tool_result = crate::ops::llm_tools::execute_tool(
                    &tool.name,
                    &tool.args,
                    &llm_manager,
                    &rtc_conn,
                    &label,
                )
                .await;

                let (observation_content, is_error) = match tool_result {
                    Ok(out) => (out, false),
                    Err(err) => (err, true),
                };

                let status_icon = if is_error { "❌" } else { "✓" };
                let observation = format!(
                    "<observation:{}>\n{}\n</observation:{}>",
                    tool.name, observation_content, tool.name
                );

                // Notify UI of observation
                let observation_msg = format!(
                    "\n\n⚙️ [Harness: Tool `{}` observation ({}):\n```\n{}\n```]\n\n",
                    tool.name, status_icon, observation_content
                );
                Self::send_msg(
                    HostMessage::LlmToken {
                        token: observation_msg,
                        is_final: false,
                        timestamp: crate::utils::get_timestamp(),
                    },
                    &rtc_conn,
                    &label,
                )
                .await;

                // Push observation to context history for next turn
                req_messages.push(ChatMessage {
                    role: "user".to_string(),
                    content: observation,
                });
            } else {
                // No tool call requested; model has finished its final turn
                crate::log!("AGENT LOOP: Complete (No tool calls).");
                break;
            }
        }

        // Commit full multi-turn trajectory to chat database
        {
            let mut c = chats.lock().await;
            if let Some(session) = c.get_mut(&cid) {
                session.messages = req_messages;
                session.updated_at = crate::utils::get_timestamp();
                Self::save_chats(&c).await;
            }
        }

        // Finalize stream
        let final_msg = HostMessage::LlmToken {
            token: String::new(),
            is_final: true,
            timestamp: crate::utils::get_timestamp(),
        };
        Self::send_msg(final_msg, &rtc_conn, &label).await;
    }

    async fn send_msg(msg: HostMessage, rtc_conn: &Arc<Mutex<RTCConn>>, label: &str) {
        if let Ok(json) = serde_json::to_string(&msg) {
            let conn = rtc_conn.lock().await;
            let _ = conn.send_message(label, &Bytes::from(json)).await;
        }
    }

    // =========================================================================
    // DC Message Handlers — called from dc_message_parser::DcMsg::parse_msg
    // =========================================================================

    pub async fn handle_list_models(id: &str, config: &crate::config::HostConfig) -> HostMessage {
        use crate::utils::{Status, get_timestamp};

        let model_dir = config.llm_model_dir.clone().unwrap_or_else(|| {
            dirs::home_dir()
                .map(|mut p| {
                    p.push("Models");
                    p.to_string_lossy().to_string()
                })
                .unwrap_or_else(|| "~/.config/frankn/llms/".to_string())
        });

        match Self::scan_models(&model_dir).await {
            Ok(data) => HostMessage::Response {
                id: id.to_string(),
                status: Status::Success,
                data: Some(data),
                timestamp: get_timestamp(),
            },
            Err(e) => HostMessage::Response {
                id: id.to_string(),
                status: Status::Error(e),
                data: None,
                timestamp: get_timestamp(),
            },
        }
    }

    pub async fn handle_start(
        id: &str,
        model_path: &str,
        llm_manager: Arc<Mutex<Self>>,
        config: &crate::config::HostConfig,
    ) -> HostMessage {
        use crate::utils::{Status, get_timestamp};

        match llm_manager
            .lock()
            .await
            .start_server(model_path, config)
            .await
        {
            Ok(_) => HostMessage::Response {
                id: id.to_string(),
                status: Status::Success,
                data: None,
                timestamp: get_timestamp(),
            },
            Err(e) => HostMessage::Response {
                id: id.to_string(),
                status: Status::Error(e),
                data: None,
                timestamp: get_timestamp(),
            },
        }
    }

    pub async fn handle_chat(
        id: &str,
        message: &str,
        system_prompt: &Option<String>,
        chat_id: &Option<String>,
        llm_manager: Arc<Mutex<Self>>,
        rtc_conn: Arc<Mutex<RTCConn>>,
        label: &str,
    ) -> HostMessage {
        use crate::utils::{Status, get_timestamp};

        let msg = message.to_string();
        let sys_prompt = system_prompt.clone();
        let cid = chat_id.clone();
        let lbl = label.to_string();
        let msg_id = id.to_string();

        let llm_m = Arc::clone(&llm_manager);
        tokio::spawn(async move {
            let model = {
                let mut l = llm_m.lock().await;
                l.ensure_chats_loaded().await;
                l.active_model
                    .clone()
                    .unwrap_or_else(|| "gemma2:9b".to_string())
            };
            Self::chat_stream_detached(llm_m, model, msg, sys_prompt, cid, msg_id, rtc_conn, lbl)
                .await;
        });

        HostMessage::Response {
            id: id.to_string(),
            status: Status::Success,
            data: None,
            timestamp: get_timestamp(),
        }
    }

    pub async fn handle_load_chat(
        id: &str,
        chat_id: &str,
        llm_manager: Arc<Mutex<Self>>,
    ) -> HostMessage {
        use crate::utils::{Status, get_timestamp};

        let mut l = llm_manager.lock().await;
        let data = l.load_chat(chat_id).await;
        let status = match data {
            Some(_) => Status::Success,
            None => Status::Error("Chat not found".to_string()),
        };
        HostMessage::Response {
            id: id.to_string(),
            status,
            data,
            timestamp: get_timestamp(),
        }
    }

    pub async fn handle_list_chats(id: &str, llm_manager: Arc<Mutex<Self>>) -> HostMessage {
        use crate::utils::{Status, get_timestamp};

        let mut l = llm_manager.lock().await;
        let data = l.list_chats().await;
        HostMessage::Response {
            id: id.to_string(),
            status: Status::Success,
            data: Some(data),
            timestamp: get_timestamp(),
        }
    }

    pub async fn handle_delete_chat(
        id: &str,
        chat_id: &str,
        llm_manager: Arc<Mutex<Self>>,
    ) -> HostMessage {
        use crate::utils::{Status, get_timestamp};

        let mut l = llm_manager.lock().await;
        let deleted = l.delete_chat(chat_id).await;
        let status = if deleted {
            Status::Success
        } else {
            Status::Error("Chat not found".to_string())
        };
        HostMessage::Response {
            id: id.to_string(),
            status,
            data: None,
            timestamp: get_timestamp(),
        }
    }

    pub async fn handle_stop(id: &str, llm_manager: Arc<Mutex<Self>>) -> HostMessage {
        use crate::utils::{Status, get_timestamp};

        llm_manager.lock().await.stop_server().await;
        HostMessage::Response {
            id: id.to_string(),
            status: Status::Success,
            data: None,
            timestamp: get_timestamp(),
        }
    }
}
