import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:frankn/services/client_rtc/rtc.dart';
import 'package:frankn/services/isolate_protocol.dart';
import 'package:frankn/services/notification_service.dart';
import 'package:frankn/services/rtc_thin_client.dart';
import 'package:frankn/services/settings_service.dart';
import 'package:frankn/services/sync_service.dart';
import 'package:frankn/services/transfer_engine.dart';
import 'package:frankn/utils/utils.dart';
import 'package:frankn/utils/dc_msg_util.dart';
import 'package:path_provider/path_provider.dart';

class FranknTaskHandler extends TaskHandler {
  static final Map<String, TransferEngine> _activeEngines = {};
  static final Map<String, int> _uploadStartTimes = {};
  static final Map<String, int> _lastUploadNotificationTimes = {};

  @override
  Future<void> onDestroy(DateTime timestamp, bool? sendPort) async {
    print('Background Isolate: DESTROYED');
  }

  @override
  void onNotificationButtonPressed(String id) {
    if (id == 'disconnect') {
      RtcClient().sendDcMsg(const DcMsgDisconnect());
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
        RtcClient().sendDcMsg(const DcMsgDisconnect());
        RtcClient().disconnectFromHost();
        return;
      }

      try {
        final msg = IsolateMsg.fromJson(data);
        // print("Background Isolate: Received Intent: ${msg.payload.toString()}");

        if (msg.type == IsolateType.intent) {
          _handleIntent(msg);
        }
      } catch (e) {
        print("Background Isolate: RX_PARSE_ERROR: $e");
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

        final msg = IsolateMsg(
          type: IsolateType.state,
          action: IsolateAction.hostState,
          payload: {
            'state': state.index,
            'id': RtcClient().currentHostId,
            'name': RtcClient().currentHostName,
          },
        );

        if (state == HostConnectionState.disconnected &&
            RtcClient().isAuthFailed) {
          final err = IsolateMsg(
            type: IsolateType.event,
            action: IsolateAction.authFailed,
            payload: {'error': 'AUTHENTICATION_REJECTED'},
          );
          _broadcastToMain(err);
          RtcThinClient().handleMsg(err);
        } else if (state == HostConnectionState.failed) {
          final err = IsolateMsg(
            type: IsolateType.event,
            action: IsolateAction.authFailed,
            payload: {'error': 'CONNECTION_FAILED'},
          );
          _broadcastToMain(err);
          RtcThinClient().handleMsg(err);
        }

        if (state == HostConnectionState.authenticated) {
          final ok = IsolateMsg(
            type: IsolateType.event,
            action: IsolateAction.authSuccess,
          );
          _broadcastToMain(ok);
          RtcThinClient().handleMsg(ok);

          // VERIFIER: Trigger sync status check for all pairs on successful authentication
          Future.delayed(const Duration(seconds: 2), () async {
            await SettingsService().reload();
            final pairs = SettingsService().syncPairs;
            for (final pair in pairs) {
              SyncService().checkSyncStatus(pair);
            }
          });
        }

        _broadcastToMain(msg);
        RtcThinClient().handleMsg(msg);
      });

      RtcClient().genDcMsgStream.listen((msg) {
        final isolateMsg = IsolateMsg(
          type: IsolateType.event,
          action: IsolateAction.commandResponse,
          payload: msg.toJson(),
        );
        _broadcastToMain(isolateMsg);
        RtcThinClient().handleMsg(isolateMsg);
      });

      RtcClient().connectionStateStream.listen((state) {
        final msg = IsolateMsg(
          type: IsolateType.state,
          action: IsolateAction.sigState,
          payload: {'state': state.index},
        );
        _broadcastToMain(msg);
        RtcThinClient().handleMsg(msg);
      });

      RtcClient().peerStatusStream.listen((data) {
        final msg = IsolateMsg(
          type: IsolateType.event,
          action: IsolateAction.peerStatus,
          payload: data,
        );
        _broadcastToMain(msg);
        RtcThinClient().handleMsg(msg);
      });

      RtcClient().hostListStream.listen((hosts) {
        final msg = IsolateMsg(
          type: IsolateType.event,
          action: IsolateAction.hostList,
          payload: {'hosts': hosts},
        );
        _broadcastToMain(msg);
        RtcThinClient().handleMsg(msg);
      });

      RtcClient().logStream.listen((logMsg) {
        final msg = IsolateMsg(
          type: IsolateType.event,
          action: IsolateAction.logEvent,
          payload: {'msg': logMsg},
        );
        _broadcastToMain(msg);
        RtcThinClient().handleMsg(msg);
      });

