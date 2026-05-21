import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:frankn/services/rtc_thin_client.dart';
import 'package:frankn/utils/utils.dart';
import 'package:frankn/utils/dc_msg_util.dart';
import 'package:xterm/xterm.dart';

class SshController extends ChangeNotifier {
  final RtcThinClient client;
  final Terminal terminal = Terminal(maxLines: 5000);

  SSHClient? _sshClient;
  SSHSession? _sshSession;
  ServerSocket? _localServer;

  bool _isConnecting = false;
  bool get isConnecting => _isConnecting;

  bool get isConnected => _sshClient != null;

  ModState ctrlState = ModState.off;
  ModState altState = ModState.off;

  bool _isDisposed = false;

  // Buffer for data that arrives before the local socket connects
  final List<Uint8List> _buffer = [];
  StreamController<Uint8List>? _hostToSocket;
  StreamSubscription? _socketSubscription;
  StreamSubscription? _commandSubscription;
  StreamSubscription? _sshDataSub;

  SshController(this.client);

  ModState _nextModState(ModState current) {
    if (current == ModState.off) return ModState.active;
    if (current == ModState.active) return ModState.locked;
    return ModState.off;
  }

  void toggleCtrl() {
    if (_isDisposed) return;
    ctrlState = _nextModState(ctrlState);
    notifyListeners();
  }

  void toggleAlt() {
    if (_isDisposed) return;
    altState = _nextModState(altState);
    notifyListeners();
  }

