#![allow(dead_code)]

use std::collections::HashMap;
use std::sync::Arc;

use argon2::{
    Argon2,
    password_hash::{PasswordHasher, SaltString},
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
        let argon2_hash = argon2
            .hash_password(password.as_bytes(), &salt_obj)
            .expect("Failed to hash password with Argon2")
            .to_string();

        let mut hasher = Sha256::new();
        hasher.update(argon2_hash.as_bytes());
        let password_hash = format!("{:x}", hasher.finalize());

        Self {
            password_hash,
            salt,
            sessions: Arc::new(RwLock::new(HashMap::new())),
        }
    }

    pub fn from_hash(hash: &str, salt: &str) -> Self {
        Self {
            password_hash: hash.to_string(),
            salt: salt.to_string(),
            sessions: Arc::new(RwLock::new(HashMap::new())),
        }
    }

    pub fn verify_password(plain: &str, stored_sha256_hash: &str, salt_str: &str) -> bool {
        use argon2::password_hash::SaltString;
        use subtle::ConstantTimeEq;

        let salt_obj = match SaltString::from_b64(salt_str) {
            Ok(s) => s,
            Err(_) => return false,
        };

        let argon2 = Argon2::default();
        let argon2_hash = match argon2.hash_password(plain.as_bytes(), &salt_obj) {
            Ok(h) => h.to_string(),
            Err(_) => return false,
        };

        let mut hasher = Sha256::new();
        hasher.update(argon2_hash.as_bytes());
        let computed_sha256 = format!("{:x}", hasher.finalize());

        let expected_bytes = stored_sha256_hash.as_bytes();
        let computed_bytes = computed_sha256.as_bytes();

        expected_bytes.len() == computed_bytes.len()
            && expected_bytes.ct_eq(computed_bytes).unwrap_u8() == 1
    }

    pub fn generate_challenge(&self) -> String {
        rand::rng()
            .sample_iter(&Alphanumeric)
            .take(32)
            .map(char::from)
            .collect()
    }

    /// Verifies the challenge response.
    /// The client is expected to send: Argon2Hash
    pub async fn verify_response(&self, _challenge: &str, response: &str) -> Option<String> {
        use subtle::ConstantTimeEq;

        let mut hasher = Sha256::new();
        hasher.update(response.as_bytes());
        let hashed_response = format!("{:x}", hasher.finalize());

        let expected_bytes = self.password_hash.as_bytes();
        let response_bytes = hashed_response.as_bytes();

        if expected_bytes.len() == response_bytes.len()
            && expected_bytes.ct_eq(response_bytes).unwrap_u8() == 1
        {
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
            println!("Auth failed: Invalid credentials.");
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
