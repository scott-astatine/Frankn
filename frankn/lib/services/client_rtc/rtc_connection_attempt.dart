import 'dart:async';
import 'dart:developer';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'auth_attempt.dart';

/// Centralized connection phase timeouts
class ConnectionTimeouts {
  static const Duration signaling = Duration(seconds: 20);
  static const Duration ice = Duration(seconds: 30);
  static const Duration authentication = Duration(seconds: 10);
}

/// Standalone, lifecycle-guarded resource manager for a single physical connection handshake attempt.
class RtcConnectionAttempt {
  final int generationId;
  final String sessionUuid;
  String? hostSessionId;

  final WebSocketChannel signalingSocket;
  final RTCPeerConnection peerConnection;
  late final AuthAttempt authAttempt;

  Timer? timeoutTimer;
  final Stopwatch stopwatch = Stopwatch()..start();
  int candidateCount = 0;

  bool _isDisposed = false;
  bool get isDisposed => _isDisposed;

  RtcConnectionAttempt({
    required this.generationId,
    required this.sessionUuid,
    required this.signalingSocket,
    required this.peerConnection,
  }) {
    authAttempt = AuthAttempt(
      generationId: generationId,
      sessionUuid: sessionUuid,
    );
  }

  /// High-precision relative millisecond timing getter (e.g. `+184ms`).
  String get elapsedMs => '+${stopwatch.elapsedMilliseconds}ms';

  /// Cancels this attempt and invalidates pending timeouts.
  void cancel() {
    if (_isDisposed) return;
    _isDisposed = true;
    log('[ATTEMPT] [G$generationId] [S:$sessionUuid] Attempt cancelled.');
    timeoutTimer?.cancel();
    timeoutTimer = null;
  }

  /// Cleans up attempt resources and detaches peer connection listeners.
  void dispose() {
    if (_isDisposed) return;
    cancel();
    stopwatch.stop();
    authAttempt.dispose();

    peerConnection.onConnectionState = null;
    peerConnection.onIceCandidate = null;
    peerConnection.onIceConnectionState = null;
    peerConnection.onSignalingState = null;

    try {
      peerConnection.dispose();
    } catch (_) {}
  }
}
