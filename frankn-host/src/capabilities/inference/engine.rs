use std::sync::Arc;
use tokio::sync::Mutex;
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use crate::HostMessage;
use crate::transport::context::CommandContext;
use crate::utils::Status;
use crate::utils::get_timestamp;
use eventsource_stream::Eventsource;
use futures_util::StreamExt;
use super::{LlmManager, ChatMessage, ChatSession};

impl LlmManager {
    pub async fn start_server(
        &mut self,
        model_path: &str,
        _config: &crate::config::HostConfig,
    ) -> Result<(), String> {
        let name = std::path::Path::new(model_path)
            .file_name()
            .map(|f| f.to_string_lossy().to_string())
            .unwrap_or_else(|| "gemma2:9b".to_string());

        if self.use_in_process_engine {
            crate::log!("Spawning isolated Dohee worker subprocess for {}", model_path);
            let exe_path = std::env::current_exe().map_err(|e| e.to_string())?;
            let child = tokio::process::Command::new(exe_path)
                .args(&["dohee-worker", "--model", model_path])
                .stdin(std::process::Stdio::piped())
                .stdout(std::process::Stdio::piped())
                .spawn()
                .map_err(|e| format!("Failed to spawn dohee-worker: {}", e))?;

            self.dohee_child = Some(child);
            self.active_model = Some(name);
            Ok(())
        } else {
            // Ollama compatibility mode
            crate::log!("Starting Ollama server for {}", model_path);
            let _ = tokio::process::Command::new("ollama")
                .args(["run", &name])
                .spawn()
                .map_err(|e| format!("Ollama spawn failed: {}", e))?;
            self.active_model = Some(name);
            Ok(())
        }
    }

    pub async fn stop_server(&mut self) {
        crate::log!("Stopping LLM model/engine subprocess");
        if let Some(mut child) = self.dohee_child.take() {
            crate::log!("Killing isolated Dohee worker process...");
            let _ = child.kill().await;
        }
        self.active_model = None;
    }
}

pub async fn run_dohee_worker(model_path: &str) {
    let mut engine_cfg = dohee_engine::EngineConfig::default();
    engine_cfg.gpu_layers = 99; // Try full GPU offload first

    let engine = match dohee_engine::DoheeEngine::load(model_path, engine_cfg.clone()) {
        Ok(eng) => eng,
        Err(e) => {
            crate::log!("Worker: GPU model load failed: {}. Retrying with CPU-only (gpu_layers: 0)...", e);
            engine_cfg.gpu_layers = 0;
            match dohee_engine::DoheeEngine::load(model_path, engine_cfg) {
                Ok(eng) => eng,
                Err(err) => {
                    let err_msg = serde_json::json!({
                        "event": "error",
                        "data": format!("Failed to load model on both GPU and CPU: {}", err)
                    }).to_string() + "\n";
                    let mut stdout = tokio::io::stdout();
                    let _ = stdout.write_all(err_msg.as_bytes()).await;
                    let _ = stdout.flush().await;
                    return;
                }
            }
        }
    };

    let stdin = tokio::io::stdin();
    let mut reader = BufReader::new(stdin).lines();
    let mut stdout = tokio::io::stdout();

    while let Ok(Some(line)) = reader.next_line().await {
        let req: serde_json::Value = match serde_json::from_str(&line) {
            Ok(json) => json,
            Err(_) => continue,
        };

        let prompt = match req.get("prompt").and_then(|p| p.as_str()) {
            Some(p) => p.to_string(),
            None => continue,
        };

        let temp = req.get("temperature").and_then(|t| t.as_f64()).unwrap_or(0.2) as f32;
        let seed = req.get("seed").and_then(|s| s.as_u64()).unwrap_or(1234) as u32;

        let session_cfg = dohee_engine::SessionConfig {
            temperature: temp,
            seed,
            ..dohee_engine::SessionConfig::default()
        };

        if let Ok(handle) = engine.create_session(session_cfg) {
            let (event_tx, mut event_rx) = tokio::sync::mpsc::unbounded_channel();
            let _ = handle.cmd_tx.send(dohee_engine::SessionCommand::RunTurn {
                prompt,
                event_tx,
            });

            while let Some(evt) = event_rx.recv().await {
                match evt {
                    dohee_engine::AgentEvent::Token(tok) => {
                        let msg = serde_json::json!({
                            "event": "token",
                            "data": tok
                        }).to_string() + "\n";
                        let _ = stdout.write_all(msg.as_bytes()).await;
                        let _ = stdout.flush().await;
                    }
                    dohee_engine::AgentEvent::Finished { reason } => {
                        let reason_str = match reason {
                            dohee_engine::FinishReason::Stop => "Stop",
                            dohee_engine::FinishReason::Cancelled => "Cancelled",
                            dohee_engine::FinishReason::MaxTokens => "MaxTokens",
                            dohee_engine::FinishReason::Error(e) => {
                                let msg = serde_json::json!({
                                    "event": "error",
                                    "data": e
                                }).to_string() + "\n";
                                let _ = stdout.write_all(msg.as_bytes()).await;
                                let _ = stdout.flush().await;
                                "Error"
                            }
                        };
                        let msg = serde_json::json!({
                            "event": "finished",
                            "reason": reason_str
                        }).to_string() + "\n";
                        let _ = stdout.write_all(msg.as_bytes()).await;
                        let _ = stdout.flush().await;
                        break;
                    }
                    dohee_engine::AgentEvent::Error(e) => {
                        let msg = serde_json::json!({
                            "event": "error",
                            "data": e
                        }).to_string() + "\n";
                        let _ = stdout.write_all(msg.as_bytes()).await;
                        let _ = stdout.flush().await;
                        break;
                    }
                    _ => {}
                }
            }
            let _ = handle.cmd_tx.send(dohee_engine::SessionCommand::Shutdown);
        } else {
            let msg = serde_json::json!({
                "event": "error",
                "data": "Failed to create session"
            }).to_string() + "\n";
            let _ = stdout.write_all(msg.as_bytes()).await;
            let _ = stdout.flush().await;
        }
    }
}

