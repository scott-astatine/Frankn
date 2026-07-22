use std::sync::Arc;
use tokio::sync::Mutex;
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
            crate::log!("Initializing in-process Dohee Engine for {}", model_path);
            let engine_cfg = dohee_engine::EngineConfig::default();

            let engine = dohee_engine::DoheeEngine::load(model_path, engine_cfg)
                .map_err(|e| format!("Failed to create Dohee engine: {}", e))?;
            self.engine = Some(Arc::new(engine));
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
        crate::log!("Stopping active LLM model/engine");
        self.engine = None;
        self.active_model = None;
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

    let engine_opt = {
        let l = llm_manager.lock().await;
        l.engine.clone()
    };

    if let Some(engine) = engine_opt {
        crate::log!("Running turn via in-process Dohee Engine");
        if let Ok(handle) = engine.create_session(dohee_engine::SessionConfig::default()) {
            let (event_tx, mut event_rx) = tokio::sync::mpsc::unbounded_channel();
            let _ = handle.cmd_tx.send(dohee_engine::SessionCommand::RunTurn {
                prompt: message.clone(),
                event_tx,
            });

            let mut assistant_content = String::new();
            while let Some(evt) = event_rx.recv().await {
                match evt {
                    dohee_engine::AgentEvent::Token(tok) => {
                        assistant_content.push_str(&tok);
                        let msg = HostMessage::LlmToken {
                            token: tok,
                            is_final: false,
                            timestamp: get_timestamp(),
                        };
                        let _ = ctx.stream(msg).await;
                    }
                    dohee_engine::AgentEvent::ToolRequest { call_id: _, tool, args } => {
                        crate::log!("AGENT LOOP (In-Process): Tool call requested: {}", tool);
                        let status_msg = format!("\n\n⚙️ [Dohee Engine: Executing tool `{}`...]\n\n", tool);
                        let _ = ctx.stream(
                            HostMessage::LlmToken {
                                token: status_msg,
                                is_final: false,
                                timestamp: get_timestamp(),
                            }
                        ).await;

                        let args_str = args.to_string();
                        let tool_result = crate::capabilities::inference_tools::execute_tool(
                            &tool,
                            &args_str,
                            &llm_manager,
                            &ctx.rtc_conn,
                            &ctx.label,
                        ).await;

                        let observation_content = match tool_result {
                            Ok(out) => out,
                            Err(err) => err,
                        };

                        let observation_msg = format!(
                            "\n\n⚙️ [Dohee Engine: Tool `{}` result:\n```\n{}\n```]\n\n",
                            tool, observation_content
                        );
                        let _ = ctx.stream(
                            HostMessage::LlmToken {
                                token: observation_msg,
                                is_final: false,
                                timestamp: get_timestamp(),
                            }
                        ).await;
                    }
                    dohee_engine::AgentEvent::Finished { .. } => {
                        break;
                    }
                    _ => {}
                }
            }

            {
                let mut c = chats.lock().await;
                if let Some(session) = c.get_mut(&cid) {
                    session.messages.push(ChatMessage {
                        role: "assistant".to_string(),
                        content: assistant_content,
                    });
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
    }

    // Ollama / fallback path
    let mut req_messages = {
        let mut c = chats.lock().await;
        let session = c.entry(cid.clone()).or_insert_with(|| ChatSession {
            id: cid.clone(),
            title: message.chars().take(30).collect::<String>(),
            messages: Vec::new(),
            updated_at: get_timestamp(),
        });

        if let Some(sp) = system_prompt {
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
