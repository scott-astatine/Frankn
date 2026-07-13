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
  int _reconnectDelaySeconds = 2;

  /// Minimum interval between host list requests to avoid spamming the signaling server.
  DateTime? _lastHostListRequest;
  static const Duration _hostListCooldown = Duration(seconds: 2);

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

    _updateSigState(SignalConnectionState.connecting);
    log("Initializing Neural Link to ${SettingsService().signalingUrl}...");

    try {
      signalingChannel = IOWebSocketChannel.connect(
        Uri.parse(SettingsService().signalingUrl),
        pingInterval: const Duration(seconds: 10),
      );

      // Set up WebSocket message handling
      signalingChannel!.stream.listen(
        (message) {
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
        'is_public': false,
      });

      // Optimistically set to connected after registration is sent
      _updateSigState(SignalConnectionState.connected);
      _reconnectDelaySeconds = 2; // Reset reconnect delay on successful connection
    } catch (e) {
      log("Fatal Connection Error: $e");
      _handleDisconnection();
    }
  }

  /// Handles signaling server disconnection and initiates reconnection.
  ///
  /// Updates connection state to disconnected (not failed), closes WebSocket,
  /// cancels existing timers, and schedules automatic reconnection after 2 seconds.
  /// Uses 'disconnected' state so the connectToSignaling guard allows reconnection.
  void _handleDisconnection() {
    final client = this as RtcClient;
    signalingChannel?.sink.close();
    client.reconnectTimer?.cancel();

    // Clear online hosts and notify UI
    client.onlineHostIds.clear();
    client._peerStatusController.add({'type': 'refresh'});

    // Reset to disconnected so the guard at the top of connectToSignaling
    // doesn't block the retry. We keep the old 'failed' emission for any
    // listeners that care about it, but set the actual state to disconnected.
    client._connectionStateController.add(SignalConnectionState.failed);
    client.sigState = SignalConnectionState.disconnected;
    
    log("Signaling reconnect scheduled in $_reconnectDelaySeconds seconds.");
    client.reconnectTimer = Timer(Duration(seconds: _reconnectDelaySeconds), () {
      connectToSignaling();
    });

    // Exponential backoff up to 60 seconds
    _reconnectDelaySeconds = (_reconnectDelaySeconds * 2).clamp(2, 60);
  }

  /// Initializes and starts the Android foreground service.
  ///
  /// The foreground service maintains the app's network connection when
  /// the app is backgrounded or the screen is off. It displays a persistent
  /// notification to indicate the service is running.
  @override
  Future<void> startBackgroundService({
    String title = 'Frankn Active',
    String text = 'Secure Link Established',
  }) async {
    if (await FlutterForegroundTask.isRunningService) {
      updateBackgroundService(title: title, text: text);
      return;
    }

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'frankn_connection',
        channelName: 'Frankn Connection',
        channelDescription: 'Maintains connection to Frankn Host',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        onlyAlertOnce: true,
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
      notificationTitle: title,
      notificationText: text,
      notificationIcon: const NotificationIcon(
        metaDataName: 'com.pravera.flutter_foreground_task.NOTIFICATION_ICON',
        backgroundColor: AppColors.neonCyan,
      ),
      notificationButtons: [
        const NotificationButton(
          id: 'disconnect',
          text: '🛑 DISCONNECT',
          textColor: AppColors.errorRed,
        ),
      ],
      callback: startCallback,
    );
  }

  @override
  Future<void> stopBackgroundService() async {
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }
  }

  @override
  Future<void> updateBackgroundService({String? title, String? text}) async {
    if (await FlutterForegroundTask.isRunningService) {
      FlutterForegroundTask.updateService(
        notificationTitle: title,
        notificationText: text,
        notificationButtons: [
          const NotificationButton(
            id: 'disconnect',
            text: '🛑 DISCONNECT',
            textColor: AppColors.errorRed,
          ),
        ],
      );
    }
  }

  /// Processes incoming messages from the signaling server.  ///
  /// Handles different message types for the WebRTC signaling process:
  /// - Registration responses
  /// - Host list updates
  /// - SDP answers from hosts
  /// - ICE candidates for connection establishment
  void _handleSignalingMessage(Map<String, dynamic> data) async {
    final type = data['type'];
    switch (type) {
      case SignalingMessage.RegisterSuccess:
        log("Identity Verified. Access Granted!");
        _updateSigState(SignalConnectionState.connected);
        requestHostList();
        break;

      case SignalingMessage.RegisterFailure:
        final error = data['error'] ?? 'Unknown registration error';
        log("Identity Verification Failed: $error");
        _handleDisconnection();
        break;

      case SignalingMessage.PeerStatusUpdate:
        final id = data['peer_id'];
        final isOnline = data['online'] as bool;
        final client = this as RtcClient;

        if (isOnline) {
          log("Host online: $id");
          client.onlineHostIds.add(id);
        } else {
          log("Host went down: $id");
          client.onlineHostIds.remove(id);
        }
        client._peerStatusController.add(data);
        break;

      case SignalingMessage.HostList:
        final client = this as RtcClient;
        client.currentHosts = data['hosts'];

        // Add public hosts from the list to onlineHostIds
        for (var host in client.currentHosts) {
          if (host['host_id'] != null) {
            client.onlineHostIds.add(host['host_id']);
          }
        }

        client._hostListController.add(client.currentHosts);
        // Trigger a status update to refresh the UI indicators
        // Use a short delay to ensure UI listeners are registered
        Future.delayed(const Duration(milliseconds: 100), () {
          client._peerStatusController.add({'type': 'refresh'});
        });
        break;

      case SignalingMessage.Answer:
        final client = this as RtcClient;
        final activeAttempt = client.activeAttempt;
        if (activeAttempt == null) {
          log("WARN: Received SDP answer but no active connection attempt. Ignoring.");
          break;
        }

        final msgSessionId = data['session_id'];
        if (msgSessionId != activeAttempt.sessionUuid) {
          log("WARN: Received SDP answer with mismatched Session ID ($msgSessionId vs ${activeAttempt.sessionUuid}). Discarding stale handshake.");
          break;
        }

        // Set the remote SDP answer to complete WebRTC handshake
        try {
          await peerConnection!.setRemoteDescription(
            RTCSessionDescription(data['sdp'], 'answer'),
          );
        } catch (e) {
          log("CORE ERROR: Failed to set remote description: $e");
        }
        break;

      case SignalingMessage.IceCandidate:
        final client = this as RtcClient;
        final activeAttempt = client.activeAttempt;
        if (activeAttempt == null) {
          log("WARN: Received ICE candidate but no active connection attempt. Ignoring.");
          break;
        }

        final msgSessionId = data['session_id'];
        if (msgSessionId != activeAttempt.sessionUuid) {
          log("WARN: Received ICE candidate with mismatched Session ID ($msgSessionId vs ${activeAttempt.sessionUuid}). Discarding stale handshake.");
          break;
        }

        // Add ICE candidate for NAT traversal
        try {
          final candStr = data['candidate'] as String;
          log("ICE_GATHER: Received remote ICE candidate: $candStr");
          var candidate = RTCIceCandidate(
            candStr,
            data['sdp_mid'],
            data['sdp_m_line_index'],
          );
          await peerConnection!.addCandidate(candidate);
        } catch (e) {
          log("CORE ERROR: Failed to add ICE candidate: $e");
        }
        break;
      case SignalingMessage.Error:
        log("DEBUG: Signaling error: ${data['message']}");
        final client = this as RtcClient;
        if (client.currentHostState != HostConnectionState.disconnected) {
          _transitionTo(HostConnectionState.failed, "Signaling error: ${data['message']}");
        }
        break;
    }
  }

  /// Requests the current list of available hosts from the signaling server.
  ///
  /// This populates the host list that users can select from in the UI.
  /// Rate-limited to prevent spamming the signaling server.
  @override
  void requestHostList() {
    final now = DateTime.now();
    if (_lastHostListRequest != null &&
        now.difference(_lastHostListRequest!) < _hostListCooldown) {
      return; // Cooldown active — skip this request
    }
    _lastHostListRequest = now;
    _sendToSignaling('list_hosts', {});
  }

  /// Updates the signaling connection state and notifies listeners.
  ///
  /// Used internally to track connection progress and notify UI components.
  void _updateSigState(SignalConnectionState newState) {
    final client = this as RtcClient;
    client.sigState = newState;
    client._connectionStateController.add(newState);
  }
}
