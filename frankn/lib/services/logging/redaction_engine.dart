/// Abstract contract for secret redaction boundaries.
abstract class RedactionEngineContract {
  String sanitizeMessage(String input);
  Map<String, dynamic>? sanitizeMetadata(Map<String, dynamic>? metadata);
}

/// Default mandatory implementation of secret redaction boundary.
/// Enforces non-bypassable masking of passwords, private keys, auth tokens,
/// Argon2 secrets, challenge responses, salts, and digital signatures.
class RedactionEngine implements RedactionEngineContract {
  static const String _redactedMask = "[REDACTED]";

  // Keys whose values MUST be masked in structured metadata maps
  static const Set<String> _sensitiveKeys = {
    'password',
    'pass',
    'secret',
    'auth_token',
    'token',
    'private_key',
    'key_pair',
    'challenge_response',
    'argon2_hash',
    'salt',
    'signature',
  };

  // Regex patterns to sanitize free-text string messages
  static final List<RegExp> _textPatterns = [
    // Argon2 hashes ($argon2id$...)
    RegExp(
      r"\$argon2id\$v=\d+\$m=\d+,t=\d+,p=\d+\$[A-Za-z0-9+/=]+",
      caseSensitive: false,
    ),
    // Sensitive Key-Value assignments in free text
    RegExp(
      r"(auth_token|token|password|secret|signature|private_key)[:=]\s*\S+",
      caseSensitive: false,
    ),
    // PEM Private Keys
    RegExp(
      r"-----BEGIN [A-Z ]+ PRIVATE KEY-----[\s\S]*?-----END [A-Z ]+ PRIVATE KEY-----",
    ),
  ];

  @override
  String sanitizeMessage(String input) {
    if (input.isEmpty) return input;
    String output = input;
    for (final pattern in _textPatterns) {
      output = output.replaceAll(pattern, _redactedMask);
    }
    return output;
  }

  @override
  Map<String, dynamic>? sanitizeMetadata(Map<String, dynamic>? metadata) {
    if (metadata == null || metadata.isEmpty) return metadata;

    final Map<String, dynamic> sanitized = {};

    metadata.forEach((key, value) {
      final lowerKey = key.toLowerCase();
      if (_sensitiveKeys.contains(lowerKey)) {
        sanitized[key] = _redactedMask;
      } else if (value is Map<String, dynamic>) {
        sanitized[key] = sanitizeMetadata(value);
      } else if (value is String) {
        sanitized[key] = sanitizeMessage(value);
      } else if (value is List) {
        sanitized[key] = value.map((item) {
          if (item is Map<String, dynamic>) return sanitizeMetadata(item);
          if (item is String) return sanitizeMessage(item);
          return item;
        }).toList();
      } else {
        sanitized[key] = value;
      }
    });

    return sanitized;
  }
}