pub async fn chat_stream_detached(
    ctx: CommandContext,
    llm_manager: Arc<Mutex<LlmManager>>,
    model: String,
    message: String,
    system_prompt: Option<String>,
    chat_id: Option<String>,
) {
    let (client, chats) = {
        let l = llm_manager.lock().await;
        (l.client.clone(), l.chats.clone())
    };

    let _ = ctx.reply(Status::Success, None).await;

    let cid = chat_id.unwrap_or_else(|| uuid::Uuid::new_v4().to_string());

    // 1. Initialize prompt and chat history
    let mut req_messages = {
        let mut c = chats.lock().await;
        let session = c.entry(cid.clone()).or_insert_with(|| ChatSession {
            id: cid.clone(),
            title: message.chars().take(30).collect::<String>(),
            messages: Vec::new(),
            updated_at: get_timestamp(),
        });

        if let Some(ref sp) = system_prompt {
            // Generate tools description dynamically from CapabilityRegistry
            let registry = crate::capabilities::registry::CapabilityRegistry::new();
            let mut tools_desc = String::new();
            let mut idx = 1;

            if let Some(cap) = registry.get("filesystem") {
                if cap.health == "healthy" {
                    tools_desc.push_str(&format!("{}. list_dir: {{\"path\": \"/path\"}}\n", idx));
                    idx += 1;
                    tools_desc.push_str(&format!("{}. read_file: {{\"path\": \"/path\"}}\n", idx));
                    idx += 1;
                    tools_desc.push_str(&format!("{}. write_file: {{\"path\": \"/path\", \"content\": \"...\"}}\n", idx));
                    idx += 1;
                }
            }

            if let Some(cap) = registry.get("system") {
                if cap.health == "healthy" {
                    tools_desc.push_str(&format!("{}. run_command: {{\"command\": \"command string\"}}\n", idx));
                }
            }

            let full_sp = format!(
                "{}\n\n[SYSTEM INSTRUCTION: Workstation Agent Skills]\nYou have access to local workstation tools. You can view directories, read/write files, and run commands. To execute a tool, use XML tags format:\n<call:tool_name>\n{{\"param\": \"value\"}}\n</call:tool_name>\n\nAvailable Tools:\n{}Follow ReAct pattern: Thought -> Action -> Observation. Output thought reasoning inside <think> tags first.",
                sp, tools_desc
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
        session.updated_at = get_timestamp();

        let msgs = session.messages.clone();
        super::store::save_chats(&c).await;
        msgs
    };

    // Check if we have an active child process
    let mut use_worker = false;
    let mut stdin_writer = None;
    let mut stdout_reader = None;

    {
        let mut l = llm_manager.lock().await;
        if let Some(ref mut child) = l.dohee_child {
            if let Some(stdin) = child.stdin.take() {
                stdin_writer = Some(stdin);
            }
            if let Some(stdout) = child.stdout.take() {
                stdout_reader = Some(BufReader::new(stdout).lines());
            }
            use_worker = true;
        }
    }

    if use_worker && stdin_writer.is_some() && stdout_reader.is_some() {
        let mut stdin = stdin_writer.unwrap();
        let mut stdout_lines = stdout_reader.unwrap();

        for turn in 0..6 {
            crate::log!("AGENT LOOP (Worker Process): Starting turn {}", turn);
            let prompt = format_chat_prompt(&req_messages);
            let cmd = serde_json::json!({
                "prompt": prompt,
                "temperature": 0.2,
                "seed": 1234
            });

            let cmd_str = cmd.to_string() + "\n";
            if let Err(e) = stdin.write_all(cmd_str.as_bytes()).await {
                crate::elog!("Failed to write to worker stdin: {}", e);
                let status_msg = format!("\n\n❌ [Host Error: Failed to write to worker process: {}]\n\n", e);
                let _ = ctx.stream(HostMessage::LlmToken {
                    token: status_msg,
                    is_final: false,
                    timestamp: get_timestamp(),
                }).await;
                break;
            }
            if let Err(e) = stdin.flush().await {
                crate::elog!("Failed to flush worker stdin: {}", e);
                let status_msg = format!("\n\n❌ [Host Error: Failed to flush worker process: {}]\n\n", e);
                let _ = ctx.stream(HostMessage::LlmToken {
                    token: status_msg,
                    is_final: false,
                    timestamp: get_timestamp(),
                }).await;
                break;
            }

            let mut assistant_content = String::new();
            let mut turn_cancelled = false;
            let mut turn_error = false;

            while let Ok(Some(line)) = stdout_lines.next_line().await {
                let event_val: serde_json::Value = match serde_json::from_str(&line) {
                    Ok(v) => v,
                    Err(_) => continue,
                };

                let event_type = event_val.get("event").and_then(|e| e.as_str()).unwrap_or("");
                match event_type {
                    "token" => {
                        if let Some(tok) = event_val.get("data").and_then(|d| d.as_str()) {
                            assistant_content.push_str(tok);
                            let msg = HostMessage::LlmToken {
                                token: tok.to_string(),
                                is_final: false,
                                timestamp: get_timestamp(),
                            };
                            let _ = ctx.stream(msg).await;
                        }
                    }
                    "finished" => {
                        let reason = event_val.get("reason").and_then(|r| r.as_str()).unwrap_or("");
                        if reason == "Cancelled" {
                            turn_cancelled = true;
                        }
                        break;
                    }
                    "error" => {
                        let err_data = event_val.get("data").and_then(|d| d.as_str()).unwrap_or("Unknown error");
                        crate::elog!("Worker reported error: {}", err_data);
                        let status_msg = format!("\n\n❌ [Dohee Engine Error: {}]\n\n", err_data);
                        let _ = ctx.stream(HostMessage::LlmToken {
                            token: status_msg,
                            is_final: false,
                            timestamp: get_timestamp(),
                        }).await;
                        turn_error = true;
                        break;
                    }
                    _ => {}
                }
            }

            if turn_cancelled || turn_error {
                break;
            }

            req_messages.push(ChatMessage {
                role: "assistant".to_string(),
                content: assistant_content.clone(),
            });

            if let Some(tool) = crate::capabilities::inference_tools::parse_tool_call(&assistant_content) {
                crate::log!("LLM (Worker Process): Extracted tool call '{}'", tool.name);

                let status_msg = format!("\n\n⚙️ [Dohee Engine: Executing tool `{}`...]\n\n", tool.name);
                let _ = ctx.stream(HostMessage::LlmToken {
                    token: status_msg,
                    is_final: false,
                    timestamp: get_timestamp(),
                }).await;

                let tool_result = crate::capabilities::inference_tools::execute_tool(
                    &tool.name,
                    &tool.args,
                    &llm_manager,
                    &ctx.rtc_conn,
                    &ctx.label,
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

                let observation_msg = format!(
                    "\n\n⚙️ [Dohee Engine: Tool `{}` observation ({}):\n```\n{}\n```]\n\n",
                    tool.name, status_icon, observation_content
                );
                let _ = ctx.stream(HostMessage::LlmToken {
                    token: observation_msg,
                    is_final: false,
                    timestamp: get_timestamp(),
                }).await;

                req_messages.push(ChatMessage {
                    role: "user".to_string(),
                    content: observation,
                });
            } else {
                crate::log!("AGENT LOOP (Worker Process): Complete (No tool calls).");
                break;
            }
        }

        // Put stdin/stdout back to child so they are kept for the next prompt run
        {
            let mut l = llm_manager.lock().await;
            if let Some(ref mut child) = l.dohee_child {
                child.stdin = Some(stdin);
                child.stdout = Some(stdout_lines.into_inner().into_inner());
            }
        }

        {
            let mut c = chats.lock().await;
            if let Some(session) = c.get_mut(&cid) {
                session.messages = req_messages;
                session.updated_at = get_timestamp();
                super::store::save_chats(&c).await;
            }
        }

        let final_msg = HostMessage::LlmToken {
            token: String::new(),
            is_final: true,
            timestamp: get_timestamp(),
        };
        let _ = ctx.stream(final_msg).await;
        return;
    }

    // Fallback to Ollama / fallback path
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
                            timestamp: get_timestamp(),
                        };
                        let _ = ctx.stream(msg).await;
                    }
                }
                Err(e) => {
                    crate::elog!("LLM ERROR: event stream error: {}", e);
                    break;
                }
            }
        }

        req_messages.push(ChatMessage {
            role: "assistant".to_string(),
            content: assistant_content.clone(),
        });

        if let Some(tool) = crate::capabilities::inference_tools::parse_tool_call(&assistant_content) {
            crate::log!("LLM: Extracted tool call '{}'", tool.name);

            let tool_result = crate::capabilities::inference_tools::execute_tool(
                &tool.name,
                &tool.args,
                &llm_manager,
                &ctx.rtc_conn,
                &ctx.label,
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

            let observation_msg = format!(
                "\n\n⚙️ [Harness: Tool `{}` observation ({}):\n```\n{}\n```]\n\n",
                tool.name, status_icon, observation_content
            );
            let _ = ctx.stream(
                HostMessage::LlmToken {
                    token: observation_msg,
                    is_final: false,
                    timestamp: get_timestamp(),
                }
            )
            .await;

            req_messages.push(ChatMessage {
                role: "user".to_string(),
                content: observation,
            });
        } else {
            crate::log!("AGENT LOOP: Complete (No tool calls).");
            break;
        }
    }

    {
        let mut c = chats.lock().await;
        if let Some(session) = c.get_mut(&cid) {
            session.messages = req_messages;
            session.updated_at = get_timestamp();
            super::store::save_chats(&c).await;
        }
    }

    let final_msg = HostMessage::LlmToken {
        token: String::new(),
        is_final: true,
        timestamp: get_timestamp(),
    };
    let _ = ctx.stream(final_msg).await;
}

fn format_chat_prompt(messages: &[ChatMessage]) -> String {
    let mut prompt = String::new();
    for msg in messages {
        match msg.role.as_str() {
            "system" => {
                prompt.push_str(&format!("<|im_start|>system\n{}<|im_end|>\n", msg.content));
            }
            "user" => {
                prompt.push_str(&format!("<|im_start|>user\n{}<|im_end|>\n", msg.content));
            }
            "assistant" => {
                prompt.push_str(&format!("<|im_start|>assistant\n{}<|im_end|>\n", msg.content));
            }
            _ => {
                prompt.push_str(&format!("<|im_start|>{}\n{}<|im_end|>\n", msg.role, msg.content));
            }
        }
    }
    prompt.push_str("<|im_start|>assistant\n");
    prompt
}
