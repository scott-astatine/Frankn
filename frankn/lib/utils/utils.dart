import 'package:flutter/material.dart';

enum SignalConnectionState { disconnected, connecting, connected, failed }

enum HostConnectionState {
  disconnected,
  connecting,
  connected,
  failed,
  authenticated,
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

class SinalingMessage {
  static const RegisterSuccess = "register_success";
  static const RegisterFailure = "register_failure";
  static const ListHosts = "list_hosts";
  static const HostList = "host_list";
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
  static const FileTransferStart = "file_transfer_start";
  static const FileChunk = "file_chunk";
  static const FileTransferEnd = "file_transfer_end";


  static const Key = "dc_msg_type";

  // Power
  static const Shutdown = "shutdown";
  static const Reboot = "reboot";
  static const LockScreen = "lock_screen";
  static const UnlockScreen = "unlock_screen";

  // System
  static const Update = "update";
  static const RestartHostServer = "restart_host_server";
  static const Ping = "ping";
  static const Kill = "kill";
  static const ListProcesses = "list_processes";
  static const SystemLog = "system_log";
  static const StartSsh = "start_ssh";
  static const StopSsh = "stop_ssh";

  // File System
  static const Ls = "ls";
  static const GetFile = "get_file";
  static const DeleteFile = "delete_file";
  static const UploadStart = "upload_start";
  static const UploadChunk = "upload_chunk";
  static const UploadEnd = "upload_end";

  // Audio Mixer
  static const GetAudioDevices = "get_audio_devices";
  static const SetDeviceVolume = "set_device_volume";
  static const SetDefaultAudioDevice = "set_default_audio_device";

  // Media
  static const TogglePlayPause = "toggle_play_pause";
  static const PlayNextTrack = "play_next_track";
  static const PlayPreviousTrack = "play_previous_track";
  static const SetVolume = "set_volume";
  static const StartMediaSync = "start_media_sync";
  static const GetMediaStatus = "get_media_status";
  static const ListPlayers = "list_players";
  static const SetActivePlayer = "set_active_player";
  static const Seek = "seek";
}

class MediaDCMessage {
  static const MediaUpdate = "media_update";
  static const MediaPositionUpdate = "media_position_update";

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
