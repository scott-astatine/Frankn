import 'dart:async';
import 'dart:developer';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:frankn/utils/utils.dart';
import 'package:frankn/services/client_rtc/rtc_connection_attempt.dart';

/// Represents exactly one remote host instance and encapsulates its WebRTC connection lifecycle.
class RtcHost {
  final String hostId;
  String hostName;

  HostConnectionState _state = HostConnectionState.disconnected;
  int _connectionGeneration = 0;
  RtcConnectionAttempt? activeAttempt;

  RTCPeerConnection? peerConnection;
  RTCDataChannel? genDC;
  RTCDataChannel? sshDC;
  RTCDataChannel? fsDC;
  RTCDataChannel? mediaDC;
  RTCDataChannel? aiDC;
  RTCDataChannel? inputDC;

  final StreamController<HostConnectionState> _stateController =
      StreamController<HostConnectionState>.broadcast();

  RtcHost({
    required this.hostId,
    required this.hostName,
  });

  /// Current connection state of this host.
  HostConnectionState get state => _state;

  /// Stream of connection state changes for this host.
  Stream<HostConnectionState> get stateStream => _stateController.stream;

  /// Monotonically increasing connection attempt generation counter.
  int get connectionGeneration => _connectionGeneration;

  /// Increments attempt generation and returns the new generation ID.
  int nextGeneration() {
    _connectionGeneration++;
    return _connectionGeneration;
  }

  /// Updates connection state and notifies listeners.
  void updateState(HostConnectionState newState, String reason) {
    if (_state == newState) return;
    log('[HOST:$hostId] [G$_connectionGeneration] State: ${_state.name} -> ${newState.name} ($reason)');
    _state = newState;
    _stateController.add(newState);
  }

  /// Cleans up data channels and peer connection for this host.
  Future<void> clearConnections() async {
    activeAttempt?.dispose();
    activeAttempt = null;

    try {
      await genDC?.close();
      await sshDC?.close();
      await fsDC?.close();
      await mediaDC?.close();
      await aiDC?.close();
      await inputDC?.close();
    } catch (_) {}

    genDC = null;
    sshDC = null;
    fsDC = null;
    mediaDC = null;
    aiDC = null;
    inputDC = null;

    try {
      await peerConnection?.close();
      await peerConnection?.dispose();
    } catch (_) {}
    peerConnection = null;
  }

  void dispose() {
    clearConnections();
    _stateController.close();
  }
}
