#![allow(dead_code)]

use std::collections::HashMap;
use std::sync::Arc;

use argon2::{
    Argon2,
    password_hash::{PasswordHasher, SaltString, PasswordVerifier},
};
use rand::Rng;
use rand::distr::Alphanumeric;
use sha2::{Digest, Sha256};
use webrtc::util::sync::RwLock;

#[derive(Clone, Debug)]
struct Session {
    token: String,
    created_at: std::time::Instant,
}

#[derive(Clone)]
pub struct AuthManager {
    pub password_hash: String,
    pub salt: String,
    sessions: Arc<RwLock<HashMap<String, Session>>>,
}

impl AuthManager {
    pub fn new(password: &str) -> Self {
        use argon2::password_hash::rand_core::OsRng;
        let salt_obj = SaltString::generate(&mut OsRng);
        let salt = salt_obj.to_string();
        let argon2 = Argon2::default();
        let password_hash = argon2
            .hash_password(password.as_bytes(), &salt_obj)
            .expect("Failed to hash password with Argon2")
            .to_string();

        Self {
            password_hash,
            salt,
            sessions: Arc::new(RwLock::new(HashMap::new())),
        }
    }

    pub fn from_hash(hash: &str) -> Self {
        // Extract salt from the PHC string ($argon2id$v=19$m=19456,t=2,p=1$SALT$HASH)
        let salt = hash.split('$').nth(4).unwrap_or("").to_string();

        Self {
            password_hash: hash.to_string(),
            salt,
            sessions: Arc::new(RwLock::new(HashMap::new())),
        }
    }

    pub fn verify_password(plain: &str, hash: &str) -> bool {
        use argon2::password_hash::PasswordHash;
        if let Ok(parsed_hash) = PasswordHash::new(hash) {
            Argon2::default().verify_password(plain.as_bytes(), &parsed_hash).is_ok()
        } else {
            false
        }
    }

    pub fn generate_challenge(&self) -> String {
        rand::rng()
            .sample_iter(&Alphanumeric)
            .take(32)
            .map(char::from)
            .collect()
    }

    /// Verifies the challenge response.
    /// The client is expected to send: Hex(Sha256(Argon2Hash + Challenge))
    pub async fn verify_response(&self, challenge: &str, response: &str) -> Option<String> {
        let mut hasher = Sha256::new();
        hasher.update(self.password_hash.as_bytes());
        hasher.update(challenge.as_bytes());
        let expected = format!("{:x}", hasher.finalize());

        if expected == response {
            let token: String = rand::rng()
                .sample_iter(&Alphanumeric)
                .take(64)
                .map(char::from)
                .collect();

            let session = Session {
                token: token.clone(),
                created_at: std::time::Instant::now(),
            };

            self.sessions.write().insert(token.clone(), session);
            Some(token)
        } else {
            println!(
                "Auth failed: Invalid response.\nExpected: {}\nReceived: {}",
                expected, response
            );
            None
        }
    }

    pub async fn verify_token(&self, token: &str) -> bool {
        let sessions = self.sessions.read();

        if let Some(session) = sessions.get(token) {
            session.created_at.elapsed().as_secs() < 32400
        } else {
            false
        }
    }

    pub async fn revoke_token(&self, token: &str) {
        self.sessions.write().remove(token);
    }
}
