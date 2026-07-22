# Graph Report - Frankn  (2026-07-22)

## Corpus Check
- 164 files · ~305,540 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 3024 nodes · 4133 edges · 185 communities (130 shown, 55 thin omitted)
- Extraction: 99% EXTRACTED · 1% INFERRED · 0% AMBIGUOUS · INFERRED: 41 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `d85da5ca`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- app_localizations.dart
- app_localizations_ko.dart
- app_localizations_en.dart
- dc_msg_util.dart
- rtc.dart
- rtc_thin_client.dart
- theme.dart
- settings_service.dart
- isolate_protocol.dart
- GeneratedPluginRegistrant.swift
- dohee_chat_screen.dart
- quick_functions.dart
- LlmManager
- code_editor_screen.dart
- utils.dart
- trackpad_screen.dart
- RTCConn
- markdown_viewer_screen.dart
- neural_deck_player.dart
- ssh_controller.dart
- file_browser_state.dart
- State
- media.rs
- sync_service.dart
- transfer_engine.dart
- antigravity_field.dart
- process_manager_screen.dart
- sync_manager_screen.dart
- HostConfig
- cyber_alert_dialog.dart
- my_application.cc
- transfer.rs
- local_dir_selector.dart
- audio_handler.dart
- main.dart
- frankn_task_handler.dart
- notification_service.dart
- .parse_msg
- frankn_dashboard.dart
- syslog_screen.dart
- ssh_screen.dart
- host_pairing_dialog.dart
- system_tray_modal.dart
- settings_screen.dart
- package:frankn/services/rtc_thin_client.dart
- image_viewer_screen.dart
- host_list_panel.dart
- win32_window.cpp
- neo_code_element_builder.dart
- SignalingClient
- file_browser_screen.dart
- settings_tile.dart
- file_browser_utils.dart
- key_bar.dart
- dart:ui
- StatelessWidget
- player_selector_dialog.dart
- FlutterWindow
- file_transfer_mixin.dart
- bluetooth_manager_dialog.dart
- volume_mixer_dialog.dart
- model_selector_dialog.dart
- cyber_button.dart
- MainActivity
- message_bubble.dart
- VoidCallback
- llm_tools.rs
- dart:async
- package:frankn/utils/dc_msg_util.dart
- _PulsingDotState
- remote_dir_selector.dart
- handle_signaling_message
- Win32Window
- dart:convert
- terminal_context_menu.dart
- Flutter Client
- check_sandbox_default
- network.rs
- wWinMain
- frankn
- chat_message.dart
- List
- model_selector_dialog.dart
- manifest.json
- volume_mixer_dialog.dart
- graphify.md
- SignalingMessage
- MessageHandler
- Bytes
- ssh.rs
- dart:async
- animated_op_btn.dart
- dart:io
- List
- ClientMessage
- AppLocalizations
- RtcClient
- graphify.md
- TransferProgressEvent
- Frankn Master Logo
- System Tray / Dashboard UI
- RegisterPlugins
- FileBrowserState
- android_icon_gen
- Linux Project CMake
- widget_test.dart
- Web Index HTML
- Windows Project CMake
- Authentication Dialog UI
- Dohee Chat LaTeX Rendering
- SSH Authentication UI
- install.sh
- Launch Image
- App Launcher Icon
- App Notification Icon
- Frankn Launcher Foreground
- Frankn Android Adaptive Icon Foreground
- Logo Background (PNG)
- Logo Foreground (PNG)
- Frankn Notification Icon
- Frankn: My Personal Remote Ops Center
- Client Live Logs UI
- Settings Configuration UI
- File Browser UI
- Process Manager UI
- Folder Synchronization UI
- Trackpad and Keyboard UI
- mod.rs
- authenticate
- sendDcMsg
- sendInputMsg
- authenticate
- connectToHost
- disconnectFromHost
- drainSshEarlyBuffer
- handleHostMessage
- _reconnectTimer
- _sendToSignaling
- _transitionTo
- updateHostState
- _downloadTargetDirs
- handleHostMessage
- _showNotificationMap
- connectToSignaling
- requestHostList
- startBackgroundService
- stopBackgroundService
- updateBackgroundService
- animated_op_btn.dart
- bool?
- DcMsg
- File?
- HostMessage
- RTCDataChannel?
- RTCPeerConnection?
- String?
- SyncPair
- Terminal
- FRANKN // Remote Operations Center
- ssh_theme.dart
- notifications.rs
- .parse_msg
- CustomPainter
- _FranknAppState
- parse_dc_msg
- log_terminal.dart
- chat_stream_detached
- .run
- .reply
- terminal_context_menu.dart
- main.rs
- .set_remote_data_channel_handler
- VoidCallback
- context.rs
- FileBrowserState

