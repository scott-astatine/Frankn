use crate::utils::Status;
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::OnceLock;

pub mod sync;
pub mod transfer;

pub static SANDBOX_HOME: OnceLock<bool> = OnceLock::new();

/// Restricts path access to a specific base directory (sandbox root)
pub fn check_sandbox(
    base_dir: &Path,
    user_path: &str,
    allow_parent: bool,
) -> Result<PathBuf, String> {
    let combined = base_dir.join(user_path);

    // Check if the path exists to canonicalize. If not, find the first existing ancestor.
    let canonical = match combined.canonicalize() {
        Ok(p) => p,
        Err(_) => {
            // Find the first parent directory that actually exists on the filesystem
            let mut ancestor = combined.clone();
            while let Some(parent) = ancestor.parent() {
                if parent.exists() {
                    ancestor = parent.to_path_buf();
                    break;
                }
                ancestor = parent.to_path_buf();
            }
            match ancestor.canonicalize() {
                Ok(mut p) => {
                    // Re-append the non-existent relative parts to reconstruct the target path
                    if let Ok(rel) = combined.strip_prefix(&ancestor) {
                        p.push(rel);
                    }
                    p
                }
                Err(e) => return Err(format!("Existing ancestor directory invalid: {}", e)),
            }
        }
    };

    let base_canonical = base_dir
        .canonicalize()
        .map_err(|e| format!("Base sandbox error: {}", e))?;

    if canonical.starts_with(&base_canonical)
        || (allow_parent && base_canonical.starts_with(&canonical))
    {
        Ok(canonical)
    } else {
        Err("Access Denied: Path resides outside sandbox.".to_string())
    }
}

/// Helper that restricts paths to the user's home directory by default
pub fn check_sandbox_default(user_path: &str, allow_parent: bool) -> Result<PathBuf, String> {
    let is_sandboxed = *SANDBOX_HOME.get().unwrap_or(&false);
    if is_sandboxed {
        let home = dirs::home_dir().ok_or_else(|| "Home directory not found".to_string())?;
        check_sandbox(&home, user_path, allow_parent)
    } else {
        let path = if user_path.starts_with('~') {
            let home = dirs::home_dir().ok_or_else(|| "Home directory not found".to_string())?;
            if user_path.len() > 1
                && (user_path.chars().nth(1) == Some('/')
                    || user_path.chars().nth(1) == Some(std::path::MAIN_SEPARATOR))
            {
                home.join(&user_path[2..])
            } else if user_path.len() > 1 {
                home.join(&user_path[1..])
            } else {
                home
            }
        } else {
            PathBuf::from(user_path)
        };
        match path.canonicalize() {
            Ok(p) => Ok(p),
            Err(_) => Ok(path),
        }
    }
}

use crate::transport::context::CommandContext;

pub async fn ls(
    ctx: &CommandContext,
    path: &str,
    sort_by: Option<String>,
    show_hidden: Option<bool>,
) {
    let sandbox_path = match check_sandbox_default(path, true) {
        Ok(p) => p,
        Err(e) => {
            let _ = ctx.reply(Status::Error(e), None).await;
            return;
        }
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

            let _ = ctx
                .reply(
                    Status::Success,
                    Some(serde_json::json!({ "entries": list })),
                )
                .await;
        }
        Err(e) => {
            let _ = ctx.reply(Status::Error(e.to_string()), None).await;
        }
    }
}

pub async fn delete_file(ctx: &CommandContext, path: &str) {
    let sandbox_path = match check_sandbox_default(path, false) {
        Ok(p) => p,
        Err(e) => {
            let _ = ctx.reply(Status::Error(e), None).await;
            return;
        }
    };

    match fs::remove_file(sandbox_path) {
        Ok(_) => {
            let _ = ctx.reply(Status::Success, None).await;
        }
        Err(e) => {
            let _ = ctx.reply(Status::Error(e.to_string()), None).await;
        }
    }
}

pub async fn mkdir(ctx: &CommandContext, path: &str) {
    let sandbox_path = match check_sandbox_default(path, false) {
        Ok(p) => p,
        Err(e) => {
            let _ = ctx.reply(Status::Error(e), None).await;
            return;
        }
    };

    match fs::create_dir_all(sandbox_path) {
        Ok(_) => {
            let _ = ctx.reply(Status::Success, None).await;
        }
        Err(e) => {
            let _ = ctx.reply(Status::Error(e.to_string()), None).await;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::check_sandbox;
    use std::fs;
    use std::path::PathBuf;

    fn test_root(name: &str) -> PathBuf {
        std::env::temp_dir().join(format!("frankn-host-{name}-{}", uuid::Uuid::new_v4()))
    }

    #[test]
    fn sandbox_allows_a_missing_path_below_the_root() {
        let root = test_root("sandbox-allows");
        let sandbox = root.join("sandbox");
        fs::create_dir_all(&sandbox).unwrap();

        let resolved = check_sandbox(&sandbox, "new/nested/file.txt", false).unwrap();

        assert_eq!(
            resolved,
            sandbox.canonicalize().unwrap().join("new/nested/file.txt")
        );
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn sandbox_rejects_parent_traversal() {
        let root = test_root("sandbox-traversal");
        let sandbox = root.join("sandbox");
        let outside = root.join("outside");
        fs::create_dir_all(&sandbox).unwrap();
        fs::create_dir_all(&outside).unwrap();

        assert!(check_sandbox(&sandbox, "../outside", false).is_err());
        fs::remove_dir_all(root).unwrap();
    }

    #[cfg(unix)]
    #[test]
    fn sandbox_rejects_a_symlink_that_escapes_the_root() {
        use std::os::unix::fs::symlink;

        let root = test_root("sandbox-symlink");
        let sandbox = root.join("sandbox");
        let outside = root.join("outside");
        fs::create_dir_all(&sandbox).unwrap();
        fs::create_dir_all(&outside).unwrap();
        fs::write(outside.join("secret.txt"), "secret").unwrap();
        symlink(&outside, sandbox.join("escape")).unwrap();

        assert!(check_sandbox(&sandbox, "escape/secret.txt", false).is_err());
        fs::remove_dir_all(root).unwrap();
    }
}
