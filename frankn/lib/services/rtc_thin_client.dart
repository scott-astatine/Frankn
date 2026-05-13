import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:frankn/services/isolate_protocol.dart';
import 'package:frankn/services/audio_handler.dart';
import 'package:frankn/utils/utils.dart';

class RtcThinClient {
  static final RtcThinClient _instance = RtcThinClient._internal();
  factory RtcThinClient() => _instance;
  RtcThinClient._internal();

  final _hostStateController =
      StreamController<HostConnectionState>.broadcast();
  Stream<HostConnectionState> get hostStateStream =>
      _hostStateController.stream;

  final _commandResponseController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get commandResponseStream =>
      _commandResponseController.stream;

  final _peerStatusController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get peerStatusStream =>
      _peerStatusController.stream;

  final _hostListController = StreamController<List<dynamic>>.broadcast();
  Stream<List<dynamic>> get hostListStream => _hostListController.stream;

  final _connectionStateController =
      StreamController<SignalConnectionState>.broadcast();
  Stream<SignalConnectionState> get connectionStateStream =>
      _connectionStateController.stream;

  final _logController = StreamController<String>.broadcast();
  Stream<String> get logStream => _logController.stream;

  final _notificationController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get notificationStream =>
      _notificationController.stream;
  final _transferProgressController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get transferProgressStream =>
      _transferProgressController.stream;

  final _aiStreamController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get aiStream => _aiStreamController.stream;

  final _sshDataController = StreamController<Uint8List>.broadcast();
  Stream<Uint8List> get sshDataStream => _sshDataController.stream;

  final _authErrorController = StreamController<String>.broadcast();
  Stream<String> get authErrorStream => _authErrorController.stream;

  HostConnectionState currentHostState = HostConnectionState.disconnected;
  SignalConnectionState sigState = SignalConnectionState.disconnected;
  String? currentHostId;
  String? currentHostName;
  String? currentPassword;

  // Temporary in-memory storage for SSH credentials
  String? lastSshUsername;
  String? lastSshPassword;

  Set<String> onlineHostIds = {};
  List<dynamic> currentHosts = [];
  List<String> logHistory = [];
  Map<String, String> activeFileNames = {};

  bool isAuthFailed = false;
  bool isIntentionalDisconnect = false;
  DateTime? firstDisconnectTime;

  // New: Bridge for intents originating from within the background isolate
  bool _isBackground = false;
  final _localIntentController = StreamController<IsolateMsg>.broadcast();
  Stream<IsolateMsg> get localIntentStream => _localIntentController.stream;

  void setIsBackground(bool value) => _isBackground = value;

  /// Callback to restart the foreground service from the UI Isolate.
  Future<void> Function()? onServiceRestartRequired;

  void sendIntent(
    String action, [
    Map<String, dynamic> payload = const {},
  ]) async {
    final msg = IsolateMsg(type: 'intent', action: action, payload: payload);
    if (_isBackground) {
      _localIntentController.add(msg);
    } else {
      // Ensure the background service is running before sending intents
      if (!(await FlutterForegroundTask.isRunningService)) {
        if (onServiceRestartRequired != null) {
          print("ThinClient: Restarting background service...");
          await onServiceRestartRequired!();

          // Wait a bit for the isolate to boot
          int retries = 0;
          while (!(await FlutterForegroundTask.isRunningService) &&
              retries < 10) {
            await Future.delayed(const Duration(milliseconds: 200));
            retries++;
          }
        }
      }
      FlutterForegroundTask.sendDataToTask(msg.toJson());
    }
  }

