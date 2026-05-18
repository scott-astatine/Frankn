import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ko.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ko'),
  ];

  /// No description provided for @appName.
  ///
  /// In en, this message translates to:
  /// **'Frankn'**
  String get appName;

  /// No description provided for @neuralDeck.
  ///
  /// In en, this message translates to:
  /// **'Neural Deck'**
  String get neuralDeck;

  /// No description provided for @systemOperations.
  ///
  /// In en, this message translates to:
  /// **'System Operations'**
  String get systemOperations;

  /// No description provided for @fileBrowser.
  ///
  /// In en, this message translates to:
  /// **'File Browser'**
  String get fileBrowser;

  /// No description provided for @terminal.
  ///
  /// In en, this message translates to:
  /// **'Terminal'**
  String get terminal;

  /// No description provided for @processes.
  ///
  /// In en, this message translates to:
  /// **'Processes'**
  String get processes;

  /// No description provided for @sysLog.
  ///
  /// In en, this message translates to:
  /// **'Sys Log'**
  String get sysLog;

  /// No description provided for @generalConfig.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get generalConfig;

  /// No description provided for @storageSync.
  ///
  /// In en, this message translates to:
  /// **'Storage Sync'**
  String get storageSync;

  /// No description provided for @manageDir.
  ///
  /// In en, this message translates to:
  /// **'Manage Dirs'**
  String get manageDir;

  /// No description provided for @hostAlias.
  ///
  /// In en, this message translates to:
  /// **'Host Alias'**
  String get hostAlias;

  /// No description provided for @liveLog.
  ///
  /// In en, this message translates to:
  /// **'Live Log'**
  String get liveLog;

  /// No description provided for @activeMonitors.
  ///
  /// In en, this message translates to:
  /// **'Active Monitors'**
  String get activeMonitors;

  /// No description provided for @fetching.
  ///
  /// In en, this message translates to:
  /// **'Fetching...'**
  String get fetching;

  /// No description provided for @syncing.
  ///
  /// In en, this message translates to:
  /// **'Syncing...'**
  String get syncing;

  /// No description provided for @linked.
  ///
  /// In en, this message translates to:
  /// **'Linked'**
  String get linked;

  /// No description provided for @error.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get error;

  /// No description provided for @offline.
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get offline;

  /// No description provided for @cpu.
  ///
  /// In en, this message translates to:
  /// **'CPU'**
  String get cpu;

  /// No description provided for @ram.
  ///
  /// In en, this message translates to:
  /// **'RAM'**
  String get ram;

  /// No description provided for @ping.
  ///
  /// In en, this message translates to:
  /// **'PING'**
  String get ping;

  /// No description provided for @neuralLinks.
  ///
  /// In en, this message translates to:
  /// **'Neural Links'**
  String get neuralLinks;

  /// No description provided for @publicDiscovery.
  ///
  /// In en, this message translates to:
  /// **'Public Discovery'**
  String get publicDiscovery;

  /// No description provided for @noPersistentLinks.
  ///
  /// In en, this message translates to:
  /// **'No Persistent Links'**
  String get noPersistentLinks;

  /// No description provided for @noAdditionalTargets.
  ///
  /// In en, this message translates to:
  /// **'No Additional Targets'**
  String get noAdditionalTargets;

  /// No description provided for @addManualTarget.
  ///
  /// In en, this message translates to:
  /// **'Add Manual Target'**
  String get addManualTarget;

  /// No description provided for @uplinkSecurity.
  ///
  /// In en, this message translates to:
  /// **'Uplink Security'**
  String get uplinkSecurity;

  /// No description provided for @enterPasscode.
  ///
  /// In en, this message translates to:
  /// **'Enter Passcode'**
  String get enterPasscode;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @establish.
  ///
  /// In en, this message translates to:
  /// **'Establish'**
  String get establish;

  /// No description provided for @disconnect.
  ///
  /// In en, this message translates to:
  /// **'Disconnect'**
  String get disconnect;

  /// No description provided for @disconnectLink.
  ///
  /// In en, this message translates to:
  /// **'Disconnect Link'**
  String get disconnectLink;

  /// No description provided for @adminOverride.
  ///
  /// In en, this message translates to:
  /// **'Admin Override'**
  String get adminOverride;

  /// No description provided for @serviceManagement.
  ///
  /// In en, this message translates to:
  /// **'Service Management'**
  String get serviceManagement;

  /// No description provided for @restartSvc.
  ///
  /// In en, this message translates to:
  /// **'Restart Svc'**
  String get restartSvc;

  /// No description provided for @sysUpdate.
  ///
  /// In en, this message translates to:
  /// **'Sys Update'**
  String get sysUpdate;

  /// No description provided for @powerState.
  ///
  /// In en, this message translates to:
  /// **'Power State'**
  String get powerState;

  /// No description provided for @lockHost.
  ///
  /// In en, this message translates to:
  /// **'Lock Host'**
  String get lockHost;

  /// No description provided for @unlockHost.
  ///
  /// In en, this message translates to:
  /// **'Unlock Host'**
  String get unlockHost;

  /// No description provided for @reboot.
  ///
  /// In en, this message translates to:
  /// **'Reboot'**
  String get reboot;

  /// No description provided for @shutdown.
  ///
  /// In en, this message translates to:
  /// **'Shutdown'**
  String get shutdown;

  /// No description provided for @criticalIntent.
  ///
  /// In en, this message translates to:
  /// **'Critical Intent'**
  String get criticalIntent;

  /// No description provided for @executeRemoteCommand.
  ///
  /// In en, this message translates to:
  /// **'Execute remote {command} command? This will terminate the current neural link.'**
  String executeRemoteCommand(String command);

  /// No description provided for @abort.
  ///
  /// In en, this message translates to:
  /// **'Abort'**
  String get abort;

  /// No description provided for @confirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

  /// No description provided for @status.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get status;

  /// No description provided for @memory.
  ///
  /// In en, this message translates to:
  /// **'Memory'**
  String get memory;

  /// No description provided for @affinity.
  ///
  /// In en, this message translates to:
  /// **'Affinity'**
  String get affinity;

  /// No description provided for @cmdPath.
  ///
  /// In en, this message translates to:
  /// **'Command Path'**
  String get cmdPath;

  /// No description provided for @killProcess.
  ///
  /// In en, this message translates to:
  /// **'Kill Process'**
  String get killProcess;

  /// No description provided for @terminateIntent.
  ///
  /// In en, this message translates to:
  /// **'Terminate Intent'**
  String get terminateIntent;

  /// No description provided for @killProcessConfirm.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to kill process {pid}? This may cause system instability.'**
  String killProcessConfirm(String pid);

  /// No description provided for @noDataFound.
  ///
  /// In en, this message translates to:
  /// **'No Data Found'**
  String get noDataFound;

  /// No description provided for @directory.
  ///
  /// In en, this message translates to:
  /// **'Directory'**
  String get directory;

  /// No description provided for @download.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get download;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @intentHandler.
  ///
  /// In en, this message translates to:
  /// **'Intent Handler'**
  String get intentHandler;

  /// No description provided for @audioMatrix.
  ///
  /// In en, this message translates to:
  /// **'Audio Matrix'**
  String get audioMatrix;

  /// No description provided for @vol.
  ///
  /// In en, this message translates to:
  /// **'VOL'**
  String get vol;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @signalingServer.
  ///
  /// In en, this message translates to:
  /// **'Signaling Server'**
  String get signalingServer;

  /// No description provided for @lastConnectedHost.
  ///
  /// In en, this message translates to:
  /// **'Last Connected Host'**
  String get lastConnectedHost;

  /// No description provided for @uiPreferences.
  ///
  /// In en, this message translates to:
  /// **'UI Preferences'**
  String get uiPreferences;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @terminalFontSize.
  ///
  /// In en, this message translates to:
  /// **'Terminal Font Size'**
  String get terminalFontSize;

  /// No description provided for @colorScheme.
  ///
  /// In en, this message translates to:
  /// **'Color Scheme'**
  String get colorScheme;

  /// No description provided for @appReset.
  ///
  /// In en, this message translates to:
  /// **'App Reset'**
  String get appReset;

  /// No description provided for @clearAllData.
  ///
  /// In en, this message translates to:
  /// **'Clear All Data'**
  String get clearAllData;

  /// No description provided for @newNeuralLink.
  ///
  /// In en, this message translates to:
  /// **'New Neural Link'**
  String get newNeuralLink;

  /// No description provided for @visualHash.
  ///
  /// In en, this message translates to:
  /// **'Visual Hash (QR)'**
  String get visualHash;

  /// No description provided for @tapToScan.
  ///
  /// In en, this message translates to:
  /// **'Tap To Scan'**
  String get tapToScan;

  /// No description provided for @orManual.
  ///
  /// In en, this message translates to:
  /// **'Or Manual'**
  String get orManual;

  /// No description provided for @hostId.
  ///
  /// In en, this message translates to:
  /// **'Host ID'**
  String get hostId;

  /// No description provided for @aliasOptional.
  ///
  /// In en, this message translates to:
  /// **'Alias (Optional)'**
  String get aliasOptional;

  /// No description provided for @initialize.
  ///
  /// In en, this message translates to:
  /// **'Initialize'**
  String get initialize;

  /// No description provided for @root.
  ///
  /// In en, this message translates to:
  /// **'root'**
  String get root;

  /// No description provided for @sortByName.
  ///
  /// In en, this message translates to:
  /// **'Sort by Name'**
  String get sortByName;

  /// No description provided for @sortBySize.
  ///
  /// In en, this message translates to:
  /// **'Sort by Size'**
  String get sortBySize;

  /// No description provided for @sortByDate.
  ///
  /// In en, this message translates to:
  /// **'Sort by Date'**
  String get sortByDate;

  /// No description provided for @selected.
  ///
  /// In en, this message translates to:
  /// **'Selected'**
  String get selected;

  /// No description provided for @search.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get search;

  /// No description provided for @trackpadSensitivity.
  ///
  /// In en, this message translates to:
  /// **'Trackpad Sensitivity'**
  String get trackpadSensitivity;

  /// No description provided for @trackpad.
  ///
  /// In en, this message translates to:
  /// **'Trackpad'**
  String get trackpad;

  /// No description provided for @filterProcesses.
  ///
  /// In en, this message translates to:
  /// **'Filter Processes...'**
  String get filterProcesses;

  /// No description provided for @terminate.
  ///
  /// In en, this message translates to:
  /// **'Terminate'**
  String get terminate;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ko'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ko':
      return AppLocalizationsKo();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
