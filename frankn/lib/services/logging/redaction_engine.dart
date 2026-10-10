import 'dart:convert';

/// Abstract contract for secret redaction boundaries.
abstract class RedactionEngineContract {
  String sanitizeMessage(String input);
  dynamic sanitizeValue(dynamic value);
  Map<String, dynamic>? sanitizeMetadata(Map<String, dynamic>? metadata);
}

/// One redaction boundary shared by every telemetry sink.
///
/// Structured values are sanitized recursively before they are formatted. The
/// text patterns are only a final guard for legacy free-form messages.
class RedactionEngine implements RedactionEngineContract {
  static const String redactedMask = '[REDACTED]';

  static const Set<String> _sensitiveKeys = {
    'password',
    'pass',
    'passcode',
    'secret',
    'authtoken',
    'token',
    'privatekey',
    'keypair',
    'challengeresponse',
    'response',
    'proof',
    'credential',
    'credentials',
    'passwordhash',
    'passwordverifier',
    'argon2',
    'argon2hash',
    'salt',
    'signature',
    'sessionkey',
    'sessiontoken',
    'bearer',
    'request',
    'finalization',
    'opaque',
    'verifier',
  };

  static final List<RegExp> _textPatterns = [
    RegExp(r"""\$argon2(?:id|i|d)\$[^\s"'})\]]+""", caseSensitive: false),
    RegExp(
      r"""(["']?(?:auth[_-]?token|access[_-]?token|session[_-]?token|token|password|passcode|pass|secret|response|proof|credential|credentials|private[_-]?key|password[_-]?hash|argon2[_-]?hash|salt|signature|bearer)["']?\s*[:=]\s*)("(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|[^\s,;}]+)""",
      caseSensitive: false,
    ),
    RegExp(
      r'-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z0-9 ]*PRIVATE KEY-----',
    ),
  ];

  static String _normalizeKey(String key) =>
      key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  @override
  dynamic sanitizeValue(dynamic value) {
    if (value is Map) {
      final type = value['type']?.toString();
      final isAuthEnvelope =
          type != null && (type.startsWith('auth_') || type == 'challenge');
      return value.map<String, dynamic>((key, item) {
        final stringKey = key.toString();
        final normalizedKey = _normalizeKey(stringKey);
        if ((isAuthEnvelope &&
                normalizedKey != 'type' &&
                normalizedKey != 'timestamp') ||
            _sensitiveKeys.contains(normalizedKey)) {
          return MapEntry(stringKey, redactedMask);
        }
        return MapEntry(stringKey, sanitizeValue(item));
      });
    }
    if (value is List) return value.map(sanitizeValue).toList();
    if (value is String) return sanitizeMessage(value);
    return value;
  }

  @override
  String sanitizeMessage(String input) {
    if (input.isEmpty) return input;
    var output = _sanitizeEmbeddedJson(input);
    for (final pattern in _textPatterns) {
      output = output.replaceAllMapped(pattern, (match) {
        if (match.groupCount == 0) return redactedMask;
        final value = match.group(2);
        final safeValue = value != null && value.startsWith('"')
            ? '"$redactedMask"'
            : value != null && value.startsWith("'")
            ? "'$redactedMask'"
            : redactedMask;
        return '${match.group(1)}$safeValue';
      });
    }
    return output;
  }

  String _sanitizeEmbeddedJson(String input) {
    // Also handles a legacy log prefix before an encoded object, e.g. "RX: {...}".
    final start = input.indexOf('{');
    if (start < 0) return input;
    var depth = 0;
    var quoted = false;
    var escaped = false;
    for (var i = start; i < input.length; i++) {
      final char = input[i];
      if (quoted) {
        if (escaped) {
          escaped = false;
        } else if (char == r'\') {
          escaped = true;
        } else if (char == '"') {
          quoted = false;
        }
        continue;
      }
      if (char == '"') {
        quoted = true;
      } else if (char == '{') {
        depth++;
      } else if (char == '}' && --depth == 0) {
        final encoded = input.substring(start, i + 1);
        try {
          final decoded = jsonDecode(encoded);
          final safe = jsonEncode(sanitizeValue(decoded));
          return '${input.substring(0, start)}$safe${input.substring(i + 1)}';
        } on FormatException {
          return input;
        }
      }
    }
    return input;
  }

  @override
  Map<String, dynamic>? sanitizeMetadata(Map<String, dynamic>? metadata) {
    if (metadata == null) return null;
    return sanitizeValue(metadata) as Map<String, dynamic>;
  }
}