      RtcClient().notificationStream.listen((msg) {
        final isolateMsg = IsolateMsg(
          type: IsolateType.event,
          action: IsolateAction.notification,
          payload: msg.toJson(),
        );
        _broadcastToMain(isolateMsg);
        RtcThinClient().handleMsg(isolateMsg);
      });

      RtcClient().sshDataStream.listen((data) {
        final msg = IsolateMsg(
          type: IsolateType.event,
          action: IsolateAction.sshOutput,
          payload: {'data': base64Encode(data)},
        );
        _broadcastToMain(msg);
        RtcThinClient().handleMsg(msg);
      });

      RtcClient().syncSnapshotStream.listen((msg) {
        final isolateMsg = IsolateMsg(
          type: IsolateType.event,
          action: IsolateAction.folderSyncSnapshot,
          payload: msg.toJson(),
        );
        _broadcastToMain(isolateMsg);
        RtcThinClient().handleMsg(isolateMsg);
      });

      RtcClient().transferProgressStream.listen((event) {
        final msg = IsolateMsg(
          type: IsolateType.event,
          action: IsolateAction.transferProgress,
          payload: event.toJson(),
        );
        _broadcastToMain(msg);
        RtcThinClient().handleMsg(msg);
      });

      print("Background Isolate: SIGNALING_READY");
      _broadcastToMain(
        IsolateMsg(type: IsolateType.state, action: IsolateAction.isolateReady),
      );

      syncState();

      // Auto-connect once ready
      RtcClient().connectToSignaling();

