import 'dart:convert';
import 'dart:developer';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart' as crypto_pkg;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:convert/convert.dart';

/// Manages Ed25519 client identity keypairs and payload envelope signatures.
class IdentityManager {
  static const String _storageKey = 'frankn_client_identity_seed';

  crypto_pkg.SimpleKeyPair? _keyPair;
  String? _selfId;
  String? _publicKeyHex;
  String? sessionId;

  /// Cached loaded Ed25519 identity keypair.
  crypto_pkg.SimpleKeyPair? get keyPair => _keyPair;
  crypto_pkg.SimpleKeyPair? get clientKeyPair => _keyPair;
  set clientKeyPair(crypto_pkg.SimpleKeyPair? kp) => _keyPair = kp;

  /// Derived sha256 base58-encoded self ID for signaling.
  String? get selfId => _selfId;
  set selfId(String? id) => _selfId = id;

  /// Hex-encoded public key string.
  String? get publicKeyHex => _publicKeyHex;

  /// Returns existing identity keypair or loads/generates from secure storage.
  Future<crypto_pkg.SimpleKeyPair> getOrCreateIdentityKey() async {
    if (_keyPair != null) {
      return _keyPair!;
    }

    const storage = FlutterSecureStorage();
    final savedSeedBase64 = await storage.read(key: _storageKey);
    final algorithm = crypto_pkg.Ed25519();

    if (savedSeedBase64 != null) {
      try {
        final seedBytes = base64Decode(savedSeedBase64);
        final keyPair = await algorithm.newKeyPairFromSeed(seedBytes);
        _keyPair = keyPair;
        await _deriveIdentifiers(keyPair);
        return keyPair;
      } catch (e) {
        log('ERROR: Stored identity seed was corrupted, generating new identity... $e');
      }
    }

    log('IDENTITY: Generating new persistent cryptographic client identity...');
    final keyPair = await algorithm.newKeyPair();
    final keyPairData = await keyPair.extract();
    final seedBytes = keyPairData.bytes;

    await storage.write(
      key: _storageKey,
      value: base64Encode(seedBytes),
    );

    _keyPair = keyPair;
    await _deriveIdentifiers(keyPair);
    return keyPair;
  }

  Future<void> _deriveIdentifiers(crypto_pkg.SimpleKeyPair keyPair) async {
    final publicKey = await keyPair.extractPublicKey();
    final publicKeyBytes = publicKey.bytes;
    _publicKeyHex = hex.encode(publicKeyBytes);

    final rawPeerId = crypto.sha256.convert(publicKeyBytes).bytes;
    _selfId = base64Url.encode(rawPeerId).replaceAll('=', '');
  }

  /// Signs binary payload envelope using Ed25519 keypair matching FRANKN-SIG-V1.
  Future<String> signEnvelope({
    required int msgType,
    required String toPeerId,
    required String payload,
    required int sequence,
    required int timestamp,
    required String activeSessionId,
  }) async {
    final keyPair = await getOrCreateIdentityKey();

    final buf = Uint8List(160);

    // Domain Separator (14 bytes)
    final domain = utf8.encode('FRANKN-SIG-V1\u0000');
    buf.setRange(0, 14, domain);

    // Version (1 byte)
    buf[14] = 0x01;

    // Message Type ID (1 byte)
    buf[15] = msgType;

    String normalizeBase64Url(String input) {
      String output = input.replaceAll('-', '+').replaceAll('_', '/');
      switch (output.length % 4) {
        case 0:
          break;
        case 2:
          output += '==';
          break;
        case 3:
          output += '=';
          break;
        default:
          throw Exception('Illegal base64url string!');
      }
      return output;
    }

    final sessionBytes = base64Decode(normalizeBase64Url(activeSessionId));
    buf.setRange(16, 48, sessionBytes);

    // Sequence (8 bytes BE)
    final seqData = ByteData(8)..setUint64(0, sequence, Endian.big);
    buf.setRange(48, 56, seqData.buffer.asUint8List());

    // Timestamp (8 bytes BE ms)
    final tsData = ByteData(8)..setUint64(0, timestamp, Endian.big);
    buf.setRange(56, 64, tsData.buffer.asUint8List());

    // From Peer ID (32 bytes)
    final fromBytes = base64Decode(normalizeBase64Url(_selfId!));
    buf.setRange(64, 96, fromBytes);

    // To Peer ID (32 bytes)
    final toBytes = base64Decode(normalizeBase64Url(toPeerId));
    buf.setRange(96, 128, toBytes);

    // Payload Hash (32 bytes)
    final payloadBytes = utf8.encode(payload);
    final payloadHash = crypto.sha256.convert(payloadBytes).bytes;
    buf.setRange(128, 160, payloadHash);

    // Sign
    final algorithm = crypto_pkg.Ed25519();
    final signature = await algorithm.sign(buf, keyPair: keyPair);

    return hex.encode(signature.bytes);
  }

  static String base58Encode(Uint8List bytes) {
    const alphabet =
        '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';
    BigInt value = BigInt.zero;
    for (final byte in bytes) {
      value = (value << 8) + BigInt.from(byte);
    }
    String result = '';
    while (value > BigInt.zero) {
      final remainder = (value % BigInt.from(58)).toInt();
      value = value ~/ BigInt.from(58);
      result = alphabet[remainder] + result;
    }
    for (final byte in bytes) {
      if (byte == 0) {
        result = alphabet[0] + result;
      } else {
        break;
      }
    }
    return result;
  }

  static Uint8List base58Decode(String str) {
    const alphabet =
        '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';
    BigInt value = BigInt.zero;
    for (int i = 0; i < str.length; i++) {
      final charIndex = alphabet.indexOf(str[i]);
      if (charIndex == -1) {
        throw FormatException('Invalid base58 character: ${str[i]}');
      }
      value = (value * BigInt.from(58)) + BigInt.from(charIndex);
    }
    final List<int> byteList = [];
    while (value > BigInt.zero) {
      byteList.add((value & BigInt.from(0xFF)).toInt());
      value = value >> 8;
    }
    final bytes = Uint8List.fromList(byteList.reversed.toList());
    int leadingZeros = 0;
    for (int i = 0; i < str.length; i++) {
      if (str[i] == alphabet[0]) {
        leadingZeros++;
      } else {
        break;
      }
    }
    final result = Uint8List(leadingZeros + bytes.length);
    result.setRange(leadingZeros, result.length, bytes);
    return result;
  }
}
