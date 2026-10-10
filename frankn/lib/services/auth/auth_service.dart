import 'dart:async';
import 'auth_state.dart';
import 'identity_manager.dart';

export 'auth_state.dart';
export 'identity_manager.dart';

/// Facade for local peer identity and the currently authenticated Host session.
class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  final IdentityManager identityManager = IdentityManager();
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
}
