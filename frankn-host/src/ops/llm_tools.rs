use crate::HostMessage;
use crate::ops::llm::LlmManager;
use crate::ops::rtc::RTCConn;
use serde_json::Value;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use tokio::process::Command;
use tokio::sync::Mutex;
use tokio_tungstenite::tungstenite::Bytes;

pub struct ToolCall {
    pub name: String,
    pub args: String,
}

pub fn parse_tool_call(content: &str) -> Option<ToolCall> {
    if let Some(start_idx) = content.find("<call:") {
        let name_start = start_idx + 6;
        if let Some(name_end) = content[name_start..].find('>') {
            let name = content[name_start..name_start + name_end]
                .trim()
                .to_string();
            let close_tag = format!("</call:{}>", name);
            if let Some(close_idx) = content.find(&close_tag) {
                let args = content[name_start + name_end + 1..close_idx]
                    .trim()
                    .to_string();
                return Some(ToolCall { name, args });
            }
        }
    }
    None
}

fn get_sandbox_root() -> Result<PathBuf, String> {
    dirs::home_dir().ok_or_else(|| "Could not determine home directory".to_string())
}

fn check_sandbox(path: &Path) -> Result<PathBuf, String> {
    let absolute_path = if path.is_absolute() {
        path.to_path_buf()
    } else {
        let home = get_sandbox_root()?;
        home.join(path)
    };

    // If the path exists, canonicalize it to resolve symlinks
    let resolved = if absolute_path.exists() {
        absolute_path
            .canonicalize()
            .map_err(|e| format!("Failed to resolve path: {}", e))?
    } else {
        // If it doesn't exist, canonicalize the first existing ancestor
        let mut ancestor = absolute_path.as_path();
        while let Some(parent) = ancestor.parent() {
            if parent.exists() {
                let canonical_parent = parent
                    .canonicalize()
                    .map_err(|e| format!("Failed to resolve parent: {}", e))?;
                let relative = absolute_path
                    .strip_prefix(parent)
                    .map_err(|_| "Failed to resolve relative path".to_string())?;
                return Ok(canonical_parent.join(relative));
            }
            ancestor = parent;
        }
        absolute_path
    };

    let is_sandboxed = *crate::fs_sync::SANDBOX_HOME.get().unwrap_or(&false);
    if is_sandboxed {
        let sandbox_root = get_sandbox_root()?
            .canonicalize()
            .map_err(|e| format!("Sandbox root resolution failed: {}", e))?;
        if resolved.starts_with(&sandbox_root) {
            Ok(resolved)
        } else {
            Err(format!(
                "Access Denied: Path {} is outside the allowed sandbox ({})",
                path.display(),
                sandbox_root.display()
            ))
        }
    } else {
        Ok(resolved)
    }
}

fn write_audit_log(tool: &str, args: &str, approved: bool, status: &str) {
    if let Some(mut path) = dirs::home_dir() {
        path.push(".config/frankn/agent_audit.log");
        if let Some(parent) = path.parent() {
            let _ = std::fs::create_dir_all(parent);
        }

        let log_entry = serde_json::json!({
            "timestamp": chrono::Utc::now().to_rfc3339(),
            "tool": tool,
            "args": args,
            "approved": approved,
            "status": status,
        });

        if let Ok(mut file) = std::fs::OpenOptions::new()
            .create(true)
            .append(true)
            .open(&path)
        {
            use std::io::Write;
            let _ = writeln!(file, "{}", log_entry.to_string());
        }
    }
}