## God Nodes (most connected - your core abstractions)
1. `CommandContext` - 60 edges
2. `RTCConn` - 36 edges
3. `HostConfig` - 30 edges
4. `RtcThinClient` - 29 edges
5. `Win32Window` - 22 edges
6. `AuthManager` - 20 edges
7. `Error` - 20 edges
8. `LlmManager` - 19 edges
9. `App` - 18 edges
10. `run_app()` - 14 edges

## Surprising Connections (you probably didn't know these)
- `Frankn Neon Frankenstein Circuit Icon` --references--> `Flutter Client`  [INFERRED]
  frankn/android/app/src/main/res/logo.svg → README.md
- `Frankn Notification Icon` --references--> `Flutter Client`  [INFERRED]
  frankn/android/app/src/main/res/drawable/ic_notification.png → README.md
- `Frankn Flutter Client Pubspec` --implements--> `Flutter Client`  [INFERRED]
  frankn/pubspec.yaml → README.md
- `stream_download()` --references--> `Error`  [EXTRACTED]
  frankn-host/src/capabilities/fs/transfer/download.rs → frankn/lib/utils/utils.dart
- `run_tui()` --references--> `Error`  [EXTRACTED]
  frankn-host/src/config/tui.rs → frankn/lib/utils/utils.dart

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **Frankn WebRTC Protocol Lanes** — frankn_cmd_channel, frankn_fs_channel, frankn_media_channel, frankn_ssh_channel, frankn_input_channel, dohee_x_channel [EXTRACTED 1.00]
- **Frankn Distributed Architecture** — frankn_flutter_client, frankn_rust_host, frankn_signaling_server [EXTRACTED 1.00]
- **Frankn Branding Assets** — frankn_assets_logo_frankn_background, frankn_assets_logo_frankn_foreground, frankn_assets_logo_frankn_master, frankn_assets_logo_ic_notification [EXTRACTED 1.00]
- **Frankn Application UI Screens** — frankn_docs_dohee_dashboard, frankn_docs_file_browser, frankn_docs_process_manager, frankn_docs_ssh_screen, frankn_docs_config_screen [INFERRED 0.90]
- **Frankn Mobile UI Components** — frankn_docs_sync_pair_dialog, frankn_docs_sys_log, frankn_docs_systray, frankn_docs_trackpad_screen [EXTRACTED 0.90]
- **Linux Build System** — frankn_linux_cmakelists, linux_flutter_cmakelists, linux_runner_cmakelists [EXTRACTED 1.00]
- **Windows Build System** — frankn_windows_cmakelists, windows_flutter_cmakelists, windows_runner_cmakelists [EXTRACTED 1.00]

## Communities (185 total, 55 thin omitted)

### Community 0 - "app_localizations.dart"
Cohesion: 0.01
Nodes (176): app_localizations_en.dart, app_localizations_ko.dart, class, abort, activeMonitors, addManualTarget, adminOverride, affinity (+168 more)

### Community 1 - "app_localizations_ko.dart"
Cohesion: 0.01
Nodes (163): abort, activeMonitors, addManualTarget, adminOverride, affinity, aliasHint, aliasOptional, appName (+155 more)

### Community 2 - "app_localizations_en.dart"
Cohesion: 0.01
Nodes (163): app_localizations.dart, abort, activeMonitors, addManualTarget, adminOverride, affinity, aliasHint, aliasOptional (+155 more)

### Community 3 - "dc_msg_util.dart"
Cohesion: 0.01
Nodes (146): appName, approvalId, approved, args, artData, authToken, body, bytesSent (+138 more)

### Community 4 - "rtc.dart"
Cohesion: 0.01
Nodes (144): class RtcClient extends, DateTime? get, activeAttempt, activeFileNames, aiDC, authentication, authFailed, _connectionGeneration (+136 more)

### Community 5 - "rtc_thin_client.dart"
Cohesion: 0.03
Nodes (72): DateTime?, activeFileNames, activeSshController, aiStream, _aiStreamController, authenticate, _authErrorController, authErrorStream (+64 more)

### Community 6 - "theme.dart"
Cohesion: 0.03
Nodes (58): accentDanger, accentError, accentPrimary, accentSecondary, accentSuccess, accentWarning, AppColors, background (+50 more)

