import 'dart:async';
import 'dart:developer';
import 'rtc_host.dart';

/// Manages the collection of remote [RtcHost] instances and coordinates host lookup and lifecycle events.
class RtcHostManager {
  final Map<String, RtcHost> _hosts = {};
  final StreamController<List<RtcHost>> _hostsStreamController =
      StreamController<List<RtcHost>>.broadcast();

  /// Map of registered hosts by host ID.
  Map<String, RtcHost> get hosts => Map.unmodifiable(_hosts);

  /// Stream of active hosts list.
  Stream<List<RtcHost>> get hostsStream => _hostsStreamController.stream;

  /// Retrieves or creates an [RtcHost] instance for [hostId].
  RtcHost getOrCreateHost(String hostId, {String? hostName}) {
    if (_hosts.containsKey(hostId)) {
      final existing = _hosts[hostId]!;
      if (hostName != null && hostName.isNotEmpty) {
        existing.hostName = hostName;
      }
      return existing;
    }

    final host = RtcHost(
      hostId: hostId,
      hostName: hostName ?? 'Remote Host',
    );
    _hosts[hostId] = host;
    log('[HOST-MANAGER] Registered host $hostId (${host.hostName})');
    _notifyHostsChanged();
    return host;
  }

  /// Finds host by [hostId] if present.
  RtcHost? findHost(String hostId) => _hosts[hostId];

  /// Removes and disposes an host by [hostId].
  void removeHost(String hostId) {
    final host = _hosts.remove(hostId);
    if (host != null) {
      host.dispose();
      log('[HOST-MANAGER] Removed host $hostId');
      _notifyHostsChanged();
    }
  }

  /// Clears active connection resources for [hostId].
  void clearConnections(String hostId) {
    final host = _hosts[hostId];
    if (host != null) {
      host.clearConnections();
    }
  }

  /// Disposes all managed host instances.
  void clearAll() {
    for (final host in _hosts.values) {
      host.dispose();
    }
    _hosts.clear();
    _notifyHostsChanged();
  }

  void _notifyHostsChanged() {
    _hostsStreamController.add(_hosts.values.toList());
  }

  void dispose() {
    clearAll();
    _hostsStreamController.close();
  }
}
