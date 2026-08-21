import 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';

export 'theme.dart';
export 'package:frankn/services/client_rtc/host_connection_state.dart';

late Directory globalTempDir;

enum SignalConnectionState { disconnected, connecting, connected, failed }

enum ModState { off, active, locked }

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
  static const AuthChallenge = "auth_challenge";
  static const Register = "register";
  static const RegisterSuccess = "register_success";
  static const RegisterFailure = "register_failure";
  static const SessionReplaced = "session_replaced";
  static const SubscribeHosts = "subscribe_hosts";
  static const CheckHostsStatus = "check_hosts_status";
  static const HostsStatusResponse = "hosts_status_response";
  static const UpdateHostAcl = "update_host_acl";
  static const ListHosts = "list_hosts";
  static const HostList = "host_list";
  static const PeerStatusUpdate = "peer_status_update";
  static const Offer = "offer";
  static const Answer = "answer";
  static const IceCandidate = "ice_candidate";
  static const Error = "error";
}

enum SyncMode { mirroring, singleSourceOfTruth }

class SyncPair {
  final String localPath;
  final String remotePath;
  final SyncMode mode;
  final bool clientIsSource; // Only used for singleSourceOfTruth
  final int intervalMinutes;
  final int? lastSynced; // Unix timestamp in seconds

  SyncPair({
    required this.localPath,
    required this.remotePath,
    required this.mode,
    this.clientIsSource = true,
    this.intervalMinutes = 60,
    this.lastSynced,
  });

  Map<String, dynamic> toJson() => {
    'local_path': localPath,
    'remote_path': remotePath,
    'mode': mode.index,
    'client_is_source': clientIsSource,
    'interval_minutes': intervalMinutes,
    'last_synced': lastSynced,
  };

  factory SyncPair.fromJson(Map<String, dynamic> json) => SyncPair(
    localPath: json['local_path'],
    remotePath: json['remote_path'],
    mode: SyncMode.values[json['mode'] ?? 0],
    clientIsSource: json['client_is_source'] ?? true,
    intervalMinutes: json['interval_minutes'] ?? 60,
    lastSynced: json['last_synced'],
  );
}

class FileUtils {
  static String formatSize(int bytes) {
    if (bytes < 1024) return "$bytes B";
    if (bytes < 1024 * 1024) return "${(bytes / 1024).toStringAsFixed(1)} KB";
    if (bytes < 1024 * 1024 * 1024) {
      return "${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB";
    }
    return "${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB";
  }

  /// Generates a stable transfer ID for a file based on its path and size.
  /// This ensures that resumable transfers can find their .part files.
  static String generateStableTransferId(String path, int size) {
    final bytes = utf8.encode("$path|$size");
    final digest = sha256.convert(bytes);
    final hex = digest.toString();

    // Format as UUID (8-4-4-4-12)
    return "${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20, 32)}";
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
