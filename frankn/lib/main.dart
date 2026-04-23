import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:frankn/generated/l10n/app_localizations.dart';
import 'package:frankn/screens/home_screen.dart';
import 'package:frankn/services/audio_handler.dart';
import 'package:frankn/services/notification_service.dart';
import 'package:frankn/services/rtc/rtc.dart';
import 'package:frankn/services/rtc_thin_client.dart';
import 'package:frankn/services/settings_service.dart';
import 'package:frankn/services/transfer_engine.dart';
import 'package:frankn/services/isolate_protocol.dart';
import 'package:frankn/utils/theme.dart';
import 'package:frankn/utils/utils.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:path_provider/path_provider.dart';

final appLocale = ValueNotifier<Locale>(const Locale('en'));

/// Starts the foreground service and initializes the background isolate.
Future<void> initForegroundService() async {
  if (await FlutterForegroundTask.isRunningService) return;

  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'frankn_connection_silent',
      channelName: 'Frankn Connection (Silent)',
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
    notificationTitle: '도회 (Frankn)',
    notificationText: 'Initializing Neural Link...',
    notificationIcon: const NotificationIcon(
      metaDataName: 'com.pravera.flutter_foreground_task.NOTIFICATION_ICON',
      backgroundColor: AppColors.voidBlack,
    ),
    callback: startCallback,
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterForegroundTask.initCommunicationPort();

  print("UI Isolate: Initializing services...");
  try {
    globalTempDir = await getTemporaryDirectory();
    await SettingsService().initialize();
    appLocale.value = Locale(SettingsService().localeCode);
    await NotificationService().initialize();
    await initAudioService();
  } catch (e) {
    print("UI Isolate: Service initialization error: $e");
  }

  // Allow the ThinClient to restart the background engine if it dies
  RtcThinClient().onServiceRestartRequired = () => initForegroundService();

  // Listen for notifications globally
  RtcThinClient().notificationStream.listen((data) {
    NotificationService().showNotificationFromHost(data);
  });

  FlutterForegroundTask.addTaskDataCallback((data) {
    if (data is String) {
      if (data == 'disconnect_intent') {
        RtcThinClient().sendDcMsg({DcMsg.Key: DcMsg.Disconnect});
        RtcThinClient().disconnectFromHost();
      } else {
        RtcThinClient().handleBackgroundEvent(data);
      }
    }
  });

  // Start background service
  print("UI Isolate: Booting background engine...");
  await initForegroundService();

  runApp(const FranknApp());
}

@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(FranknTaskHandler());
}

class FranknTaskHandler extends TaskHandler {
  void _broadcastToMain(IsolateMsg msg) {
    FlutterForegroundTask.sendDataToMain(msg.toJson());
  }