  Future<void> startSession(String username, String? password) async {
    if (_isConnecting || _isDisposed) return;
    _isConnecting = true;
    notifyListeners();

    terminal.write(
      '\x1b[36m[SYSTEM]\x1b[0m Checking Host SSH availability...\r\n',
    );

    try {
      // 1. Prepare for data flow via Isolate Bridge
      _buffer.clear();
      _hostToSocket = StreamController<Uint8List>();

      _sshDataSub = client.sshDataStream.listen((data) {
        if (_isDisposed) return;
        if (_hostToSocket != null && _hostToSocket!.hasListener) {
          _hostToSocket!.add(data);
        } else {
          _buffer.add(data);
        }
      });

      // 2. Start listening for the response BEFORE sending the command
      bool hostReady = false;
      final completer = Completer<bool>();

      _commandSubscription = client.genDcMsgStream.listen((msg) {
        if (_isDisposed) return;

        Map<String, dynamic>? data;
        String? status;
        String? error;

        if (msg is HostMsgResponse) {
            data = msg.data is Map ? msg.data as Map<String, dynamic> : null;
            status = msg.status;
            error = msg.error;
        } else if (msg is HostMsgUnknown) {
            data = msg.raw;
            status = msg.raw['status']?.toString();
        }

        if (status?.toLowerCase() == 'success' &&
            data?['message']?.contains('SSH reachable') == true) {
          terminal.write(
            '\x1b[32m[SYSTEM]\x1b[0m Host SSH bridge confirmed ready.\r\n',
          );
          if (!completer.isCompleted) completer.complete(true);
        } else if (status?.toLowerCase() == 'error' || error != null) {
          final errorMsg = error ?? data?['message'] ?? 'Host SSH Error';
          if (!completer.isCompleted) completer.completeError(errorMsg);
        }
      });

      try {
        // 3. Send command to host to prepare SSH
        terminal.write(
          '\x1b[36m[SYSTEM]\x1b[0m Requesting bridge start from Host...\r\n',
        );
        client.startSsh();

        // 4. Wait for response
        hostReady = await completer.future.timeout(const Duration(seconds: 10));
      } catch (e) {
        if (_isDisposed) return;
        throw Exception("Host SSH check timed out or failed: $e");
      } finally {
        _commandSubscription?.cancel();
        _commandSubscription = null;
      }

      if (_isDisposed) return;
      if (!hostReady) throw Exception("Host SSH not ready.");

      terminal.write(
        '\x1b[36m[SYSTEM]\x1b[0m P2P Tunnel Open. Spawning bridge...\r\n',
      );

      _localServer = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);

      _localServer!.listen((socket) {
        if (_isDisposed) {
          socket.destroy();
          return;
        }
        // Forward data from local socket to background isolate (via ThinClient)
        socket.listen(
          (data) {
            if (_isDisposed) return;
            client.sendSshInput(Uint8List.fromList(data));
          },
          onDone: () => stopSession(),
          onError: (e) {
            if (_isDisposed) return;
            terminal.write('\r\n\x1b[31m[BRIDGE ERROR]\x1b[0m $e\r\n');
          },
        );

        // Forward buffered and future data from isolate stream to local socket
        for (var data in _buffer) {
          socket.add(data);
        }
        _buffer.clear();

        _socketSubscription = _hostToSocket?.stream.listen((data) {
          if (_isDisposed) return;
          socket.add(data);
        });
      });

      terminal.write(
        '\x1b[36m[SYSTEM]\x1b[0m Bridge active on port: ${_localServer!.port}\r\n',
      );
      terminal.write('\x1b[36m[SYSTEM]\x1b[0m Handshaking via Tunnel...\r\n');

      final socket = await SSHSocket.connect(
        '127.0.0.1',
        _localServer!.port,
      ).timeout(const Duration(seconds: 15));

      if (_isDisposed) {
        socket.destroy();
        return;
      }

      _sshClient = SSHClient(
        socket,
        username: username,
        onPasswordRequest: () => password ?? (client.currentPassword ?? ''),
      );

      await _sshClient!.authenticated;
      if (_isDisposed) return;
      terminal.write(
        '\x1b[32m[SUCCESS]\x1b[0m Neural Handshake Established.\r\n',
      );

      _sshSession = await _sshClient!.shell(
        pty: SSHPtyConfig(
          width: terminal.viewWidth,
          height: terminal.viewHeight,
        ),
      );

      if (_isDisposed) return;

      terminal.onResize = (width, height, pixelWidth, pixelHeight) {
        if (_isDisposed) return;
        _sshSession?.resizeTerminal(width, height);
      };

      terminal.onOutput = (data) {
        if (_isDisposed) return;
        _handleInput(data);
      };

      // Use stateful decoders to handle multi-byte characters split across chunks
      const stdoutDecoder = Utf8Decoder(allowMalformed: true);
      const stderrDecoder = Utf8Decoder(allowMalformed: true);

      _sshSession!.stdout.listen((data) {
        if (_isDisposed) return;
        terminal.write(stdoutDecoder.convert(data));
      }, onDone: () => stopSession());

      _sshSession!.stderr.listen((data) {
        if (_isDisposed) return;
        terminal.write(stderrDecoder.convert(data));
      });

      notifyListeners();
      await _sshSession!.done;
      if (_isDisposed) return;
      terminal.write('\r\n\x1b[33m[SYSTEM] Remote Shell ended.\x1b[0m\r\n');
    } catch (e) {
      if (_isDisposed) return;
      terminal.write(
        '\r\n\x1b[31m[FATAL ERROR]\x1b[0m ${e.toString().replaceAll('Exception: ', '')}\r\n',
      );
      stopSession();
      rethrow;
    } finally {
      if (!_isDisposed) {
        _isConnecting = false;
        notifyListeners();
      }
    }
  }

  void _handleInput(String data) {
    if (_sshSession == null || _isDisposed) return;

    if (ctrlState != ModState.off) {
      if (data.length == 1) {
        final char = data.toUpperCase().codeUnitAt(0);
        if (char >= 64 && char <= 95) {
          _sshSession!.write(Uint8List.fromList([char & 0x1f]));
        } else {
          _sshSession!.write(utf8.encode(data));
        }
      } else {
        _sshSession!.write(utf8.encode(data));
      }
      if (ctrlState == ModState.active) {
        ctrlState = ModState.off;
        notifyListeners();
      }
    } else if (altState != ModState.off) {
      _sshSession!.write(utf8.encode('\x1b$data'));
      if (altState == ModState.active) {
        altState = ModState.off;
        notifyListeners();
      }
    } else {
      _sshSession!.write(utf8.encode(data));
    }
  }

  void sendRaw(String sequence) {
    if (_isDisposed) return;
    _sshSession?.write(utf8.encode(sequence));
  }

  void stopSession() {
    if (_isDisposed) return;
    client.stopSsh();
    _sshSession?.close();
    _sshClient?.close();
    _localServer?.close();
    _socketSubscription?.cancel();
    _hostToSocket?.close();
    _commandSubscription?.cancel();
    _sshDataSub?.cancel();

    _sshSession = null;
    _sshClient = null;
    _localServer = null;
    _hostToSocket = null;
    _socketSubscription = null;
    _commandSubscription = null;
    _sshDataSub = null;
    ctrlState = ModState.off;
    altState = ModState.off;
    notifyListeners();
  }

  @override
  void notifyListeners() {
    if (_isDisposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    stopSession();
    _isDisposed = true;
    super.dispose();
  }
}
