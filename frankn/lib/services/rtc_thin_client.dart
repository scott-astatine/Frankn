import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:frankn/services/audio_handler.dart';
import 'package:frankn/services/isolate_protocol.dart';
import 'package:frankn/utils/utils.dart';
import 'package:frankn/utils/dc_msg_util.dart';

class RtcThinClient {
  static final RtcThinClient _instance = RtcThinClient._internal();
  final _hostStateController =
      StreamController<HostConnectionState>.broadcast();
  final _genDcMsgStreamC = StreamController<HostMessage>.broadcast();

  final _peerStatusController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _hostListController = StreamController<List<dynamic>>.broadcast();

  final _connectionStateController =
      StreamController<SignalConnectionState>.broadcast();
  final _logController = StreamController<String>.broadcast();

  final _notificationController =
      StreamController<HostMsgNotification>.broadcast();
  final _transferProgressController =
      StreamController<TransferProgressEvent>.broadcast();

  final _aiStreamController =
      StreamController<HostMsgLlmToken>.broadcast();
  final _sshDataController = StreamController<Uint8List>.broadcast();
  final _syncSnapshotController =
      StreamController<HostMsgSyncSnapshot>.broadcast();
  final _syncBatchProgressController =
      StreamController<SyncBatchProgressEvent>.broadcast();
  final _syncStatusController =
      StreamController<SyncStatusEvent>.broadcast();

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
  Stream<HostMsgLlmToken> get aiStream => _aiStreamController.stream;

  Stream<String> get authErrorStream => _authErrorController.stream;
  Stream<SignalConnectionState> get connectionStateStream =>
      _connectionStateController.stream;
  Stream<HostMessage> get genDcMsgStream => _genDcMsgStreamC.stream;
  Stream<List<dynamic>> get hostListStream => _hostListController.stream;

  Stream<HostConnectionState> get hostStateStream =>
      _hostStateController.stream;
  Stream<IsolateMsg> get localIntentStream => _localIntentController.stream;
  Stream<String> get logStream => _logController.stream;

  Stream<HostMsgNotification> get notificationStream =>
      _notificationController.stream;
  Stream<Map<String, dynamic>> get peerStatusStream =>
      _peerStatusController.stream;
  Stream<Uint8List> get sshDataStream => _sshDataController.stream;
  Stream<HostMsgSyncSnapshot> get syncSnapshotStream {
    final myId = identityHashCode(this);
    log("SYNC_DEBUG[$myId]: syncSnapshotStream getter called.");
    return _syncSnapshotController.stream;
  }
  Stream<SyncBatchProgressEvent> get syncBatchProgressStream =>
      _syncBatchProgressController.stream;

  Stream<SyncStatusEvent> get syncStatusStream =>
      _syncStatusController.stream;

  // Mocks for DC state checks
  RTCDataChannel? get sshDC => null;

  Stream<TransferProgressEvent> get transferProgressStream =>
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
      handleMsg(msg);
    } catch (e) {
      print("ThinClient parse error: $e");
    }
  }

  void handleMsg(IsolateMsg msg) {
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
        final hostMsg = HostMessage.fromJson(msg.payload);
        _genDcMsgStreamC.add(hostMsg);

        // Handle UI isolate media sync to prevent background isolate crashes
        if (hostMsg is HostMsgMediaUpdate) {
          try {
            final media = hostMsg;

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

            franknAudioHandlerInstance?.updateMediaState(
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

        if (msg.payload['type'] == 'llm_token') {
          _aiStreamController.add(HostMsgLlmToken.fromJson(msg.payload));
        }

        // BRIDGE: If this is a stream_end, also notify the transfer progress stream
        // so that viewers (Editor/Image) know to stop loading.
        if (msg.payload['type'] == 'download_end') {
          _transferProgressController.add(TransferProgressComplete(
            id: msg.payload['id'] ?? 'unknown',
          ));
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
        _notificationController.add(HostMsgNotification.fromJson(msg.payload));
      case (IsolateType.event, IsolateAction.transferProgress):
        _transferProgressController.add(TransferProgressEvent.fromJson(msg.payload));
      case (IsolateType.event, IsolateAction.transferComplete):
        _transferProgressController.add(TransferProgressComplete(
            id: msg.payload['id'],
            finalPath: msg.payload['target_path'],
            fileName: msg.payload['file_name'],
        ));
      case (IsolateType.event, IsolateAction.downloadStart):
        _transferProgressController.add(TransferProgressStart(msg.payload['id']));
      case (IsolateType.event, IsolateAction.downloadEnd):
        _transferProgressController.add(TransferProgressComplete(id: msg.payload['id']));
      case (IsolateType.event, IsolateAction.transferFailed):
        _transferProgressController.add(TransferProgressFailed(
            id: msg.payload['id'],
            error: msg.payload['error'] ?? 'Transfer failed',
        ));
      case (IsolateType.event, IsolateAction.sshOutput):
        _sshDataController.add(base64Decode(msg.payload['data']));
      case (IsolateType.event, IsolateAction.folderSyncSnapshot):
        log(
          "SYNC_DEBUG[${identityHashCode(this)}]: Pushing snapshot to controller for ${msg.payload['root_path']}",
        );
        _syncSnapshotController.add(HostMsgSyncSnapshot.fromJson(msg.payload));
      case (IsolateType.event, IsolateAction.syncBatchProgress):
        _syncBatchProgressController.add(SyncBatchProgressEvent.fromJson(msg.payload));
      case (IsolateType.event, IsolateAction.syncStatusUpdate):
        _syncStatusController.add(SyncStatusEvent.fromJson(msg.payload));
      case (IsolateType.event, IsolateAction.authFailed):
        _authErrorController.add(
          msg.payload['error'] ?? 'AUTHENTICATION_FAILED',
        );
      case (IsolateType.event, IsolateAction.authSuccess):
        _authErrorController.add('SUCCESS');
    }
  }

  void log(String msg) {
    sendIntent(IsolateAction.logIntent, {'msg': msg});
  }

  void requestHostList() => sendIntent(IsolateAction.requestHostList);

  void sendDcMsg(DcMsg cmd) =>
      sendIntent(IsolateAction.sendDcMsg, cmd.toJson());

  void sendEvent(String action, [Map<String, dynamic> payload = const {}]) {
    if (!_isBackground) return;
    final msg = IsolateMsg(
      type: IsolateType.event,
      action: action,
      payload: payload,
    );
    _broadcastToMain(msg);
  }

  void _broadcastToMain(IsolateMsg msg) {
    FlutterForegroundTask.sendDataToMain(msg.toJson());
  }

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
    final msg = IsolateMsg(
      type: IsolateType.intent,
      action: action,
      payload: payload,
    );
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
