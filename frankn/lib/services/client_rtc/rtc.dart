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
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';
import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:cryptography/cryptography.dart' as crypto_pkg;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:frankn/main.dart';
import 'package:frankn/utils/utils.dart';
import 'package:frankn/utils/dc_msg_util.dart';
import 'package:frankn/services/auth_service.dart';
import 'package:frankn/services/audio_handler.dart';
import 'package:frankn/services/notification_service.dart';
import 'package:frankn/services/settings_service.dart';
import 'package:frankn/services/isolate_protocol.dart';
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
  /// Used throughout the library for debugging and monitoring.
  void log(String msg);

  /// Sends a JSON message directly to the connected host via the command channel.
  /// Used primarily for authentication messages that don't require session tokens.
  void sendHostMessage(Map<String, dynamic> msg);

  /// Updates the current host connection state and notifies listeners.
  /// Handles automatic reconnection logic and state transition validation.
  void updateHostState(HostConnectionState newState);

  /// Sends a data channel command to the host with proper authentication.
  /// Automatically routes to the appropriate WebRTC channel based on command type.
  void sendDcMsg(DcMsg cmd);

  /// Sends a raw input message over the frankn_input channel.
  void sendInputMsg(Map<String, dynamic> msg);

  /// Sends a message to a specific WebRTC data channel with logging.
  /// Validates channel state before sending to prevent errors.
  void sendToChannel(RTCDataChannel? channel, String msg, String label);

  /// Get list of active Hosts from the signaling server.
  void requestHostList();

  /// Subscribes to private presence status updates for all saved hosts.
  void subscribeToSavedHosts();

  /// Sends a message to the signaling server via WebSocket.
  /// Includes timestamp and client ID in all messages.
  void _sendToSignaling(String type, Map<String, dynamic> payload);

  Future<void> _sendDataPlaneToSignaling(String type, Map<String, dynamic> payload);

  void disconnectFromHost();

  void _transitionTo(HostConnectionState nextState, String reason);

  /// Returns current Unix timestamp (seconds since epoch).
  /// Used for message ordering and security validation.
  int getTimestamp();

  /// Initiates a WebRTC P2P connection to the specified host.
  /// Creates all data channels and begins the SDP offer process.
  ///
  /// Parameters:
  /// - hostId: Unique identifier of the target host
  /// - password: Optional authentication password
  /// - hostName: Optional display name for the host
  Future<void> connectToHost(
    String hostId, {
    String? password,
    String? hostName,
  });

  /// Establishes connection to the Frankn signaling server.
  /// Handles device registration and background service initialization.
  Future<void> connectToSignaling();

  /// Waits until the signaling layer is connected, identity key loaded, and registered.
  Future<bool> waitForSignalingReady({Duration timeout = const Duration(seconds: 10)});

  /// Initiates the Argon2id challenge-response authentication process.
  /// Sends authentication request to host to begin the security handshake.
  void authenticate(String password);

  /// Processes incoming messages from the host via WebRTC data channels.
  /// Handles JSON and binary messages, routing them to appropriate handlers.
  void handleHostMessage(dynamic rawData);

  /// Starts the Android foreground service with a persistent notification.
  Future<void> startBackgroundService({String title, String text});

  /// Stops the Android foreground service.
  Future<void> stopBackgroundService();

  /// Updates the foreground service notification content.
  Future<void> updateBackgroundService({String? title, String? text});

  /// Maps transfer IDs to their final destination directories.
  /// Used by RtcMessageHandler to relocate files after download.
  Map<String, String> get downloadTargetDirs;

  /// Maps transfer IDs to whether notifications should be shown.
  Map<String, bool> get showNotificationMap;

  /// Marks authentication as failed. Used by message handlers.
  set authFailed(bool value);

  // ========== STATE MANAGEMENT ==========

  /// Current authentication password. Set during connection initiation.
  String? get currentPassword;
  set currentPassword(String? value);

  /// Unique identifier of the currently connected host.
  String? get currentHostId;
  set currentHostId(String? value);

  /// Display name of the currently connected host.
  String? get currentHostName;
  set currentHostName(String? value);

  /// Home directory of the user on the remote host.
  String? get homeDir;
  set homeDir(String? value);

  /// Flag indicating if the last authentication attempt failed.
  bool get isAuthFailed;
  set isAuthFailed(bool value);

  /// Flag indicating if the current disconnect was intentional by the user.
  /// Prevents automatic reconnection when user manually disconnects.
  bool get isIntentionalDisconnect;
  set isIntentionalDisconnect(bool value);

  /// Timestamp of the first disconnect in the current session.
  /// Used to determine if reconnection attempts should continue.
  DateTime? get firstDisconnectTime;
  set firstDisconnectTime(DateTime? value);

  // ========== CONNECTION OBJECTS ==========

  /// WebSocket connection to the Frankn signaling server.
  /// Handles peer discovery, SDP exchange, and ICE candidate forwarding.
  WebSocketChannel? get signalingChannel;
  set signalingChannel(WebSocketChannel? value);

  /// Main WebRTC peer connection object.
  /// Manages the P2P connection and all data channels.
  RTCPeerConnection? get hostPeerConnection;
  set hostPeerConnection(RTCPeerConnection? value);

  // ========== WEBRTC DATA CHANNELS ==========

  /// Command channel for general operations (frankn_cmd, ID: 1).
  /// Handles authentication, power control, process management, etc.
  RTCDataChannel? get genDC;
  set genDC(RTCDataChannel? value);

  /// File system channel for file operations (frankn_fs, ID: 3).
  /// Handles directory listing, file transfers, and file system commands.
  RTCDataChannel? get fsDC;
  set fsDC(RTCDataChannel? value);

  /// Media control channel for audio/video operations (frankn_media, ID: 4).
  /// Handles media player control, volume, and playback status.
  RTCDataChannel? get mediaDC;
  set mediaDC(RTCDataChannel? value);

  /// SSH terminal channel for shell access (frankn_ssh, ID: 2).
  /// Provides full terminal emulation over WebRTC.
  RTCDataChannel? get sshDC;
  set sshDC(RTCDataChannel? value);

  /// AI channel for LLM streaming (dohee_x, ID: 5).
  RTCDataChannel? get aiDC;
  set aiDC(RTCDataChannel? value);

  /// Input channel for keyboard and mouse control (frankn_input, ID: 6).
  RTCDataChannel? get inputDC;
  set inputDC(RTCDataChannel? value);

  // ========== CLIENT IDENTITY ==========

  /// Unique identifier for this client instance.
  /// Generated on first connection to signaling server.
  String? get selfId;
  set selfId(String? value);

  String? get sessionId;
  set sessionId(String? value);

  crypto_pkg.SimpleKeyPair? get clientKeyPair;
  set clientKeyPair(crypto_pkg.SimpleKeyPair? value);

  int get sequence;
  set sequence(int value);

  /// Current state of the signaling server connection.
  SignalConnectionState get sigState;
  set sigState(SignalConnectionState value);

  /// List of currently available hosts from signaling server.
  List<dynamic> get currentHosts;
  set currentHosts(List<dynamic> value);

  /// Set of online host IDs (accessible for signaling updates).
  Set<String> get onlineHostIds;

  /// Drains the early SSH buffer and marks the handler as active.
  List<Uint8List> drainSshEarlyBuffer();

  /// Current state of the host connection.
  HostConnectionState get currentHostState;
  set currentHostState(HostConnectionState value);

  /// Timer for automatic reconnection attempts.
  /// Cancelled when connection is established or user disconnects.
  Timer? get reconnectTimer;
  set reconnectTimer(Timer? value);

  // ========== STREAM CONTROLLERS ==========

  /// Maps transfer IDs to file names for active file downloads.
  /// Used to correlate transfer completion with file metadata.
  Map<String, String> get activeFileNames;

  /// Controller for command responses from host.
  /// Streams JSON responses to command executions.
  StreamController<HostMessage> get genDcMsgController;

  /// Controller for system notifications from host.
  /// Receives D-Bus notifications that are displayed on the mobile device.
  StreamController<HostMsgNotification> get notificationController;

  /// Controller for SSH binary data from host.
  StreamController<Uint8List> get sshDataController;

  /// Controller for folder sync snapshot metadata.
  StreamController<HostMsgSyncSnapshot> get syncSnapshotController;

  /// Controller for host connection state changes.
  /// Used by UI to update connection status indicators.
  StreamController<HostConnectionState> get hostStateController;

  /// Stream of file transfer progress updates.
  Stream<TransferProgressEvent> get transferProgressStream;

  /// Controller for file transfer progress updates.
  StreamController<TransferProgressEvent> get transferProgressController;
}