      // Start Background Sync Scheduler
      Timer.periodic(const Duration(minutes: 1), (timer) async {
        if (RtcClient().currentHostState != HostConnectionState.authenticated) {
          return;
        }

        final pairs = SettingsService().syncPairs;
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

        for (final pair in pairs) {
          final lastSync = pair.lastSynced ?? 0;
          final elapsed = (now - lastSync) / 60;

          if (elapsed >= pair.intervalMinutes) {
            print("BG_SCHEDULER: Triggering sync for ${pair.localPath}");
            SyncService().performFullSync(pair);
          }
        }
      });
    } catch (e, stack) {
      print("Background Isolate: CRITICAL_ERROR: $e");
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
    _activeEngines[id] = engine;
    final fileName = msg.payload['file_name'];
    final localPath = msg.payload['local_path'];
    final bool showNotif = msg.payload['show_notification'] ?? true;

    _uploadStartTimes[id] = DateTime.now().millisecondsSinceEpoch;

    // Show initial notification if requested
    if (showNotif) {
       final file = File(localPath);
       if (file.existsSync()) {
          final size = file.lengthSync();
          NotificationService().showProgressNotification(
            id.hashCode.abs() % 100000,
            "⇧ [UPLD_RUN] // 0.0% Completed [□□□□□□□□□□]",
            "⇄ 0 B/s  |  ⧗ Calculating...  |  ⛃ 0 B / ${FileUtils.formatSize(size)}",
            0.0,
            transferId: id,
          );
       }
    }

    // Check for existing partial file to enable resume
    int resumeOffset = 0;
    // Note: We don't have a reliable way to track local partials for uploads yet, 
    // but the engine supports it if passed. 
    // For now, resumeOffset is 0.

    engine
        .upload(
          id: id,
          remotePath: msg.payload['remote_path'],
          file: File(localPath),
          hash: msg.payload['hash'],
          resumeOffset: resumeOffset,
          onProgress:
              ({
                required progress,
                required bytesTransferred,
                required totalBytes,
              }) {
                final progMsg = IsolateMsg(
                  type: IsolateType.event,
                  action: IsolateAction.transferProgress,
                  payload: TransferProgressUpdate(
                    id: id,
                    progress: progress,
                    bytesSent: bytesTransferred,
                    totalBytes: totalBytes,
                  ).toJson(),
                );
                _broadcastToMain(progMsg);
                RtcThinClient().handleMsg(progMsg);

                if (showNotif) {
                  final now = DateTime.now().millisecondsSinceEpoch;
                  final lastUpdate = _lastUploadNotificationTimes[id] ?? 0;
                  final isComplete = bytesTransferred == totalBytes;

                  if (isComplete || now - lastUpdate > 500) {
                    _lastUploadNotificationTimes[id] = now;

                    final startTime = _uploadStartTimes[id] ?? now;
                    final timeDiffSec = (now - startTime) / 1000.0;
                    
                    final double speed = timeDiffSec > 0.1 ? bytesTransferred / timeDiffSec : 0.0;
                    final double etaSec = speed > 1024 ? (totalBytes - bytesTransferred) / speed : 0.0;

                    String etaStr = "Calculating...";
                    if (etaSec > 0) {
                      if (etaSec < 60) {
                        etaStr = "⧗ ${etaSec.toStringAsFixed(0)}s remaining";
                      } else {
                        final minutes = etaSec ~/ 60;
                        final seconds = (etaSec % 60).toInt();
                        etaStr = "⧗ ${minutes}m ${seconds}s remaining";
                      }
                    } else if (isComplete) {
                      etaStr = "⧗ Complete";
                    }

                    final String speedStr = "${FileUtils.formatSize(speed.toInt())}/s";
                    final String sizeInfo = "${FileUtils.formatSize(bytesTransferred)} / ${FileUtils.formatSize(totalBytes)}";

                    NotificationService().showProgressNotification(
                      id.hashCode.abs() % 100000,
                      "⇧ [UPLD_RUN] // ${(progress * 100).toStringAsFixed(1)}%",
                      "⇄ $speedStr  |  ⧗ $etaStr  |  ⛃ $sizeInfo",
                      progress * 100,
                      transferId: id,
                    );
                  }
                }
              },
        )
        .then((_) {
          engine.dispose();
          _activeEngines.remove(id);
          _uploadStartTimes.remove(id);
          _lastUploadNotificationTimes.remove(id);
          
          final okMsg = IsolateMsg(
            type: IsolateType.event,
            action: IsolateAction.transferComplete,
            payload: TransferProgressComplete(
              id: id,
              finalPath: msg.payload['remote_path'],
            ).toJson(),
          );
          _broadcastToMain(okMsg);
          RtcThinClient().handleMsg(okMsg);

          if (showNotif) {
            NotificationService().dismiss(id.hashCode.abs() % 100000);
            AwesomeNotifications().createNotification(
              content: NotificationContent(
                id: id.hashCode.abs() % 100000,
                channelKey: 'frankn_host_alerts',
                title: "◈ [UPLD_DONE] // $fileName",
                body: "'$fileName' uploaded successfully.",
                notificationLayout: NotificationLayout.Default,
                category: NotificationCategory.Status,
                color: AppColors.matrixGreen,
                backgroundColor: AppColors.panelGrey,
              ),
            );
          }
        })
        .catchError((e) {
          engine.dispose();
          _activeEngines.remove(id);
          _uploadStartTimes.remove(id);
          _lastUploadNotificationTimes.remove(id);
          
          final failMsg = IsolateMsg(
            type: IsolateType.event,
            action: IsolateAction.transferFailed,
            payload: TransferProgressFailed(
                id: id, 
                error: e.toString()
            ).toJson(),
          );
          _broadcastToMain(failMsg);
          RtcThinClient().handleMsg(failMsg);

          if (showNotif) {
            NotificationService().dismiss(id.hashCode.abs() % 100000);
            AwesomeNotifications().createNotification(
              content: NotificationContent(
                id: id.hashCode.abs() % 100000,
                channelKey: 'frankn_host_alerts',
                title: "⚠ [UPLD_ERR] // $fileName",
                body: "'$fileName' failed to upload.",
                notificationLayout: NotificationLayout.Default,
                category: NotificationCategory.Status,
                color: AppColors.errorRed,
                backgroundColor: AppColors.panelGrey,
              ),
            );
          }
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
        RtcClient().sendDcMsg(DcMsg.fromJson(msg.payload));
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
      case IsolateAction.logIntent:
        RtcClient().log(msg.payload['msg'] ?? '');
        break;
      case (IsolateAction.uploadInit):
        _handleUploadInit(msg);
        break;
      case IsolateAction.triggerBackgroundSync:
        final pair = SyncPair.fromJson(msg.payload);
        SyncService().performFullSync(pair);
        break;
      case IsolateAction.checkSyncStatus:
        final pair = SyncPair.fromJson(msg.payload);
        SyncService().checkSyncStatus(pair);
        break;
      case IsolateAction.stopSync:
        final folderPath = msg.payload.containsKey('id')
            ? msg.payload['id']
            : null;
        SyncService().stopSync(folderPath);
        break;
      case IsolateAction.cancelTransfer:
        final tid = msg.payload['id'];
        if (tid != null) {
          if (_activeEngines.containsKey(tid)) {
            _activeEngines[tid]?.cancel(tid);
          } else {
            // Probably a download or external transfer
            RtcClient().sendTransferCancel(tid);
          }
        }
        break;
    }
  }
}
