import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:frankn/services/audio_handler.dart';
import 'package:frankn/services/isolate_protocol.dart';
import 'package:frankn/utils/utils.dart';

class RtcThinClient {
  static final RtcThinClient _instance = RtcThinClient._internal();
  final _hostStateController =
      StreamController<HostConnectionState>.broadcast();
  final _genDcMsgStreamC = StreamController<Map<String, dynamic>>.broadcast();

  final _peerStatusController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _hostListController = StreamController<List<dynamic>>.broadcast();

  final _connectionStateController =
      StreamController<SignalConnectionState>.broadcast();
  final _logController = StreamController<String>.broadcast();

  final _notificationController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _transferProgressController =
      StreamController<Map<String, dynamic>>.broadcast();

  final _aiStreamController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _sshDataController = StreamController<Uint8List>.broadcast();

  final _authErrorController = StreamController<String>.broadcast();
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
  /// Callback to restart the foreground service from the UI Isolate.
  Future<void> Function()? onServiceRestartRequired;
  factory RtcThinClient() => _instance;

  RtcThinClient._internal();
  Stream<Map<String, dynamic>> get aiStream => _aiStreamController.stream;

  Stream<String> get authErrorStream => _authErrorController.stream;
  Stream<SignalConnectionState> get connectionStateStream =>
      _connectionStateController.stream;
  Stream<Map<String, dynamic>> get genDcMsgStream => _genDcMsgStreamC.stream;
  Stream<List<dynamic>> get hostListStream => _hostListController.stream;

  Stream<HostConnectionState> get hostStateStream =>
      _hostStateController.stream;
  Stream<IsolateMsg> get localIntentStream => _localIntentController.stream;
  Stream<String> get logStream => _logController.stream;

  Stream<Map<String, dynamic>> get notificationStream =>
      _notificationController.stream;
  Stream<Map<String, dynamic>> get peerStatusStream =>
      _peerStatusController.stream;
  Stream<Uint8List> get sshDataStream => _sshDataController.stream;

  // Mocks for DC state checks
  RTCDataChannel? get sshDC => null;

  Stream<Map<String, dynamic>> get transferProgressStream =>
      _transferProgressController.stream;

  void authenticate(String password) =>
      sendIntent(IsolateAction.authenticate, {'password': password});

  void connectToHost(String id, {String? password, String? hostName}) {
    sendIntent(IsolateAction.connectHost, {
      'id': id,
      'password': password,
      'hostName': hostName,
    });
  }

  void connectToSignaling() {
    sendIntent(IsolateAction.connectSignaling);
  }

  void disconnectFromHost() => sendIntent(IsolateAction.disconnectHost);

  List<Uint8List> drainSshEarlyBuffer() {
    return []; // Handled in background
  }

