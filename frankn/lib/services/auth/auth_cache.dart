import 'auth_credentials.dart';

/// In-memory cache for derived Argon2id password verifiers.
/// Keyed by salt and password to prevent expensive re-computations during reconnects.
class AuthCache {
  DerivedCredential? _credential;

  /// Returns cached derived credential if password and salt match.
  DerivedCredential? get(String password, String salt) {
    if (_credential != null &&
        _credential!.password == password &&
        _credential!.salt == salt) {
      return _credential;
    }
    return null;
  }

  /// Stores a derived credential in memory.
  void put(DerivedCredential credential) {
    _credential = credential;
  }

  /// Invalidate/clear stored derived credentials.
  void clear() {
    _credential = null;
  }
}
