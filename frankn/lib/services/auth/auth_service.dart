import 'dart:async';
import 'auth_cache.dart';
import 'auth_credentials.dart';
import 'auth_crypto.dart';
import 'auth_state.dart';
import 'identity_manager.dart';

/// Facade orchestrating authentication infrastructure, identity management,
/// Argon2id computation, and verifier caching for Frankn.
class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  final IdentityManager identityManager = IdentityManager();
  final AuthCache _cache = AuthCache();

  AuthState _state = AuthState.idle;
  final StreamController<AuthState> _stateController =
      StreamController<AuthState>.broadcast();

  String? _sessionToken;

  /// Current authentication state.
  AuthState get state => _state;

  /// Stream emitting authentication state changes.
  Stream<AuthState> get stateStream => _stateController.stream;

  /// Active host session token.
  String? get token => _sessionToken;
  String? get sessionToken => _sessionToken;

  void updateState(AuthState newState) {
    _state = newState;
    _stateController.add(newState);
  }

  void setToken(String token) {
    _sessionToken = token;
    updateState(AuthState.authenticated);
  }

  void clearToken() {
    _sessionToken = null;
    updateState(AuthState.idle);
  }

  /// Computes or retrieves cached Argon2id password hash for a given salt.
  Future<String> computeArgon2Hash(String password, String saltStr) async {
    final cached = _cache.get(password, saltStr);
    if (cached != null) {
      print('[AUTH] Argon2 cache hit.');
      return cached.argon2Hash;
    }

    updateState(AuthState.derivingCredential);
    final hash = await AuthCrypto.deriveArgon2Hash(password, saltStr);

    _cache.put(
      DerivedCredential(
        password: password,
        salt: saltStr,
        argon2Hash: hash,
      ),
    );

    return hash;
  }

  /// Computes HMAC-SHA256 response for a host challenge.
  String computeResponse(String argon2Hash, String challenge) {
    updateState(AuthState.sendingResponse);
    return AuthCrypto.computeChallengeResponse(argon2Hash, challenge);
  }

  /// Clears in-memory verifier cache.
  void clearCache() {
    _cache.clear();
  }
}
