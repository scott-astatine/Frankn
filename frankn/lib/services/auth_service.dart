import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart';

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  String? _sessionToken;
  String? get sessionToken => _sessionToken;

  void setToken(String token) {
    _sessionToken = token;
  }

  /// Computes the Argon2 hash of the password using the provided salt.
  Future<String> computeArgon2Hash(String password, String saltStr) async {
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

  /// Computes Hex(Sha256(Argon2Hash + Challenge))
  String computeResponse(String argon2Hash, String challenge) {
    final bytes = utf8.encode(argon2Hash + challenge);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }
}
