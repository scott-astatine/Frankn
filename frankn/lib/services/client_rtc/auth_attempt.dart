import 'dart:async';
import 'dart:developer';
import '../auth/auth_credentials.dart';
import '../auth/auth_state.dart';

/// Represents authentication for a single connection attempt generation.
class AuthAttempt {
  final int generationId;
  final String sessionUuid;

  AuthState state = AuthState.idle;
  AuthChallenge? challenge;
  AuthResponse? response;

  Timer? timeoutTimer;
  bool isCancelled = false;

  AuthAttempt({
    required this.generationId,
    required this.sessionUuid,
  });

  /// Updates internal authentication state.
  void updateState(AuthState newState) {
    if (state == newState || isCancelled) return;
    log('[AUTH-ATTEMPT] [G$generationId] State: ${state.name} -> ${newState.name}');
    state = newState;
  }

  /// Cancels this authentication attempt and stops timers.
  void cancel() {
    if (isCancelled) return;
    isCancelled = true;
    log('[AUTH-ATTEMPT] [G$generationId] Auth attempt cancelled.');
    timeoutTimer?.cancel();
    timeoutTimer = null;
    state = AuthState.failed;
  }

  /// Disposes auth attempt resources.
  void dispose() {
    cancel();
  }
}
