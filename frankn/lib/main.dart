import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:frankn/screens/home_screen.dart';
import 'package:frankn/services/audio_handler.dart';
import 'package:frankn/services/notification_service.dart';
import 'package:frankn/services/rtc/rtc.dart';
import 'package:frankn/services/settings_service.dart';
import 'package:frankn/utils/theme.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:frankn/generated/l10n/app_localizations.dart';

final appLocale = ValueNotifier<Locale>(Locale(SettingsService().localeCode));

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterForegroundTask.initCommunicationPort();

  await SettingsService().initialize();
  appLocale.value = Locale(SettingsService().localeCode);
  await NotificationService().initialize();
  await initAudioService();

  // Listen for notifications globally
  RtcClient().notificationStream.listen((data) {
    NotificationService().showNotificationFromHost(data);
  });

  // Initiate Neural Link to Signaling Server
  RtcClient().connectToSignaling();

  runApp(const FranknApp());
}

@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(FranknTaskHandler());
}

class FranknTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    print('Foreground task started at $timestamp');
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // This runs periodically (default 5s).
    // Just logging to keep the isolate busy and network active.
    // FlutterForegroundTask.updateService(
    //   notificationTitle: 'Frankn Active',
    //   notificationText: 'Link stable at ${timestamp.hour}:${timestamp.minute}:${timestamp.second}',
    // );
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool? sendPort) async {
    print('Foreground task destroyed');
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
      }
    );
  }
}
