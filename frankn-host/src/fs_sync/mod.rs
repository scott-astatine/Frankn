use crate::{HostMessage, utils::Status};
use std::fs;
use std::path::{Path, PathBuf};

pub mod transfer;
pub mod sync;

/// Restricts path access to a specific base directory (sandbox root)
pub fn check_sandbox(base_dir: &Path, user_path: &str, allow_parent: bool) -> Result<PathBuf, String> {
    let combined = base_dir.join(user_path);
    
    // Check if the path exists to canonicalize. If not, canonicalize its parent.
    let canonical = match combined.canonicalize() {
        Ok(p) => p,
        Err(_) => {
            // If the target path doesn't exist (e.g. for mkdir or fresh upload),
            // we canonicalize its parent directory to ensure it is in the sandbox.
            if let Some(parent) = combined.parent() {
                match parent.canonicalize() {
                    Ok(mut p) => {
                        if let Some(file_name) = combined.file_name() {
                            p.push(file_name);
                        }
                        p
                    }
                    Err(e) => return Err(format!("Parent directory does not exist or invalid: {}", e)),
                }
            } else {
                return Err("Path has no parent and does not exist".to_string());
            }
        }
    };
    
    let base_canonical = base_dir.canonicalize()
        .map_err(|e| format!("Base sandbox error: {}", e))?;
        
    if canonical.starts_with(&base_canonical) || (allow_parent && base_canonical.starts_with(&canonical)) {
        Ok(canonical)
    } else {
        Err("Access Denied: Path resides outside sandbox.".to_string())
    }
}

/// Helper that restricts paths to the user's home directory by default
pub fn check_sandbox_default(user_path: &str, allow_parent: bool) -> Result<PathBuf, String> {
    let home = dirs::home_dir().ok_or_else(|| "Home directory not found".to_string())?;
    check_sandbox(&home, user_path, allow_parent)
}

pub fn ls(id: &str, path: &str, sort_by: Option<String>, show_hidden: Option<bool>) -> HostMessage {
    let sandbox_path = match check_sandbox_default(path, true) {
        Ok(p) => p,
        Err(e) => return HostMessage::Response {
            id: id.to_string(),
            status: Status::Error(e),
            data: None,
            timestamp: crate::utils::get_timestamp(),
        },
    };

    let entries = fs::read_dir(sandbox_path);
    match entries {
        Ok(read_dir) => {
            let mut list = Vec::new();
            for entry in read_dir.filter_map(|e| e.ok()) {
                let name = entry.file_name().to_string_lossy().to_string();
                if show_hidden == Some(false) && name.starts_with('.') {
                    continue;
                }
                let metadata = fs::metadata(entry.path()).ok();
                let is_dir = metadata.as_ref().map(|m| m.is_dir()).unwrap_or(false);
                let size = metadata.as_ref().map(|m| m.len()).unwrap_or(0);

                let modified_time = metadata
                    .as_ref()
                    .and_then(|m| m.modified().ok())
                    .unwrap_or(std::time::SystemTime::UNIX_EPOCH);
                let dt: chrono::DateTime<chrono::Local> = modified_time.into();
                let modified_str = dt.format("%Y-%m-%d %H:%M:%S").to_string();
                let timestamp = dt.timestamp();

                list.push(serde_json::json!({
                    "name": name,
                    "is_dir": is_dir,
                    "size": size,
                    "modified": modified_str,
                    "timestamp": timestamp,
                }));
            }

            // Sorting logic
            let sort_by_field = sort_by.as_deref().unwrap_or("name");
            list.sort_by(|a, b| {
                let is_dir_a = a["is_dir"].as_bool().unwrap_or(false);
                let is_dir_b = b["is_dir"].as_bool().unwrap_or(false);

                // Always put directories first
                if is_dir_a && !is_dir_b {
                    return std::cmp::Ordering::Less;
                } else if !is_dir_a && is_dir_b {
                    return std::cmp::Ordering::Greater;
                }

                match sort_by_field {
                    "size" => {
                        let size_a = a["size"].as_u64().unwrap_or(0);
                        let size_b = b["size"].as_u64().unwrap_or(0);
                        size_b.cmp(&size_a) // Descending size
                    }
                    "modified" => {
                        let time_a = a["timestamp"].as_i64().unwrap_or(0);
                        let time_b = b["timestamp"].as_i64().unwrap_or(0);
                        time_b.cmp(&time_a) // Descending modified time
                    }
                    _ => {
                        // Default to name sorting
                        let name_a = a["name"].as_str().unwrap_or("").to_lowercase();
                        let name_b = b["name"].as_str().unwrap_or("").to_lowercase();
                        name_a.cmp(&name_b)
                    }
                }
            });

            HostMessage::Response {
                id: id.to_string(),
                status: Status::Success,
                data: Some(serde_json::json!({ "entries": list })),
                timestamp: crate::utils::get_timestamp(),
            }
        }
        Err(e) => HostMessage::Response {
            id: id.to_string(),
            status: Status::Error(e.to_string()),
            data: None,
            timestamp: crate::utils::get_timestamp(),
        },
    }
}

pub fn delete_file(id: &str, path: &str) -> HostMessage {
    let sandbox_path = match check_sandbox_default(path, false) {
        Ok(p) => p,
        Err(e) => return HostMessage::Response {
            id: id.to_string(),
            status: Status::Error(e),
            data: None,
            timestamp: crate::utils::get_timestamp(),
        },
    };

    match fs::remove_file(sandbox_path) {
        Ok(_) => HostMessage::Response {
            id: id.into(),
            status: Status::Success,
            data: None,
            timestamp: crate::utils::get_timestamp(),
        },
        Err(e) => HostMessage::Response {
            id: id.into(),
            status: Status::Error(e.to_string()),
            data: None,
            timestamp: crate::utils::get_timestamp(),
        },
    }
}

pub fn mkdir(id: &str, path: &str) -> HostMessage {
    let sandbox_path = match check_sandbox_default(path, false) {
        Ok(p) => p,
        Err(e) => return HostMessage::Response {
            id: id.to_string(),
            status: Status::Error(e),
            data: None,
            timestamp: crate::utils::get_timestamp(),
        },
    };

    match fs::create_dir_all(sandbox_path) {
        Ok(_) => HostMessage::Response {
            id: id.into(),
            status: Status::Success,
            data: None,
            timestamp: crate::utils::get_timestamp(),
        },
        Err(e) => HostMessage::Response {
            id: id.into(),
            status: Status::Error(e.to_string()),
            data: None,
            timestamp: crate::utils::get_timestamp(),
        },
    }
}