pub async fn execute_tool(
    name: &str,
    args_str: &str,
    llm_manager: &Arc<Mutex<LlmManager>>,
    rtc_conn: &Arc<Mutex<RTCConn>>,
    label: &str,
) -> Result<String, String> {
    let args: Value =
        serde_json::from_str(args_str).map_err(|e| format!("Invalid JSON arguments: {}", e))?;

    // Determine if the action requires safety approval (mutating actions: write_file, run_command)
    let approved = if name == "write_file" || name == "run_command" {
        // Generate a unique approval ID
        let approval_id = uuid::Uuid::new_v4().to_string();
        let (tx, rx) = tokio::sync::oneshot::channel();

        // Register oneshot sender
        {
            let mut l = llm_manager.lock().await;
            l.approval_registry.insert(approval_id.clone(), tx);
        }

        // Send tool_approval_request to the client
        let msg = HostMessage::ToolApprovalRequest {
            approval_id: approval_id.clone(),
            tool: name.to_string(),
            args: args_str.to_string(),
            timestamp: crate::utils::get_timestamp(),
        };

        // Send message over WebRTC
        if let Ok(json) = serde_json::to_string(&msg) {
            let conn = rtc_conn.lock().await;
            let _ = conn.send_message(label, &Bytes::from(json)).await;
        }

        // Await user decision
        crate::log!(
            "AGENT LOOP: Awaiting user approval for tool `{}` (ID: {})",
            name,
            approval_id
        );
        let user_choice = rx.await.unwrap_or(false);

        if !user_choice {
            write_audit_log(name, args_str, false, "Denied by Operator");
            return Err("Execution Denied by Operator".to_string());
        }

        true
    } else {
        // Read-only tools do not require approval
        true
    };

    let result = match name {
        "list_dir" => {
            let path_str = args["path"].as_str().unwrap_or(".");
            let path = check_sandbox(Path::new(path_str))?;

            let mut entries = tokio::fs::read_dir(&path)
                .await
                .map_err(|e| format!("Failed to read directory: {}", e))?;

            let mut result = Vec::new();
            while let Ok(Some(entry)) = entries.next_entry().await {
                let file_name = entry.file_name().to_string_lossy().to_string();
                let file_type = entry
                    .file_type()
                    .await
                    .map(|t| if t.is_dir() { "dir" } else { "file" })
                    .unwrap_or("unknown");
                result.push(format!("{} [{}]", file_name, file_type));
            }
            Ok(result.join("\n"))
        }
        "read_file" => {
            let path_str = args["path"]
                .as_str()
                .ok_or_else(|| "Missing 'path' parameter".to_string())?;
            let path = check_sandbox(Path::new(path_str))?;

            let content = tokio::fs::read_to_string(&path)
                .await
                .map_err(|e| format!("Failed to read file: {}", e))?;
            Ok(content)
        }
        "write_file" => {
            let path_str = args["path"]
                .as_str()
                .ok_or_else(|| "Missing 'path' parameter".to_string())?;
            let content = args["content"]
                .as_str()
                .ok_or_else(|| "Missing 'content' parameter".to_string())?;
            let path = check_sandbox(Path::new(path_str))?;

            // Ensure parent directory exists
            if let Some(parent) = path.parent() {
                tokio::fs::create_dir_all(parent)
                    .await
                    .map_err(|e| format!("Failed to create directories: {}", e))?;
            }

            tokio::fs::write(&path, content)
                .await
                .map_err(|e| format!("Failed to write file: {}", e))?;
            Ok(format!("Successfully wrote file: {}", path_str))
        }
        "run_command" => {
            let command_str = args["command"]
                .as_str()
                .ok_or_else(|| "Missing 'command' parameter".to_string())?;

            crate::log!("Agent running workstation command: {}", command_str);

            #[cfg(target_os = "windows")]
            let mut cmd = Command::new("powershell");
            #[cfg(target_os = "windows")]
            cmd.args(["-Command", command_str]);

            #[cfg(not(target_os = "windows"))]
            let mut cmd = Command::new("sh");
            #[cfg(not(target_os = "windows"))]
            cmd.args(["-c", command_str]);

            let output = cmd
                .output()
                .await
                .map_err(|e| format!("Failed to run command: {}", e))?;

            let stdout = String::from_utf8_lossy(&output.stdout).to_string();
            let stderr = String::from_utf8_lossy(&output.stderr).to_string();

            if output.status.success() {
                Ok(stdout)
            } else {
                Err(format!(
                    "Exit Code {}. Stderr: {}",
                    output.status.code().unwrap_or(-1),
                    stderr
                ))
            }
        }
        _ => Err(format!("Unknown tool: {}", name)),
    };

    // Log the result in the audit file
    match &result {
        Ok(out) => {
            let status = if out.len() > 100 {
                format!("Success ({} bytes)", out.len())
            } else {
                format!("Success: {}", out)
            };
            write_audit_log(name, args_str, approved, &status);
        }
        Err(err) => {
            write_audit_log(name, args_str, approved, &format!("Failed: {}", err));
        }
    }

    result
}
