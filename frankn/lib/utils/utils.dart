import 'dart:io';
import 'package:flutter/material.dart';

late Directory globalTempDir;

enum SignalConnectionState { disconnected, connecting, connected, failed }

enum HostConnectionState {
  disconnected,
  connecting,
  connected,
  failed,
  authenticated,
}

class MediaUpdate {
  final bool playing;
  final String metadata;
  final String? artData;
  final double position; // u64 in Rust translates to int in Dart
  final double length;
  final double volume; // f64 in Rust translates to double in Dart
  final int timestamp;

  final String playerName;
  final String trackId;

  MediaUpdate({
    required this.playing,
    required this.metadata,
    this.artData,
    required this.position,
    required this.length,
    required this.volume,
    required this.timestamp,
    required this.playerName,
    required this.trackId,
  });

  // The factory constructor acts as your JSON parser
  factory MediaUpdate.fromJson(Map<String, dynamic> json) {
    return MediaUpdate(
      playerName: (json['player_name'] ?? 'Unknown').toString().replaceAll(
            "org.mpris.MediaPlayer2.",
            "",
          ),
      playing: json['playing'] == true,
      metadata: (json['metadata'] ?? 'No Media').toString(),
      artData: json['art_data']?.toString(),
      position: (json['position'] as num?)?.toDouble() ?? 0.0,
      length: (json['length'] as num?)?.toDouble() ?? 0.0,
      volume: (json['volume'] as num?)?.toDouble() ?? 0.0,
      timestamp: (json['timestamp'] as num?)?.toInt() ?? 0,
      trackId: (json['track_id'] ?? '').toString(),
    );
  }
}

enum ModState { off, active, locked }

class NeoColors {
  static const background = Color(0xFF09090B);
  static const darkZinc = Color(0xFF18181B);
  static const zinc = Color(0xFF71717A);
  static const cyan = Color(0xFF06B6D4);
  static const fuchsia = Color(0xFFD946EF);
  static const matrixGreen = Color(0xFF10B981);
}

class AppColors {
  // Backgrounds
  static const Color voidBlack = Color(0xFF050505);
  static const Color deepSpace = Color(0xFF0B0D17);
  static const Color panelGrey = Color(0xFF1A1A2E);

  // Neon Accents
  static const Color neonCyan = Color(0xFF00F3FF);
  static const Color neonPink = Color(0xFFFF00FF);
  static const Color cyberYellow = Color(0xFFFFEE00);
  static const Color matrixGreen = Color(0xFF00FF41);

  // Functional Colors
  static const Color errorRed = Color(0xFFFF2A2A);
  static const Color textWhite = Color(0xFFE0E0E0);
  static const Color textGrey = Color(0xFFAAAAAA);
}

class AppConstants {
  // Layout Breakpoints
  static const double mobileBreakpoint = 1200.0;

  // UI Constants
  static const double defaultPadding = 16.0;
  static const double borderRadius = 8.0; // Sharp corners for cyberpunk feel
}

class InputSig {
  static const MouseClick = "mouse_click";
  static const Text = "type_text";
  static const MouseMove = "mouse_move";
  static const KeyPress = "key_press";
  static const Scroll = "scroll";
}

class SignalingMessage {
  static const RegisterSuccess = "register_success";
  static const RegisterFailure = "register_failure";
  static const ListHosts = "list_hosts";
  static const HostList = "host_list";
  static const PeerStatusUpdate = "peer_status_update";
  static const Offer = "offer";
  static const Answer = "answer";
  static const IceCandidate = "ice_candidate";
  static const Error = "error";
}

class DcMsg {
  static const Challenge = "challenge";
  static const AuthSuccess = "auth_success";
  static const AuthRequest = "auth_request";
  static const AuthFailed = "auth_failed";
  static const Notification = "notification";
  static const HostResponse = "response";
  static const Telemetry = "telemetry";

  static const Key = "dc_msg_type";

  // Power
  static const Disconnect = "disconnect";
  static const Shutdown = "shutdown";
  static const Reboot = "reboot";
  static const LockScreen = "lock_screen";
  static const UnlockScreen = "unlock_screen";