  void handleBackgroundEvent(String data) {
    try {
      final msg = IsolateMsg.fromJson(data);
      switch ((msg.type, msg.action)) {
        case (IsolateType.state, IsolateAction.hostState):
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
        case (IsolateType.state, IsolateAction.sigState):
          final stateIndex = msg.payload['state'] as int;
          sigState = SignalConnectionState.values[stateIndex];
          _connectionStateController.add(sigState);
        case (IsolateType.state, IsolateAction.syncState):
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
        case (IsolateType.state, IsolateAction.isolateReady):
          print("ThinClient: Background isolate is alive. Syncing...");
          sendIntent(IsolateAction.syncState);
        case (IsolateType.event, IsolateAction.commandResponse):
          _genDcMsgStreamC.add(msg.payload);

          // Handle UI isolate media sync to prevent background isolate crashes
          final d = msg.payload;
          if (d['type'] == MediaDCMessage.MediaUpdate) {
            try {
              final media = MediaUpdate.fromJson(d);

              Uri? artUri;
              if (media.artData != null) {
                final artStr = media.artData!;
                if (artStr.startsWith('http') || artStr.startsWith('file://')) {
                  artUri = Uri.parse(artStr);
                }
              }

              String? title;
              String? artist;
              if (media.metadata.isNotEmpty) {
                if (media.metadata.contains(" - ")) {
                  final parts = media.metadata.split(" - ");
                  title = parts[0];
                  artist = parts.length > 1 ? parts[1] : "Unknown Artist";
                } else {
                  title = media.metadata;
                  artist = "Unknown Artist";
                }
              }

              franknAudioHandler.updateMediaState(
                isPlaying: media.playing,
                title: title,
                artist: artist,
                playerName: media.playerName,
                position: Duration(microseconds: media.position.toInt()),
                duration: Duration(microseconds: media.length.toInt()),
                artUri: artUri,
                volume: media.volume,
              );
            } catch (e) {
              print("AUDIO ERROR IN UI ISOLATE: $e");
            }
          }

          if (msg.payload['type'] == DcMsg.LlmToken) {
            _aiStreamController.add(msg.payload);
          }

          // BRIDGE: If this is a stream_end, also notify the transfer progress stream
          // so that viewers (Editor/Image) know to stop loading.
          if (msg.payload['type'] == FsMsg.DownloadEnd) {
            _transferProgressController.add({
              ...msg.payload,
              'type': 'complete',
            });
          }
        case (IsolateType.event, IsolateAction.peerStatus):
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
        case (IsolateType.event, IsolateAction.hostList):
          currentHosts = msg.payload['hosts'] ?? [];
          for (var host in currentHosts) {
            if (host['host_id'] != null) {
              onlineHostIds.add(host['host_id']);
            }
          }
          _hostListController.add(currentHosts);
        case (IsolateType.event, IsolateAction.logEvent):
          final String logMsg = msg.payload['msg'];
          logHistory.add(logMsg);
          if (logHistory.length > 1000) logHistory.removeAt(0);
          _logController.add(logMsg);
        case (IsolateType.event, IsolateAction.notification):
          _notificationController.add(msg.payload);
        case (IsolateType.event, IsolateAction.transferProgress):
          _transferProgressController.add(msg.payload);
        case (IsolateType.event, IsolateAction.transferComplete):
          _transferProgressController.add({...msg.payload, 'type': 'complete'});
        case (IsolateType.event, IsolateAction.downloadStart):
          _transferProgressController.add({...msg.payload, 'type': 'start'});
        case (IsolateType.event, IsolateAction.downloadEnd):
          _transferProgressController.add({...msg.payload, 'type': 'complete'});
        case (IsolateType.event, IsolateAction.transferFailed):
          _transferProgressController.add({...msg.payload, 'type': 'failed'});
        case (IsolateType.event, IsolateAction.sshOutput):
          _sshDataController.add(base64Decode(msg.payload['data']));
        case (IsolateType.event, IsolateAction.authFailed):
          _authErrorController.add(
            msg.payload['error'] ?? 'AUTHENTICATION_FAILED',
          );
        case (IsolateType.event, IsolateAction.authSuccess):
          _authErrorController.add('SUCCESS');
      }
    } catch (e) {
      print("ThinClient parse error: $e");
    }
  }

  void log(String msg) {
    sendIntent(IsolateAction.logIntent, {'msg': msg});
  }

  void requestHostList() => sendIntent(IsolateAction.requestHostList);

  void sendDcMsg(Map<String, dynamic> cmd) => sendIntent(IsolateAction.sendDcMsg, cmd);

  void sendDownloadInit({
    required String id,
    required String path,
    int resumeOffset = 0,
    String? targetDir,
    bool showNotification = true,
  }) {
    sendIntent(IsolateAction.downloadInit, {
      'id': id,
      'path': path,
      'resume_offset': resumeOffset,
      'target_dir': targetDir,
      'show_notification': showNotification,
    });
  }

  void sendInputMsg(Map<String, dynamic> msg) {
    if (currentHostState != HostConnectionState.authenticated) return;
    sendIntent(IsolateAction.sendInput, msg);
  }

  void sendIntent(
    String action, [
    Map<String, dynamic> payload = const {},
  ]) async {
    final msg = IsolateMsg(type: IsolateType.intent, action: action, payload: payload);
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

  void sendSshInput(Uint8List data) {
    sendIntent(IsolateAction.sshInput, {'data': base64Encode(data)});
  }

  void setIsBackground(bool value) => _isBackground = value;

  void startSsh() => sendIntent(IsolateAction.startSsh);

  void stopSsh() => sendIntent(IsolateAction.stopSsh);
}
