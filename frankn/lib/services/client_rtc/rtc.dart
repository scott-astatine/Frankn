// Frankn Real-Time Communication (RTC) Client Library
///
/// This library implements the client-side WebRTC infrastructure for Frankn,
/// providing P2P communication between mobile devices and desktop hosts.
/// Uses a modular mixin architecture for clean separation of concerns.
///
/// Architecture:
/// - WebRTC Data Channels: frankn_cmd, frankn_fs, frankn_media, frankn_ssh
/// - Signaling Server: WebSocket-based peer discovery and SDP exchange
/// - Authentication: Argon2id challenge-response protocol
/// - Background Service: Maintains connection when app is backgrounded
///
/// Key Features:
/// - Automatic reconnection with 30-second recovery window
/// - Multi-channel WebRTC for specialized traffic types
/// - Real-time media sync and control
/// - File transfer with chunked uploads/downloads
/// - SSH terminal over WebRTC
/// - D-Bus notification mirroring
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:convert/convert.dart';

import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:uuid/uuid.dart';
import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:cryptography/cryptography.dart' as crypto_pkg;

import 'package:frankn/main.dart';
import 'package:frankn/utils/utils.dart';
import 'package:frankn/utils/dc_msg_util.dart';
import 'package:frankn/services/auth_service.dart';
import 'package:frankn/services/audio_handler.dart';
import 'package:frankn/services/notification_service.dart';
import 'package:frankn/services/settings_service.dart';
import 'package:frankn/services/isolate_protocol.dart';
import 'package:frankn/services/client_rtc/websocket_transport.dart';
import 'package:frankn/services/client_rtc/signaling_outbox.dart';
import 'package:frankn/services/client_rtc/rtc_host.dart';
import 'package:frankn/services/client_rtc/rtc_host_manager.dart';
import 'package:frankn/services/client_rtc/rtc_connection_attempt.dart';
import 'package:frankn/services/rtc_thin_client.dart';
part 'rtc_message_handler.dart';
part 'rtc_signaling.dart';
part 'rtc_connection.dart';
part 'rtc_commands.dart';
part 'node_peer_session.dart';
part 'capability_session_manager.dart';

/// Abstract base class defining the interface for RTC client implementations.
///
/// This interface provides a contract for all WebRTC operations including:
/// - Connection management (signaling server and P2P peers)
/// - Authentication and security
/// - Message routing across data channels
/// - State management and event streaming
///
/// All concrete implementations must provide these capabilities through mixins.
abstract class RtcClientBase {
  /// Logs a message to the console and internal log stream.
  void log(String msg);

  /// Sends a JSON message directly to the connected host via the command channel.
  void sendHostMessage(Map<String, dynamic> msg);

  /// Updates the current host connection state and notifies listeners.
  void updateHostState(HostConnectionState newState);

  /// Sends a data channel command to the host with proper authentication.
  void sendDcMsg(DcMsg cmd);

  /// Sends a raw input message over the frankn_input channel.
  void sendInputMsg(Map<String, dynamic> msg);

  /// Sends a message to a specific WebRTC data channel with logging.
  void sendToChannel(RTCDataChannel? channel, String msg, String label);

  /// Get list of active Hosts from the signaling server.
  void requestHostList();

  /// Subscribes to private presence status updates for all saved hosts.
  void subscribeToSavedHosts();

  /// Sends a message to the signaling server via WebSocket.
  void _sendToSignaling(String type, Map<String, dynamic> payload);

  Future<void> _sendDataPlaneToSignaling(
    String type,
    Map<String, dynamic> payload,
  );

  void disconnectFromHost();

  void _transitionTo(HostConnectionState nextState, String reason);

  /// Returns current Unix timestamp (seconds since epoch).
  int getTimestamp();

  /// Initiates a WebRTC P2P connection to the specified host.
  Future<void> connectToHost(
    String hostId, {
    String? password,
    String? hostName,
  });

  /// Establishes connection to the Frankn signaling server.
  Future<void> connectToSignaling();

  /// Waits until the signaling layer is connected, identity key loaded, and registered.
  Future<bool> waitForSignalingReady({
    Duration timeout = const Duration(seconds: 10),
  });

  /// Initiates the Argon2id challenge-response authentication process.
  void authenticate(String password);

  /// Processes incoming messages from the host via WebRTC data channels.
  void handleHostMessage(dynamic rawData);

  /// Starts the Android foreground service with a persistent notification.
  Future<void> startBackgroundService({String title, String text});

  /// Stops the Android foreground service.
  Future<void> stopBackgroundService();

  /// Updates the foreground service notification content.
  Future<void> updateBackgroundService({String? title, String? text});

  /// Maps transfer IDs to their final destination directories.
  Map<String, String> get downloadTargetDirs;

  /// Maps transfer IDs to whether notifications should be shown.
  Map<String, bool> get showNotificationMap;

  /// Marks authentication as failed. Used by message handlers.
  set authFailed(bool value);

  // ========== STATE MANAGEMENT ==========

  String? get currentPassword;
  set currentPassword(String? value);

