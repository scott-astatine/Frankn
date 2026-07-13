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
  String get sysLog => 'System Log';

  @override
  String get generalConfig => 'General';

  @override
  String get storageSync => 'Storage Sync';

  @override
  String get manageDir => 'Manage Dirs';

  @override
  String get hostAlias => 'Host Alias';

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
  String get search => 'Search';

  @override
  String get trackpadSensitivity => 'Trackpad Sensitivity';

  @override
  String get trackpad => 'Trackpad';

  @override
  String get filterProcesses => 'Filter Processes...';

  @override
  String get terminate => 'Terminate';

  @override
  String get folderSynchronization => 'Folder Synchronization';

  @override
  String get folderSyncComplete => 'Folder Sync Complete';

  @override
  String get folderSyncCompleteNoChanges => 'Folder Sync Complete: No Changes';

  @override
  String get fullStorageAccessRequired => 'Full Storage Access Required';

  @override
  String get establishNewLink => 'Establish New Link';

  @override
  String get modifyLink => 'Modify Link';

  @override
  String get localDir => 'Local Directory';

  @override
  String get notSelected => 'Not Selected';

  @override
  String get remoteDir => 'Remote Directory';

  @override
  String get syncStrategy => 'Sync Strategy';

  @override
  String get bidirectionalMirror => 'Bidirectional Mirror';

  @override
  String get singleSourceBackup => 'Single Source Backup';

  @override
  String get clientIsSourceLabel => 'Client Is Source';

  @override
  String get syncInterval => 'Sync Interval';

  @override
  String everyNMinutes(int minutes) {
    return 'Every $minutes Minutes';
  }

  @override
  String get everyHour => 'Every Hour';

  @override
  String get every6Hours => 'Every 6 Hours';

  @override
  String get onceADay => 'Once A Day';

  @override
  String get update => 'Update';

  @override
  String get localEndpoint => 'Local Endpoint';

  @override
  String get remoteEndpoint => 'Remote Endpoint';

  @override
  String get mirror => 'Mirror';

  @override
  String get backup => 'Backup';

  @override
  String lastSyncedLabel(String time) {
    return 'Last Synced: $time';
  }

  @override
  String get triggerSyncNow => 'Trigger Sync Now';

  @override
  String get noSyncPairsEstablished => 'No Sync Pairs Established';

  @override
  String get inSync => 'In Sync';

  @override
  String changesPending(int count) {
    return '$count Changes Pending';
  }

  @override
  String get verifying => 'Verifying...';

  @override
  String get english => 'English';

  @override
  String get korean => 'Korean';

  @override
  String pixels(int size) {
    return '$size PX';
  }

  @override
  String multiplier(double value) {
    return '${value}X Multiplier';
  }

  @override
  String multiplierValue(double value) {
    return '${value}X';
  }

  @override
  String get renameHost => 'Rename Host';

  @override
  String get reinitializingNeuralLink =>
      'Re-initializing Neural Link to new server...';

  @override
  String get invalidUrlFormat =>
      'Invalid URL format. Must start with ws:// or wss://';

  @override
  String get defaultLlm => 'Default LLM';

  @override
  String get unknown => 'Unknown';

  @override
  String get notSet => 'Not Set';

  @override
  String get uiDefaults => 'UI Defaults';

  @override
  String get criticalReset => 'Critical Reset';

  @override
  String get terminateConfigsConfirm =>
      'Terminate all persistent links and system configurations?';

  @override
  String get execute => 'Execute';

  @override
  String get forgetIntents => 'Forget Intents';

  @override
  String get noMediaPlaying => 'No Media Playing';

  @override
  String get idle => 'Idle';

  @override
  String get idleInstance => 'Idle Instance';

  @override
  String get doheeChat => 'Dohee Chat';

  @override
  String get unknownArtist => 'Unknown Artist';

  @override
  String get bluetoothDevices => 'Bluetooth Devices';

  @override
  String get noDevicesFound => 'No Devices Found';

  @override
  String get wifiNetworks => 'Wi-Fi Networks';

  @override
  String get noNetworksFound => 'No Networks Found';

  @override
  String connectToSsid(String ssid) {
    return 'Connect To $ssid';
  }

  @override
  String get password => 'Password';

  @override
  String get neuralModelVault => 'Neural Model Vault';

  @override
  String get scanningVault => 'Scanning Vault...';

  @override
  String get noModelsFound => 'No .gguf models found in host vault directory.';

  @override
  String get connectivityAudio => 'Connectivity & Audio';

  @override
  String criticalAction(String action) {
    return 'Critical // $action';
  }

  @override
  String get remoteCommandConfirm =>
      'Are you sure you want to proceed with this remote command?';

  @override
  String get scanning => 'Scanning...';

  @override
  String get connected => 'Connected';

  @override
  String get importFromImage => 'Import From Image';

  @override
  String get hostIdHint => 'e.g. 550e8400-e29b...';

  @override
  String get aliasHint => 'e.g. WORK-RIG';

  @override
  String get defaultDownloadDir => 'Default Download Dir';

  @override
  String get chooseOnDownload => 'Choose on Download';

  @override
  String get downloadFolder => 'Download Folder';

  @override
  String get noDefaultFolderConfigured =>
      'No default landing folder has been configured yet. It will be set automatically on your first download, or you can choose one below.';

  @override
  String currentFolder(String folderPath) {
    return 'Current Folder: $folderPath\n\nWould you like to clear this or choose a new folder?';
  }

  @override
  String get clearDefault => 'CLEAR DEFAULT';

  @override
  String get chooseFolder => 'CHOOSE FOLDER';

  @override
  String get saveAs => 'Save As';
}
