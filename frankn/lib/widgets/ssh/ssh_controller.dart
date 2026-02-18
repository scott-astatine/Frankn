import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:frankn/services/rtc/rtc.dart';
import 'package:xterm/xterm.dart';

class SshController extends ChangeNotifier {
  final RtcClient client;
  final Terminal terminal = Terminal(maxLines: 5000);

  SSHClient? _sshClient;
  SSHSession? _sshSession;
  ServerSocket? _localServer;
  RTCDataChannel? _sshChannel;

  bool _isConnecting = false;
  bool get isConnecting => _isConnecting;

  bool get isConnected => _sshClient != null;

  bool ctrlActive = false;
  bool altActive = false;

  bool _isDisposed = false;

  // Buffer for data that arrives before the local socket connects
  final List<Uint8List> _buffer = [];
  StreamController<Uint8List>? _hostToSocket;
  StreamSubscription? _socketSubscription;
  StreamSubscription? _commandSubscription;

  SshController(this.client);

  void toggleCtrl() {
    if (_isDisposed) return;
    ctrlActive = !ctrlActive;
    notifyListeners();
  }

  void toggleAlt() {
    if (_isDisposed) return;
    altActive = !altActive;
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
      _sshChannel = client.sshDC;
      if (_sshChannel == null) {
        throw Exception("WebRTC SSH Channel not found.");
      }

      // 1. Prepare for data flow
      _buffer.clear();
      _hostToSocket =
          StreamController<Uint8List>(); // Single subscriber (the socket)

      _sshChannel!.onMessage = (msg) {
        if (_isDisposed) return;
        final data = msg.isBinary ? msg.binary : utf8.encode(msg.text);
        if (_hostToSocket != null && _hostToSocket!.hasListener) {
          _hostToSocket!.add(Uint8List.fromList(data));
        } else {
          _buffer.add(Uint8List.fromList(data));
        }
      };

      // 2. Start listening for the response BEFORE sending the command
      bool hostReady = false;
      final completer = Completer<bool>();

      _commandSubscription = client.commandResponseStream.listen((resp) {
        if (_isDisposed) return;
        print("DEBUG: SshController received response: $resp");

        final Map<String, dynamic> data;
        if (resp['type'] == 'response' && resp.containsKey('data')) {
          data = (resp['data'] as Map<String, dynamic>?) ?? {};
        } else {
          data = resp;
        }

        final status = resp['status']?.toString().toLowerCase();

        if (status == 'success' &&
            data['message']?.contains('SSH reachable') == true) {
          terminal.write(
            '\x1b[32m[SYSTEM]\x1b[0m Host SSH bridge confirmed ready.\r\n',
          );
          if (!completer.isCompleted) completer.complete(true);
        } else if (status == 'error' ||
            (resp['status'] is Map && resp['status'].containsKey('Error'))) {
          final errorMsg =
              resp['status_msg'] ??
              data['message'] ??
              (resp['status'] is Map ? resp['status']['Error'] : null) ??
              'Host SSH Error';
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

      // 5. Wait for channel to be OPEN

      int retries = 0;
      terminal.write(
        '\x1b[36m[SYSTEM]\x1b[0m Waiting for P2P DataChannel (State: ${_sshChannel!.state})...\r\n',
      );
      while (_sshChannel!.state != RTCDataChannelState.RTCDataChannelOpen &&
          retries < 100) {
        if (_isDisposed) return;
        await Future.delayed(const Duration(milliseconds: 100));
        retries++;
        if (retries % 10 == 0) {
          terminal.write(
            '\x1b[36m[SYSTEM]\x1b[0m Still waiting... (${_sshChannel!.state})\r\n',
          );
        }
      }

      if (_sshChannel!.state != RTCDataChannelState.RTCDataChannelOpen) {
        throw Exception(
          "WebRTC SSH Tunnel failed to open (State: ${_sshChannel!.state}).",
        );
      }

      terminal.write(
        '\x1b[36m[SYSTEM]\x1b[0m P2P Tunnel Open. Spawning bridge...\r\n',
      );

      _localServer = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);

      _localServer!.listen((socket) {
        if (_isDisposed) {
          socket.destroy();
          return;
        }
        // Forward data from local socket to DataChannel
        socket.listen(
          (data) {
            if (_isDisposed) return;
            if (_sshChannel?.state == RTCDataChannelState.RTCDataChannelOpen) {
              _sshChannel?.send(
                RTCDataChannelMessage.fromBinary(Uint8List.fromList(data)),
              );
            }
          },
          onDone: () => stopSession(),
          onError: (e) {
            if (_isDisposed) return;
            terminal.write('\r\n\x1b[31m[BRIDGE ERROR]\x1b[0m $e\r\n');
          },
        );

        // Forward buffered and future data from DataChannel to local socket
        for (var data in _buffer) {
          socket.add(data);
        }
        _buffer.clear();

        _socketSubscription = _hostToSocket?.stream.listen((data) {
          if (_isDisposed) return;
          socket.add(data);
        });

        _sshChannel!.onDataChannelState = (state) {
          if (_isDisposed) return;
          if (state == RTCDataChannelState.RTCDataChannelClosed) {
            terminal.write(
              '\r\n\x1b[31m[SYSTEM] P2P Tunnel Terminated by Host.\x1b[0m\r\n',
            );
            stopSession();
          }
        };
      });

      terminal.write(
        '\x1b[36m[SYSTEM]\x1b[0m Bridge active on port: ${_localServer!.port}\r\n',
      );
      terminal.write('\x1b[36m[SYSTEM]\x1b[0m Handshaking via Tunnel...\r\n');

      final socket = await SSHSocket.connect(
        '127.0.0.1',
        _localServer!.port,
      ).timeout(const Duration(seconds: 10));

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

      _sshSession!.stdout.listen((data) {
        if (_isDisposed) return;
        terminal.write(utf8.decode(data));
      }, onDone: () => stopSession());

      _sshSession!.stderr.listen((data) {
        if (_isDisposed) return;
        terminal.write(utf8.decode(data));
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

    if (ctrlActive) {
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
      ctrlActive = false;
      notifyListeners();
    } else if (altActive) {
      _sshSession!.write(utf8.encode('\x1b$data'));
      altActive = false;
      notifyListeners();
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

    _sshSession = null;
    _sshClient = null;
    _localServer = null;
    _hostToSocket = null;
    _socketSubscription = null;
    _commandSubscription = null;
    ctrlActive = false;
    altActive = false;
    notifyListeners();
  }

  @override
  void notifyListeners() {
    if (_isDisposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    stopSession();
    super.dispose();
  }
}
