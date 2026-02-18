/// Frankn Real-Time Communication (RTC) Client Library
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
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:hex/hex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:frankn/main.dart';
import 'package:frankn/utils/utils.dart';
import 'package:frankn/services/audio_handler.dart';
import 'package:frankn/services/auth_service.dart';
import 'package:frankn/services/settings_service.dart';

part 'rtc_message_handler.dart';
part 'rtc_signaling.dart';
part 'rtc_connection.dart';
part 'rtc_commands.dart';

/// Abstract base class defining the interface for RTC client implementations.
///
/// This interface provides a contract for all WebRTC operations including:
/// - Connection management (signaling server and P2P peers)
/// - Authentication and security
/// - Message routing across data channels
/// - State management and event streaming
///
/// All concrete implementations must provide these capabilities through mixins.
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
  void sendDcMsg(Map<String, dynamic> cmd);

  /// Sends a message to a specific WebRTC data channel with logging.
  /// Validates channel state before sending to prevent errors.
  void sendToChannel(RTCDataChannel? channel, String msg, String label);

  /// Get list of active Hosts from the signaling server.
  void requestHostList();

  /// Sends a message to the signaling server via WebSocket.
  /// Includes timestamp and client ID in all messages.
  void _sendToSignaling(String type, Map<String, dynamic> payload);

  void disconnectFromHost();

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

  /// Initiates the Argon2id challenge-response authentication process.
  /// Sends authentication request to host to begin the security handshake.
  void authenticate(String password);

  /// Processes incoming messages from the host via WebRTC data channels.
  /// Handles JSON and binary messages, routing them to appropriate handlers.
  void handleHostMessage(dynamic rawData);

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
  RTCPeerConnection? get peerConnection;
  set peerConnection(RTCPeerConnection? value);

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

  // ========== CLIENT IDENTITY ==========

  /// Unique identifier for this client instance.
  /// Generated on first connection to signaling server.
  String? get selfId;
  set selfId(String? value);

  /// Current state of the signaling server connection.
  SignalConnectionState get sigState;
  set sigState(SignalConnectionState value);

  /// List of currently available hosts from signaling server.
  List<dynamic> get currentHosts;
  set currentHosts(List<dynamic> value);

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

  /// Controller for media player status updates from host.
  /// Streams play/pause/stop states as strings.
  StreamController<String> get mediaStatusController;

  /// Controller for command responses from host.
  /// Streams JSON responses to command executions.
  StreamController<Map<String, dynamic>> get commandResponseController;

  /// Controller for system notifications from host.
  /// Streams D-Bus notifications for display on mobile device.
  StreamController<Map<String, dynamic>> get notificationController;

  /// Controller for host connection state changes.
  /// Used by UI to update connection status indicators.
  StreamController<HostConnectionState> get hostStateController;
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
    with RtcMessageHandler, RtcSignaling, RtcConnection, RtcCommands {
  /// Singleton instance - only one RTC client exists per app instance.
  static final RtcClient _instance = RtcClient._internal();

  /// Factory constructor that returns the singleton instance.
  factory RtcClient() => _instance;

  /// Private constructor for singleton pattern.
  RtcClient._internal();

  // ========== CONNECTION OBJECTS ==========

  @override
  WebSocketChannel? signalingChannel;

  @override
  RTCPeerConnection? peerConnection;

  // ========== WEBRTC DATA CHANNELS ==========

  @override
  RTCDataChannel? genDC;

  @override
  RTCDataChannel? fsDC;

  @override
  RTCDataChannel? mediaDC;

  @override
  RTCDataChannel? sshDC;

  // ========== CLIENT IDENTITY ==========

  @override
  String? selfId;

  @override
  String? currentPassword;

  @override
  String? currentHostId;

  @override
  String? currentHostName;

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

  // ========== STREAM CONTROLLERS ==========

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

  /// Broadcast controller for media player status updates.
  /// Streams play/pause/stop states from the host's media player.
  @override
  final StreamController<String> mediaStatusController =
      StreamController<String>.broadcast();
  Stream<String> get mediaStatusStream => mediaStatusController.stream;

  /// Broadcast controller for responses to commands sent to the host.
  /// Includes file operations, system commands, and media controls.
  @override
  final StreamController<Map<String, dynamic>> commandResponseController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get commandResponseStream =>
      commandResponseController.stream;

  /// Broadcast controller for system notifications from the host.
  /// Receives D-Bus notifications that are displayed on the mobile device.
  @override
  final StreamController<Map<String, dynamic>> notificationController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get notificationStream =>
      notificationController.stream;

  // ========== BASE IMPLEMENTATION ==========

  /// Setter for authentication failure flag.
  /// Used by message handlers to mark auth failures.
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
    final logMsg = "[$time] $msg";
    print(logMsg);
    _logController.add(logMsg);
  }

  /// Sends a message to a specific WebRTC data channel with state validation.
  /// Includes debug logging and checks channel readiness before sending.
  @override
  void sendToChannel(RTCDataChannel? channel, String msg, String label) {
    log("DEBUG: $msg, on channel: $label");
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
}
