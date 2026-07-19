import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:frankn/generated/l10n/app_localizations.dart';
import 'package:frankn/screens/home_screen.dart';
import 'package:frankn/services/audio_handler.dart';
import 'package:frankn/services/frankn_task_handler.dart';
import 'package:frankn/services/notification_service.dart';
import 'package:frankn/services/rtc_thin_client.dart';
import 'package:frankn/services/settings_service.dart';
import 'package:frankn/services/file_viewer_service.dart';
import 'package:frankn/services/sharing_service.dart';
import 'package:frankn/utils/dc_msg_util.dart';
import 'package:frankn/utils/utils.dart';
import 'package:path_provider/path_provider.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
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
        RtcThinClient().sendDcMsg(const DcMsgDisconnect());
        RtcThinClient().disconnectFromHost();
      } else {
        RtcThinClient().handleBackgroundEvent(data);
      }
    }
  });

  // Start background service
  print("UI Isolate: Booting background engine...");
  await initForegroundService();

  // Initialize share listener service
  SharingService(client: RtcThinClient(), navigatorKey: navigatorKey);

  // Initialize file viewer listener service
  FileViewerService(navigatorKey: navigatorKey);

  runApp(const FranknApp());
}

final appLocale = ValueNotifier<Locale>(const Locale('en'));

/// Starts the foreground service and initializes the background isolate.
Future<void> initForegroundService() async {
  if (await FlutterForegroundTask.isRunningService) return;

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
    notificationTitle: '도회 (Frankn)',
    notificationText: 'Initializing Neural Link...',
    notificationIcon: const NotificationIcon(
      metaDataName: 'com.pravera.flutter_foreground_task.NOTIFICATION_ICON',
      backgroundColor: AppColors.background,
    ),
    callback: startCallback,
  );
}

@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(FranknTaskHandler());
}

class FranknApp extends StatefulWidget {
  const FranknApp({super.key});

  @override
  State<FranknApp> createState() => _FranknAppState();
}

class _FranknAppState extends State<FranknApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    // Forcefully restore sticky immersive fullscreen when overlay offsets change
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Locale>(
      valueListenable: appLocale,
      builder: (context, locale, _) {
        return MaterialApp(
          navigatorKey: navigatorKey,
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