  void syncState() {
    _broadcastToMain(
      IsolateMsg(
        type: 'state',
        action: 'sync_state',
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

      await NotificationService().initialize();
      await initAudioService();

      print("Background Isolate: SERVICES_READY");

      RtcClient().hostStateController.stream.listen((state) {
        // MIRROR state to local background proxy so AudioHandler is not 'blind'
        RtcThinClient().currentHostState = state;
        RtcThinClient().currentHostId = RtcClient().currentHostId;
        RtcThinClient().currentHostName = RtcClient().currentHostName;

        if (state == HostConnectionState.disconnected && RtcClient().isAuthFailed) {
          _broadcastToMain(IsolateMsg(
            type: 'event',
            action: 'auth_failed',
            payload: {'error': 'AUTHENTICATION_REJECTED'},
          ));
        } else if (state == HostConnectionState.failed) {
          _broadcastToMain(IsolateMsg(
            type: 'event',
            action: 'auth_failed',
            payload: {'error': 'CONNECTION_FAILED'},
          ));
        }

        if (state == HostConnectionState.authenticated) {
          _broadcastToMain(IsolateMsg(
            type: 'event',
            action: 'auth_success',
          ));
        }

        _broadcastToMain(IsolateMsg(
            type: 'state',
            action: 'host_state',
            payload: {
              'state': state.index,
              'id': RtcClient().currentHostId,
              'name': RtcClient().currentHostName,
            },
          ),
        );
      });

      RtcClient().commandResponseStream.listen((data) {
        _broadcastToMain(
          IsolateMsg(type: 'event', action: 'command_response', payload: data),
        );
      });

      RtcClient().connectionStateStream.listen((state) {
        _broadcastToMain(
          IsolateMsg(
            type: 'state',
            action: 'sig_state',
            payload: {'state': state.index},
          ),
        );
      });

      RtcClient().peerStatusStream.listen((data) {
        _broadcastToMain(
          IsolateMsg(type: 'event', action: 'peer_status', payload: data),
        );
      });

      RtcClient().hostListStream.listen((hosts) {
        _broadcastToMain(
          IsolateMsg(
            type: 'event',
            action: 'host_list',
            payload: {'hosts': hosts},
          ),
        );
      });

      RtcClient().logStream.listen((logMsg) {
        _broadcastToMain(
          IsolateMsg(type: 'event', action: 'log', payload: {'msg': logMsg}),
        );
      });

      RtcClient().mediaStatusStream.listen((status) {
        _broadcastToMain(
          IsolateMsg(
            type: 'event',
            action: 'media_status',
            payload: {'status': status},
          ),
        );
      });

      RtcClient().notificationStream.listen((data) {
        _broadcastToMain(
          IsolateMsg(type: 'event', action: 'notification', payload: data),
        );
      });

      RtcClient().sshDataStream.listen((data) {
        _broadcastToMain(
          IsolateMsg(
            type: 'event',
            action: 'ssh_output',
            payload: {'data': base64Encode(data)},
          ),
        );
      });

      print("Background Isolate: SIGNALING_READY");
      _broadcastToMain(IsolateMsg(type: 'state', action: 'isolate_ready'));

      syncState();

      // Auto-connect once ready
      RtcClient().connectToSignaling();
    } catch (e, stack) {
      print("Background Isolate: CRITICAL_ERROR: $e");
      print(stack);
    }
  }

  void _handleIntent(IsolateMsg msg) {
    switch (msg.action) {
      case 'connect_signaling':
        RtcClient().connectToSignaling();
        break;
      case 'connect_host':
        RtcClient().connectToHost(
          msg.payload['id'],
          password: msg.payload['password'],
          hostName: msg.payload['hostName'],
        );
        break;
      case 'disconnect_host':
        RtcClient().disconnectFromHost();
        break;
      case 'send_dc_msg':
        RtcClient().sendDcMsg(msg.payload);
        break;
      case 'download_init':
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
      case 'authenticate':
        RtcClient().authenticate(msg.payload['password']);
        break;
      case 'ssh_input':
        if (RtcClient().sshDC?.state ==
            RTCDataChannelState.RTCDataChannelOpen) {
          RtcClient().sshDC!.send(
            RTCDataChannelMessage.fromBinary(base64Decode(msg.payload['data'])),
          );
        }
        break;
      case 'start_ssh':
        RtcClient().startSsh();
        break;
      case 'stop_ssh':
        RtcClient().stopSsh();
        break;
      case 'request_host_list':
        RtcClient().requestHostList();
        break;
      case 'sync_state':
        syncState();
        break;
      case 'upload_init':
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
                        type: 'event',
                        action: 'transfer_progress',
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
                  type: 'event',
                  action: 'transfer_complete',
                  payload: {
                    'id': id,
                    'target_path': msg.payload['remote_path'],
                  },
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
                  type: 'event',
                  action: 'transfer_failed',
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
        break;
    }
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
        print("Background Isolate: Received Intent: ${msg.action}");

        if (msg.type == 'intent') {
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
  Future<void> onDestroy(DateTime timestamp, bool? sendPort) async {
    print('Background Isolate: DESTROYED');
  }
}

class FranknApp extends StatelessWidget {
  const FranknApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Locale>(
      valueListenable: appLocale,
      builder: (context, locale, _) {
        return MaterialApp(
          onGenerateTitle: (context) => AppLocalizations.of(context)!.appName,
          theme: CyberTheme.themeData,
          locale: locale,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: const HomeScreen(),
          debugShowCheckedModeBanner: false,
        );
      },
    );
  }
}
