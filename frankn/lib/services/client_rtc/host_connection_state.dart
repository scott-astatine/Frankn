import 'dart:developer';

/// Explicit states for the host WebRTC connection lifecycle.
enum HostConnectionState {
  disconnected, // Default state
  reconnectWaiting, // Backoff timer active
  connecting, // Initializing WebRTC setup
  signaling, // WebSocket SDP Offer enqueued / waiting for SDP Answer
  iceConnecting, // WebRTC SDP Answer received, ICE candidate exchange active
  connected, // Legacy compatibility placeholder
  authenticating, // Command DataChannel OPEN, Argon2id challenge active
  authenticated, // Host AuthSuccess received, session token acquired
  failed, // Connection or authentication failed
  disconnecting, // User termination active
}

/// Transition validation logic for [HostConnectionState].
class HostConnectionStateValidation {
  static const Map<HostConnectionState, Set<HostConnectionState>> _validTransitions = {
    HostConnectionState.disconnected: {
      HostConnectionState.connecting,
      HostConnectionState.reconnectWaiting,
    },
    HostConnectionState.reconnectWaiting: {
      HostConnectionState.connecting,
      HostConnectionState.disconnected,
    },
    HostConnectionState.connecting: {
      HostConnectionState.signaling,
      HostConnectionState.failed,
      HostConnectionState.disconnected,
    },
    HostConnectionState.signaling: {
      HostConnectionState.iceConnecting,
      HostConnectionState.failed,
      HostConnectionState.disconnected,
    },
    HostConnectionState.iceConnecting: {
      HostConnectionState.authenticating,
      HostConnectionState.connecting,
      HostConnectionState.failed,
      HostConnectionState.disconnected,
    },
    HostConnectionState.authenticating: {
      HostConnectionState.authenticated,
      HostConnectionState.failed,
      HostConnectionState.disconnected,
    },
    HostConnectionState.authenticated: {
      HostConnectionState.disconnecting,
      HostConnectionState.disconnected,
      HostConnectionState.failed,
    },
    HostConnectionState.failed: {
      HostConnectionState.reconnectWaiting,
      HostConnectionState.disconnected,
      HostConnectionState.connecting,
    },
    HostConnectionState.disconnecting: {
      HostConnectionState.disconnected,
    },
  };

  /// Returns true if transitioning from [current] to [next] is legal.
  static bool isValidTransition(HostConnectionState current, HostConnectionState next) {
    if (current == next) return true;
    final allowed = _validTransitions[current];
    final isAllowed = allowed != null && allowed.contains(next);
    if (!isAllowed) {
      log('[FSM WARNING] Illegal state transition attempted: ${current.name} -> ${next.name}');
    }
    return isAllowed;
  }
}
