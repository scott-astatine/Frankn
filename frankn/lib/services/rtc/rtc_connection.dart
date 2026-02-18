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

  /// Initiates a WebRTC P2P connection to the specified host.
  ///
  /// This method handles the complete connection establishment process:
  /// 1. Parameter validation and state initialization
  /// 2. Cleanup of previous connections
  /// 3. WebRTC peer connection creation with STUN servers
  /// 4. Data channel creation in strict order (prevents m-line conflicts)
  /// 5. Event handler setup for messages and state changes
  /// 6. SDP offer creation and signaling via WebSocket
  ///
  /// The connection process is asynchronous and updates state throughout.
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
    isAuthFailed = false;
    isIntentionalDisconnect = false;
    if (password != null) currentPassword = password;

    log("Initiating P2P to ${currentHostName ?? hostId}");

    try {
      // Ensure any previous connection is completely cleaned up
      await _clearHostConnections();

      // WebRTC configuration with redundant STUN servers for NAT traversal
      // Consistent with frankn-host/src/sys/rtc.rs for optimal compatibility
      final config = {
        'iceServers': [
          // Google STUN servers (primary - most reliable)
          {'urls': 'stun:stun.l.google.com:19302'},
          {'urls': 'stun:stun1.l.google.com:19302'},
          {'urls': 'stun:stun2.l.google.com:19302'},
          {'urls': 'stun:stun3.l.google.com:19302'},
          {'urls': 'stun:stun4.l.google.com:19302'},

          // Mozilla STUN (independent provider for redundancy)
          {'urls': 'stun:stun.services.mozilla.com'},

          // Twilio STUN (enterprise-grade reliability)
          {'urls': 'stun:global.stun.twilio.com:3478'},
        ],
        'sdpSemantics': 'unified-plan',
        'iceCandidatePoolSize':
            10, // Pre-gather candidates for faster connection
        'iceTransportPolicy': 'all', // Allow both relay and direct connections
        'rtcpMuxPolicy': 'require', // Multiplex RTP/RTCP for efficiency
        'bundlePolicy': 'max-bundle', // Bundle media streams when possible
      };

      peerConnection = await createPeerConnection(config);

      // Create data channels in STRICT order to avoid SDP m-line conflicts
      // Channel IDs must match the order expected by the host
      genDC = await peerConnection!.createDataChannel(
        'frankn_cmd',
        RTCDataChannelInit()..id = 1,
      );
      sshDC = await peerConnection!.createDataChannel(
        'frankn_ssh',
        RTCDataChannelInit()..id = 2,
      );
      fsDC = await peerConnection!.createDataChannel(
        'frankn_fs',
        RTCDataChannelInit()..id = 3,
      );
      mediaDC = await peerConnection!.createDataChannel(
        'frankn_media',
        RTCDataChannelInit()..id = 4,
      );

      // Set up message handlers for incoming data from host
      genDC!.onMessage = (msg) =>
          handleHostMessage(msg.isBinary ? msg.binary : msg.text);
      fsDC!.onMessage = (msg) =>
          handleHostMessage(msg.isBinary ? msg.binary : msg.text);
      mediaDC!.onMessage = (msg) =>
          handleHostMessage(msg.isBinary ? msg.binary : msg.text);

      // Monitor data channel state for connection progress
      genDC!.onDataChannelState = (dcState) {
        log("DC State [frankn_cmd]: $dcState");
        switch (dcState) {
          case RTCDataChannelState.RTCDataChannelConnecting:
            updateHostState(HostConnectionState.connecting);
            break;
          case RTCDataChannelState.RTCDataChannelOpen:
            log("P2P Uplink Established.");
            firstDisconnectTime = null; // Reset reconnection timer
            updateHostState(HostConnectionState.connected);
            // Auto-authenticate if password was provided
            if (currentPassword != null) {
              authenticate(currentPassword!);
            }
            break;
          case RTCDataChannelState.RTCDataChannelClosed:
          case RTCDataChannelState.RTCDataChannelClosing:
            log("DC [frankn_cmd] Severed. Triggering UI Reset.");
            updateHostState(HostConnectionState.disconnected);
            break;
          default:
            break;
        }
      };

      // Monitor overall peer connection state
      peerConnection!.onConnectionState = (ps) {
        log("PC State: $ps");
        switch (ps) {
          case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
          case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
          case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
            log("Neural Link Severed (PC State). Resetting UI.");
            updateHostState(HostConnectionState.disconnected);
            break;
          default:
            break;
        }
      };

      // Forward ICE candidates to signaling server for NAT traversal
      peerConnection!.onIceCandidate = (candidate) {
        _sendToSignaling(SinalingMessage.IceCandidate, {
          'to': hostId,
          'candidate': candidate.candidate,
          'sdp_mid': candidate.sdpMid,
          'sdp_mline_index': candidate.sdpMLineIndex,
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
      _sendToSignaling(SinalingMessage.Offer, {'to': hostId, 'sdp': offer.sdp});
    } catch (e) {
      log("CORE ERROR: Failed to initialize WebRTC stack: $e");
      updateHostState(HostConnectionState.failed);
    } finally {
      _isConnectingInternal = false;
    }
  }

  /// Updates the host connection state with automatic reconnection logic.
  ///
  /// This method handles state transitions and implements the reconnection policy:
  /// - Connected: Resets timers and flags
  /// - Disconnected/Failed: Attempts auto-reconnection within 30-second window
  /// - After timeout: Requires manual reconnection
  ///
  /// Prevents redundant state updates and manages cleanup on disconnection.
  @override
  void updateHostState(HostConnectionState newState) {
    final client = this as RtcClient;

    // Avoid redundant state transitions
    if (newState == currentHostState) return;

    switch (newState) {
      case HostConnectionState.connected:
        firstDisconnectTime = null;
        isIntentionalDisconnect = false;
        break;

      case HostConnectionState.disconnected:
      case HostConnectionState.failed:
        if (!isIntentionalDisconnect &&
            !isAuthFailed &&
            currentHostId != null) {
          firstDisconnectTime ??= DateTime.now();
          requestHostList();
          
          final elapsed = DateTime.now()
              .difference(firstDisconnectTime!)
              .inSeconds;

          if (elapsed < _reconnectWindowSeconds) {
            log(
              "Neural link unstable. Retrying... (${_reconnectWindowSeconds - elapsed}s remaining)",
            );
            client.currentHostState = HostConnectionState.connecting;
            hostStateController.add(HostConnectionState.connecting);

            _clearHostConnections();

            Timer(const Duration(seconds: 3), () {
              if (currentHostId != null && !isIntentionalDisconnect) {
                connectToHost(currentHostId!);
              }
            });
            return;
          } else {
            log("Uplink timeout. Threshold exceeded.");
            firstDisconnectTime = null;
            currentHostId = null;
          }
        } // If diconnection is intentional
        else {
          firstDisconnectTime = null;
          if (isIntentionalDisconnect) {
            currentHostId = null;
            currentHostName = null;
          }
        }
        break;
      default:
        break;
    }

    client.currentHostState = newState;
    hostStateController.add(newState);

    if (newState == HostConnectionState.disconnected ||
        newState == HostConnectionState.failed) {
      _clearHostConnections();
      log("Neural Link Severed.");
    }
  }

  /// Gracefully disconnects from the host and prevents automatic reconnection.
  ///
  /// Sets the intentional disconnect flag to prevent auto-reconnection logic
  /// and updates state to trigger cleanup.
  @override
  void disconnectFromHost() {
    isIntentionalDisconnect = true;
    updateHostState(HostConnectionState.disconnected);
  }

  /// Completely cleans up all WebRTC connections and resources.
  ///
  /// Closes all data channels and disposes of the peer connection.
  /// Nullifies all connection objects to prevent reuse.
  /// Used both during reconnection and final disconnection.
  Future<void> _clearHostConnections() async {
    try {
      await genDC?.close();
      await fsDC?.close();
      await mediaDC?.close();
      await sshDC?.close();
      await peerConnection?.dispose(); // Use dispose for full cleanup
    } catch (_) {}

    genDC = null;
    fsDC = null;
    mediaDC = null;
    sshDC = null;
    peerConnection = null;
  }

  @override
  void authenticate(String password);
  @override
  void handleHostMessage(dynamic rawData);
  @override
  void _sendToSignaling(String type, Map<String, dynamic> payload);
}
