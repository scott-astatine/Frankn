/// Frankn Transfer Engine — Resume-aware file transfer over WebRTC DCs
///
/// Binary frame format:
///   [0x01][36-byte ID][8-byte offset BE][4-byte seq BE][1-byte flags][N bytes data]
///
/// Flags:
///   0x01 = RESUME (host has existing partial)
///   0x02 = FINAL (last chunk)
///   0x04 = ACK_REQUESTED (client wants host to send transfer_ack)
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'package:frankn/services/client_rtc/rtc.dart';
import 'package:frankn/utils/dc_msg_util.dart';

/// Binary frame constants — must match host-side definitions.
class _FrameConst {
  static const int magic = 0x01;
  static const int idSize = 36;
  static const int offsetSize = 8;
  static const int seqSize = 4;
  static const int flagsSize = 1;
  static const int headerSize = 1 + idSize + offsetSize + seqSize + flagsSize;

  // static const int flagResume = 0x01; // Reserved for future use
  static const int flagFinal = 0x02;
  static const int flagAckRequested = 0x04;
}

/// Progress callback signature.
typedef TransferProgress =
    void Function({
      required double progress, // 0.0 - 1.0
      required int bytesTransferred,
      required int totalBytes,
    });

/// Transfer engine for resume-aware file uploads/downloads over WebRTC.
class TransferEngine {
  final RtcClient client;

  // Active transfer state
  final Map<String, _TransferState> _activeTransfers = {};
  final Set<String> _cancelledTransfers = {};

  // Stream subscription for transfer-related messages
  StreamSubscription<HostMessage>? _messageSub;

  TransferEngine(this.client) {
    _messageSub = client.genDcMsgStream.listen(_onMessage);
  }

  void dispose() {
    _messageSub?.cancel();
    _messageSub = null;
  }

  /// Cancel an in-progress transfer.
  Future<void> cancel(String id) async {
    _cancelledTransfers.add(id);
    _activeTransfers.remove(id);
    client.sendTransferCancel(id);
  }

  /// Upload a file to the host with resume support.
  ///
  /// [id] — Transfer ID (UUID). Pass the same ID to resume a failed upload.
  /// [remotePath] — Target path on the host.
  /// [file] — local File path.
  /// [hash] — SHA-256 hex string for integrity verification.
  /// [resumeOffset] — Byte offset to resume from (0 = fresh, or from getResumeOffset).
  /// [onProgress] — Progress callback.
  Future<void> upload({
    required String id,
    required String remotePath,
    required File file,
    required String hash,
    int resumeOffset = 0,
    TransferProgress? onProgress,
  }) async {
    final totalSize = await file.length();
    const chunkSize = 61440; // 60KB
    const bufferThreshold = 1024 * 1024; // 1MB

    _activeTransfers[id] = _TransferState(
      totalBytes: totalSize,
      bytesTransferred: resumeOffset,
    );

    // Initialize transfer on host
    int actualResumeOffset = resumeOffset;
    final initCompleter = Completer<void>();
    final initSub = client.genDcMsgStream.listen((msg) {
      if (msg is HostMsgResponse && msg.id == id) {
        final respData = msg.data;
        if (respData != null && respData is Map && respData['offset'] != null) {
          actualResumeOffset = respData['offset'] as int;
          client.log("FS: Host requested resume from offset $actualResumeOffset");
        }
        initCompleter.complete();
      } else if (msg is HostMsgTransferComplete && msg.id == id) {
        // Host finished before we sent all data (edge case — resume matched total)
        initCompleter.complete();
      }
    });

    client.sendTransferInit(
      id: id,
      path: remotePath,
      totalSize: totalSize,
      hash: hash,
      resumeOffset: resumeOffset,
    );

    await initCompleter.future.timeout(const Duration(seconds: 15));
    initSub.cancel();

    // Stream chunks
    int offset = actualResumeOffset;
    int seq = 0;

    final raf = await file.open(mode: FileMode.read);
    try {
      await raf.setPosition(actualResumeOffset);

      while (offset < totalSize) {
        if (_cancelledTransfers.contains(id)) {
          client.log("FS: Upload $id cancelled by user.");
          throw Exception("TRANSFER_CANCELLED");
        }

        if (client.fsDC?.state != RTCDataChannelState.RTCDataChannelOpen) {
          throw Exception("FS channel closed during upload $id");
        }

        // Backpressure: wait if buffered amount is too high
        if ((client.fsDC?.bufferedAmount ?? 0) > bufferThreshold) {
          await Future.delayed(const Duration(milliseconds: 10));
          continue;
        }

        final remaining = totalSize - offset;
        final toRead = remaining < chunkSize ? remaining : chunkSize;
        final chunk = await raf.read(toRead);
        final isFinal = (offset + toRead) >= totalSize;

        // Build binary frame
        final frame = _encodeFrame(
          id: id,
          offset: offset,
          seq: seq,
          flags:
              (isFinal ? _FrameConst.flagFinal : 0) |
              (seq % 50 == 0 ? _FrameConst.flagAckRequested : 0),
          data: chunk,
        );

        client.fsDC!.send(RTCDataChannelMessage.fromBinary(frame));

        offset += toRead;
        seq++;

        _activeTransfers[id]?.bytesTransferred = offset;
        onProgress?.call(
          progress: offset / totalSize,
          bytesTransferred: offset,
          totalBytes: totalSize,
        );
      }
    } finally {
      await raf.close();
    }

    // Wait for host ACK of completion
    final completeSub = client.genDcMsgStream.listen((msg) {
      if (msg is HostMsgTransferComplete && msg.id == id) {
        final state = _activeTransfers[id];
        state?.isComplete = true;
      }
    });

    // Give host time to finalize
    await Future.delayed(const Duration(seconds: 2));
    completeSub.cancel();

    _activeTransfers.remove(id);

    final state = _activeTransfers[id];
    if (state != null && !state.isComplete) {
      throw Exception("Upload $id completed locally but host did not confirm");
    }
  }