/// Concrete implementation of the RTC client using mixin composition.
///
/// This singleton class combines all RTC functionality through mixins:
/// - RtcMessageHandler: Processes incoming host messages
/// - RtcSignaling: Manages signaling server communication
/// - RtcConnection: Handles WebRTC peer connection lifecycle
/// - RtcCommands: Provides command execution methods
///
/// The singleton pattern ensures all parts of the app use the same connection instance.
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

  // ========== CONNECTION OBJECTS ==========

  @override
  WebSocketChannel? signalingChannel;

  @override
  RTCPeerConnection? hostPeerConnection;

  // ========== CONNECTION ATTEMPT TRACKING ==========
  RtcConnectionAttempt? activeAttempt;
  int _connectionGeneration = 0;
  int get connectionGeneration => _connectionGeneration;

  void incrementGeneration() {
    _connectionGeneration++;
  }

  // ========== WEBRTC DATA CHANNELS ==========

  @override
  RTCDataChannel? genDC;

  @override
  RTCDataChannel? fsDC;

  @override
  RTCDataChannel? mediaDC;

  @override
  RTCDataChannel? sshDC;

  @override
  RTCDataChannel? aiDC;

  @override
  RTCDataChannel? inputDC;

  // ========== CLIENT IDENTITY ==========

  @override
  String? selfId;

  @override
  String? sessionId;

  @override
  crypto_pkg.SimpleKeyPair? clientKeyPair;

  @override
  int sequence = 0;

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
      if (descriptor?['id'] == capabilityId && provider?['provider_id'] != null) {
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
    sendToChannel(genDC, jsonEncode(msg), "CMD");
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

  /// Sends a structured message to the signaling server via WebSocket.
  /// Adds required fields (from, timestamp) and handles encoding errors.
  @override
  void _sendToSignaling(String type, Map<String, dynamic> payload) {
    if (signalingChannel == null) return;
    try {
      final msg = {
        'type': type,
        'from': selfId,
        'timestamp': getTimestamp(),
        ...payload,
      };
      signalingChannel!.sink.add(jsonEncode(msg));
    } catch (e) {
      log("Send Error: $e");
    }
  }

  @override
  Future<void> _sendDataPlaneToSignaling(String type, Map<String, dynamic> payload) async {
    if (signalingChannel == null) return;

    try {
      if (clientKeyPair == null) {
        await _getOrCreateIdentityKey();
      }

      if (sessionId == null) {
        for (int i = 0; i < 30; i++) {
          if (sessionId != null) break;
          await Future.delayed(const Duration(milliseconds: 100));
        }
      }

      final msgType = type == SignalingMessage.Offer ? 1 : 3; // 1 = Offer, 3 = IceCandidate
      final to = payload['to'] as String;
      final content = type == SignalingMessage.Offer ? payload['sdp'] : payload['candidate'];

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final seq = sequence++;

      final signatureHex = await signEnvelope(
        msgType: msgType,
        toPeerId: to,
        payload: content,
        sequence: seq,
        timestamp: timestamp,
      );

      final msg = {
        'type': type,
        'from': selfId,
        'to': to,
        'session_id': sessionId,
        'sequence': seq,
        'signature': signatureHex,
        'timestamp': timestamp,
        ...payload,
      };

      signalingChannel!.sink.add(jsonEncode(msg));
      if (type == SignalingMessage.Offer) {
        log("[SIG] [G${activeAttempt?.generationId ?? connectionGeneration}] [${activeAttempt?.elapsedMs ?? '+0ms'}] SDP Offer transmitted to WebSocket sink.");
      }
    } catch (e) {
      log("Data Plane Send Error: $e");
    }
  }

  Future<String> signEnvelope({
    required int msgType,
    required String toPeerId,
    required String payload,
    required int sequence,
    required int timestamp,
  }) async {
    var keyPair = clientKeyPair;
    keyPair ??= await _getOrCreateIdentityKey();

    final activeSessionId = sessionId;
    if (activeSessionId == null) {
      throw Exception("No active signaling session");
    }

    final buf = Uint8List(160);

    // Domain Separator (14 bytes)
    final domain = utf8.encode("FRANKN-SIG-V1\u0000");
    buf.setRange(0, 14, domain);

    // Version (1 byte)
    buf[14] = 0x01;

    // Message Type ID (1 byte)
    buf[15] = msgType;

    // Session ID (32 bytes)
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
    final sessionBytes = base64Decode(normalizeBase64Url(activeSessionId));
    buf.setRange(16, 48, sessionBytes);

    // Sequence (8 bytes BE)
    final seqData = ByteData(8)..setUint64(0, sequence, Endian.big);
    buf.setRange(48, 56, seqData.buffer.asUint8List());

    // Timestamp (8 bytes BE ms)
    final tsData = ByteData(8)..setUint64(0, timestamp, Endian.big);
    buf.setRange(56, 64, tsData.buffer.asUint8List());

    // From Peer ID (32 bytes)
    final fromBytes = base64Decode(normalizeBase64Url(selfId!));
    buf.setRange(64, 96, fromBytes);

    // To Peer ID (32 bytes)
    final toBytes = base64Decode(normalizeBase64Url(toPeerId));
    buf.setRange(96, 128, toBytes);

    // Payload Hash (32 bytes)
    final payloadBytes = utf8.encode(payload);
    final payloadHash = sha256.convert(payloadBytes).bytes;
    buf.setRange(128, 160, payloadHash);

    // Sign
    final algorithm = crypto_pkg.Ed25519();
    final signature = await algorithm.sign(buf, keyPair: keyPair);

    return hex.encode(signature.bytes);
  }
}

