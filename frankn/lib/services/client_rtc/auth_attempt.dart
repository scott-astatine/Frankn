import 'dart:async';
import 'dart:developer';
import '../auth/auth_state.dart';
import 'package:frankn_opaque/frankn_opaque.dart';
import 'package:uuid/uuid.dart';

/// Represents authentication for a single connection attempt generation.
class AuthAttempt {
  final int generationId;
  final String sessionUuid;
  final String opaqueAttemptId = const Uuid().v4();

  AuthState state = AuthState.idle;
  int? opaqueHandle;
  String? sessionCredential;

  Timer? timeoutTimer;
  bool isCancelled = false;

  AuthAttempt({required this.generationId, required this.sessionUuid});

  /// Updates internal authentication state.
  void updateState(AuthState newState) {
    if (state == newState || isCancelled) return;
    log(
      '[AUTH-ATTEMPT] [G$generationId] State: ${state.name} -> ${newState.name}',
    );
    state = newState;
  }

  /// Cancels this authentication attempt and stops timers.
  void cancel() {
    if (isCancelled) return;
    isCancelled = true;
    log('[AUTH-ATTEMPT] [G$generationId] Auth attempt cancelled.');
    timeoutTimer?.cancel();
    timeoutTimer = null;
    clearOpaqueState();
    state = AuthState.failed;
  }

  void clearOpaqueState() {
    final handle = opaqueHandle;
    opaqueHandle = null;
    if (handle != null) {
      try {
        FranknOpaqueClient().cancel(handle);
      } catch (_) {}
    }
    sessionCredential = null;
  }

  /// Disposes auth attempt resources.
  void dispose() {
    cancel();
  }
}
