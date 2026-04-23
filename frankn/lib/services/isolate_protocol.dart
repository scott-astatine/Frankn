import 'dart:convert';

class IsolateMsg {
  final String type; // e.g., 'intent', 'event', 'state'
  final String action; // e.g., 'connect', 'upload', 'host_state_change'
  final Map<String, dynamic> payload;

  IsolateMsg({
    required this.type,
    required this.action,
    this.payload = const {},
  });

  String toJson() =>
      jsonEncode({'type': type, 'action': action, 'payload': payload});

  factory IsolateMsg.fromJson(String source) {
    final map = jsonDecode(source);
    return IsolateMsg(
      type: map['type']?.toString() ?? '',
      action: map['action']?.toString() ?? '',
      payload: map['payload'] is Map<String, dynamic>
          ? map['payload'] as Map<String, dynamic>
          : {},
    );
  }
}
