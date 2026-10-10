use base64::{Engine, engine::general_purpose::URL_SAFE_NO_PAD};
use hkdf::Hkdf;
use opaque_ke::{
    CipherSuite, ClientLogin, ClientLoginFinishParameters, ClientRegistration,
    ClientRegistrationFinishParameters, CredentialFinalization, CredentialRequest,
    CredentialResponse, Identifiers, Ristretto255, ServerLogin, ServerLoginParameters,
    ServerRegistration, ServerSetup, TripleDh,
};
use rand::rngs::OsRng;
use serde::{Deserialize, Serialize};
use sha2::{Sha256, Sha512};
use std::{
    collections::HashMap,
    ffi::{CStr, CString, c_char},
    sync::{
        Mutex, OnceLock,
        atomic::{AtomicU64, Ordering},
    },
};
use zeroize::Zeroizing;

const OPAQUE_USER_ID: &[u8] = b"frankn-host-passcode-v1";
const CONTEXT_LABEL: &[u8] = b"FRANKN-OPAQUE-LOGIN-V1\0";
const TOKEN_SALT: &[u8] = b"FRANKN-OPAQUE-SESSION-CREDENTIAL-V1";

struct FranknCipherSuite;
impl CipherSuite for FranknCipherSuite {
    type OprfCs = Ristretto255;
    type KeyExchange = TripleDh<Ristretto255, Sha512>;
    type Ksf = opaque_ke::argon2::Argon2<'static>;
}

/// Versioned Host-side OPAQUE server setup and password file.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OpaqueEnrollment {
    pub version: u8,
    pub server_setup: String,
    pub password_file: String,
}

pub struct PendingServerLogin(ServerLogin<FranknCipherSuite>);

pub struct PendingClientLogin {
    state: ClientLogin<FranknCipherSuite>,
    password: Zeroizing<Vec<u8>>,
    context: Vec<u8>,
}

fn context(client_id: &str, host_id: &str) -> Result<Vec<u8>, String> {
    if client_id.is_empty() || host_id.is_empty() || client_id.len() > 256 || host_id.len() > 256 {
        return Err("Invalid OPAQUE identity".into());
    }
    let mut ctx = Vec::with_capacity(CONTEXT_LABEL.len() + client_id.len() + host_id.len() + 8);
    ctx.extend_from_slice(CONTEXT_LABEL);
    for value in [client_id.as_bytes(), host_id.as_bytes()] {
        let len = u32::try_from(value.len()).map_err(|_| "Invalid OPAQUE identity")?;
        ctx.extend_from_slice(&len.to_be_bytes());
        ctx.extend_from_slice(value);
    }
    Ok(ctx)
}

fn identifiers() -> Identifiers<'static> {
    Identifiers {
        client: Some(OPAQUE_USER_ID),
        server: None,
    }
}

fn session_credential(session_key: &[u8], ctx: &[u8]) -> Result<String, String> {
    let hkdf = Hkdf::<Sha256>::new(Some(TOKEN_SALT), session_key);
    let mut token = Zeroizing::new([0u8; 32]);
    hkdf.expand(ctx, &mut token[..])
        .map_err(|_| "Session credential derivation failed")?;
    Ok(URL_SAFE_NO_PAD.encode(&token[..]))
}

pub fn enroll(password: &[u8]) -> Result<OpaqueEnrollment, String> {
    if password.is_empty() || password.len() > 1024 {
        return Err("Passcode length is invalid".into());
    }
    let mut rng = OsRng;
    let setup = ServerSetup::<FranknCipherSuite>::new(&mut rng);
    let client_start = ClientRegistration::<FranknCipherSuite>::start(&mut rng, password)
        .map_err(|_| "OPAQUE enrollment failed")?;
    let server_start = ServerRegistration::<FranknCipherSuite>::start(
        &setup,
        client_start.message,
        OPAQUE_USER_ID,
    )
    .map_err(|_| "OPAQUE enrollment failed")?;
    let client_finish = client_start
        .state
        .finish(
            &mut rng,
            password,
            server_start.message,
            ClientRegistrationFinishParameters::new(identifiers(), None),
        )
        .map_err(|_| "OPAQUE enrollment failed")?;
    let password_file = ServerRegistration::<FranknCipherSuite>::finish(client_finish.message);
    Ok(OpaqueEnrollment {
        version: 1,
        server_setup: URL_SAFE_NO_PAD.encode(setup.serialize()),
        password_file: URL_SAFE_NO_PAD.encode(password_file.serialize()),
    })
}

