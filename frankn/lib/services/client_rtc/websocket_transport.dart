import 'dart:async';
import 'dart:developer';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';

/// Transport states for the signaling WebSocket connection.
enum TransportState {
  disconnected,
  connecting,
  connected,
  failed,
}

/// Pure transport layer managing WebSocket socket lifecycle, sink writes, and incoming byte stream.
class WebSocketTransport {
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  TransportState _state = TransportState.disconnected;

  final StreamController<TransportState> _stateController =
      StreamController<TransportState>.broadcast();
  final StreamController<dynamic> _messageController =
      StreamController<dynamic>.broadcast();

  /// Current state of the transport connection.
  TransportState get state => _state;

  /// Stream of transport connection state changes.
  Stream<TransportState> get stateStream => _stateController.stream;

  /// Stream of raw incoming signaling messages.
  Stream<dynamic> get messageStream => _messageController.stream;

  /// Active channel reference (if connected).
  WebSocketChannel? get channel => _channel;

  /// Establishes WebSocket connection to [url].
  Future<void> connect(String url) async {
    if (_state == TransportState.connecting || _state == TransportState.connected) {
      return;
    }

    _setState(TransportState.connecting);
    log('[TRANSPORT] Connecting to signaling server: $url');

    try {
      _channel = IOWebSocketChannel.connect(url);
      _setState(TransportState.connected);

      _subscription = _channel!.stream.listen(
        (message) {
          final len = message is String ? message.length : 0;
          log('[TRANSPORT_DIAG] WebSocket RX raw payload ($len chars)');
          _messageController.add(message);
        },
        onError: (error) {
          log('[TRANSPORT] Error in WebSocket stream: $error');
          _handleDisconnect();
        },
        onDone: () {
          log('[TRANSPORT] WebSocket connection closed by server.');
          _handleDisconnect();
        },
        cancelOnError: true,
      );
    } catch (e) {
      log('[TRANSPORT] Failed to connect to $url: $e');
      _setState(TransportState.failed);
      rethrow;
    }
  }

  /// Sends a raw encoded string payload over the WebSocket sink.
  bool send(String payload) {
    if (_state != TransportState.connected || _channel == null) {
      log('[TRANSPORT] Cannot send message: Transport disconnected.');
      return false;
    }

    try {
      _channel!.sink.add(payload);
      return true;
    } catch (e) {
      log('[TRANSPORT] Error sending payload over WebSocket: $e');
      return false;
    }
  }

  /// Closes active WebSocket connection cleanly.
  Future<void> disconnect() async {
    _handleDisconnect();
  }

  void _handleDisconnect() {
    _subscription?.cancel();
    _subscription = null;

    try {
      _channel?.sink.close();
    } catch (_) {}
    _channel = null;

    _setState(TransportState.disconnected);
  }

  void _setState(TransportState newState) {
    if (_state == newState) return;
    _state = newState;
    _stateController.add(newState);
  }

  void dispose() {
    disconnect();
    _stateController.close();
    _messageController.close();
  }
}
