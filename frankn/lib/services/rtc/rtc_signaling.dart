/// Mixin handling WebSocket communication with the Frankn signaling server.
///
/// This mixin manages the signaling channel used for:
/// - Peer discovery and host listing
/// - SDP offer/answer exchange for WebRTC
/// - ICE candidate forwarding for NAT traversal
/// - Client registration and identity management
/// - Background service initialization for persistent connections
part of 'rtc.dart';

mixin RtcSignaling on RtcClientBase {
  /// Establishes WebSocket connection to the signaling server.
  ///
  /// Handles the complete signaling connection lifecycle:
  /// 1. Prevents duplicate connections
  /// 2. Starts background service for persistence
  /// 3. Creates WebSocket connection with error handling
  /// 4. Sets up message listeners and reconnection logic
  /// 5. Registers client with device information
  ///
  /// The connection is kept alive automatically and will reconnect on failures.
  @override
  Future<void> connectToSignaling() async {
    final client = this as RtcClient;
    if (client.sigState == SignalConnectionState.connected ||
        client.sigState == SignalConnectionState.connecting) {
      return;
    }

    _startBackgroundService();

    _updateSigState(SignalConnectionState.connecting);
    log("Initializing Neural Link to ${SettingsService().signalingUrl}...");

    try {
      signalingChannel = WebSocketChannel.connect(
        Uri.parse(SettingsService().signalingUrl),
      );

      // Set up WebSocket message handling
      signalingChannel!.stream.listen(
        (message) {
          if (client.sigState != SignalConnectionState.connected) {
            _updateSigState(SignalConnectionState.connected);
          }
          _handleSignalingMessage(jsonDecode(message));
        },
        onError: (e) {
          log("Signaling Error: $e");
          _handleDisconnection();
        },
        onDone: () {
          log("Signaling Disconnected (Server Closed).");
          _handleDisconnection();
        },
      );

      // Generate unique client ID if not set
      selfId ??= const Uuid().v4();

      // Get device information for display name
      String displayName = "Unknown Device";
      try {
        final deviceInfo = DeviceInfoPlugin();
        if (Platform.isAndroid) {
          final androidInfo = await deviceInfo.androidInfo;
          displayName = "${androidInfo.manufacturer} ${androidInfo.model}";
        } else if (Platform.isLinux) {
          final linuxInfo = await deviceInfo.linuxInfo;
          displayName = linuxInfo.name;
        } else if (Platform.isIOS) {
          final iosInfo = await deviceInfo.iosInfo;
          displayName = iosInfo.name;
        }
      } catch (e) {
        log("Error getting device info: $e");
      }

      // Register with signaling server
      _sendToSignaling('register', {
        'peer_id': selfId,
        'peer_type': 'Client',
        'display_name': displayName,
        'is_public': false
      });
    } catch (e) {
      log("Fatal Connection Error: $e");
      _handleDisconnection();
    }
  }

  /// Handles signaling server disconnection and initiates reconnection.
  ///
  /// Updates connection state to failed, closes WebSocket, cancels existing
  /// timers, and schedules automatic reconnection after 2 seconds.
  void _handleDisconnection() {
    final client = this as RtcClient;
    _updateSigState(SignalConnectionState.failed);
    signalingChannel?.sink.close();
    client.reconnectTimer?.cancel();
    client.reconnectTimer = Timer(const Duration(seconds: 2), () {
      connectToSignaling();
    });
  }

  /// Initializes and starts the Android foreground service.
  ///
  /// The foreground service maintains the app's network connection when
  /// the app is backgrounded or the screen is off. It displays a persistent
  /// notification to indicate the service is running.
  Future<void> _startBackgroundService() async {
    if (await FlutterForegroundTask.isRunningService) return;

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'frankn_connection',
        channelName: 'Frankn Connection',
        channelDescription: 'Maintains connection to Frankn Host',
        channelImportance: NotificationChannelImportance.HIGH,
        priority: NotificationPriority.HIGH,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );

    await FlutterForegroundTask.startService(
      notificationTitle: 'Frankn Active',
      notificationText: 'Connected to Neural Link',
      callback: startCallback,
    );
  }

  /// Processes incoming messages from the signaling server.
  ///
  /// Handles different message types for the WebRTC signaling process:
  /// - Registration responses
  /// - Host list updates
  /// - SDP answers from hosts
  /// - ICE candidates for connection establishment
  void _handleSignalingMessage(Map<String, dynamic> data) async {
    final type = data['type'];
    switch (type) {
      case SinalingMessage.RegisterSuccess:
        log("Identity Verified. Access Granted!");
        _updateSigState(SignalConnectionState.connected);
        requestHostList();
        break;

      case SinalingMessage.HostList:
        final client = this as RtcClient;
        client.currentHosts = data['hosts'];
        client._hostListController.add(client.currentHosts);

        // Auto-reconnect to previous host if signaling reconnected
        // if (currentHostId != null &&
        //     !isIntentionalDisconnect &&
        //     !isAuthFailed) {
        //   log("Re-establishing P2P connection after signaling reconnect...");
        //   connectToHost(currentHostId!, hostName: currentHostName);
        // }
        break;

      case SinalingMessage.Answer:
        // Set the remote SDP answer to complete WebRTC handshake
        await peerConnection?.setRemoteDescription(
          RTCSessionDescription(data['sdp'], 'answer'),
        );
        break;

      case SinalingMessage.IceCandidate:
        // Add ICE candidate for NAT traversal
        var candidate = RTCIceCandidate(
          data['candidate'],
          data['sdp_mid'],
          data['sdp_m_line_index'],
        );
        await peerConnection?.addCandidate(candidate);
        break;
      case SinalingMessage.Error:
        log("DEBUG: Signaling error: $data['message']");
        currentHostName = null;
        currentHostId = null;
        currentPassword = null;
        break;
    }
  }

  /// Requests the current list of available hosts from the signaling server.
  ///
  /// This populates the host list that users can select from in the UI.
  @override
  void requestHostList() => _sendToSignaling('list_hosts', {});

  /// Updates the signaling connection state and notifies listeners.
  ///
  /// Used internally to track connection progress and notify UI components.
  void _updateSigState(SignalConnectionState newState) {
    final client = this as RtcClient;
    client.sigState = newState;
    client._connectionStateController.add(newState);
  }
}