  void handleBackgroundEvent(String data) {
    try {
      final msg = IsolateMsg.fromJson(data);
      if (msg.type == 'state') {
        if (msg.action == 'host_state') {
          final stateIndex = msg.payload['state'] as int;
          currentHostState = HostConnectionState.values[stateIndex];
          if (currentHostState == HostConnectionState.disconnected ||
              currentHostState == HostConnectionState.failed) {
            lastSshUsername = null;
            lastSshPassword = null;
          }
          currentHostId = msg.payload['id'];
          currentHostName = msg.payload['name'];
          _hostStateController.add(currentHostState);
        } else if (msg.action == 'sig_state') {
          final stateIndex = msg.payload['state'] as int;
          sigState = SignalConnectionState.values[stateIndex];
          _connectionStateController.add(sigState);
        } else if (msg.action == 'sync_state') {
          // full sync
          if (msg.payload['host_state'] != null) {
            currentHostState =
                HostConnectionState.values[msg.payload['host_state'] as int];
          }
          if (msg.payload['sig_state'] != null) {
            sigState =
                SignalConnectionState.values[msg.payload['sig_state'] as int];
          }
          currentHostId = msg.payload['host_id'];
          currentHostName = msg.payload['host_name'];
          if (msg.payload['online_hosts'] != null) {
            onlineHostIds = Set<String>.from(msg.payload['online_hosts']);
          }
          if (msg.payload['current_hosts'] != null) {
            currentHosts = List<dynamic>.from(msg.payload['current_hosts']);
            _hostListController.add(currentHosts);
          }
        } else if (msg.action == 'isolate_ready') {
          print("ThinClient: Background isolate is alive. Syncing...");
          sendIntent('sync_state');
        }
      } else if (msg.type == 'event') {
        if (msg.action == 'command_response') {
          _commandResponseController.add(msg.payload);

          // Handle UI isolate media sync to prevent background isolate crashes
          final d = msg.payload;
          if (d['type'] == 'media_update' ||
              d['media_status'] != null ||
              d['metadata'] != null) {
            String? status = d['media_status'] ?? d['status'];
            String? metadata = d['metadata'];
            String? playerName = d['player_name'];
            double? volume = d['volume'] != null
                ? (d['volume'] as num).toDouble()
                : null;
            Duration? position;
            Duration? length;
            Uri? artUri;

            if (d['position'] != null) {
              position = Duration(microseconds: (d['position'] as num).toInt());
            }
            if (d['length'] != null) {
              length = Duration(microseconds: (d['length'] as num).toInt());
            }
            if (d['art_data'] != null) {
              final artStr = d['art_data'] as String;
              if (artStr.startsWith('http')) {
                artUri = Uri.parse(artStr);
              } else if (artStr.startsWith('file://')) {
                artUri = Uri.parse(artStr);
              }
            }

            String? title;
            String? artist;
            if (metadata != null && metadata.isNotEmpty) {
              if (metadata.contains(" - ")) {
                final parts = metadata.split(" - ");
                title = parts[0];
                artist = parts.length > 1 ? parts[1] : "Unknown Artist";
              } else {
                title = metadata;
                artist = "Unknown Artist";
              }
            }

            try {
              if (volume != null) {
                _volumeController.add(volume);
              }
              franknAudioHandler.updateMediaState(
                status: status,
                title: title,
                artist: artist,
                playerName: playerName,
                position: position,
                duration: length,
                artUri: artUri,
                volume: volume,
              );
            } catch (e) {
              print("AUDIO ERROR IN UI ISOLATE: $e");
            }
          }

          if (msg.payload['type'] == DcMsg.LlmToken ||
              msg.payload['type'] == 'llm_token') {
            _aiStreamController.add(msg.payload);
          }

          // BRIDGE: If this is a stream_end, also notify the transfer progress stream
          // so that viewers (Editor/Image) know to stop loading.
          if (msg.payload['type'] == DcMsg.StreamEnd ||
              msg.payload['type'] == 'download_end') {
            _transferProgressController.add({
              ...msg.payload,
              'type': 'complete',
            });
          }
        } else if (msg.action == 'peer_status') {
          final id = msg.payload['peer_id'];
          final isOnline = msg.payload['online'] as bool?;
          if (id != null && isOnline != null) {
            if (isOnline) {
              onlineHostIds.add(id);
            } else {
              onlineHostIds.remove(id);
            }
          }
          _peerStatusController.add(msg.payload);
        } else if (msg.action == 'host_list') {
          currentHosts = msg.payload['hosts'] ?? [];
          for (var host in currentHosts) {
            if (host['host_id'] != null) {
              onlineHostIds.add(host['host_id']);
            }
          }
          _hostListController.add(currentHosts);
        } else if (msg.action == 'log') {
          final String logMsg = msg.payload['msg'];
          logHistory.add(logMsg);
          if (logHistory.length > 1000) logHistory.removeAt(0);
          _logController.add(logMsg);
        } else if (msg.action == 'notification') {
          _notificationController.add(msg.payload);
        } else if (msg.action == 'transfer_progress') {
          _transferProgressController.add(msg.payload);
        } else if (msg.action == 'transfer_complete') {
          _transferProgressController.add({...msg.payload, 'type': 'complete'});
        } else if (msg.action == 'download_start') {
          _transferProgressController.add({...msg.payload, 'type': 'start'});
        } else if (msg.action == 'download_end') {
          _transferProgressController.add({...msg.payload, 'type': 'complete'});
        } else if (msg.action == 'transfer_failed') {
          _transferProgressController.add({...msg.payload, 'type': 'failed'});
        } else if (msg.action == 'ssh_output') {
          _sshDataController.add(base64Decode(msg.payload['data']));
        } else if (msg.action == 'auth_failed') {
          _authErrorController.add(
            msg.payload['error'] ?? 'AUTHENTICATION_FAILED',
          );
        } else if (msg.action == 'auth_success') {
          _authErrorController.add('SUCCESS');
        }
      }
    } catch (e) {
      print("ThinClient parse error: $e");
    }
  }

  void log(String msg) {
    sendIntent('log', {'msg': msg});
  }

  void connectToSignaling() {
    sendIntent('connect_signaling');
  }

  void connectToHost(String id, {String? password, String? hostName}) {
    sendIntent('connect_host', {
      'id': id,
      'password': password,
      'hostName': hostName,
    });
  }

  void disconnectFromHost() => sendIntent('disconnect_host');

  void sendDcMsg(Map<String, dynamic> cmd) => sendIntent('send_dc_msg', cmd);

  void sendInputMsg(Map<String, dynamic> msg) {
    if (currentHostState != HostConnectionState.authenticated) return;
    sendIntent('send_input', msg);
  }

  void sendDownloadInit({
    required String id,
    required String path,
    int resumeOffset = 0,
    String? targetDir,
    bool showNotification = true,
  }) {
    sendIntent('download_init', {
      'id': id,
      'path': path,
      'resume_offset': resumeOffset,
      'target_dir': targetDir,
      'show_notification': showNotification,
    });
  }

  void authenticate(String password) =>
      sendIntent('authenticate', {'password': password});

  void sendSshInput(Uint8List data) {
    sendIntent('ssh_input', {'data': base64Encode(data)});
  }

  void startSsh() => sendIntent('start_ssh');

  void stopSsh() => sendIntent('stop_ssh');

  void requestHostList() => sendIntent('request_host_list');

  List<Uint8List> drainSshEarlyBuffer() {
    return []; // Handled in background
  }

  // Mocks for DC state checks
  RTCDataChannel? get sshDC => null;
}
