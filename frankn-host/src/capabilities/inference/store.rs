use super::{ChatSession, LlmManager};
use std::collections::HashMap;
use std::path::PathBuf;

pub async fn get_chats_path() -> PathBuf {
    let mut path = dirs::home_dir().unwrap_or_default();
    path.push(".config/frankn/chats.json");
    path
}

pub async fn save_chats(chats: &HashMap<String, ChatSession>) {
    let path = get_chats_path().await;
    if let Ok(data) = serde_json::to_string_pretty(chats) {
        let _ = tokio::fs::write(&path, data).await;
    }
}

impl LlmManager {
    pub async fn ensure_chats_loaded(&mut self) {
        if self.chats_loaded {
            return;
        }
        let path = get_chats_path().await;
        if let Ok(data) = tokio::fs::read_to_string(&path).await
            && let Ok(loaded) = serde_json::from_str::<HashMap<String, ChatSession>>(&data)
        {
            let mut c = self.chats.lock().await;
            *c = loaded;
        }
        self.chats_loaded = true;
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
        c.get(chat_id)
            .map(|s| serde_json::to_value(s).unwrap_or(serde_json::Value::Null))
    }

    pub async fn delete_chat(&mut self, chat_id: &str) -> bool {
        self.ensure_chats_loaded().await;
        let mut c = self.chats.lock().await;
        let removed = c.remove(chat_id).is_some();
        if removed {
            save_chats(&c).await;
        }
        removed
    }
}