pub fn server_login_start(
    enrollment: &OpaqueEnrollment,
    client_id: &str,
    host_id: &str,
    request: &[u8],
) -> Result<(PendingServerLogin, Vec<u8>), String> {
    if enrollment.version != 1 {
        return Err("Unsupported OPAQUE credential version".into());
    }
    let setup_bytes = URL_SAFE_NO_PAD
        .decode(&enrollment.server_setup)
        .map_err(|_| "Invalid OPAQUE Host setup")?;
    let file_bytes = URL_SAFE_NO_PAD
        .decode(&enrollment.password_file)
        .map_err(|_| "Invalid OPAQUE credential file")?;
    let setup = ServerSetup::<FranknCipherSuite>::deserialize(&setup_bytes)
        .map_err(|_| "Invalid OPAQUE Host setup")?;
    let password_file = ServerRegistration::<FranknCipherSuite>::deserialize(&file_bytes)
        .map_err(|_| "Invalid OPAQUE credential file")?;
    let request = CredentialRequest::<FranknCipherSuite>::deserialize(request)
        .map_err(|_| "Invalid OPAQUE login request")?;
    let ctx = context(client_id, host_id)?;
    let mut rng = OsRng;
    let started = ServerLogin::start(
        &mut rng,
        &setup,
        Some(password_file),
        request,
        OPAQUE_USER_ID,
        ServerLoginParameters {
            context: Some(&ctx),
            identifiers: identifiers(),
        },
    )
    .map_err(|_| "Authentication failed")?;
    Ok((
        PendingServerLogin(started.state),
        started.message.serialize().to_vec(),
    ))
}

pub fn server_login_finish(
    pending: PendingServerLogin,
    client_id: &str,
    host_id: &str,
    finalization: &[u8],
) -> Result<String, String> {
    let ctx = context(client_id, host_id)?;
    let finalization = CredentialFinalization::<FranknCipherSuite>::deserialize(finalization)
        .map_err(|_| "Authentication failed")?;
    let result = pending
        .0
        .finish(
            finalization,
            ServerLoginParameters {
                context: Some(&ctx),
                identifiers: identifiers(),
            },
        )
        .map_err(|_| "Authentication failed")?;
    session_credential(&result.session_key, &ctx)
}

/// Verifies a passcode against a stored enrollment by running a complete local
/// client/server exchange. No reusable verifier or passcode is retained.
pub fn verify_password_locally(
    enrollment: &OpaqueEnrollment,
    password: &[u8],
    host_id: &str,
) -> bool {
    let local_client_id = "frankn-local-passcode-check";
    let Ok((client_state, request)) = client_login_start(password, local_client_id, host_id) else {
        return false;
    };
    let Ok((server_state, response)) =
        server_login_start(enrollment, local_client_id, host_id, &request)
    else {
        return false;
    };
    let Ok((finalization, client_credential)) = client_login_finish(client_state, &response) else {
        return false;
    };
    let Ok(server_credential) =
        server_login_finish(server_state, local_client_id, host_id, &finalization)
    else {
        return false;
    };
    client_credential == server_credential
}

