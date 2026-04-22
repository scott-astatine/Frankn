// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'Frankn';

  @override
  String get neuralDeck => 'Neural Deck';

  @override
  String get systemOperations => 'System Operations';

  @override
  String get fileBrowser => 'File Browser';

  @override
  String get terminal => 'Terminal';

  @override
  String get processes => 'Processes';

  @override
  String get sysLog => 'Sys Log';

  @override
  String get liveLog => 'Live Log';

  @override
  String get activeMonitors => 'Active Monitors';

  @override
  String get fetching => 'Fetching...';

  @override
  String get syncing => 'Syncing...';

  @override
  String get linked => 'Linked';

  @override
  String get error => 'Error';

  @override
  String get offline => 'Offline';

  @override
  String get cpu => 'CPU';

  @override
  String get ram => 'RAM';

  @override
  String get ping => 'PING';

  @override
  String get neuralLinks => 'Neural Links';

  @override
  String get publicDiscovery => 'Public Discovery';

  @override
  String get noPersistentLinks => 'No Persistent Links';

  @override
  String get noAdditionalTargets => 'No Additional Targets';

  @override
  String get addManualTarget => 'Add Manual Target';

  @override
  String get uplinkSecurity => 'Uplink Security';

  @override
  String get enterPasscode => 'Enter Passcode';

  @override
  String get cancel => 'Cancel';

  @override
  String get establish => 'Establish';

  @override
  String get disconnect => 'Disconnect';

  @override
  String get disconnectLink => 'Disconnect Link';

  @override
  String get adminOverride => 'Admin Override';

  @override
  String get serviceManagement => 'Service Management';

  @override
  String get restartSvc => 'Restart Svc';

  @override
  String get sysUpdate => 'Sys Update';

  @override
  String get powerState => 'Power State';

  @override
  String get lockHost => 'Lock Host';

  @override
  String get unlockHost => 'Unlock Host';

  @override
  String get reboot => 'Reboot';

  @override
  String get shutdown => 'Shutdown';

  @override
  String get criticalIntent => 'Critical Intent';

  @override
  String executeRemoteCommand(String command) {
    return 'Execute remote $command command? This will terminate the current neural link.';
  }

  @override
  String get abort => 'Abort';

  @override
  String get confirm => 'Confirm';

  @override
  String get status => 'Status';

  @override
  String get memory => 'Memory';

  @override
  String get affinity => 'Affinity';

  @override
  String get cmdPath => 'Command Path';

  @override
  String get killProcess => 'Kill Process';

  @override
  String get terminateIntent => 'Terminate Intent';

  @override
  String killProcessConfirm(String pid) {
    return 'Are you sure you want to kill process $pid? This may cause system instability.';
  }

  @override
  String get noDataFound => 'No Data Found';

  @override
  String get directory => 'Directory';

  @override
  String get download => 'Download';

  @override
  String get edit => 'Edit';

  @override
  String get delete => 'Delete';

  @override
  String get intentHandler => 'Intent Handler';

  @override
  String get audioMatrix => 'Audio Matrix';

  @override
  String get vol => 'VOL';

  @override
  String get close => 'Close';

  @override
  String get settings => 'Settings';

  @override
  String get neuralLinkConfiguration => 'Neural Link Configuration';

  @override
  String get signalingServer => 'Signaling Server';

  @override
  String get lastConnectedHost => 'Last Connected Host';

  @override
  String get uiPreferences => 'UI Preferences';

  @override
  String get language => 'Language';

  @override
  String get terminalFontSize => 'Terminal Font Size';

  @override
  String get colorScheme => 'Color Scheme';

  @override
  String get appReset => 'App Reset';

  @override
  String get clearAllData => 'Clear All Data';

  @override
  String get newNeuralLink => 'New Neural Link';

  @override
  String get visualHash => 'Visual Hash (QR)';

  @override
  String get tapToScan => 'Tap To Scan';

  @override
  String get orManual => 'Or Manual';

  @override
  String get hostId => 'Host ID';

  @override
  String get aliasOptional => 'Alias (Optional)';

  @override
  String get initialize => 'Initialize';

  @override
  String get root => 'root';

  @override
  String get sortByName => 'Sort by Name';

  @override
  String get sortBySize => 'Sort by Size';

  @override
  String get sortByDate => 'Sort by Date';

  @override
  String get selected => 'Selected';

  @override
  String get filterProcesses => 'Filter Processes...';
}
