import 'package:flutter/foundation.dart';
import 'capability_descriptor.dart';
import 'capability_provider.dart';

enum CapabilityAvailability {
  available,
  offline,
  busy,
  unknown;

  static CapabilityAvailability fromString(String? val) {
    if (val == null) return CapabilityAvailability.unknown;
    switch (val.toLowerCase()) {
      case 'available':
      case 'online':
      case 'active':
        return CapabilityAvailability.available;
      case 'offline':
      case 'disconnected':
        return CapabilityAvailability.offline;
      case 'busy':
      case 'in_use':
        return CapabilityAvailability.busy;
      default:
        return CapabilityAvailability.unknown;
    }
  }
}

class CapabilityInventoryEntry {
  final CapabilityDescriptor descriptor;
  final CapabilityProvider provider;
  final CapabilityAvailability availability;

  const CapabilityInventoryEntry({
    required this.descriptor,
    required this.provider,
    this.availability = CapabilityAvailability.available,
  });

  String get key => '${provider.kind.name}:${provider.providerId}:${descriptor.id}';

  factory CapabilityInventoryEntry.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> descMap;
    final Map<String, dynamic> provMap;
    String? availabilityStr;

    if (json.containsKey('descriptor') && json['descriptor'] is Map) {
      descMap = Map<String, dynamic>.from(json['descriptor'] as Map);
      provMap = json['provider'] is Map
          ? Map<String, dynamic>.from(json['provider'] as Map)
          : <String, dynamic>{};
      availabilityStr = json['availability'] as String?;
    } else {
      descMap = json;
      provMap = json;
      availabilityStr = 'available';
    }

    return CapabilityInventoryEntry(
      descriptor: CapabilityDescriptor.fromJson(descMap),
      provider: CapabilityProvider.fromJson(provMap),
      availability: CapabilityAvailability.fromString(availabilityStr),
    );
  }

  Map<String, dynamic> toJson() => {
    'descriptor': descriptor.toJson(),
    'provider': provider.toJson(),
    'availability': availability.name,
  };
}

class CapabilityInventory extends ChangeNotifier {
  final Map<String, CapabilityInventoryEntry> _entries = {};

  List<CapabilityInventoryEntry> get entries => List.unmodifiable(_entries.values);

  void updateFromList(List<Map<String, dynamic>> rawList) {
    _entries.clear();
    for (final item in rawList) {
      final entry = CapabilityInventoryEntry.fromJson(item);
      _entries[entry.key] = entry;
    }
    notifyListeners();
  }

  void updateEntry(CapabilityInventoryEntry entry) {
    _entries[entry.key] = entry;
    notifyListeners();
  }

  void removeByProvider(String providerId) {
    _entries.removeWhere((_, entry) => entry.provider.providerId == providerId);
    notifyListeners();
  }

  void clear() {
    _entries.clear();
    notifyListeners();
  }

  Iterable<CapabilityInventoryEntry> byCapability(String capabilityId) {
    return _entries.values.where((e) => e.descriptor.id == capabilityId);
  }

  Iterable<CapabilityInventoryEntry> byProvider(String providerId) {
    return _entries.values.where((e) => e.provider.providerId == providerId);
  }

  CapabilityInventoryEntry? find(String capabilityId, String providerId) {
    for (final entry in _entries.values) {
      if (entry.descriptor.id == capabilityId &&
          (entry.provider.providerId == providerId || providerId == 'unknown' || providerId == 'host')) {
        return entry;
      }
    }
    return null;
  }
}