pub fn client_login_start(
    password: &[u8],
    client_id: &str,
    host_id: &str,
) -> Result<(PendingClientLogin, Vec<u8>), String> {
    if password.is_empty() || password.len() > 1024 {
        return Err("Passcode length is invalid".into());
    }
    let ctx = context(client_id, host_id)?;
    let mut rng = OsRng;
    let started = ClientLogin::<FranknCipherSuite>::start(&mut rng, password)
        .map_err(|_| "Authentication failed")?;
    Ok((
        PendingClientLogin {
            state: started.state,
            password: Zeroizing::new(password.to_vec()),
            context: ctx,
        },
        started.message.serialize().to_vec(),
    ))
}

pub fn client_login_finish(
    pending: PendingClientLogin,
    response: &[u8],
) -> Result<(Vec<u8>, String), String> {
    let response = CredentialResponse::<FranknCipherSuite>::deserialize(response)
        .map_err(|_| "Authentication failed")?;
    let mut rng = OsRng;
    let result = pending
        .state
        .finish(
            &mut rng,
            &pending.password,
            response,
            ClientLoginFinishParameters::new(Some(&pending.context), identifiers(), None),
        )
        .map_err(|_| "Authentication failed")?;
    let finalization = result.message.serialize().to_vec();
    let credential = session_credential(&result.session_key, &pending.context)?;
    Ok((finalization, credential))
}

// Small C ABI for Dart FFI. Handles refer to one in-flight attempt and are
// consumed on finish/cancel. All input pointers are copied before returning.
static NEXT_HANDLE: AtomicU64 = AtomicU64::new(1);
static CLIENT_ATTEMPTS: OnceLock<Mutex<HashMap<u64, (PendingClientLogin, std::time::Instant)>>> =
    OnceLock::new();
fn attempts() -> &'static Mutex<HashMap<u64, (PendingClientLogin, std::time::Instant)>> {
    CLIENT_ATTEMPTS.get_or_init(|| Mutex::new(HashMap::new()))
}

unsafe fn read_bytes<'a>(ptr: *const u8, len: usize) -> Result<&'a [u8], String> {
    if ptr.is_null() && len != 0 {
        return Err("Invalid FFI buffer".into());
    }
    if len > 16 * 1024 {
        return Err("FFI buffer exceeds limit".into());
    }
    Ok(if len == 0 {
        &[]
    } else {
        unsafe { std::slice::from_raw_parts(ptr, len) }
    })
}

unsafe fn read_string(ptr: *const c_char) -> Result<String, String> {
    if ptr.is_null() {
        return Err("Invalid FFI string".into());
    }
    unsafe { CStr::from_ptr(ptr) }
        .to_str()
        .map(str::to_owned)
        .map_err(|_| "Invalid FFI string".into())
}

