import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

class OpaqueLoginStart {
  final int handle;
  final String request;

  const OpaqueLoginStart({required this.handle, required this.request});
}

/// RFC 9807 client facade. The native Rust core owns protocol state and
/// computes the OPAQUE transcript; this class only converts typed wire bytes.
class FranknOpaqueClient {
  late final DynamicLibrary _library;
  late final _ClientStartDart _start;
  late final _ClientFinishDart _finish;
  late final _ClientCancelDart _cancel;
  late final _StringFreeDart _free;

  FranknOpaqueClient() {
    final ios = Platform.isIOS;
    if (Platform.isIOS) {
      _library = DynamicLibrary.process();
    } else if (Platform.isAndroid) {
      _library = DynamicLibrary.open('libfrankn_opaque.so');
    } else {
      throw UnsupportedError(
        'Frankn OPAQUE currently supports Android and iOS.',
      );
    }
    _start = _library.lookupFunction<_ClientStartNative, _ClientStartDart>(
      ios ? 'frankn_opaque_ios_client_start' : 'frankn_opaque_client_start',
    );
    _finish = _library.lookupFunction<_ClientFinishNative, _ClientFinishDart>(
      ios ? 'frankn_opaque_ios_client_finish' : 'frankn_opaque_client_finish',
    );
    _cancel = _library.lookupFunction<_ClientCancelNative, _ClientCancelDart>(
      ios ? 'frankn_opaque_ios_client_cancel' : 'frankn_opaque_client_cancel',
    );
    _free = _library.lookupFunction<_StringFreeNative, _StringFreeDart>(
      ios ? 'frankn_opaque_ios_string_free' : 'frankn_opaque_string_free',
    );
  }

  OpaqueLoginStart begin({
    required String password,
    required String clientId,
    required String hostId,
  }) {
    final passwordBytes = Uint8List.fromList(utf8.encode(password));
    final nativePassword = calloc<Uint8>(passwordBytes.length);
    final nativeClient = clientId.toNativeUtf8();
    final nativeHost = hostId.toNativeUtf8();
    Pointer<Utf8> result = nullptr;
    try {
      nativePassword.asTypedList(passwordBytes.length).setAll(0, passwordBytes);
      result = _start(
        nativePassword,
        passwordBytes.length,
        nativeClient,
        nativeHost,
      );
      final value = _decodeResult(result);
      return OpaqueLoginStart(
        handle: (value['handle'] as num).toInt(),
        request: value['request'] as String,
      );
    } finally {
      passwordBytes.fillRange(0, passwordBytes.length, 0);
      nativePassword
          .asTypedList(passwordBytes.length)
          .fillRange(0, passwordBytes.length, 0);
      calloc.free(nativePassword);
      calloc.free(nativeClient);
      calloc.free(nativeHost);
      if (result != nullptr) _free(result);
    }
  }

  ({String finalization, String credential}) finish({
    required int handle,
    required String response,
  }) {
    final responseBytes = base64Url.decode(base64Url.normalize(response));
    final nativeResponse = calloc<Uint8>(responseBytes.length);
    Pointer<Utf8> result = nullptr;
    try {
      nativeResponse.asTypedList(responseBytes.length).setAll(0, responseBytes);
      result = _finish(handle, nativeResponse, responseBytes.length);
      final value = _decodeResult(result);
      return (
        finalization: value['finalization'] as String,
        credential: value['credential'] as String,
      );
    } finally {
      responseBytes.fillRange(0, responseBytes.length, 0);
      nativeResponse
          .asTypedList(responseBytes.length)
          .fillRange(0, responseBytes.length, 0);
      calloc.free(nativeResponse);
      if (result != nullptr) _free(result);
    }
  }

  void cancel(int handle) => _cancel(handle);

  Map<String, dynamic> _decodeResult(Pointer<Utf8> result) {
    if (result == nullptr) throw StateError('OPAQUE authentication failed.');
    final decoded = jsonDecode(result.toDartString());
    if (decoded is! Map<String, dynamic> || decoded.containsKey('error')) {
      throw StateError('OPAQUE authentication failed.');
    }
    return decoded;
  }
}

typedef _ClientStartNative =
    Pointer<Utf8> Function(
      Pointer<Uint8>,
      IntPtr,
      Pointer<Utf8>,
      Pointer<Utf8>,
    );
typedef _ClientStartDart =
    Pointer<Utf8> Function(Pointer<Uint8>, int, Pointer<Utf8>, Pointer<Utf8>);
typedef _ClientFinishNative =
    Pointer<Utf8> Function(Uint64, Pointer<Uint8>, IntPtr);
typedef _ClientFinishDart = Pointer<Utf8> Function(int, Pointer<Uint8>, int);
typedef _ClientCancelNative = Void Function(Uint64);
typedef _ClientCancelDart = void Function(int);
typedef _StringFreeNative = Void Function(Pointer<Utf8>);
typedef _StringFreeDart = void Function(Pointer<Utf8>);