  String? get currentHostId;
  set currentHostId(String? value);

  String? get currentHostName;
  set currentHostName(String? value);

  String? get homeDir;
  set homeDir(String? value);

  bool get isAuthFailed;
  set isAuthFailed(bool value);

  bool get isIntentionalDisconnect;
  set isIntentionalDisconnect(bool value);

  DateTime? get firstDisconnectTime;
  set firstDisconnectTime(DateTime? value);

  // ========== CONNECTION STATE ==========

  SignalConnectionState get sigState;
  set sigState(SignalConnectionState value);

  List<dynamic> get currentHosts;
  set currentHosts(List<dynamic> value);

  Set<String> get onlineHostIds;

  List<Uint8List> drainSshEarlyBuffer();

  HostConnectionState get currentHostState;
  set currentHostState(HostConnectionState value);

  Timer? get reconnectTimer;
  set reconnectTimer(Timer? value);

  // ========== STREAM CONTROLLERS & STREAMS ==========

  Map<String, String> get activeFileNames;

  StreamController<HostMessage> get genDcMsgController;
  StreamController<HostMsgNotification> get notificationController;
  StreamController<Uint8List> get sshDataController;
  StreamController<HostMsgSyncSnapshot> get syncSnapshotController;
  StreamController<HostConnectionState> get hostStateController;
  Stream<TransferProgressEvent> get transferProgressStream;
  StreamController<TransferProgressEvent> get transferProgressController;
}

