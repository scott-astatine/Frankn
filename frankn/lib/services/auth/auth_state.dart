/// Explicit states for the host authentication lifecycle.
enum AuthState {
  idle,
  awaitingChallenge,
  derivingCredential,
  sendingResponse,
  authenticated,
  failed,
}