  // System
  static const Update = "update";
  static const RestartHostServer = "restart_host_server";
  static const Ping = "ping";
  static const Pong = "Pong";
  static const Kill = "kill";
  static const ListProcesses = "list_processes";
  static const SystemLog = "system_log";
  static const StartSsh = "start_ssh";
  static const StopSsh = "stop_ssh";

  // File System (basic operations)
  static const Ls = "ls";
  static const DeleteFile = "delete_file";

  // Audio Mixer
  static const GetAudioDevices = "get_audio_devices";
  static const SetDeviceVolume = "set_device_volume";
  static const SetDefaultAudioDevice = "set_default_audio_device";

  // Media
  static const TogglePlayPause = "toggle_play_pause";
  static const PlayNextTrack = "play_next_track";
  static const PlayPreviousTrack = "play_previous_track";
  static const SetVolume = "set_volume";
  static const GetMediaStatus = "get_media_status";
  static const ListPlayers = "list_players";
  static const SetActivePlayer = "set_active_player";
  static const Seek = "seek";

  // Network
  static const GetNetworkStatus = "get_network_status";
  static const ToggleRadio = "toggle_radio";
  static const ListWifiNetworks = "list_wifi_networks";
  static const ConnectWifi = "connect_wifi";
  static const ListBluetoothDevices = "list_bluetooth_devices";
  static const ConnectBluetooth = "connect_bluetooth";

  // LLM
  static const LlmStart = "llm_start";
  static const LlmChat = "llm_chat";
  static const LlmLoadChat = "llm_load_chat";
  static const LlmDeleteChat = "llm_delete_chat";
  static const LlmListChats = "llm_list_chats";
  static const LlmStop = "llm_stop";
  static const LlmToken = "llm_token";

  // Folder Sync
  static const SyncRequest = "sync_request";
}

class FsMsg {
  // File Transfer (resume-aware binary protocol)
  static const TransferInit = "transfer_init";
  static const TransferAck = "transfer_ack";
  static const TransferComplete = "transfer_complete";
  static const TransferCancel = "transfer_cancel";
  static const DownloadInit = "download_init";
  static const DownloadStart = "download_start";
  static const DownloadEnd = "download_end";

  // Folder Sync
  static const SyncSnapshot = "sync_snapshot";
}

enum SyncMode { mirroring, singleSourceOfTruth }

class SyncPair {
  final String localPath;
  final String remotePath;
  final SyncMode mode;
  final bool clientIsSource; // Only used for singleSourceOfTruth
  final int intervalMinutes;

  SyncPair({
    required this.localPath,
    required this.remotePath,
    required this.mode,
    this.clientIsSource = true,
    this.intervalMinutes = 60,
  });

  Map<String, dynamic> toJson() => {
        'local_path': localPath,
        'remote_path': remotePath,
        'mode': mode.index,
        'client_is_source': clientIsSource,
        'interval_minutes': intervalMinutes,
      };

  factory SyncPair.fromJson(Map<String, dynamic> json) => SyncPair(
        localPath: json['local_path'],
        remotePath: json['remote_path'],
        mode: SyncMode.values[json['mode'] ?? 0],
        clientIsSource: json['client_is_source'] ?? true,
        intervalMinutes: json['interval_minutes'] ?? 60,
      );
}

class MediaDCMessage {
  static const MediaUpdate = "media_update";
}

class FileUtils {
  static String formatSize(int bytes) {
    if (bytes < 1024) return "$bytes B";
    if (bytes < 1024 * 1024) return "${(bytes / 1024).toStringAsFixed(1)} KB";
    return "${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB";
  }

  static IconData getFileIcon(String name) {
    final ext = name.split('.').last.toLowerCase();
    switch (ext) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
        return Icons.image;
      case 'mp4':
      case 'mkv':
      case 'mov':
        return Icons.movie;
      case 'mp3':
      case 'wav':
      case 'flac':
        return Icons.music_note;
      case 'zip':
      case 'tar':
      case 'gz':
      case '7z':
        return Icons.archive;
      case 'rs':
      case 'dart':
      case 'py':
      case 'js':
        return Icons.code;
      default:
        return Icons.insert_drive_file;
    }
  }
}