class RtcClient extends RtcClientBase
    with RtcSignaling, RtcConnection, RtcCommands, RtcMessageHandler {
  /// Singleton instance - only one RTC client exists per app instance.
  static final RtcClient _instance = RtcClient._internal();

  /// Factory constructor that returns the singleton instance.
  factory RtcClient() => _instance;

  CapabilitySessionManager get capabilitySessionManager =>
      RtcThinClient().capabilitySessionManager;

  /// Private constructor for singleton pattern.
  RtcClient._internal();

  /// Subsystem instances
  final WebSocketTransport transport = WebSocketTransport();
  late final SignalingOutbox outbox = SignalingOutbox(transport);
  final RtcHostManager hostManager = RtcHostManager();
  IdentityManager get identityManager => AuthService().identityManager;

  /// Current Host accessor
  RtcHost? get currentHost => currentHostId != null ? hostManager.findHost(currentHostId!) : null;

  // ========== CONNECTION ATTEMPT TRACKING ==========
  RtcConnectionAttempt? activeAttempt;
  int _connectionGeneration = 0;
  int get connectionGeneration => _connectionGeneration;

  void incrementGeneration() {
    _connectionGeneration++;
  }

  @override
  void _sendToSignaling(String type, Map<String, dynamic> payload) {
    if (transport.state != TransportState.connected) return;
    try {
      final msg = jsonEncode({
        'type': type,
        'from': identityManager.selfId,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        ...payload,
      });
      transport.send(msg);
    } catch (e) {
      log("Signaling Send Error: $e");
    }
  }

  @override
  Future<void> _sendDataPlaneToSignaling(
    String type,
    Map<String, dynamic> payload,
  ) async {
    if (transport.state != TransportState.connected) return;
    final to = payload['to'] as String? ?? '';
    await outbox.enqueueDataPlaneMessage(
      type: type,
      toPeerId: to,
      sessionId: identityManager.sessionId,
      payload: payload,
    );
  }

  @override
  String? currentPassword;

  @override
  String? currentHostId;

  @override
  String? currentHostName;

  @override
  String? homeDir;

  List<Map<String, dynamic>> availableCapabilities = [];

  String? findProviderForCapability(String capabilityId) {
    for (final cap in availableCapabilities) {
      final descriptor = cap['descriptor'] as Map?;
      final provider = cap['provider'] as Map?;
      if (descriptor?['id'] == capabilityId &&
          provider?['provider_id'] != null) {
        return provider!['provider_id'].toString();
      }
    }
    return null;
  }

  // ========== RECONNECTION LOGIC ==========

  @override
  DateTime? firstDisconnectTime;

  @override
  bool isAuthFailed = false;

  @override
  bool isIntentionalDisconnect = false;

  // ========== ACTIVE OPERATIONS ==========

  @override
  final Map<String, String> activeFileNames = {};

  // ========== CONNECTION STATE ==========

  @override
  SignalConnectionState sigState = SignalConnectionState.disconnected;

  @override
  List<dynamic> currentHosts = [];

  @override
  HostConnectionState currentHostState = HostConnectionState.disconnected;

  @override
  Timer? reconnectTimer;

  // ========== ACTIVE OPERATIONS ==========

  /// Set of Host IDs that are currently online according to the signaling server.
  @override
  final Set<String> onlineHostIds = {};

  // ========== STREAM CONTROLLERS ==========

  /// Broadcast controller for peer status updates (online/offline).
  final StreamController<Map<String, dynamic>> _peerStatusController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get peerStatusStream =>
      _peerStatusController.stream;

  /// Broadcast controller for available hosts list from signaling server.
  /// Emitted when host list is received or updated.
  final StreamController<List<dynamic>> _hostListController =
      StreamController<List<dynamic>>.broadcast();
  Stream<List<dynamic>> get hostListStream => _hostListController.stream;

  /// Broadcast controller for signaling server connection state changes.
  /// Used by UI to show signaling connection status.
  final StreamController<SignalConnectionState> _connectionStateController =
      StreamController<SignalConnectionState>.broadcast();
  Stream<SignalConnectionState> get connectionStateStream =>
      _connectionStateController.stream;

  /// Broadcast controller for host connection state changes.
  /// Critical for UI updates showing connection progress and status.
  @override
  final StreamController<HostConnectionState> hostStateController =
      StreamController<HostConnectionState>.broadcast();
  Stream<HostConnectionState> get hostStateStream => hostStateController.stream;

  /// Broadcast controller for debug log messages.
  /// Used by UI components that want to display connection logs.
  final StreamController<String> _logController =
      StreamController<String>.broadcast();
  Stream<String> get logStream => _logController.stream;

  final List<String> _logHistory = [];
  List<String> get logHistory => List.unmodifiable(_logHistory);

  /// Broadcast controller for responses to commands sent to the host.
  /// Includes file operations, system commands, and media controls.
  @override
  final StreamController<HostMessage> genDcMsgController =
      StreamController<HostMessage>.broadcast();
  Stream<HostMessage> get genDcMsgStream => genDcMsgController.stream;

  /// Broadcast controller for system notifications from the host.
  /// Receives D-Bus notifications that are displayed on the mobile device.
  @override
  final StreamController<HostMsgNotification> notificationController =
      StreamController<HostMsgNotification>.broadcast();
  Stream<HostMsgNotification> get notificationStream =>
      notificationController.stream;

  @override
  final StreamController<Uint8List> sshDataController =
      StreamController<Uint8List>.broadcast();
  Stream<Uint8List> get sshDataStream => sshDataController.stream;

  @override
  final StreamController<HostMsgSyncSnapshot> syncSnapshotController =
      StreamController<HostMsgSyncSnapshot>.broadcast();
  Stream<HostMsgSyncSnapshot> get syncSnapshotStream =>
      syncSnapshotController.stream;

  @override
  final StreamController<TransferProgressEvent> transferProgressController =
      StreamController<TransferProgressEvent>.broadcast();
  @override
  Stream<TransferProgressEvent> get transferProgressStream =>
      transferProgressController.stream;

  // ========== BASE IMPLEMENTATION ==========

  /// Setter for authentication failure flag.
  /// Used by message handlers to mark auth failures.
  @override
  Map<String, String> get downloadTargetDirs => _downloadTargetDirs;

  @override
  Map<String, bool> get showNotificationMap => _showNotificationMap;

  @override
  set authFailed(bool value) => isAuthFailed = value;

  /// Returns current Unix timestamp in seconds.
  /// Used for message ordering and preventing replay attacks.
  @override
  int getTimestamp() {
    return DateTime.now().millisecondsSinceEpoch ~/ 1000;
  }

  /// Sends a JSON message to the host via the command data channel.
  /// Used for authentication and other non-token-protected messages.
  @override
  void sendHostMessage(Map<String, dynamic> msg) {
    sendToChannel(currentHost?.genDC, jsonEncode(msg), "CMD");
  }

  /// Logs a message with timestamp to console and log stream.
  /// All RTC operations use this for consistent logging.
  @override
  void log(String msg) {
    final time = DateTime.now().toIso8601String().substring(11, 19);

    // Truncate large messages to prevent buffer overflow crashes in release mode
    String safeMsg = msg;
    if (msg.length > 2048) {
      safeMsg = "${msg.substring(0, 2048)}... [TRUNCATED]";
    }

    final logMsg = "[$time] $safeMsg";
    print(logMsg);

    _logHistory.insert(0, logMsg);
    if (_logHistory.length > 1000) _logHistory.removeLast();

    _logController.add(logMsg);
  }

  /// Sends a message to a specific WebRTC data channel with state validation.
  /// Includes debug logging and checks channel readiness before sending.
  @override
  void sendToChannel(RTCDataChannel? channel, String msg, String label) {
    // Only log non-noisy messages (skip ping, telemetry, and file chunks)
    if (!msg.contains('ping') &&
        !msg.contains('telemetry') &&
        !msg.contains('toggle_play_pause') &&
        !msg.contains(InputSig.MouseMove) &&
        !msg.contains(InputSig.MouseClick) &&
        !msg.contains(InputSig.Scroll) &&
        !msg.contains(InputSig.Text) &&
        !msg.contains(InputSig.KeyPress)) {
      log("SENT to $currentHostName [$label]: $msg");
    }
    if (channel?.state == RTCDataChannelState.RTCDataChannelOpen) {
      channel!.send(RTCDataChannelMessage(msg));
    } else {
      log("Uplink [$label] Offline (State: ${channel?.state}). Cannot send.");
    }
  }
}
