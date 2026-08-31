import 'package:flutter/foundation.dart';
import 'capability_descriptor.dart';
import 'capability_provider.dart';

enum CapabilitySessionStatus {
  idle,
  requesting,
  pending,
  active,
  failed,
  closing,
  closed;

  static CapabilitySessionStatus fromString(String? val) {
    if (val == null) return CapabilitySessionStatus.idle;
    switch (val.toLowerCase()) {
      case 'idle':
        return CapabilitySessionStatus.idle;
      case 'requesting':
        return CapabilitySessionStatus.requesting;
      case 'pending':
        return CapabilitySessionStatus.pending;
      case 'active':
      case 'available':
        return CapabilitySessionStatus.active;
      case 'failed':
        return CapabilitySessionStatus.failed;
      case 'closing':
        return CapabilitySessionStatus.closing;
      case 'closed':
      case 'deactivated':
        return CapabilitySessionStatus.closed;
      default:
        return CapabilitySessionStatus.idle;
    }
  }
}

class CapabilitySession extends ChangeNotifier {
  final String sessionId;
  final CapabilityProvider provider;
  final CapabilityDescriptor descriptor;
  final Map<String, dynamic> properties;

  CapabilitySessionStatus _status = CapabilitySessionStatus.idle;
  String? _error;

  CapabilitySessionStatus get status => _status;
  String? get error => _error;
  bool get isActive => _status == CapabilitySessionStatus.active;

  CapabilitySession({
    required this.sessionId,
    required this.provider,
    required this.descriptor,
    this.properties = const {},
    CapabilitySessionStatus initialStatus = CapabilitySessionStatus.idle,
  }) : _status = initialStatus;

  void updateStatus(CapabilitySessionStatus newStatus, [String? err]) {
    if (_status == newStatus && _error == err) return;
    _status = newStatus;
    if (err != null) _error = err;
    notifyListeners();
  }
}