### Community 7 - "settings_service.dart"
Cohesion: 0.04
Nodes (52): double get, clearAll, colorScheme, _defaultColorScheme, defaultDownloadDir, _defaultLlmModel, _defaultLlmProvider, _defaultLlmSystemPrompt (+44 more)

### Community 8 - "isolate_protocol.dart"
Cohesion: 0.04
Nodes (51): action, authenticate, authFailed, authSuccess, cancelTransfer, checkSyncStatus, commandResponse, connectHost (+43 more)

### Community 9 - "GeneratedPluginRegistrant.swift"
Cohesion: 0.05
Nodes (36): Any, audio_service, audio_session, awesome_notifications, Cocoa, device_info_plus, file_picker, file_selector_macos (+28 more)

### Community 10 - "dohee_chat_screen.dart"
Cohesion: 0.05
Nodes (44): _aiSub, _availableChats, _availableModels, build, _buildConnectionStatus, _buildHeader, _buildHistoryPanel, _buildInputDeck (+36 more)

### Community 11 - "quick_functions.dart"
Cohesion: 0.10
Nodes (20): _buildItem, _buildLiveLog, build, _processFileData, _buildContent, _buildLiveLog, build, _buildOperationsGrid (+12 more)

### Community 12 - "LlmManager"
Cohesion: 0.16
Nodes (15): Client, DoheeEngine, ChatMessage, ChatSession, LlmManager, Arc, HashMap, Mutex (+7 more)

### Community 13 - "code_editor_screen.dart"
Cohesion: 0.05
Nodes (36): CodeLineEditingController, _activeDownloadId, build, _buildBody, _buildHeader, client, _controller, createState (+28 more)

### Community 14 - "utils.dart"
Cohesion: 0.05
Nodes (36): Directory, Answer, AppConstants, borderRadius, clientIsSource, defaultPadding, FileUtils, formatSize (+28 more)

### Community 15 - "trackpad_screen.dart"
Cohesion: 0.06
Nodes (36): FocusNode, _alt, _batchTimer, build, _buildKey, _buildModKey, client, createState (+28 more)

### Community 16 - "RTCConn"
Cohesion: 0.15
Nodes (16): Display, Formatter, Box, F, HashMap, Option, Result, RTCPeerConnection (+8 more)

### Community 17 - "markdown_viewer_screen.dart"
Cohesion: 0.09
Nodes (21): _activeDownloadId, build, _buildBody, _buildHeader, client, createState, dispose, fileName (+13 more)

### Community 18 - "neural_deck_player.dart"
Cohesion: 0.06
Nodes (32): AnimatedIconButton, _AnimatedIconButtonState, _artData, build, _buildArtImage, _buildProgressSection, client, color (+24 more)

### Community 19 - "ssh_controller.dart"
Cohesion: 0.06
Nodes (34): altState, _buffer, client, _commandSubscription, ctrlState, dispose, _handleInput, _hostToSocket (+26 more)

### Community 20 - "file_browser_state.dart"
Cohesion: 0.06
Nodes (31): clearSelection, client, _currentPath, dispose, _entries, exitSearch, _fetchDirectory, getFilteredEntries (+23 more)

### Community 21 - "State"
Cohesion: 0.12
Nodes (16): canViewAsText, defaultPath, FileBrowserConstants, FileTypeHelper, getFilename, getIcon, getParent, isImage (+8 more)

### Community 22 - "media.rs"
Cohesion: 0.07
Nodes (47): Connection, Arc, Box, InputManager, LlmManager, Mutex, Option, PeerMap (+39 more)

### Community 23 - "sync_service.dart"
Cohesion: 0.07
Nodes (29): Digest, _activeTransferId, calculateDelta, _cancelledSyncPairs, checkSyncStatus, _client, executeSyncBatch, fromJson (+21 more)

### Community 24 - "transfer_engine.dart"
Cohesion: 0.07
Nodes (28): _activeTransfers, bytesTransferred, cancel, _cancelledTransfers, client, dispose, _encodeFrame, flagAckRequested (+20 more)

### Community 25 - "antigravity_field.dart"
Cohesion: 0.08
Nodes (23): build, color, _controller, createState, didChangeDependencies, dispose, initState, paint (+15 more)

### Community 26 - "process_manager_screen.dart"
Cohesion: 0.08
Nodes (24): build, _buildBadge, _buildDetailItem, _buildHeader, _buildProcessRow, _buildStatBar, _buildSystemStats, client (+16 more)

