import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:frankn/services/client_rtc/rtc.dart';
import 'package:frankn/services/isolate_protocol.dart';
import 'package:frankn/services/notification_service.dart';
import 'package:frankn/services/rtc_thin_client.dart';
import 'package:frankn/services/settings_service.dart';
import 'package:frankn/services/transfer_engine.dart';
import 'package:frankn/utils/utils.dart';
import 'package:path_provider/path_provider.dart';

class FranknTaskHandler extends TaskHandler {
  @override
  Future<void> onDestroy(DateTime timestamp, bool? sendPort) async {
    print('Background Isolate: DESTROYED');
  }

  @override
  void onNotificationButtonPressed(String id) {
    if (id == 'disconnect') {
      RtcClient().sendDcMsg({DcMsg.Key: DcMsg.Disconnect});
      RtcClient().disconnectFromHost();
    }
  }

  @override
  void onNotificationPressed() {
    FlutterForegroundTask.launchApp();
  }

  @override
  void onReceiveData(Object data) {
    if (data is String) {
      if (data == 'disconnect_intent') {
        RtcClient().sendDcMsg({DcMsg.Key: DcMsg.Disconnect});
        RtcClient().disconnectFromHost();
        return;
      }

      try {
        final msg = IsolateMsg.fromJson(data);
        // print("Background Isolate: Received Intent: \${msg.action}");

        if (msg.type == IsolateType.intent) {
          _handleIntent(msg);
        }
      } catch (e) {
        print("Background Isolate: RX_PARSE_ERROR: \$e");
      }
    }
  }

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    print("Background Isolate: BOOTING...");
    try {
      DartPluginRegistrant.ensureInitialized();
      WidgetsFlutterBinding.ensureInitialized();

      await SettingsService().initialize();
      globalTempDir = await getTemporaryDirectory();

      // Ensure ThinClient knows it's in the background so AudioHandler can route correctly
      RtcThinClient().setIsBackground(true);

      // Listen for intents originating from within the background isolate (AudioHandler)
      RtcThinClient().localIntentStream.listen((msg) => _handleIntent(msg));

      // Re-sync host name in memory so AudioHandler picks it up
      RtcClient().currentHostName = SettingsService().savedHosts.isNotEmpty
          ? SettingsService().savedHosts.first['name']
          : null;

      await NotificationService().initialize(requestPermissions: false);

      print("Background Isolate: SERVICES_READY");

      RtcClient().hostStateController.stream.listen((state) {
        // MIRROR state to local background proxy so AudioHandler is not 'blind'
        RtcThinClient().currentHostState = state;
        RtcThinClient().currentHostId = RtcClient().currentHostId;
        RtcThinClient().currentHostName = RtcClient().currentHostName;

        if (state == HostConnectionState.disconnected &&
            RtcClient().isAuthFailed) {
          _broadcastToMain(
            IsolateMsg(
              type: IsolateType.event,
              action: IsolateAction.authFailed,
              payload: {'error': 'AUTHENTICATION_REJECTED'},
            ),
          );
        } else if (state == HostConnectionState.failed) {
          _broadcastToMain(
            IsolateMsg(
              type: IsolateType.event,
              action: IsolateAction.authFailed,
              payload: {'error': 'CONNECTION_FAILED'},
            ),
          );
        }

        if (state == HostConnectionState.authenticated) {
          _broadcastToMain(
            IsolateMsg(
              type: IsolateType.event,
              action: IsolateAction.authSuccess,
            ),
          );
        }

        _broadcastToMain(
          IsolateMsg(
            type: IsolateType.state,
            action: IsolateAction.hostState,
            payload: {
              'state': state.index,
              'id': RtcClient().currentHostId,
              'name': RtcClient().currentHostName,
            },
          ),
        );
      });

      RtcClient().genDcMsgStream.listen((data) {
        _broadcastToMain(
          IsolateMsg(
            type: IsolateType.event,
            action: IsolateAction.commandResponse,
            payload: data,
          ),
        );
      });

      RtcClient().connectionStateStream.listen((state) {
        _broadcastToMain(
          IsolateMsg(
            type: IsolateType.state,
            action: IsolateAction.sigState,
            payload: {'state': state.index},
          ),
        );
      });

      RtcClient().peerStatusStream.listen((data) {
        _broadcastToMain(
          IsolateMsg(
            type: IsolateType.event,
            action: IsolateAction.peerStatus,
            payload: data,
          ),
        );
      });

      RtcClient().hostListStream.listen((hosts) {
        _broadcastToMain(
          IsolateMsg(
            type: IsolateType.event,
            action: IsolateAction.hostList,
            payload: {'hosts': hosts},
          ),
        );
      });

      RtcClient().logStream.listen((logMsg) {
        _broadcastToMain(
          IsolateMsg(
            type: IsolateType.event,
            action: IsolateAction.logEvent,
            payload: {'msg': logMsg},
          ),
        );
      });

      RtcClient().notificationStream.listen((data) {
        _broadcastToMain(
          IsolateMsg(
            type: IsolateType.event,
            action: IsolateAction.notification,
            payload: data,
          ),
        );
      });

      RtcClient().sshDataStream.listen((data) {
        _broadcastToMain(
          IsolateMsg(
            type: IsolateType.event,
            action: IsolateAction.sshOutput,
            payload: {'data': base64Encode(data)},
          ),
        );
      });

      RtcClient().syncSnapshotStream.listen((data) {
        _broadcastToMain(
          IsolateMsg(
            type: IsolateType.event,
            action: IsolateAction.folderSyncSnapshot,
            payload: data,
          ),
        );
      });

      print("Background Isolate: SIGNALING_READY");
      _broadcastToMain(
        IsolateMsg(type: IsolateType.state, action: IsolateAction.isolateReady),
      );

      syncState();

      // Auto-connect once ready
      RtcClient().connectToSignaling();
    } catch (e, stack) {
      print("Background Isolate: CRITICAL_ERROR: \$e");
      print(stack);
    }
  }

  void syncState() {
    _broadcastToMain(
      IsolateMsg(
        type: IsolateType.state,
        action: IsolateAction.syncState,
        payload: {
          'host_state': RtcClient().currentHostState.index,
          'sig_state': RtcClient().sigState.index,
          'host_id': RtcClient().currentHostId,
          'host_name': RtcClient().currentHostName,
          'online_hosts': RtcClient().onlineHostIds.toList(),
          'current_hosts': RtcClient().currentHosts,
        },
      ),
    );
  }

  void _broadcastToMain(IsolateMsg msg) {
    FlutterForegroundTask.sendDataToMain(msg.toJson());
  }

  void _handleUploadInit(IsolateMsg msg) {
    final engine = TransferEngine(RtcClient());
    final id = msg.payload['id'];
    final fileName = msg.payload['file_name'];
    engine
        .upload(
          id: id,
          remotePath: msg.payload['remote_path'],
          file: File(msg.payload['local_path']),
          hash: msg.payload['hash'],
          onProgress:
              ({
                required progress,
                required bytesTransferred,
                required totalBytes,
              }) {
                _broadcastToMain(
                  IsolateMsg(
                    type: IsolateType.event,
                    action: IsolateAction.transferProgress,
                    payload: {
                      'id': id,
                      'progress': progress,
                      'bytes_transferred': bytesTransferred,
                      'total_bytes': totalBytes,
                    },
                  ),
                );

                if (bytesTransferred % (1024 * 1024) < 61440 ||
                    bytesTransferred == totalBytes) {
                  NotificationService().showProgressNotification(
                    id.hashCode.abs() % 100000,
                    "Uploading '$fileName'...",
                    "${(progress * 100).toStringAsFixed(1)}%",
                    progress * 100,
                  );
                }
              },
        )
        .then((_) {
          engine.dispose();
          _broadcastToMain(
            IsolateMsg(
              type: IsolateType.event,
              action: IsolateAction.transferComplete,
              payload: {'id': id, 'target_path': msg.payload['remote_path']},
            ),
          );
          NotificationService().showProgressNotification(
            id.hashCode.abs() % 100000,
            "Upload Complete",
            "'$fileName' uploaded successfully.",
            100.0,
          );
        })
        .catchError((e) {
          engine.dispose();
          _broadcastToMain(
            IsolateMsg(
              type: IsolateType.event,
              action: IsolateAction.transferFailed,
              payload: {'id': id, 'error': e.toString()},
            ),
          );
          NotificationService().showProgressNotification(
            id.hashCode.abs() % 100000,
            "Upload Failed",
            "'$fileName' failed to upload.",
            100.0,
          );
        });
  }

  void _handleIntent(IsolateMsg msg) {
    switch (msg.action) {
      case IsolateAction.connectSignaling:
        RtcClient().connectToSignaling();
        break;
      case IsolateAction.connectHost:
        RtcClient().connectToHost(
          msg.payload['id'],
          password: msg.payload['password'],
          hostName: msg.payload['hostName'],
        );
        break;
      case IsolateAction.disconnectHost:
        RtcClient().disconnectFromHost();
        break;
      case IsolateAction.sendDcMsg:
        RtcClient().sendDcMsg(msg.payload);
        break;
      case IsolateAction.sendInput:
        RtcClient().sendInputMsg(msg.payload);
        break;
      case IsolateAction.downloadInit:
        RtcClient().downloadTargetDirs[msg.payload['id']] =
            msg.payload['target_dir'] ?? '';
        RtcClient().showNotificationMap[msg.payload['id']] =
            msg.payload['show_notification'] ?? true;
        RtcClient().sendDownloadInit(
          id: msg.payload['id'],
          path: msg.payload['path'],
          resumeOffset: msg.payload['resume_offset'] ?? 0,
        );
        break;
      case IsolateAction.authenticate:
        RtcClient().authenticate(msg.payload['password']);
        break;
      case IsolateAction.sshInput:
        if (RtcClient().sshDC?.state ==
            RTCDataChannelState.RTCDataChannelOpen) {
          RtcClient().sshDC!.send(
            RTCDataChannelMessage.fromBinary(base64Decode(msg.payload['data'])),
          );
        }
        break;
      case IsolateAction.startSsh:
        RtcClient().startSsh();
        break;
      case IsolateAction.stopSsh:
        RtcClient().stopSsh();
        break;
      case IsolateAction.requestHostList:
        RtcClient().requestHostList();
        break;
      case IsolateAction.syncState:
        syncState();
        break;
      case IsolateAction.uploadInit:
        _handleUploadInit(msg);
        break;
    }
  }
}