fn ffi_result(value: Result<serde_json::Value, String>) -> *mut c_char {
    let json = match value {
        Ok(value) => value,
        Err(_) => serde_json::json!({ "error": "Authentication failed" }),
    };
    CString::new(json.to_string()).map_or(std::ptr::null_mut(), CString::into_raw)
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn frankn_opaque_client_start(
    password: *const u8,
    password_len: usize,
    client_id: *const c_char,
    host_id: *const c_char,
) -> *mut c_char {
    let result = (|| {
        let password = unsafe { read_bytes(password, password_len)? };
        let client_id = unsafe { read_string(client_id)? };
        let host_id = unsafe { read_string(host_id)? };
        let (pending, request) = client_login_start(password, &client_id, &host_id)?;
        let handle = NEXT_HANDLE.fetch_add(1, Ordering::Relaxed);
        let mut attempts = attempts().lock().map_err(|_| "Authentication failed")?;
        attempts.retain(|_, (_, started)| started.elapsed() < std::time::Duration::from_secs(60));
        if attempts.len() >= 16 {
            return Err("Too many OPAQUE login attempts".into());
        }
        attempts.insert(handle, (pending, std::time::Instant::now()));
        Ok(serde_json::json!({ "handle": handle, "request": URL_SAFE_NO_PAD.encode(request) }))
    })();
    ffi_result(result)
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn frankn_opaque_client_finish(
    handle: u64,
    response: *const u8,
    response_len: usize,
) -> *mut c_char {
    let result = (|| {
        let response = unsafe { read_bytes(response, response_len)? };
        let (pending, started) = attempts()
            .lock()
            .map_err(|_| "Authentication failed")?
            .remove(&handle)
            .ok_or("Authentication failed")?;
        if started.elapsed() >= std::time::Duration::from_secs(60) {
            return Err("Authentication failed".into());
        }
        let (finalization, credential) = client_login_finish(pending, response)?;
        Ok(serde_json::json!({
            "finalization": URL_SAFE_NO_PAD.encode(finalization),
            "credential": credential
        }))
    })();
    ffi_result(result)
}

#[unsafe(no_mangle)]
pub extern "C" fn frankn_opaque_client_cancel(handle: u64) {
    if let Ok(mut attempts) = attempts().lock() {
        attempts.remove(&handle);
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn frankn_opaque_string_free(value: *mut c_char) {
    if !value.is_null() {
        unsafe { drop(CString::from_raw(value)) };
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rfc9807_client_and_server_complete_identity_bound_login() {
        let enrollment = enroll(b"sample passcode").unwrap();
        let (client_state, request) =
            client_login_start(b"sample passcode", "client-a", "host-a").unwrap();
        let (server_state, response) =
            server_login_start(&enrollment, "client-a", "host-a", &request).unwrap();
        let (finalization, client_credential) =
            client_login_finish(client_state, &response).unwrap();
        let server_credential =
            server_login_finish(server_state, "client-a", "host-a", &finalization).unwrap();
        assert_eq!(client_credential, server_credential);
    }

    #[test]
    fn wrong_password_or_different_peer_identity_fails_login() {
        let enrollment = enroll(b"sample passcode").unwrap();
        let (client_state, request) =
            client_login_start(b"wrong passcode", "client-a", "host-a").unwrap();
        let (server_state, response) =
            server_login_start(&enrollment, "client-a", "host-a", &request).unwrap();
        assert!(client_login_finish(client_state, &response).is_err());
        drop(server_state);

        let (client_state, request) =
            client_login_start(b"sample passcode", "client-a", "host-a").unwrap();
        let (server_state, response) =
            server_login_start(&enrollment, "client-b", "host-a", &request).unwrap();
        assert!(client_login_finish(client_state, &response).is_err());
        drop(server_state);

        let (client_state, request) =
            client_login_start(b"sample passcode", "client-a", "host-a").unwrap();
        let (server_state, response) =
            server_login_start(&enrollment, "client-a", "host-b", &request).unwrap();
        assert!(client_login_finish(client_state, &response).is_err());
        drop(server_state);
    }

    #[test]
    fn finalization_cannot_be_replayed_into_a_fresh_server_exchange() {
        let enrollment = enroll(b"sample passcode").unwrap();
        let (client_state, request) =
            client_login_start(b"sample passcode", "client-a", "host-a").unwrap();
        let (server_state, response) =
            server_login_start(&enrollment, "client-a", "host-a", &request).unwrap();
        let (finalization, _) = client_login_finish(client_state, &response).unwrap();
        assert!(server_login_finish(server_state, "client-a", "host-a", &finalization).is_ok());

        let (replay_state, _) =
            server_login_start(&enrollment, "client-a", "host-a", &request).unwrap();
        assert!(server_login_finish(replay_state, "client-a", "host-a", &finalization).is_err());
    }

    #[test]
    fn local_passcode_check_uses_the_opaque_enrollment() {
        let enrollment = enroll(b"sample passcode").unwrap();
        assert!(verify_password_locally(
            &enrollment,
            b"sample passcode",
            "host-a"
        ));
        assert!(!verify_password_locally(
            &enrollment,
            b"wrong passcode",
            "host-a"
        ));
    }
}
