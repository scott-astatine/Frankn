use crate::HostMessage;
use crate::ops::rtc::RTCConn;
use eventsource_stream::Eventsource;
use futures_util::StreamExt;
use reqwest::Client;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::process::Stdio;
use std::sync::Arc;
use tokio::process::{Child, Command};
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
    process: Option<Child>,
    client: Client,
    chats: Arc<Mutex<HashMap<String, ChatSession>>>,
    chats_loaded: bool,
}

impl LlmManager {
    pub fn new() -> Self {
        Self {
            process: None,
            client: Client::new(),
            chats: Arc::new(Mutex::new(HashMap::new())),
            chats_loaded: false,
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
        model_path: &str,
        config: &crate::config::HostConfig,
    ) -> Result<(), String> {
        if self.process.is_some() {
            return Ok(());
        }

        // Basic directory traversal protection
        let path = std::path::Path::new(model_path);

        let final_path = if path.is_absolute() {
            path.to_path_buf()
        } else {
            // Join with the configured model directory
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
            std::path::Path::new(&model_dir).join(model_path)
        };

        if !final_path.exists() {
            return Err(format!(
                "Model file does not exist: {}",
                final_path.display()
            ));
        }

        // Ensure llama-server is in PATH
        match which::which("llama-server") {
            Ok(_) => {}
            Err(_) => return Err("llama-server binary not found in PATH.".to_string()),
        }

        let child = Command::new("llama-server")
            .args([
                "-m",
                &final_path.to_string_lossy(),
                "--port",
                "8080",
                "-c",
                "8192", // --jinja -c 8192 -ngl 99
                "-ngl",
                "99",
            ])
            .stdout(Stdio::null())
            .stderr(Stdio::piped()) // Capture stderr for debugging if it crashes
            .spawn()
            .map_err(|e| format!("Failed to spawn llama-server: {}", e))?;

        self.process = Some(child);

        // Wait for server to boot by polling the endpoint instead of hardcoded sleep
        let mut retries = 0;
        let mut is_ready = false;
        while retries < 15 {
            tokio::time::sleep(tokio::time::Duration::from_millis(500)).await;
            if let Ok(res) = self.client.get("http://localhost:8080/health").send().await
                && res.status().is_success()
            {
                is_ready = true;
                break;
            }

            // Check if it crashed while we were waiting
            if let Some(child) = &mut self.process
                && let Ok(Some(status)) = child.try_wait()
            {
                self.process = None;
                return Err(format!(
                    "llama-server crashed during startup with status: {}",
                    status
                ));
            }
            retries += 1;
        }

        if !is_ready {
            self.stop_server().await;
            return Err("llama-server failed to become ready within 7.5 seconds.".to_string());
        }

        Ok(())
    }

    pub async fn stop_server(&mut self) {
        if let Some(mut child) = self.process.take() {
            let _ = child.kill().await;
        }
    }

    pub async fn scan_models(dir_path: &str) -> Result<serde_json::Value, String> {
        let mut entries = match tokio::fs::read_dir(dir_path).await {
            Ok(entries) => entries,
            Err(e) => return Err(format!("Failed to read model directory: {}", e)),
        };

        let mut models = Vec::new();
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

                models.push(serde_json::json!({
                    "name": name,
                    "size": size,
                }));
            }
        }

        Ok(serde_json::json!({ "models": models }))
    }

    pub fn get_client(&self) -> Client {
        self.client.clone()
    }

    pub fn get_chats(&self) -> Arc<Mutex<HashMap<String, ChatSession>>> {
        self.chats.clone()
    }

    pub async fn chat_stream_detached(
        client: Client,
        chats: Arc<Mutex<HashMap<String, ChatSession>>>,
        message: String,
        system_prompt: Option<String>,
        chat_id: Option<String>,
        msg_id: String,
        rtc_conn: Arc<Mutex<RTCConn>>,
        label: String,
    ) {
        // 1. Send the initial success response to unblock the Flutter client
        let response = HostMessage::Response {
            id: msg_id,
            status: crate::utils::Status::Success,
            data: None,
            timestamp: crate::utils::get_timestamp(),
        };
        Self::send_msg(response, &rtc_conn, &label).await;

        let cid = chat_id.unwrap_or_else(|| uuid::Uuid::new_v4().to_string());

        let req_messages = {
            let mut c = chats.lock().await;
            let session = c.entry(cid.clone()).or_insert_with(|| ChatSession {
                id: cid.clone(),
                title: message.chars().take(30).collect::<String>(),
                messages: Vec::new(),
                updated_at: crate::utils::get_timestamp(),
            });

            if let Some(sp) = system_prompt {
                if session.messages.is_empty() || session.messages[0].role != "system" {
                    session.messages.insert(
                        0,
                        ChatMessage {
                            role: "system".to_string(),
                            content: sp.clone(),
                        },
                    );
                } else {
                    session.messages[0].content = sp.clone();
                }
            }

            session.messages.push(ChatMessage {
                role: "user".to_string(),
                content: message.clone(),
            });
            session.updated_at = crate::utils::get_timestamp();

            let msgs = session
                .messages
                .iter()
                .map(|m| {
                    serde_json::json!({
                        "role": m.role,
                        "content": m.content
                    })
                })
                .collect::<Vec<serde_json::Value>>();

            Self::save_chats(&c).await;
            msgs
        };

        let request_body = serde_json::json!({
            "messages": req_messages,
            "stream": true
        });

        let res = match client
            .post("http://localhost:8080/v1/chat/completions")
            .json(&request_body)
            .send()
            .await
        {
            Ok(r) => r,
            Err(e) => {
                crate::elog!("LLM ERROR: failed to send request: {}", e);
                return;
            }
        };

        let mut stream = res.bytes_stream().eventsource();
        let mut assistant_content = String::new();

        while let Some(event) = stream.next().await {
            match event {
                Ok(event) => {
                    let data = event.data;
                    if data == "[DONE]" {
                        let msg = HostMessage::LlmToken {
                            token: String::new(),
                            is_final: true,
                            timestamp: crate::utils::get_timestamp(),
                        };
                        Self::send_msg(msg, &rtc_conn, &label).await;
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

        // Save the assistant's response to the session
        {
            let mut c = chats.lock().await;
            if let Some(session) = c.get_mut(&cid) {
                session.messages.push(ChatMessage {
                    role: "assistant".to_string(),
                    content: assistant_content,
                });
                session.updated_at = crate::utils::get_timestamp();
                Self::save_chats(&c).await;
            }
        }
    }

    async fn send_msg(msg: HostMessage, rtc_conn: &Arc<Mutex<RTCConn>>, label: &str) {
        if let Ok(json) = serde_json::to_string(&msg) {
            let conn = rtc_conn.lock().await;
            let _ = conn.send_message(label, &Bytes::from(json)).await;
        }
    }
}