### Community 27 - "sync_manager_screen.dart"
Cohesion: 0.07
Nodes (29): build, _buildClientSourceToggle, _buildDialogField, _buildEmptyState, _buildIntervalDropdown, _buildPairCard, _buildPathRow, _buildStatusBadge (+21 more)

### Community 28 - "HostConfig"
Cohesion: 0.14
Nodes (16): B, Frame, App, centered_rect(), InputMode, Box, Option, Rect (+8 more)

### Community 29 - "cyber_alert_dialog.dart"
Cohesion: 0.09
Nodes (22): build, _buildAppBar, _showSystemTray, buildBreadcrumbs, buildDefaultContent, FileBrowserAppBar, SignalConnectionState, paint (+14 more)

### Community 30 - "my_application.cc"
Cohesion: 0.10
Nodes (20): FlPluginRegistry, fl_register_plugins(), main(), my_application_activate(), my_application_class_init(), my_application_dispose(), my_application_init(), my_application_local_command_line() (+12 more)

### Community 31 - "transfer.rs"
Cohesion: 0.08
Nodes (37): AtomicBool, handle_download_init(), Arc, File, HostMessage, Mutex, Result, RTCDataChannel (+29 more)

### Community 32 - "local_dir_selector.dart"
Cohesion: 0.09
Nodes (22): build, _buildEmptyState, _buildErrorState, _buildListView, _createNewFolder, createState, _currentPath, _errorMessage (+14 more)

### Community 33 - "audio_handler.dart"
Cohesion: 0.09
Nodes (21): AudioHandler, BaseAudioHandler, audioHandler, _client, _currentHostVolume, fastForward, FranknAudioHandler, franknAudioHandlerInstance (+13 more)

### Community 34 - "main.dart"
Cohesion: 0.09
Nodes (21): appLocale, build, createState, didChangeAppLifecycleState, didChangeMetrics, dispose, initForegroundService, initState (+13 more)

### Community 35 - "frankn_task_handler.dart"
Cohesion: 0.09
Nodes (21): _activeEngines, _broadcastToMain, FranknTaskHandler, _handleIntent, _handleUploadInit, _lastUploadNotificationTimes, onDestroy, onNotificationButtonPressed (+13 more)

### Community 36 - "notification_service.dart"
Cohesion: 0.10
Nodes (20): @pragma, dart:isolate, startCallback, dismiss, initialize, _instance, NotificationService, onActionReceivedMethod (+12 more)

### Community 37 - ".parse_msg"
Cohesion: 0.15
Nodes (23): connect_bluetooth(), connect_wifi(), get_network_status(), list_bluetooth_devices(), list_wifi_networks(), Option, String, toggle_radio() (+15 more)

### Community 38 - "frankn_dashboard.dart"
Cohesion: 0.11
Nodes (17): build, _buildHUDDivider, _buildStatItem, _buildTelemetryHUD, client, _cpu, createState, dispose (+9 more)

### Community 39 - "syslog_screen.dart"
Cohesion: 0.08
Nodes (25): build, _buildHeader, client, createState, initState, _logs, _activeLines, _activePriority (+17 more)

### Community 40 - "ssh_screen.dart"
Cohesion: 0.11
Nodes (19): _attemptAutoLogin, build, _buildHud, client, _controller, createState, dispose, _handleExplicitExit (+11 more)

### Community 41 - "host_pairing_dialog.dart"
Cohesion: 0.11
Nodes (18): _aliasController, build, _buildDivider, _buildInputField, _buildScannerSection, createState, dispose, HostPairingDialog (+10 more)

### Community 42 - "system_tray_modal.dart"
Cohesion: 0.10
Nodes (20): _btEnabled, build, _buildCompactActionButton, _buildGridButton, _buildSectionLabel, client, _confirmDestructiveAction, createState (+12 more)

### Community 43 - "settings_screen.dart"
Cohesion: 0.28
Nodes (14): check_sandbox(), check_sandbox_default(), delete_file(), ls(), mkdir(), Option, Path, PathBuf (+6 more)

### Community 44 - "package:frankn/services/rtc_thin_client.dart"
Cohesion: 0.27
Nodes (14): check_sandbox(), execute_tool(), get_sandbox_root(), parse_tool_call(), Arc, LlmManager, Mutex, Option (+6 more)

### Community 45 - "image_viewer_screen.dart"
Cohesion: 0.11
Nodes (17): _activeDownloadId, build, _buildBody, _buildTinyStatusBar, client, createState, dispose, fileName (+9 more)