  /// Encode a binary transfer frame.
  static Uint8List _encodeFrame({
    required String id,
    required int offset,
    required int seq,
    required int flags,
    required Uint8List data,
  }) {
    final idBytes = utf8.encode(id);
    final header = Uint8List(_FrameConst.idSize);
    header.setRange(0, idBytes.length.clamp(0, _FrameConst.idSize), idBytes);

    final frame = Uint8List(_FrameConst.headerSize + data.length);
    frame[0] = _FrameConst.magic;
    frame.setRange(1, 1 + _FrameConst.idSize, header);

    // Offset: 8 bytes big-endian
    final offsetBytes = ByteData(8);
    offsetBytes.setUint64(0, offset);
    frame.setRange(
      1 + _FrameConst.idSize,
      1 + _FrameConst.idSize + _FrameConst.offsetSize,
      offsetBytes.buffer.asUint8List(),
    );

    // Seq: 4 bytes big-endian
    final seqBytes = ByteData(4);
    seqBytes.setUint32(0, seq);
    frame.setRange(
      1 + _FrameConst.idSize + _FrameConst.offsetSize,
      1 + _FrameConst.idSize + _FrameConst.offsetSize + _FrameConst.seqSize,
      seqBytes.buffer.asUint8List(),
    );

    // Flags
    frame[1 +
            _FrameConst.idSize +
            _FrameConst.offsetSize +
            _FrameConst.seqSize] =
        flags;

    // Data
    frame.setRange(
      _FrameConst.headerSize,
      _FrameConst.headerSize + data.length,
      data,
    );

    return frame;
  }

  /// Process incoming transfer-related JSON messages.
  void _onMessage(HostMessage msg) {
    if (msg is HostMsgTransferAck) {
      final state = _activeTransfers[msg.id];
      if (state != null) {
        state.lastAckOffset = msg.offset;
        state.lastAckSeq = msg.seq;
      }
    } else if (msg is HostMsgTransferComplete) {
      final state = _activeTransfers[msg.id];
      if (state != null) {
        state.isComplete = true;
      }
    }
  }
}

/// Internal state for an active transfer.
class _TransferState {
  final int totalBytes;
  int bytesTransferred;
  int lastAckOffset = 0;
  int lastAckSeq = 0;
  bool isComplete = false;

  _TransferState({required this.totalBytes, this.bytesTransferred = 0});
}
