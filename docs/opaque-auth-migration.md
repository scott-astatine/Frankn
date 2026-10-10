# OPAQUE Authentication Integration

## Implementation boundary

Use RFC 9807 OPAQUE through the maintained Rust `opaque-ke` implementation. Put the client and server protocol operations in a transport independent Rust auth core. The Host calls its server API; Flutter calls the same core through native FFI. Do not implement OPAQUE from primitives in Dart, use the older CFRG draft binding, or fall back to the current replayable verifier protocol.

Expose typed operations and serialized OPAQUE messages from the auth core. WebRTC only carries those messages; it does not own the authentication state machine. Bind the OPAQUE client and server identifiers to the Frankn client peer ID and Host peer ID so a proof for one Host or client cannot be replayed for another.

## Enrollment and credential storage

For a new Host, local setup derives the OPAQUE registration record from the passcode before the Host begins accepting clients. Store the serialized `ServerSetup` secret and `ServerRegistration` record in the Host config with restrictive file permissions. New and migrated configs clear the legacy Argon2 verifier fields. Flutter holds the entered passcode only for the active in-memory reconnect flow; it does not store or transmit a reusable verifier.

The current Host config has only a one-way legacy verifier, which cannot be converted into an OPAQUE record. Add an explicit local migration command. It prompts for the existing passcode, verifies it against that verifier, creates the OPAQUE setup and registration record locally, then atomically saves the new versioned auth config. Preserve `host_id`, `allowed_clients`, and all pairing state. If verification or saving fails, keep the prior config intact. A migrated Host rejects legacy auth messages; there is no automatic downgrade. Existing paired clients keep their IDs and ACL entries but need a client build with the OPAQUE binding.

## Login transcript and session establishment

The client sends an OPAQUE credential request with a fresh attempt ID. The Host returns the OPAQUE credential response with the same ID. The client finishes using the entered passcode and sends OPAQUE credential finalization. The Host accepts the peer only after the library verifies the finalization; the client accepts the Host only after it verifies the server confirmation and checks the attempt ID. On success, both sides derive the same short lived application session credential from OPAQUE's session key using a versioned HKDF context. The credential is never sent as part of the login transcript. The Host grants the authenticated role only after OPAQUE completes.

Reject malformed, repeated, mismatched, timed out, or failed exchanges with one generic authentication failure. Clear per-attempt OPAQUE state on completion, failure, timeout, or peer disconnect. Do not create an authenticated session, pair a private Host ACL entry, or dispatch any capability operation on partial success.

## Platform packaging and validation

The repository now includes a Flutter FFI package backed by the shared Rust core. Android builds `libfrankn_opaque.so` with `cargo-ndk`; iOS creates a device/simulator XCFramework during CocoaPods preparation. A mobile release build requires the Android NDK plus `cargo-ndk`, or Xcode plus the Apple Rust targets. The current Linux development environment cannot verify those native platform builds. Rust transcript tests cover valid login, wrong passcode, client/Host identity mismatch, and replay into a fresh server exchange. The client and Host must ship together because legacy `auth_request`/`auth_response` is rejected with an update-required error.