### Community 46 - "host_list_panel.dart"
Cohesion: 0.12
Nodes (15): _authDialog, build, _buildDiscoveryContent, _buildHostCard, _buildSectionHeader, client, createState, dispose (+7 more)

### Community 47 - "win32_window.cpp"
Cohesion: 0.18
Nodes (14): Size, wchar_t, Scale(), Create, Destroy, UpdateTheme, Win32Window::Win32Window(), WindowClassRegistrar (+6 more)

### Community 48 - "neo_code_element_builder.dart"
Cohesion: 0.24
Nodes (8): visitElementAfter, visitElementAfter, package:flutter_highlighter/flutter_highlighter.dart, package:flutter_highlighter/themes/monokai-sublime.dart, package:flutter_markdown/flutter_markdown.dart, package:flutter_math_fork/flutter_math.dart, package:google_fonts/google_fonts.dart, package:markdown/markdown.dart

### Community 49 - "SignalingClient"
Cohesion: 0.28
Nodes (12): PeerType, Arc, Box, Option, Result, RwLock, Self, String (+4 more)

### Community 50 - "file_browser_screen.dart"
Cohesion: 0.08
Nodes (24): dart:async, _browserState, build, _buildMainContent, client, createState, dispose, _handleBulkDelete (+16 more)

### Community 51 - "settings_tile.dart"
Cohesion: 0.08
Nodes (24): bool get, direction, edges, fromId, _getNodeType, _getOrAddNode, id, isHorizontal (+16 more)

### Community 52 - "file_browser_utils.dart"
Cohesion: 0.08
Nodes (24): dart:math, MermaidGraph, build, _buildFallbackCodeBlock, _buildHeader, code, createState, didUpdateWidget (+16 more)

### Community 53 - "key_bar.dart"
Cohesion: 0.14
Nodes (13): ModState, altState, build, _buildKeyBtn, _buildModifierBtn, ctrlState, onLockAlt, onLockCtrl (+5 more)

### Community 54 - "dart:ui"
Cohesion: 0.08
Nodes (37): FranknApp, _FranknAppState, CodeEditorScreen, _CodeEditorScreenState, FileBrowserScreen, _FileBrowserScreenState, FranknDashboard, _FranknDashboardState (+29 more)

### Community 55 - "StatelessWidget"
Cohesion: 0.17
Nodes (12): kill_process(), list_processes(), Option, String, ClientMessage, HostMessage, DcMsg, Option (+4 more)

### Community 56 - "player_selector_dialog.dart"
Cohesion: 0.15
Nodes (12): _activePlayer, build, _cleanName, client, createState, dispose, initState, _isLoading (+4 more)

### Community 57 - "FlutterWindow"
Cohesion: 0.13
Nodes (13): DartProject, HWND, LPARAM, LRESULT, UINT, WPARAM, FlutterWindow, flutter_controller_ (+5 more)

### Community 58 - "file_transfer_mixin.dart"
Cohesion: 0.22
Nodes (14): get_all_audio_devices(), get_media_status(), list_players(), next_track(), previous_track(), PeerMap, String, seek() (+6 more)

### Community 59 - "bluetooth_manager_dialog.dart"
Cohesion: 0.08
Nodes (24): build, client, _connect, createState, _devices, dispose, _fetchDevices, initState (+16 more)

### Community 60 - "volume_mixer_dialog.dart"
Cohesion: 0.25
Nodes (8): CapabilityDescriptor, CapabilityRegistry, HashMap, Option, Self, String, Value, Vec

### Community 61 - "model_selector_dialog.dart"
Cohesion: 0.40
Nodes (5): _PulsingDot, _PulsingDotState, AntigravityField, _AntigravityFieldState, SingleTickerProviderStateMixin

### Community 62 - "cyber_button.dart"
Cohesion: 0.13
Nodes (15): AnimationController, build, _controller, createState, CyberButton, _CyberButtonState, CyberButtonVariant, dispose (+7 more)

### Community 63 - "MainActivity"
Cohesion: 0.23
Nodes (7): AudioServiceActivity, Bundle, FlutterEngine, MainActivity, Intent, MethodChannel, Uri

### Community 64 - "message_bubble.dart"
Cohesion: 0.14
Nodes (13): ChatMessage, build, _buildAssistant, _buildAssistantContent, _buildOperator, _buildSystem, message, package:flutter_markdown_latex/flutter_markdown_latex.dart (+5 more)

