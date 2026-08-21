import 'dart:collection';
import 'dart:developer';
import '../auth/auth_service.dart';
import 'signaling_protocol.dart';
import 'websocket_transport.dart';

/// Outbound message entry queued for signaling transmission.
class OutboxItem {
  final String type;
  final String toPeerId;
  final Map<String, dynamic> payload;
  final int sequence;
  final int timestamp;

  OutboxItem({
    required this.type,
    required this.toPeerId,
    required this.payload,
    required this.sequence,
    required this.timestamp,
  });
}

/// Serialized outbound signaling message queue with signing and readiness verification.
class SignalingOutbox {
  final WebSocketTransport transport;
  final Queue<OutboxItem> _queue = Queue<OutboxItem>();
  bool _isProcessing = false;
  int _sequence = 1;

  SignalingOutbox(this.transport);

  /// Enqueues a data plane signaling message (SDP Offer, ICE Candidate) for transmission.
  Future<void> enqueueDataPlaneMessage({
    required String type,
    required String toPeerId,
    required String? sessionId,
    required Map<String, dynamic> payload,
  }) async {
    final seq = _sequence++;
    final ts = DateTime.now().millisecondsSinceEpoch;

    final item = OutboxItem(
      type: type,
      toPeerId: toPeerId,
      payload: payload,
      sequence: seq,
      timestamp: ts,
    );

    _queue.add(item);
    await processQueue(sessionId: sessionId);
  }

  /// Processes outbound queue sequentially.
  Future<void> processQueue({required String? sessionId}) async {
    if (_isProcessing || _queue.isEmpty) return;
    _isProcessing = true;

    try {
      while (_queue.isNotEmpty) {
        if (transport.state != TransportState.connected) {
          log('[OUTBOX] Transport disconnected. Pausing outbound queue.');
          break;
        }

        final item = _queue.removeFirst();
        final identityManager = AuthService().identityManager;

        if (identityManager.selfId == null || sessionId == null) {
          log('[OUTBOX] Identity or sessionId not ready. Re-queuing item.');
          _queue.addFirst(item);
          break;
        }

        final int msgTypeInt;
        if (item.type == SignalingMessageType.offer) {
          msgTypeInt = 1;
        } else if (item.type == SignalingMessageType.answer) {
          msgTypeInt = 2;
        } else {
          msgTypeInt = 3;
        }

        final content = (item.type == SignalingMessageType.offer ||
                item.type == SignalingMessageType.answer)
            ? (item.payload['sdp'] as String? ?? '')
            : (item.payload['candidate'] as String? ?? '');

        final signatureHex = await identityManager.signEnvelope(
          msgType: msgTypeInt,
          toPeerId: item.toPeerId,
          payload: content,
          sequence: item.sequence,
          timestamp: item.timestamp,
          activeSessionId: sessionId,
        );

        final encodedMsg = SignalingProtocol.encodeDataPlaneMessage(
          type: item.type,
          selfId: identityManager.selfId!,
          toPeerId: item.toPeerId,
          sessionId: sessionId,
          sequence: item.sequence,
          signatureHex: signatureHex,
          timestamp: item.timestamp,
          payload: item.payload,
        );

        final success = transport.send(encodedMsg);
        if (success && item.type == SignalingMessageType.offer) {
          log('[SIG] SDP Offer transmitted to WebSocket sink.');
        }
      }
    } catch (e, st) {
      log('[OUTBOX] Error processing outbox item: $e\n$st');
    } finally {
      _isProcessing = false;
    }
  }

  /// Purges all queued messages and resets sequence for new signaling sessions.
  void reset() {
    _queue.clear();
    _sequence = 1;
    _isProcessing = false;
  }

  /// Purges all queued messages.
  void clear() {
    _queue.clear();
  }
}
