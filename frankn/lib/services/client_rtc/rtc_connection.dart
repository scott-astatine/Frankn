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
    if (!HostConnectionStateValidation.isValidTransition(current, nextState)) {
      log(
        "[FSM] Ignored invalid state transition: $current -> $nextState ($reason)",
      );
      return;
    }

    final gen =
        client.activeAttempt?.generationId ?? client.connectionGeneration;
    final session = client.activeAttempt?.sessionUuid.substring(0, 8) ?? "none";

    final elapsed = client.activeAttempt?.elapsedMs ?? "+0ms";

    // Structured Logging
    log(
      "[LINK] [G$gen] [S:$session] [$elapsed] [State: $current -> $nextState] ($reason)",
    );

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
        _transitionTo(
          HostConnectionState.failed,
          "Timeout during connection stage: $stateName",
        );
      }
    });
  }

  /// Centralized state change side-effects handler
  void _handleStateEffects(
    HostConnectionState oldState,
    HostConnectionState newState,
  ) {
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
      final hostName = client.currentHostName ?? "Remote PC";
      if (isIntentionalDisconnect || isAuthFailed) {
        updateBackgroundService(
          title: "Frankn Active",
          text: '⚡ Neural Link Standby // Signaling Online',
        );
      } else {
        updateBackgroundService(
          title: "☁️ [RECONNECTING] // $hostName",
          text: '⚡ Connection unstable. Retrying...',
        );
      }
    }

    // Automatic reconnection logic
    if (newState == HostConnectionState.disconnected ||
        newState == HostConnectionState.failed) {
      _clearHostConnections();

      if (!isIntentionalDisconnect && !isAuthFailed && currentHostId != null) {
        firstDisconnectTime ??= DateTime.now();
        requestHostList();

        final elapsed = DateTime.now()
            .difference(firstDisconnectTime!)
            .inSeconds;
        if (elapsed < _reconnectWindowSeconds) {
          _transitionTo(
            HostConnectionState.reconnectWaiting,
            "Scheduling reconnect retry",
          );

          _reconnectTimer?.cancel();
          _reconnectTimer = Timer(const Duration(seconds: 3), () async {
            _reconnectTimer = null;
            if (currentHostId != null && !isIntentionalDisconnect) {
              if (client.sigState != SignalConnectionState.connected) {
                log(
                  "[RECONNECT] Signaling server offline. Postponing neural P2P link retry.",
                );
                _reconnectTimer = Timer(const Duration(seconds: 2), () async {
                  _reconnectTimer = null;
                  if (currentHostId != null && !isIntentionalDisconnect) {
                    if (client.onlineHostIds.contains(currentHostId)) {
                      _transitionTo(
                        HostConnectionState.connecting,
                        "Retrying connection after signaling check",
                      );
                      connectToHost(currentHostId!);
                    } else {
                      log(
                        "[RECONNECT] Host is offline after signaling check. Retrying later.",
                      );
                      _transitionTo(HostConnectionState.failed, "Host offline");
                    }
                  }
                });
              } else {
                if (client.onlineHostIds.contains(currentHostId)) {
                  _transitionTo(
                    HostConnectionState.connecting,
                    "Retrying connection",
                  );
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
          _transitionTo(
            HostConnectionState.disconnected,
            "Timeout window exceeded",
          );
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

    final client = this as RtcClient;

    final identity = client.identityManager;
    // Enforce Signaling Readiness Barrier: Do NOT create WebRTC PeerConnection or gather ICE candidates
    // until the signaling WebSocket is connected, Ed25519 identity key is loaded, and session_id is registered.
    if (client.sigState != SignalConnectionState.connected ||
        identity.sessionId == null ||
        identity.keyPair == null) {
      log(
        "Signaling layer not ready (State: ${client.sigState}, Session: ${identity.sessionId}). Awaiting registration barrier...",
      );
      if (client.sigState == SignalConnectionState.disconnected) {
        connectToSignaling();
      }
      final ready = await waitForSignalingReady(
        timeout: const Duration(seconds: 10),
      );
      if (!ready) {
        log(
          "ERROR: Signaling registration barrier timed out. Aborting connectToHost.",
        );
        _isConnectingInternal = false;
        _transitionTo(
          HostConnectionState.failed,
          "Signaling layer unavailable",
        );
        return;
      }
    }

    log("Initiating P2P to ${currentHostName ?? hostId}");

    // Generate unique session identifier and increment local connection generation
    final sessionUuid = const Uuid().v4();
    client.incrementGeneration();
    final attemptGen = client.connectionGeneration;

    try {
      // Ensure any previous connection is completely cleaned up
      await _clearHostConnections();
      final host = client.hostManager.getOrCreateHost(
        hostId,
        hostName: hostName,
      );
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

      final pc = await createPeerConnection(config);
      host.peerConnection = pc;

      // Instantiate the active attempt object cleanly (RAII pattern)
      final attempt = RtcConnectionAttempt(
        generationId: attemptGen,
        sessionUuid: sessionUuid,
        signalingSocket: client.transport.channel!,
        peerConnection: pc,
      );
      client.activeAttempt = attempt;
      host.activeAttempt = attempt;

      log(
        "[RTC] [G$attemptGen] [${attempt.elapsedMs}] PeerConnection created.",
      );

      // Create data channels in STRICT order with fixed IDs for Host compatibility
      host.genDC = await pc.createDataChannel(
        'frankn_cmd',
        RTCDataChannelInit()..id = 1,
      );
      _setupChannelHandlers(host.genDC!);

      host.sshDC = await pc.createDataChannel(
        'frankn_ssh',
        RTCDataChannelInit()..id = 2,
      );
      _setupChannelHandlers(host.sshDC!);
      host.sshDC!.onMessage = (msg) {
        if (attemptGen != client.connectionGeneration) return;
        final data = msg.isBinary ? msg.binary : utf8.encode(msg.text);
        final bytes = Uint8List.fromList(data);
        if (!_sshHandlerActive) {
          _sshEarlyBuffer.add(bytes);
        }
        sshDataController.add(bytes);
      };

      host.fsDC = await pc.createDataChannel(
        'frankn_fs',
        RTCDataChannelInit()..id = 3,
      );
      _setupChannelHandlers(host.fsDC!);

      host.mediaDC = await pc.createDataChannel(
        'frankn_media',
        RTCDataChannelInit()..id = 4,
      );
      _setupChannelHandlers(host.mediaDC!);

      host.aiDC = await pc.createDataChannel(
        'dohee_x',
        RTCDataChannelInit()..id = 5,
      );
      _setupChannelHandlers(host.aiDC!);

      host.inputDC = await pc.createDataChannel(
        'frankn_input',
        RTCDataChannelInit()..id = 6,
      );
      _setupChannelHandlers(host.inputDC!);

      // Monitor main command channel state for connection progress
      final existingGenDCHandler = host.genDC!.onDataChannelState;
      host.genDC!.onDataChannelState = (dcState) {
        if (attemptGen != client.connectionGeneration) return;
        existingGenDCHandler?.call(dcState);
        log(
          "[RTC] [G$attemptGen] [${attempt.elapsedMs}] DC State [frankn_cmd]: $dcState",
        );
        switch (dcState) {
          case RTCDataChannelState.RTCDataChannelConnecting:
            _transitionTo(
              HostConnectionState.connecting,
              "Data channel connecting",
            );
            break;
          case RTCDataChannelState.RTCDataChannelOpen:
            log(
              "[RTC] [G$attemptGen] [${attempt.elapsedMs}] P2P Uplink Established.",
            );
            firstDisconnectTime = null; // Reset reconnection timer
            _transitionTo(
              HostConnectionState.authenticating,
              "Data channel open, authenticating",
            );
            if (currentPassword != null) {
              authenticate(currentPassword!);
            }
            break;
          case RTCDataChannelState.RTCDataChannelClosed:
          case RTCDataChannelState.RTCDataChannelClosing:
            log(
              "[RTC] [G$attemptGen] [${attempt.elapsedMs}] DC [frankn_cmd] Severed.",
            );
            _transitionTo(
              HostConnectionState.disconnected,
              "Data channel closed",
            );
            break;
        }
      };

      // Monitor overall peer connection state
      pc.onConnectionState = (ps) {
        if (attemptGen != client.connectionGeneration) return;
        log("[RTC] [G$attemptGen] [${attempt.elapsedMs}] PC Connection State: $ps");
        switch (ps) {
          case RTCPeerConnectionState.RTCPeerConnectionStateConnecting:
            _transitionTo(
              HostConnectionState.iceConnecting,
              "ICE gathering and connection active",
            );
            break;
          case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
            log(
              "[RTC] [G$attemptGen] [${attempt.elapsedMs}] Transient peer connection state: $ps. Waiting for ICE recovery or failure.",
            );
            break;
          case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
          case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
            log(
              "[RTC] [G$attemptGen] [${attempt.elapsedMs}] Neural Link Severed (PC State: $ps).",
            );
            _transitionTo(
              HostConnectionState.failed,
              "Peer connection lost ($ps)",
            );
            break;
          default:
            break;
        }
      };

      pc.onIceConnectionState = (ics) {
        if (attemptGen != client.connectionGeneration) return;
        log("[RTC_DIAG] [G$attemptGen] [${attempt.elapsedMs}] ICE Connection State: $ics");
      };

      int firstCandMs = 0;
      int lastCandMs = 0;

      // PHASE 0 EXPERIMENT: Isolated ICE candidate callback (Zero logging, zero signing, zero outbox)
      pc.onIceCandidate = (candidate) {
        if (attemptGen != client.connectionGeneration) return;
        if (candidate.candidate == null) return;
        attempt.candidateCount++;
        final now = attempt.stopwatch.elapsedMilliseconds;
        if (attempt.candidateCount == 1) firstCandMs = now;
        lastCandMs = now;
      };

      pc.onIceGatheringState = (state) {
        if (attemptGen != client.connectionGeneration) return;
        log(
          "[ICE_EXP] [G$attemptGen] [${attempt.elapsedMs}] Gathering state: $state | Candidates gathered so far: ${attempt.candidateCount} (First: ${firstCandMs}ms, Last: ${lastCandMs}ms)",
        );
      };

      log("[RTC] [G$attemptGen] [${attempt.elapsedMs}] createOffer started");
      // Create and send SDP offer to initiate connection
      final offer = await pc.createOffer({
        'mandatory': {
          'OfferToReceiveAudio': false,
          'OfferToReceiveVideo': false,
        },
        'optional': [],
      });
      log("[RTC] [G$attemptGen] [${attempt.elapsedMs}] createOffer completed");

      log(
        "[RTC] [G$attemptGen] [${attempt.elapsedMs}] setLocalDescription started",
      );
      await pc.setLocalDescription(offer);
      log(
        "[RTC] [G$attemptGen] [${attempt.elapsedMs}] setLocalDescription completed",
      );

      _transitionTo(HostConnectionState.signaling, "Sending SDP Offer");
      log(
        "[SIG] [G$attemptGen] [${attempt.elapsedMs}] Enqueuing SDP Offer to signaling",
      );
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
    channel.onDataChannelState = (dcState) {
      if (attemptGen != client.connectionGeneration) return;
      log(
        "[DC_DIAG] [G$attemptGen] [${client.activeAttempt?.elapsedMs ?? '+0ms'}] DataChannel [${channel.label} (id: ${channel.id})] State: $dcState",
      );
    };
    channel.onMessage = (msg) {
      if (attemptGen != client.connectionGeneration) return;
      handleHostMessage(msg.isBinary ? msg.binary : msg.text);
    };
  }

  /// Gracefully disconnects from the host and prevents automatic reconnection.
  @override
  void disconnectFromHost() {
    isIntentionalDisconnect = true;
    _transitionTo(
      HostConnectionState.disconnected,
      "Intentional disconnect requested",
    );
  }

  /// Completely cleans up all WebRTC connections and resources.
  Future<void> _clearHostConnections() async {
    final client = this as RtcClient;

    // Invalidate session token to prevent stale transmission
    AuthService().clearToken();

    // Clean up host manager entry
    if (currentHostId != null) {
      client.hostManager.clearConnections(currentHostId!);
    }

    // Ensure active file transfer streams and maps are closed and purged
    if (this is RtcMessageHandler) {
      (this as RtcMessageHandler).clearActiveTransfers();
    }

    // Clean up all active Node capability WebRTC sessions
    await client.capabilitySessionManager.closeAllSessions();

    // Cancel any pending reconnect timer
    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    client.activeAttempt?.dispose();
    client.activeAttempt = null;

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
