part of 'rtc.dart';

enum NodeSessionState {
  idle,
  requesting,
  pending,
  connecting,
  connected,
  failed,
  closing,
  closed,
}

/// Callback for sending signal messages back to the Host for relay to the Node.
typedef SendNodeSignalCallback = Future<void> Function({
  required String sessionId,
  required Map<String, dynamic> signal,
});

/// Represents a single, isolated Client ↔ Node capability WebRTC session.
class NodePeerSession extends ChangeNotifier {
  final String sessionId;
  final String nodeId;
  final String capabilityId;
  final SendNodeSignalCallback _sendSignal;

  NodeSessionState _state = NodeSessionState.idle;
  String? _error;

  RTCPeerConnection? _peerConnection;
  Future<RTCPeerConnection>? _peerConnectionFuture;

  MediaStreamTrack? _videoTrack;
  MediaStream? _mediaStream;
  RTCDataChannel? _dataChannel;

  bool _hasRemoteDescription = false;
  final List<RTCIceCandidate> _pendingIceCandidates = [];

  // Sequential queue for signal processing to prevent race conditions during async yields
  Future<void> _signalQueue = Future.value();

  NodeSessionState get state => _state;
  String? get error => _error;
  MediaStreamTrack? get videoTrack => _videoTrack;
  MediaStream? get mediaStream => _mediaStream;
  RTCDataChannel? get dataChannel => _dataChannel;
  bool get isConnected => _state == NodeSessionState.connected;

  NodePeerSession({
    required this.sessionId,
    required this.nodeId,
    required this.capabilityId,
    required SendNodeSignalCallback onSendSignal,
  }) : _sendSignal = onSendSignal {
    RtcThinClient().log('[NODE_SESSION] Session created: id=$sessionId, capability=$capabilityId, node=$nodeId');
  }

  void updateState(NodeSessionState newState, [String? err]) {
    if (_state == newState) return;
    RtcThinClient().log('[NODE_SESSION] State change [$sessionId]: ${_state.name} -> ${newState.name}${err != null ? " (Error: $err)" : ""}');
    _state = newState;
    if (err != null) _error = err;
    notifyListeners();
  }

  /// Handles incoming signals forwarded from the Host (`HostSignal`), serialized via a queue.
  Future<void> handleSignal(Map<String, dynamic> signal) {
    _signalQueue = _signalQueue.then((_) => _processSignal(signal)).catchError((e) {
      RtcThinClient().log('[NODE_SESSION] Signal queue error [$sessionId]: $e');
      updateState(NodeSessionState.failed, 'Signal processing error: $e');
    });
    return _signalQueue;
  }

  Future<void> _processSignal(Map<String, dynamic> signal) async {
    final type = signal['type'] as String?;
    RtcThinClient().log('[NODE_SESSION] Incoming signal [$sessionId]: type=$type');

    if (type == 'offer') {
      final sdp = signal['sdp'] as String?;
      if (sdp != null) {
        RtcThinClient().log('[NODE_SESSION] Processing SDP Offer (${sdp.length} chars) for session [$sessionId]');
        await _handleOffer(sdp);
      }
    } else if (type == 'answer') {
      final sdp = signal['sdp'] as String?;
      if (sdp != null) {
        RtcThinClient().log('[NODE_SESSION] Processing SDP Answer (${sdp.length} chars) for session [$sessionId]');
        await _handleAnswer(sdp);
      }
    } else if (type == 'ice_candidate' || signal.containsKey('candidate')) {
      final candidateStr = signal['candidate'] as String?;
      final sdpMid = signal['sdp_mid'] as String?;
      final sdpMLineIndex = signal['sdp_m_line_index'] as int?;

      if (candidateStr != null) {
        await _handleIceCandidate(candidateStr, sdpMid, sdpMLineIndex);
      }
    }
  }

  /// Ensures exactly one RTCPeerConnection is created per session using a cached Future.
  Future<RTCPeerConnection> _getPeerConnection() {
    return _peerConnectionFuture ??= _createPeerConnection();
  }

  Future<RTCPeerConnection> _createPeerConnection() async {
    RtcThinClient().log('[NODE_SESSION] Creating single RTCPeerConnection for session [$sessionId]...');

    final config = <String, dynamic>{
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
        {'urls': 'stun:stun1.l.google.com:19302'},
      ],
      'sdpSemantics': 'unified-plan',
    };

    final pc = await createPeerConnection(config);
    _peerConnection = pc;

    pc.onIceCandidate = (candidate) {
      if (candidate.candidate != null) {
        RtcThinClient().log('[NODE_SESSION] Local ICE Candidate generated [$sessionId]: mid=${candidate.sdpMid}, mline=${candidate.sdpMLineIndex}');
        _sendSignal(
          sessionId: sessionId,
          signal: {
            'type': 'ice_candidate',
            'from': '',
            'to': nodeId,
            'candidate': candidate.candidate,
            'sdp_mid': candidate.sdpMid,
            'sdp_m_line_index': candidate.sdpMLineIndex,
            'session_id': sessionId,
            'sequence': 0,
            'signature': '',
            'timestamp': DateTime.now().millisecondsSinceEpoch ~/ 1000,
          },
        );
      }
    };

    pc.onTrack = (event) async {
      RtcThinClient().log('[NODE_SESSION] Track received [$sessionId]: kind=${event.track.kind}, id=${event.track.id}, streams=${event.streams.length}');
      if (event.track.kind == 'video') {
        _videoTrack = event.track;
        if (event.streams.isNotEmpty) {
          _mediaStream = event.streams.first;
          RtcThinClient().log('[NODE_SESSION] Video MediaStream attached [$sessionId]: streamId=${_mediaStream!.id}');
        } else {
          _mediaStream = await createLocalMediaStream('remote-stream-$sessionId');
          await _mediaStream!.addTrack(_videoTrack!);
          RtcThinClient().log('[NODE_SESSION] Fallback MediaStream created with video track [$sessionId]: streamId=${_mediaStream!.id}');
        }
        notifyListeners();
      }
    };

