import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:pointycastle/export.dart';

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  String? _sessionToken;
  String? get sessionToken => _sessionToken;

  String? _cachedPassword;
  String? _cachedSalt;
  String? _cachedHash;

  void setToken(String token) {
    _sessionToken = token;
  }

  void clearToken() {
    _sessionToken = null;
    _cachedPassword = null;
    _cachedSalt = null;
    _cachedHash = null;
  }

  /// Computes the Argon2 hash of the password using the provided salt.
  /// Uses in-memory caching and offloads CPU computation to a background isolate.
  Future<String> computeArgon2Hash(String password, String saltStr) async {
    if (_cachedPassword == password &&
        _cachedSalt == saltStr &&
        _cachedHash != null) {
      print("[AUTH] Argon2 cache hit.");
      return _cachedHash!;
    }

    print("[AUTH] Argon2 calculation started (Isolate.run)...");
    final sw = Stopwatch()..start();
    final hash = await Isolate.run(
      () => _doArgon2Computation(password, saltStr),
    );
    print("[AUTH] Argon2 calculation completed in +${sw.elapsedMilliseconds}ms.");

    _cachedPassword = password;
    _cachedSalt = saltStr;
    _cachedHash = hash;

    return hash;
  }

  static String _doArgon2Computation(String password, String saltStr) {
    // Rust defaults: argon2id, v=19, m=19456, t=2, p=1, len=32
    final salt = base64.decode(
      saltStr.padRight((saltStr.length + 3) & ~3, '='),
    );
    final passwordBytes = Uint8List.fromList(utf8.encode(password));

    final generator = Argon2BytesGenerator();

    generator.init(
      Argon2Parameters(
        Argon2Parameters.ARGON2_id,
        salt,
        desiredKeyLength: 32,
        iterations: 2,
        memory: 19456,
        lanes: 1, // 'parallelism' is 'lanes' in pointycastle
        version: Argon2Parameters.ARGON2_VERSION_13,
      ),
    );

    // process(input) -> output
    final hashBytes = generator.process(passwordBytes);

    // Construct the PHC string to match Rust's output
    // Format: $argon2id$v=19$m=19456,t=2,p=1$SALT$HASH
    final b64Salt = base64.encode(salt).replaceAll('=', '');
    final b64Hash = base64.encode(hashBytes).replaceAll('=', '');

    return "\$argon2id\$v=19\$m=19456,t=2,p=1\$$b64Salt\$$b64Hash";
  }

  /// Computes Hex(Sha256(Argon2Hash + Challenge)) - Now returns Argon2Hash directly for secure verifier protocol
  String computeResponse(String argon2Hash, String challenge) {
    return argon2Hash;
  }
}
