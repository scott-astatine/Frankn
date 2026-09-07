import 'dart:convert';

/// Immutable point-in-time runtime state snapshot schema.
/// Captured at Diagnostic Capture Session START and END to record system context.
class FranknStateSnapshot {
  final int timestampMs;
  final String label; // "CAPTURE_START" or "CAPTURE_END"
  final String hostConnectionState; // e.g. "authenticated", "connecting", "disconnected"
  final String signalingState; // e.g. "connected", "reconnecting", "offline"
  final String? activeHostId;
  final String? activeHostName;
  final bool hasActiveInternet;
  final List<String> onlineHostIds;
  final int activeCapabilitySessions;
  final int activeSyncPairs;
  final Map<String, dynamic> systemMemoryInfo;

  const FranknStateSnapshot({
    required this.timestampMs,
    required this.label,
    required this.hostConnectionState,
    required this.signalingState,
    this.activeHostId,
    this.activeHostName,
    required this.hasActiveInternet,
    required this.onlineHostIds,
    required this.activeCapabilitySessions,
    required this.activeSyncPairs,
    required this.systemMemoryInfo,
  });

  Map<String, dynamic> toJson() => {
        'ts': timestampMs,
        'label': label,
        'host_state': hostConnectionState,
        'sig_state': signalingState,
        if (activeHostId != null) 'host_id': activeHostId,
        if (activeHostName != null) 'host_name': activeHostName,
        'has_internet': hasActiveInternet,
        'online_hosts': onlineHostIds,
        'cap_sessions': activeCapabilitySessions,
        'sync_pairs': activeSyncPairs,
        'sys_info': systemMemoryInfo,
      };

  factory FranknStateSnapshot.fromJson(Map<String, dynamic> map) =>
      FranknStateSnapshot(
        timestampMs: map['ts'] as int,
        label: map['label'] as String,
        hostConnectionState: map['host_state'] as String,
        signalingState: map['sig_state'] as String,
        activeHostId: map['host_id'] as String?,
        activeHostName: map['host_name'] as String?,
        hasActiveInternet: map['has_internet'] as bool? ?? false,
        onlineHostIds: List<String>.from(map['online_hosts'] ?? []),
        activeCapabilitySessions: map['cap_sessions'] as int? ?? 0,
        activeSyncPairs: map['sync_pairs'] as int? ?? 0,
        systemMemoryInfo: Map<String, dynamic>.from(map['sys_info'] ?? {}),
      );

  String toEncodedJson() => jsonEncode(toJson());

  factory FranknStateSnapshot.fromEncodedJson(String source) =>
      FranknStateSnapshot.fromJson(jsonDecode(source) as Map<String, dynamic>);
}