/// Centralized connection phase timeouts
class ConnectionTimeouts {
  static const Duration signaling = Duration(seconds: 10);
  static const Duration ice = Duration(seconds: 15);
  static const Duration authentication = Duration(seconds: 5);
}

/// Idempotent, thread-safe resource manager class for a single physical connection handshake attempt
class RtcConnectionAttempt {
  final int generationId;
  final String sessionUuid;
  String? hostSessionId;
  
  final WebSocketChannel signalingSocket;
  final RTCPeerConnection peerConnection;
  Timer? timeoutTimer;
  final Stopwatch stopwatch = Stopwatch()..start();
  int candidateCount = 0;
  
  bool _isDisposed = false;
  bool get isDisposed => _isDisposed;
  
  String get elapsedMs => "+${stopwatch.elapsedMilliseconds}ms";

  RtcConnectionAttempt({
    required this.generationId,
    required this.sessionUuid,
    required this.signalingSocket,
    required this.peerConnection,
  });

  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    
    timeoutTimer?.cancel();
    
    // Detach all listeners before disposing peer connection to prevent callback leakage
    peerConnection.onConnectionState = null;
    peerConnection.onIceCandidate = null;
    peerConnection.onIceConnectionState = null;
    peerConnection.onSignalingState = null;
    // Do not close the shared signalingSocket here as it is persistent
    try { peerConnection.dispose(); } catch (_) {}
  }
}