### Community 65 - "VoidCallback"
Cohesion: 0.29
Nodes (8): HostConfig, Option, PathBuf, Self, String, SyncPair, Vec, SyncPair

### Community 66 - "llm_tools.rs"
Cohesion: 0.31
Nodes (10): get_system_log(), lock_screen(), reboot(), restart_host(), Child, Option, Output, Result (+2 more)

### Community 67 - "dart:async"
Cohesion: 0.13
Nodes (14): client, downloadFile, isLoading, _onGenericMessage, refreshDirectory, saveEditorContent, setupTransferListener, transferMsg (+6 more)

### Community 68 - "package:frankn/utils/dc_msg_util.dart"
Cohesion: 0.14
Nodes (13): RemoteEntry, build, _buildGrid, _buildList, entry, fullPath, isDirIcon, isGrid (+5 more)

### Community 69 - "_PulsingDotState"
Cohesion: 0.15
Nodes (12): build, client, _connect, createState, dispose, _fetchNetworks, initState, _isLoading (+4 more)

### Community 70 - "remote_dir_selector.dart"
Cohesion: 0.26
Nodes (8): get_chats_path(), LlmManager, HashMap, Option, PathBuf, String, Value, save_chats()

### Community 71 - "handle_signaling_message"
Cohesion: 0.25
Nodes (13): get_timestamp(), handle_peer_connection(), handle_signaling_message(), main(), Message, Option, PeerMap, String (+5 more)

### Community 72 - "Win32Window"
Cohesion: 0.20
Nodes (14): OnCreate, OnDestroy, RECT, HWND, Win32Window, child_content_, GetClientArea, OnCreate (+6 more)

### Community 73 - "dart:convert"
Cohesion: 0.15
Nodes (12): dart:convert, dart:typed_data, AuthService, clearToken, computeArgon2Hash, computeResponse, _instance, _sessionToken (+4 more)

### Community 74 - "terminal_context_menu.dart"
Cohesion: 0.39
Nodes (7): HostRuntime, Arc, InputManager, LlmManager, Mutex, Option, PeerMap

### Community 75 - "Flutter Client"
Cohesion: 0.18
Nodes (12): dohee_x Neural Chat Channel, Frankn Notification Icon, Frankn Neon Frankenstein Circuit Icon, frankn_cmd Data Channel, Flutter Client, frankn_fs Data Channel, frankn_input Data Channel, frankn_media Data Channel (+4 more)

### Community 76 - "check_sandbox_default"
Cohesion: 0.29
Nodes (7): build, content, createState, _isExpanded, isStreaming, NeoThinkBlock, _NeoThinkBlockState

### Community 77 - "network.rs"
Cohesion: 0.11
Nodes (19): _buildDangerGroup, _buildSectionHeader, _buildSelectorTile, _buildSettingsGroup, _buildSettingsItem, _client, createState, _editDefaultModel (+11 more)

### Community 78 - "wWinMain"
Cohesion: 0.24
Nodes (9): wWinMain(), string, wchar_t, CreateAndAttachConsole(), GetCommandLineArguments(), Utf8FromUtf16(), _In_, _In_opt_ (+1 more)

### Community 79 - "frankn"
Cohesion: 0.25
Nodes (7): 📖 Android `ACTION_VIEW` File Reader Integration, 🛠️ Build & Development Setup, ⚡ Frankn Flutter Client, 📸 Key Screens & Subsystems, Prerequisites, Run locally, Run Static Analysis

### Community 80 - "chat_message.dart"
Cohesion: 0.18
Nodes (10): ChatRole, ChatMessage, contentNotifier, dispose, _formatTimestamp, isStreamingNotifier, role, timestamp (+2 more)

### Community 81 - "List"
Cohesion: 0.11
Nodes (18): FileViewerService, _channel, _checkInitialSharing, client, didChangeAppLifecycleState, dispose, _executeUpload, _isDialogShowing (+10 more)

### Community 82 - "model_selector_dialog.dart"
Cohesion: 0.32
Nodes (6): Bytes, PeerMap, _send_notification_to_client(), start_notification_listener(), RemoteDescriptionState, Mutex

### Community 83 - "manifest.json"
Cohesion: 0.18
Nodes (10): background_color, description, display, icons, name, orientation, prefer_related_applications, short_name (+2 more)

### Community 84 - "volume_mixer_dialog.dart"
Cohesion: 0.15
Nodes (12): build, client, createState, _debounceTimer, _devices, dispose, initState, _isLoading (+4 more)

