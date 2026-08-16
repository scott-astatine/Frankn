/// Mixin handling WebRTC peer connection lifecycle and data channel management.
///
/// This mixin manages the complete P2P connection process including:
/// - WebRTC peer connection creation and configuration
/// - Data channel initialization with strict ordering
/// - ICE candidate exchange via signaling server
/// - Automatic reconnection with backoff logic
/// - Connection state management and cleanup
part of 'rtc.dart';

mixin RtcConnection on RtcClientBase {
  /// Maximum time window for automatic reconnection attempts (30 seconds).
  /// After this period, manual reconnection is required.
  static const int _reconnectWindowSeconds = 30;

  /// Flag to prevent concurrent connection attempts.
  /// Ensures only one connection process runs at a time.
  bool _isConnectingInternal = false;

  /// Timer for the next reconnection attempt. Stored to prevent timer stacking.
  Timer? _reconnectTimer;

  /// Buffer for SSH messages that arrive before SshController takes over the handler.
  final List<Uint8List> _sshEarlyBuffer = [];

  /// Flag indicating whether SshController has installed its own handler.
  bool _sshHandlerActive = false;

  /// Returns the early-buffered SSH messages and clears the buffer.
  /// Called by SshController when it installs its onMessage handler.
  @override
  List<Uint8List> drainSshEarlyBuffer() {
    final drained = List<Uint8List>.from(_sshEarlyBuffer);
    _sshEarlyBuffer.clear();
    _sshHandlerActive = true;
    return drained;
  }

  /// Transition reduction state machine with validation and structured logging
  @override
  void _transitionTo(HostConnectionState nextState, String reason) {
    final client = this as RtcClient;
    final current = client.currentHostState;
    if (nextState == current) return;

    // Transition validation checks
    if (current == HostConnectionState.disconnecting && nextState != HostConnectionState.disconnected) {
      log("[FSM] Ignored invalid state transition: $current -> $nextState ($reason)");
      return;
    }

    final gen = client.activeAttempt?.generationId ?? client.connectionGeneration;
    final session = client.activeAttempt?.sessionUuid.substring(0, 8) ?? "none";
    
    // Structured Logging
    log("[LINK] [Gen: $gen] [Session: $session] [State: $current -> $nextState] ($reason)");

    client.currentHostState = nextState;
    hostStateController.add(nextState);

    _handleStateEffects(current, nextState);
  }

  /// Manages state-specific escape timeouts to prevent hangs
  void _startTimeoutTimer(Duration duration, String stateName) {
    final client = this as RtcClient;
    final gen = client.connectionGeneration;
    client.activeAttempt?.timeoutTimer?.cancel();
    client.activeAttempt?.timeoutTimer = Timer(duration, () {
      if (client.connectionGeneration == gen &&
          client.currentHostState != HostConnectionState.authenticated &&
          client.currentHostState != HostConnectionState.disconnected) {
        _transitionTo(HostConnectionState.failed, "Timeout during connection stage: $stateName");
      }
    });
  }

  /// Centralized state change side-effects handler
  void _handleStateEffects(HostConnectionState oldState, HostConnectionState newState) {
    final client = this as RtcClient;

    // Timeout orchestration
    if (newState == HostConnectionState.connecting) {
      _startTimeoutTimer(ConnectionTimeouts.signaling, "connecting");
    } else if (newState == HostConnectionState.signaling) {
      _startTimeoutTimer(ConnectionTimeouts.signaling, "signaling");
    } else if (newState == HostConnectionState.iceConnecting) {
      _startTimeoutTimer(ConnectionTimeouts.ice, "iceConnecting");
    } else if (newState == HostConnectionState.authenticating) {
      _startTimeoutTimer(ConnectionTimeouts.authentication, "authenticating");
    } else if (newState == HostConnectionState.authenticated ||
               newState == HostConnectionState.disconnected ||
               newState == HostConnectionState.failed) {
      client.activeAttempt?.timeoutTimer?.cancel();
    }

    // Background Service management
    if (newState == HostConnectionState.authenticated) {
      final hostName = client.currentHostName ?? "Remote PC";
      startBackgroundService(
        title: "☁️ $hostName",
        text: '⚡ Connected to Host',
      );
    } else if (newState == HostConnectionState.connecting ||
               newState == HostConnectionState.signaling ||
               newState == HostConnectionState.iceConnecting ||
               newState == HostConnectionState.authenticating ||
               newState == HostConnectionState.reconnectWaiting) {
      if (!isIntentionalDisconnect && client.firstDisconnectTime != null) {
        final hostName = client.currentHostName ?? "Remote PC";
        updateBackgroundService(
          title: "☁️ [RECONNECTING] // $hostName",
          text: '⚡ Connection unstable. Retrying...',
        );
      }
    } else if (newState == HostConnectionState.disconnected ||
               newState == HostConnectionState.failed) {
      if (isIntentionalDisconnect || isAuthFailed) {
        stopBackgroundService();
      } else {
        final hostName = client.currentHostName ?? "Remote PC";
        updateBackgroundService(
          title: "☁️ [RECONNECTING] // $hostName",
          text: '⚡ Connection unstable. Retrying...',
        );
      }
    }

    // Automatic reconnection logic
    if (newState == HostConnectionState.disconnected || newState == HostConnectionState.failed) {
      _clearHostConnections();

      if (!isIntentionalDisconnect && !isAuthFailed && currentHostId != null) {
        firstDisconnectTime ??= DateTime.now();
        requestHostList();

        final elapsed = DateTime.now().difference(firstDisconnectTime!).inSeconds;
        if (elapsed < _reconnectWindowSeconds) {
          _transitionTo(HostConnectionState.reconnectWaiting, "Scheduling reconnect retry");
          
          _reconnectTimer?.cancel();
          _reconnectTimer = Timer(const Duration(seconds: 3), () async {
            _reconnectTimer = null;
            if (currentHostId != null && !isIntentionalDisconnect) {
              if (client.sigState != SignalConnectionState.connected) {
                log("[RECONNECT] Signaling server offline. Postponing neural P2P link retry.");
                _reconnectTimer = Timer(const Duration(seconds: 2), () async {
                  _reconnectTimer = null;
                  if (currentHostId != null && !isIntentionalDisconnect) {
                    if (client.onlineHostIds.contains(currentHostId)) {
                      _transitionTo(HostConnectionState.connecting, "Retrying connection after signaling check");
                      connectToHost(currentHostId!);
                    } else {
                      log("[RECONNECT] Host is offline after signaling check. Retrying later.");
                      _transitionTo(HostConnectionState.failed, "Host offline");
                    }
                  }
                });
              } else {
                if (client.onlineHostIds.contains(currentHostId)) {
                  _transitionTo(HostConnectionState.connecting, "Retrying connection");
                  connectToHost(currentHostId!);
                } else {
                  log("[RECONNECT] Host is offline. Retrying later.");
                  _transitionTo(HostConnectionState.failed, "Host offline");
                }
              }
            }
          });
        } else {
          log("[RECONNECT] Reconnection window exceeded. Stopping retry loop.");
          firstDisconnectTime = null;
          currentHostId = null;
          _transitionTo(HostConnectionState.disconnected, "Timeout window exceeded");
        }
      } else {
        firstDisconnectTime = null;
        if (isIntentionalDisconnect) {
          currentHostId = null;
          currentHostName = null;
        }
      }
    }
  }

  /// Initiates a WebRTC P2P connection to the specified host.
  @override
  Future<void> connectToHost(
    String hostId, {
    String? password,
    String? hostName,
  }) async {
    if (_isConnectingInternal) {
      log("UPLINK: Connection already in progress. Ignoring request.");
      return;
    }

    _isConnectingInternal = true;
    currentHostId = hostId;
    if (hostName != null) currentHostName = hostName;

    // Reset lifecycle flags for the connection attempt
    isAuthFailed = false;
    isIntentionalDisconnect = false;
    firstDisconnectTime = null;

    if (password != null) currentPassword = password;

    log("Initiating P2P to ${currentHostName ?? hostId}");

    // Generate unique session identifier and increment local connection generation
    final sessionUuid = const Uuid().v4();
    final client = this as RtcClient;
    client.incrementGeneration();
    final attemptGen = client.connectionGeneration;

    try {
      // Ensure any previous connection is completely cleaned up
      await _clearHostConnections();
      _transitionTo(HostConnectionState.connecting, "Initiating WebRTC setup");

      // WebRTC configuration with redundant STUN servers for NAT traversal
      final config = {
        'iceServers': [
          {'urls': 'stun:stun.l.google.com:19302'},
          {'urls': 'stun:stun1.l.google.com:19302'},
          {'urls': 'stun:stun2.l.google.com:19302'},
          {'urls': 'stun:stun3.l.google.com:19302'},
          {'urls': 'stun:stun4.l.google.com:19302'},
          {'urls': 'stun:stun.services.mozilla.com'},
          {'urls': 'stun:global.stun.twilio.com:3478'},
        ],
        'sdpSemantics': 'unified-plan',
        'iceCandidatePoolSize': 10,
        'iceTransportPolicy': 'all',
        'rtcpMuxPolicy': 'require',
        'bundlePolicy': 'max-bundle',
      };

      peerConnection = await createPeerConnection(config);

      // Create data channels in STRICT order with fixed IDs for Host compatibility
      genDC = await peerConnection!.createDataChannel(
        'frankn_cmd',
        RTCDataChannelInit()..id = 1,
      );
      _setupChannelHandlers(genDC!);

      sshDC = await peerConnection!.createDataChannel(
        'frankn_ssh',
        RTCDataChannelInit()..id = 2,
      );
      sshDC!.onMessage = (msg) {
        if (attemptGen != client.connectionGeneration) return;
        final data = msg.isBinary ? msg.binary : utf8.encode(msg.text);
        final bytes = Uint8List.fromList(data);
        if (!_sshHandlerActive) {
          _sshEarlyBuffer.add(bytes);
        }
        sshDataController.add(bytes);
      };

      fsDC = await peerConnection!.createDataChannel(
        'frankn_fs',
        RTCDataChannelInit()..id = 3,
      );
      _setupChannelHandlers(fsDC!);

      mediaDC = await peerConnection!.createDataChannel(
        'frankn_media',
        RTCDataChannelInit()..id = 4,
      );
      _setupChannelHandlers(mediaDC!);

      aiDC = await peerConnection!.createDataChannel(
        'dohee_x',
        RTCDataChannelInit()..id = 5,
      );
      _setupChannelHandlers(aiDC!);

      inputDC = await peerConnection!.createDataChannel(
        'frankn_input',
        RTCDataChannelInit()..id = 6,
      );
      _setupChannelHandlers(inputDC!);

      // Monitor main command channel state for connection progress
      genDC!.onDataChannelState = (dcState) {
        if (attemptGen != client.connectionGeneration) return;
        log("DC State [frankn_cmd]: $dcState");
        switch (dcState) {
          case RTCDataChannelState.RTCDataChannelConnecting:
            _transitionTo(HostConnectionState.connecting, "Data channel connecting");
            break;
          case RTCDataChannelState.RTCDataChannelOpen:
            log("P2P Uplink Established.");
            firstDisconnectTime = null; // Reset reconnection timer
            _transitionTo(HostConnectionState.authenticating, "Data channel open, authenticating");
            if (currentPassword != null) {
              authenticate(currentPassword!);
            }
            break;
          case RTCDataChannelState.RTCDataChannelClosed:
          case RTCDataChannelState.RTCDataChannelClosing:
            log("DC [frankn_cmd] Severed. Triggering UI Reset.");
            _transitionTo(HostConnectionState.disconnected, "Data channel closed");
            break;
        }
      };

      // Monitor overall peer connection state
      peerConnection!.onConnectionState = (ps) {
        if (attemptGen != client.connectionGeneration) return;
        log("PC State: $ps");
        switch (ps) {
          case RTCPeerConnectionState.RTCPeerConnectionStateConnecting:
            _transitionTo(HostConnectionState.iceConnecting, "ICE gathering and connection active");
            break;
          case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
          case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
          case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
            log("Neural Link Severed (PC State: $ps). Resetting UI.");
            _transitionTo(HostConnectionState.disconnected, "Peer connection lost");
            break;
          default:
            break;
        }
      };

      // Forward ICE candidates to signaling server for NAT traversal
      peerConnection!.onIceCandidate = (candidate) {
        if (attemptGen != client.connectionGeneration) return;
        log("ICE_GATHER: Generated local ICE candidate: ${candidate.candidate}");
        _sendDataPlaneToSignaling(SignalingMessage.IceCandidate, {
          'to': hostId,
          'candidate': candidate.candidate,
          'sdp_mid': candidate.sdpMid,
          'sdp_m_line_index': candidate.sdpMLineIndex,
        });
      };

      // Create and send SDP offer to initiate connection
      final offer = await peerConnection!.createOffer({
        'mandatory': {
          'OfferToReceiveAudio': false,
          'OfferToReceiveVideo': false,
        },
        'optional': [],
      });

      await peerConnection!.setLocalDescription(offer);

      // Ensure signaling is ready before sending offer
      int retryCount = 0;
      while (signalingChannel == null && retryCount < 10) {
        log("UPLINK: Waiting for Signaling Server... ($retryCount)");
        await Future.delayed(const Duration(milliseconds: 500));
        retryCount++;
      }

      if (signalingChannel == null) {
        throw Exception("Signaling Server offline. Handshake aborted.");
      }

      // Instantiate the active attempt object cleanly (RAII pattern)
      client.activeAttempt = RtcConnectionAttempt(
        generationId: attemptGen,
        sessionUuid: sessionUuid,
        signalingSocket: signalingChannel!,
        peerConnection: peerConnection!,
      );

      _transitionTo(HostConnectionState.signaling, "Sending SDP Offer");
      _sendDataPlaneToSignaling(SignalingMessage.Offer, {
        'to': hostId,
        'sdp': offer.sdp,
      });
    } catch (e) {
      log("CORE ERROR: Failed to initialize WebRTC stack: $e");
      isAuthFailed = false;
      _transitionTo(HostConnectionState.failed, "Initialization error: $e");
    } finally {
      _isConnectingInternal = false;
    }
  }

  void _setupChannelHandlers(RTCDataChannel channel) {
    final client = this as RtcClient;
    final attemptGen = client.connectionGeneration;
    channel.onMessage = (msg) {
      if (attemptGen != client.connectionGeneration) return;
      handleHostMessage(msg.isBinary ? msg.binary : msg.text);
    };
  }

  /// Gracefully disconnects from the host and prevents automatic reconnection.
  @override
  void disconnectFromHost() {
    isIntentionalDisconnect = true;
    _transitionTo(HostConnectionState.disconnected, "Intentional disconnect requested");
  }

  /// Completely cleans up all WebRTC connections and resources.
  Future<void> _clearHostConnections() async {
    final client = this as RtcClient;
    
    // Invalidate session token to prevent stale transmission
    AuthService().clearToken();

    // Ensure active file transfer streams and maps are closed and purged
    if (this is RtcMessageHandler) {
      (this as RtcMessageHandler).clearActiveTransfers();
    }

    // Cancel any pending reconnect timer
    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    client.activeAttempt?.dispose();
    client.activeAttempt = null;

    genDC = null;
    fsDC = null;
    mediaDC = null;
    sshDC = null;
    aiDC = null;
    inputDC = null;
    peerConnection = null;
    // Reset SSH buffering state
    _sshEarlyBuffer.clear();
    _sshHandlerActive = false;
  }

  @override
  void updateHostState(HostConnectionState newState) {
    _transitionTo(newState, "External state trigger");
  }

  @override
  void authenticate(String password);
  @override
  void handleHostMessage(dynamic rawData);
  @override
  void _sendToSignaling(String type, Map<String, dynamic> payload);
}
