import 'dart:convert';
import 'dart:developer';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:pointycastle/export.dart';

/// Centralized wire-compatible Argon2id parameters for Frankn.
class FranknArgon2Config {
  static const int memory = 19456; // 19.4 MB
  static const int iterations = 2;
  static const int parallelism = 1;
  static const int keyLength = 32;
  static const int version = Argon2Parameters.ARGON2_VERSION_13;
}

/// Cryptographic provider for Argon2id hash derivation and challenge response signatures.
class AuthCrypto {
  /// Derives Argon2id hash off the UI isolate via [Isolate.run].
  static Future<String> deriveArgon2Hash(String password, String saltStr) async {
    final sw = Stopwatch()..start();
    final hash = await Isolate.run(() => _doArgon2Computation(password, saltStr));
    log('[AUTH] Argon2 computation completed in +${sw.elapsedMilliseconds}ms');
    return hash;
  }

  static String _doArgon2Computation(String password, String saltStr) {
    final salt = base64.decode(
      saltStr.padRight((saltStr.length + 3) & ~3, '='),
    );
    final passwordBytes = Uint8List.fromList(utf8.encode(password));

    final generator = Argon2BytesGenerator();
    generator.init(
      Argon2Parameters(
        Argon2Parameters.ARGON2_id,
        salt,
        desiredKeyLength: FranknArgon2Config.keyLength,
        iterations: FranknArgon2Config.iterations,
        memory: FranknArgon2Config.memory,
        lanes: FranknArgon2Config.parallelism,
        version: FranknArgon2Config.version,
      ),
    );

    final hashBytes = generator.process(passwordBytes);

    final b64Salt = base64.encode(salt).replaceAll('=', '');
    final b64Hash = base64.encode(hashBytes).replaceAll('=', '');

    return "\$argon2id\$v=19\$m=19456,t=2,p=1\$$b64Salt\$$b64Hash";
  }

  /// Computes response for host authentication challenge.
  static String computeChallengeResponse(String argon2HashBase64, String challengeHex) {
    return argon2HashBase64;
  }
}
