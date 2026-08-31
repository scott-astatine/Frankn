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


  Future<void> _handleAuthChallenge(String challengeStr) async {
    try {
      final identity = AuthService().identityManager;
      final keyPair = await identity.getOrCreateIdentityKey();
      final derivedPeerId = identity.selfId!;
      final publicKeyHex = identity.publicKeyHex!;

      String normalizeBase64Url(String input) {
        String output = input.replaceAll('-', '+').replaceAll('_', '/');
        switch (output.length % 4) {
          case 0:
            break;
          case 2:
            output += '==';
            break;
          case 3:
            output += '=';
            break;
          default:
            throw Exception('Illegal base64url string!');
        }
        return output;
      }
      final challengeBytes = base64Decode(normalizeBase64Url(challengeStr));

      final algorithm = crypto_pkg.Ed25519();
      final signature = await algorithm.sign(challengeBytes, keyPair: keyPair);
      final signatureHex = hex.encode(signature.bytes);

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

      _sendToSignaling('register', {
        'protocol_version': 1,
        'peer_id': derivedPeerId,
        'peer_type': 'Client',
        'display_name': displayName,
        'is_public': false,
        'public_key': publicKeyHex,
        'signature': signatureHex,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
    } catch (e) {
      log("ERROR in challenge response: $e");
      _handleDisconnection();
    }
  }

  /// Waits until the signaling layer is fully connected, identity key loaded, and session_id established.
  @override
  Future<bool> waitForSignalingReady({Duration timeout = const Duration(seconds: 10)}) async {
    final client = this as RtcClient;
    final identity = AuthService().identityManager;
    if (client.sigState == SignalConnectionState.connected &&
        identity.sessionId != null &&
        identity.keyPair != null) {
      return true;
    }

    final completer = Completer<bool>();
    late StreamSubscription sub;
    final timer = Timer(timeout, () {
      if (!completer.isCompleted) {
        sub.cancel();
        completer.complete(false);
      }
    });

    sub = client.connectionStateStream.listen((state) {
      if (state == SignalConnectionState.connected &&
          identity.sessionId != null &&
          identity.keyPair != null) {
        timer.cancel();
        sub.cancel();
        if (!completer.isCompleted) {
          completer.complete(true);
        }
      }
    });

    return completer.future;
  }

  StreamSubscription? _signalingSubscription;

  /// Establishes WebSocket connection to the signaling server.
  Future<void> connectToSignaling() async {
    final client = this as RtcClient;
    if (client.sigState == SignalConnectionState.connected ||
        client.sigState == SignalConnectionState.connecting) {
      return;
    }

    _updateSigState(SignalConnectionState.connecting);
    log("Initializing Neural Link to ${SettingsService().signalingUrl}...");

    try {
      await _signalingSubscription?.cancel();
      _signalingSubscription = client.transport.messageStream.listen(
        (message) {
          if (message is String) {
            _handleSignalingMessage(jsonDecode(message));
          }
        },
        onError: (e) {
          log("Signaling Error: $e");
          _handleDisconnection();
        },
      );

      await client.transport.connect(SettingsService().signalingUrl);
      _reconnectDelaySeconds = 2; // Reset reconnect delay on successful connection
    } catch (e) {
      log("Fatal Connection Error: $e");
      _handleDisconnection();
    }
  }

  /// Handles signaling server disconnection and initiates reconnection.
  void _handleDisconnection() {
    final client = this as RtcClient;
    client.transport.disconnect();
    client.reconnectTimer?.cancel();

    _updateSigState(SignalConnectionState.disconnected);
    AuthService().identityManager.sessionId = null;

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
        backgroundColor: AppColors.accentPrimary,
      ),
      notificationButtons: [
        const NotificationButton(
          id: 'disconnect',
          text: '🛑 DISCONNECT',
          textColor: AppColors.accentError,
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
            textColor: AppColors.accentError,
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
      case SignalingMessage.AuthChallenge:
        final challenge = data['challenge'] as String;
        await _handleAuthChallenge(challenge);
        break;

      case SignalingMessage.RegisterSuccess:
        log("Identity Verified. Access Granted!");
        AuthService().identityManager.sessionId = data['session_id'];
        (this as RtcClient).outbox.reset();
        _updateSigState(SignalConnectionState.connected);
        requestHostList();
        subscribeToSavedHosts();
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

        log("[SIG] [G${activeAttempt.generationId}] [${activeAttempt.elapsedMs}] Received SDP Answer from host.");
        final msgSessionId = data['session_id'] as String;
        activeAttempt.hostSessionId = msgSessionId;

        // Immediately transition to iceConnecting to cancel signaling stage timeout while setRemoteDescription runs
        _transitionTo(HostConnectionState.iceConnecting, "Received SDP Answer");

        // Set the remote SDP answer to complete WebRTC handshake
        try {
          log("[RTC] [G${activeAttempt.generationId}] [${activeAttempt.elapsedMs}] setRemoteDescription started");
          await activeAttempt.peerConnection.setRemoteDescription(
            RTCSessionDescription(data['sdp'], 'answer'),
          );
          log("[RTC] [G${activeAttempt.generationId}] [${activeAttempt.elapsedMs}] setRemoteDescription completed");
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
        if (activeAttempt.hostSessionId != null && msgSessionId != activeAttempt.hostSessionId) {
          log("WARN: Received ICE candidate with mismatched Host Session ID ($msgSessionId vs ${activeAttempt.hostSessionId}). Discarding stale candidate.");
          break;
        }

        // Add ICE candidate for NAT traversal
        try {
          final candStr = data['candidate'] as String;
          final parts = candStr.split(' ');
          final proto = parts.length > 2 ? parts[2] : 'udp';
          final candTypeIndex = parts.indexOf('typ');
          final candType =
              (candTypeIndex != -1 && parts.length > candTypeIndex + 1)
                  ? parts[candTypeIndex + 1]
                  : 'host';
          log(
            "[ICE] [G${activeAttempt.generationId}] [${activeAttempt.elapsedMs}] Received remote candidate ($proto/$candType)",
          );
          var candidate = RTCIceCandidate(
            candStr,
            data['sdp_mid'],
            data['sdp_m_line_index'],
          );
          await activeAttempt.peerConnection.addCandidate(candidate);
        } catch (e) {
          log("CORE ERROR: Failed to add ICE candidate: $e");
        }
        break;
      case SignalingMessage.HostsStatusResponse:
        final client = this as RtcClient;
        final statuses = data['statuses'] as Map<String, dynamic>?;
        if (statuses != null) {
          statuses.forEach((id, isOnline) {
            final onlineBool = isOnline == true;
            if (onlineBool) {
              log("Subscribed host online: $id");
              client.onlineHostIds.add(id);
            } else {
              log("Subscribed host offline: $id");
              client.onlineHostIds.remove(id);
            }
            client._peerStatusController.add({
              'type': 'peer_status_update',
              'peer_id': id,
              'online': onlineBool,
            });
          });
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

  @override
  void subscribeToSavedHosts() {
    final client = this as RtcClient;
    if (client.sigState == SignalConnectionState.connected) {
      SettingsService().reload().then((_) {
        final savedHosts = SettingsService().savedHosts;
        if (savedHosts.isNotEmpty) {
          final hostIds = savedHosts.map((h) => h['id']!).toList();
          log("Subscribing to presence status for saved hosts: $hostIds");
          _sendToSignaling(SignalingMessage.SubscribeHosts, {
            'host_ids': hostIds,
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          });
        }
      });
    }
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
