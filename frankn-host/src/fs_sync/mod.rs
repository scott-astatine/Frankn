use crate::{HostMessage, utils::Status};
use std::fs;

pub mod transfer;
pub mod sync;

pub fn ls(id: &str, path: &str, sort_by: Option<String>, show_hidden: Option<bool>) -> HostMessage {
    let entries = fs::read_dir(path);
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
                timestamp: 0,
            }
        }
        Err(e) => HostMessage::Response {
            id: id.to_string(),
            status: Status::Error(e.to_string()),
            data: None,
            timestamp: 0,
        },
    }
}

pub fn delete_file(id: &str, path: &str) -> HostMessage {
    match fs::remove_file(path) {
        Ok(_) => HostMessage::Response {
            id: id.into(),
            status: Status::Success,
            data: None,
            timestamp: 0,
        },
        Err(e) => HostMessage::Response {
            id: id.into(),
            status: Status::Error(e.to_string()),
            data: None,
            timestamp: 0,
        },
    }
}

pub fn mkdir(id: &str, path: &str) -> HostMessage {
    match fs::create_dir_all(path) {
        Ok(_) => HostMessage::Response {
            id: id.into(),
            status: Status::Success,
            data: None,
            timestamp: 0,
        },
        Err(e) => HostMessage::Response {
            id: id.into(),
            status: Status::Error(e.to_string()),
            data: None,
            timestamp: 0,
        },
    }
}


