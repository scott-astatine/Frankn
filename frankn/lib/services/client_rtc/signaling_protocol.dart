import 'dart:convert';

/// Wire message type constants for Frankn signaling protocol.
class SignalingMessageType {
  static const String register = 'register';
  static const String registerSuccess = 'register_success';
  static const String registerFailure = 'register_failure';
  static const String authChallenge = 'auth_challenge';
  static const String authResponse = 'auth_response';
  static const String offer = 'offer';
  static const String answer = 'answer';
  static const String iceCandidate = 'ice_candidate';
  static const String hostsStatusRequest = 'hosts_status_request';
  static const String hostsStatusResponse = 'hosts_status_response';
  static const String hostsStatusSubscribe = 'hosts_status_subscribe';
}

/// Parsed signaling envelope.
class SignalingEnvelope {
  final String type;
  final Map<String, dynamic> raw;

  SignalingEnvelope({required this.type, required this.raw});

  static SignalingEnvelope? parse(dynamic input) {
    if (input is! String) return null;
    try {
      final data = jsonDecode(input);
      if (data is! Map<String, dynamic>) return null;
      final type = data['type'] as String?;
      if (type == null) return null;
      return SignalingEnvelope(type: type, raw: data);
    } catch (_) {
      return null;
    }
  }
}

/// Protocol serializer for outbound signaling envelopes.
class SignalingProtocol {
  /// Encodes data-plane envelope with signature and correlation metadata.
  static String encodeDataPlaneMessage({
    required String type,
    required String selfId,
    required String toPeerId,
    required String? sessionId,
    required int sequence,
    required String signatureHex,
    required int timestamp,
    required Map<String, dynamic> payload,
  }) {
    final msg = {
      'type': type,
      'from': selfId,
      'to': toPeerId,
      'session_id': sessionId,
      'sequence': sequence,
      'signature': signatureHex,
      'timestamp': timestamp,
      ...payload,
    };
    return jsonEncode(msg);
  }

  /// Encodes authentication response envelope.
  static String encodeAuthResponse({
    required String publicKeyHex,
    required String signatureHex,
    required String deviceName,
    required String osName,
    required String clientVersion,
  }) {
    return jsonEncode({
      'type': SignalingMessageType.authResponse,
      'public_key': publicKeyHex,
      'signature': signatureHex,
      'device_name': deviceName,
      'os_name': osName,
      'client_version': clientVersion,
    });
  }

  /// Encodes host status subscription envelope.
  static String encodeHostStatusSubscribe(List<String> hostIds) {
    return jsonEncode({
      'type': SignalingMessageType.hostsStatusSubscribe,
      'host_ids': hostIds,
    });
  }
}