    pc.onDataChannel = (channel) {
      RtcThinClient().log('[NODE_SESSION] DataChannel received [$sessionId]: label=${channel.label}, id=${channel.id}');
      _dataChannel = channel;
      _dataChannel!.onDataChannelState = (state) {
        RtcThinClient().log('[NODE_SESSION] DataChannel state changed [$sessionId]: state=$state');
        if (state == RTCDataChannelState.RTCDataChannelOpen) {
          notifyListeners();
        }
      };
    };

    pc.onConnectionState = (state) {
      RtcThinClient().log('[NODE_SESSION] RTCPeerConnectionState changed [$sessionId]: state=$state');
      switch (state) {
        case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
          updateState(NodeSessionState.connected);
          break;
        case RTCPeerConnectionState.RTCPeerConnectionStateConnecting:
          updateState(NodeSessionState.connecting);
          break;
        case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
          updateState(NodeSessionState.failed, 'Peer connection $state');
          break;
        case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
          RtcThinClient().log('[NODE_SESSION] Transient peer connection state [$sessionId]: $state');
          break;
        case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
          updateState(NodeSessionState.closed);
          break;
        default:
          break;
      }
    };

    return pc;
  }

  Future<void> _handleOffer(String sdp) async {
    updateState(NodeSessionState.connecting);
    final pc = await _getPeerConnection();

    RtcThinClient().log('[NODE_SESSION] Setting remote description (Offer) [$sessionId]...');
    final desc = RTCSessionDescription(sdp, 'offer');
    await pc.setRemoteDescription(desc);

    RtcThinClient().log('[NODE_SESSION] Creating SDP Answer [$sessionId]...');
    final answer = await pc.createAnswer();

    RtcThinClient().log('[NODE_SESSION] Setting local description (Answer) [$sessionId]...');
    await pc.setLocalDescription(answer);
    _hasRemoteDescription = true;

    RtcThinClient().log('[NODE_SESSION] Sending SDP Answer to Node via Host relay [$sessionId]...');
    await _sendSignal(
      sessionId: sessionId,
      signal: {
        'type': 'answer',
        'from': '',
        'to': nodeId,
        'sdp': answer.sdp,
        'session_id': sessionId,
        'sequence': 0,
        'signature': '',
        'timestamp': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      },
    );

    // Flush any remote ICE candidates that arrived before local description/answer was completed!
    if (_pendingIceCandidates.isNotEmpty) {
      RtcThinClient().log('[NODE_SESSION] Flushing ${_pendingIceCandidates.length} buffered remote ICE candidates [$sessionId]...');
      for (final candidate in _pendingIceCandidates) {
        try {
          await pc.addCandidate(candidate);
        } catch (e) {
          RtcThinClient().log('[NODE_SESSION] Error adding buffered ICE candidate [$sessionId]: $e');
        }
      }
      _pendingIceCandidates.clear();
    }
  }

  Future<void> _handleAnswer(String sdp) async {
    final pc = await _getPeerConnection();
    RtcThinClient().log('[NODE_SESSION] Setting remote description (Answer) [$sessionId]...');
    final desc = RTCSessionDescription(sdp, 'answer');
    await pc.setRemoteDescription(desc);
    _hasRemoteDescription = true;

    if (_pendingIceCandidates.isNotEmpty) {
      RtcThinClient().log('[NODE_SESSION] Flushing ${_pendingIceCandidates.length} buffered remote ICE candidates [$sessionId]...');
      for (final candidate in _pendingIceCandidates) {
        try {
          await pc.addCandidate(candidate);
        } catch (e) {
          RtcThinClient().log('[NODE_SESSION] Error adding buffered ICE candidate [$sessionId]: $e');
        }
      }
      _pendingIceCandidates.clear();
    }
  }

  Future<void> _handleIceCandidate(
    String candidate,
    String? sdpMid,
    int? sdpMLineIndex,
  ) async {
    final pc = await _getPeerConnection();
    final iceCandidate = RTCIceCandidate(candidate, sdpMid, sdpMLineIndex);

    if (!_hasRemoteDescription) {
      RtcThinClient().log('[NODE_SESSION] Buffering remote ICE Candidate [$sessionId] (remote description not set yet)');
      _pendingIceCandidates.add(iceCandidate);
      return;
    }

    RtcThinClient().log('[NODE_SESSION] Adding remote ICE Candidate [$sessionId]: mid=$sdpMid, mline=$sdpMLineIndex');
    try {
      await pc.addCandidate(iceCandidate);
    } catch (e) {
      RtcThinClient().log('[NODE_SESSION] Error adding remote ICE candidate [$sessionId]: $e');
    }
  }

  /// Disposes this specific capability session without affecting other sessions or Host link.
  @override
  Future<void> dispose() async {
    if (_state == NodeSessionState.closing || _state == NodeSessionState.closed) {
      return;
    }
    RtcThinClient().log('[NODE_SESSION] Disposing session [$sessionId]...');
    updateState(NodeSessionState.closing);

    try {
      await _dataChannel?.close();
      await _peerConnection?.close();
    } catch (_) {}

    _dataChannel = null;
    _peerConnection = null;
    _peerConnectionFuture = null;
    _videoTrack = null;
    _mediaStream = null;

    updateState(NodeSessionState.closed);
    super.dispose();
  }
}
