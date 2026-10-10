use std::collections::HashMap;
use std::sync::Arc;

use argon2::{Argon2, password_hash::PasswordHasher};
use frankn_opaque::{OpaqueEnrollment, PendingServerLogin};
use sha2::{Digest, Sha256};
use tokio::sync::Mutex;
use webrtc::util::sync::RwLock;

#[derive(Clone, Debug)]
struct Session {
    token: String,
    created_at: std::time::Instant,
}

struct PendingLogin {
    state: PendingServerLogin,
    client_id: String,
    host_id: String,
    owner_scope: String,
    created_at: std::time::Instant,
}

#[derive(Clone)]
pub struct AuthManager {
    pub opaque_enrollment: Option<OpaqueEnrollment>,
    sessions: Arc<RwLock<HashMap<String, Session>>>,
    pending_logins: Arc<Mutex<HashMap<String, PendingLogin>>>,
}

impl AuthManager {
    /// Creates a fresh RFC 9807 OPAQUE record without retaining a reusable verifier.
    pub fn new(password: &str) -> Result<Self, String> {
        let opaque_enrollment = Some(frankn_opaque::enroll(password.as_bytes())?);
        Ok(Self {
            opaque_enrollment,
            sessions: Arc::new(RwLock::new(HashMap::new())),
            pending_logins: Arc::new(Mutex::new(HashMap::new())),
        })
    }

    pub fn from_config(opaque_enrollment: Option<OpaqueEnrollment>) -> Self {
        Self {
            opaque_enrollment,
            sessions: Arc::new(RwLock::new(HashMap::new())),
            pending_logins: Arc::new(Mutex::new(HashMap::new())),
        }
    }

    pub fn verify_password(plain: &str, stored_sha256_hash: &str, salt_str: &str) -> bool {
        use argon2::password_hash::SaltString;
        use subtle::ConstantTimeEq;

        let salt_obj = match SaltString::from_b64(salt_str) {
            Ok(s) => s,
            Err(_) => return false,
        };
        let argon2_hash = match Argon2::default().hash_password(plain.as_bytes(), &salt_obj) {
            Ok(h) => h.to_string(),
            Err(_) => return false,
        };
        let computed_sha256 = format!("{:x}", Sha256::digest(argon2_hash.as_bytes()));
        stored_sha256_hash.len() == computed_sha256.len()
            && stored_sha256_hash
                .as_bytes()
                .ct_eq(computed_sha256.as_bytes())
                .unwrap_u8()
                == 1
    }

    pub async fn begin_opaque_login(
        &self,
        owner_scope: &str,
        attempt_id: &str,
        client_id: &str,
        host_id: &str,
        request: &[u8],
    ) -> Result<Vec<u8>, String> {
        if attempt_id.is_empty() || attempt_id.len() > 128 || owner_scope.is_empty() {
            return Err("Authentication failed".into());
        }
        let enrollment = self
            .opaque_enrollment
            .as_ref()
            .ok_or_else(|| "Host OPAQUE migration is required".to_string())?;
        let (state, response) =
            frankn_opaque::server_login_start(enrollment, client_id, host_id, request)?;
        let mut pending = self.pending_logins.lock().await;
        pending.retain(|_, login| login.created_at.elapsed() < std::time::Duration::from_secs(30));
        if pending.contains_key(attempt_id) || pending.len() >= 128 {
            return Err("Authentication temporarily unavailable".into());
        }
        let created_at = std::time::Instant::now();
        pending.insert(
            attempt_id.to_string(),
            PendingLogin {
                state,
                client_id: client_id.to_string(),
                host_id: host_id.to_string(),
                owner_scope: owner_scope.to_string(),
                created_at,
            },
        );
        drop(pending);
        let pending_logins = Arc::clone(&self.pending_logins);
        let attempt_id = attempt_id.to_string();
        tokio::spawn(async move {
            tokio::time::sleep(std::time::Duration::from_secs(30)).await;
            let mut pending = pending_logins.lock().await;
            if pending
                .get(&attempt_id)
                .is_some_and(|login| login.created_at == created_at)
            {
                pending.remove(&attempt_id);
            }
        });
        Ok(response)
    }

    pub async fn finish_opaque_login(
        &self,
        owner_scope: &str,
        attempt_id: &str,
        client_id: &str,
        host_id: &str,
        finalization: &[u8],
    ) -> Result<String, String> {
        let pending = self
            .pending_logins
            .lock()
            .await
            .remove(attempt_id)
            .ok_or_else(|| "Authentication failed".to_string())?;
        if pending.created_at.elapsed() >= std::time::Duration::from_secs(30)
            || pending.owner_scope != owner_scope
            || pending.client_id != client_id
            || pending.host_id != host_id
        {
            return Err("Authentication failed".into());
        }
        let token =
            frankn_opaque::server_login_finish(pending.state, client_id, host_id, finalization)?;
        self.sessions.write().insert(
            token.clone(),
            Session {
                token: token.clone(),
                created_at: std::time::Instant::now(),
            },
        );
        Ok(token)
    }

    pub async fn cancel_opaque_logins_for_scope(&self, owner_scope: &str) {
        self.pending_logins
            .lock()
            .await
            .retain(|_, login| login.owner_scope != owner_scope);
    }

    pub async fn verify_token(&self, token: &str) -> bool {
        let sessions = self.sessions.read();
        sessions.get(token).is_some_and(|session| {
            session.created_at.elapsed().as_secs() < 32400 && session.token == token
        })
    }

    pub async fn revoke_token(&self, token: &str) {
        self.sessions.write().remove(token);
    }
}