### Community 86 - "SignalingMessage"
Cohesion: 0.33
Nodes (9): HostInfo, PeerConnection, PeerType, Message, Option, String, UnboundedSender, Vec (+1 more)

### Community 87 - "MessageHandler"
Cohesion: 0.36
Nodes (10): HWND, LPARAM, LRESULT, UINT, WPARAM, EnableFullDpiSupportIfAvailable(), GetHandle, GetThisFromHandle (+2 more)

### Community 88 - "Bytes"
Cohesion: 0.47
Nodes (5): generate_quick_hash(), handle_sync_request(), Option, Path, String

### Community 89 - "ssh.rs"
Cohesion: 0.42
Nodes (8): handle_ssh_channel(), Arc, Mutex, RTCDataChannel, start_ssh_tunnel(), stop_ssh_tunnel(), stop_ssh_tunnel_internal(), Receiver

### Community 90 - "dart:async"
Cohesion: 0.50
Nodes (4): _ViewerCodeElementBuilder, NeoCodeElementBuilder, NeoLatexElementBuilder, MarkdownElementBuilder

### Community 91 - "animated_op_btn.dart"
Cohesion: 0.09
Nodes (22): Color, dart:ui, bgColor, borderColor, build, child, CyberCard, label (+14 more)

### Community 92 - "dart:io"
Cohesion: 0.25
Nodes (7): dart:io, hasFullStorageAccess, _instance, PermissionService, requestStoragePermissions, package:permission_handler/permission_handler.dart, static final PermissionService

### Community 93 - "List"
Cohesion: 0.18
Nodes (10): _delimiterList, _escapeRegex, _generateRegexRules, inlinePatterns, NeoLatexInlineSyntax, _neoLatexPattern, onMatch, replaceAllMapped (+2 more)

### Community 94 - "ClientMessage"
Cohesion: 0.29
Nodes (7): ClientMessage, ClientMsgAuthRequest, ClientMsgAuthResponse, ClientMsgDownloadInit, ClientMsgTransferCancel, ClientMsgTransferInit, ClientMsgXDcMsg

### Community 95 - "AppLocalizations"
Cohesion: 0.40
Nodes (6): AppLocalizations, _AppLocalizationsDelegate, AppLocalizationsEn, AppLocalizationsKo, of, LocalizationsDelegate

### Community 96 - "RtcClient"
Cohesion: 0.60
Nodes (6): RtcClient, RtcClientBase, RtcCommands, RtcConnection, RtcMessageHandler, RtcSignaling

### Community 98 - "TransferProgressEvent"
Cohesion: 0.40
Nodes (5): TransferProgressComplete, TransferProgressEvent, TransferProgressFailed, TransferProgressStart, TransferProgressUpdate

### Community 99 - "Frankn Master Logo"
Cohesion: 0.50
Nodes (4): Frankn Background Logo, Frankn Foreground Logo, Frankn Master Logo, Master Logo (PNG)

### Community 100 - "System Tray / Dashboard UI"
Cohesion: 0.50
Nodes (4): Folder Synchronization UI, System Log UI, System Tray / Dashboard UI, Frankn App Logo

### Community 102 - "FileBrowserState"
Cohesion: 0.18
Nodes (11): AnimatedOpBtn, _AnimatedOpBtnState, build, color, createState, icon, _isPressed, label (+3 more)

### Community 104 - "Linux Project CMake"
Cohesion: 0.67
Nodes (3): Linux Project CMake, Linux Flutter CMake, Linux Runner CMake

### Community 106 - "Web Index HTML"
Cohesion: 0.67
Nodes (3): Web Favicon, Web Index HTML, Web App Icon 192

### Community 107 - "Windows Project CMake"
Cohesion: 0.67
Nodes (3): Windows Project CMake, Windows Flutter CMake, Windows Runner CMake

### Community 130 - "mod.rs"
Cohesion: 0.16
Nodes (9): Device, InputManager, InputMsg, Result, Self, String, InputManager, Result (+1 more)

### Community 163 - "ssh_theme.dart"
Cohesion: 0.18
Nodes (10): 1. Architectural Philosophy, 2. Core Runtime Services, 3. Communication & P2P Transport Layer (`R7`), 4. Zero-Trust Security & Sandboxing (`R5`), 5. Engineering Discipline, A. Capability Registry & Loader (`R1`), B. Memory Service & State Store (`R2`, `R3`), C. Core Event Bus (`R4`) (+2 more)

### Community 164 - "notifications.rs"
Cohesion: 0.12
Nodes (17): HomeScreen, DesktopLayout, MessageBubble, FileBrowserItem, MobileLayout, QuickFunction, build, icon (+9 more)

### Community 165 - ".parse_msg"
Cohesion: 0.31
Nodes (8): DcMsg, Arc, HostMessage, LlmManager, Mutex, Option, PeerMap, String

### Community 166 - "CustomPainter"
Cohesion: 0.50
Nodes (4): CustomPainter, AntigravityPainter, ScanlinePainter, NeoMermaidGraphPainter

### Community 168 - "_FranknAppState"
Cohesion: 0.17
Nodes (11): _browserState, build, client, _createNewFolder, createState, dispose, initialPath, initState (+3 more)

### Community 170 - "parse_dc_msg"
Cohesion: 0.25
Nodes (9): RtcThinClient, HostConnectionState, build, _client, build, client, package:frankn/services/rtc_thin_client.dart, package:frankn/widgets/host_list_panel.dart (+1 more)

### Community 175 - "log_terminal.dart"
Cohesion: 0.18
Nodes (10): build, _buildHeaderBtn, _buildRichLogLine, isExpanded, isMinimized, logs, LogTerminal, onFullscreen (+2 more)

### Community 176 - "chat_stream_detached"
Cohesion: 0.27
Nodes (7): chat_stream_detached(), LlmManager, Arc, Mutex, Option, Result, String

### Community 177 - ".run"
Cohesion: 0.25
Nodes (6): Box, Result, Self, get_cpu_temp(), get_timestamp(), Result

### Community 178 - ".reply"
Cohesion: 0.39
Nodes (5): HostMessage, Option, Result, String, Value

### Community 179 - "terminal_context_menu.dart"
Cohesion: 0.22
Nodes (8): build, _buildMenuItem, child, _showMenu, terminal, TerminalContextMenu, package:flutter/services.dart, package:xterm/xterm.dart

### Community 180 - "main.rs"
Cohesion: 0.29
Nodes (7): Cli, Commands, main(), Box, Option, Result, String

### Community 181 - ".set_remote_data_channel_handler"
Cohesion: 0.29
Nodes (6): Clone, Fn, Arc, RTCDataChannel, Send, Sync

### Community 182 - "VoidCallback"
Cohesion: 0.29
Nodes (6): build, isConnected, isConnecting, onExit, SshStatusBar, VoidCallback

### Community 183 - "context.rs"
Cohesion: 0.50
Nodes (3): Arc, Mutex, Self

### Community 184 - "FileBrowserState"
Cohesion: 0.67
Nodes (3): ChangeNotifier, FileBrowserState, SshController

## Knowledge Gaps
- **1941 isolated node(s):** `MediaPlayer`, `localeName`, `delegate`, `localizationsDelegates`, `supportedLocales` (+1936 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **55 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `Error` connect `RTCConn` to `mod.rs`, `utils.dart`, `.run`, `SignalingClient`, `main.rs`, `media.rs`, `HostConfig`, `transfer.rs`?**
  _High betweenness centrality (0.196) - this node is a cross-community bridge._
- **Why does `RTCConn` connect `RTCConn` to `.parse_msg`, `package:frankn/services/rtc_thin_client.dart`, `model_selector_dialog.dart`, `.set_remote_data_channel_handler`, `media.rs`, `context.rs`, `ssh.rs`, `transfer.rs`?**
  _High betweenness centrality (0.069) - this node is a cross-community bridge._
- **Why does `CommandContext` connect `.parse_msg` to `VoidCallback`, `settings_screen.dart`, `LlmManager`, `chat_stream_detached`, `RTCConn`, `.reply`, `StatelessWidget`, `Bytes`, `ssh.rs`, `file_transfer_mixin.dart`, `context.rs`?**
  _High betweenness centrality (0.052) - this node is a cross-community bridge._
- **What connects `MediaPlayer`, `localeName`, `delegate` to the rest of the system?**
  _1941 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `app_localizations.dart` be split into smaller, more focused modules?**
  _Cohesion score 0.011299435028248588 - nodes in this community are weakly interconnected._
- **Should `app_localizations_ko.dart` be split into smaller, more focused modules?**
  _Cohesion score 0.012195121951219513 - nodes in this community are weakly interconnected._
- **Should `app_localizations_en.dart` be split into smaller, more focused modules?**
  _Cohesion score 0.012195121951219513 - nodes in this community are weakly interconnected._