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

import 'package:frankn/services/rtc/rtc.dart';
import 'package:frankn/utils/utils.dart';

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

  // Stream subscription for transfer-related messages
  StreamSubscription<Map<String, dynamic>>? _messageSub;

  TransferEngine(this.client) {
    _messageSub = client.commandResponseStream.listen(_onMessage);
  }

  void dispose() {
    _messageSub?.cancel();
    _messageSub = null;
  }

  /// Cancel an in-progress transfer.
  Future<void> cancel(String id) async {
    _activeTransfers.remove(id);
    client.sendDcMsg({DcMsg.Key: DcMsg.TransferCancel, "id": id});
  }

  /// Upload a file to the host with resume support.
  ///
  /// [id] — Transfer ID (UUID). Pass the same ID to resume a failed upload.
  /// [remotePath] — Target path on the host.
  /// [data] — File bytes.
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
    final initCompleter = Completer<void>();
    final initSub = client.commandResponseStream.listen((data) {
      if (data['type'] == 'response' && data['id'] == id) {
        initCompleter.complete();
      } else if (data['type'] == 'transfer_complete' && data['id'] == id) {
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
    int offset = resumeOffset;
    int seq = 0;

    final raf = await file.open(mode: FileMode.read);
    try {
      await raf.setPosition(resumeOffset);

      while (offset < totalSize) {
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
    final completeSub = client.commandResponseStream.listen((data) {
      if (data['type'] == 'transfer_complete' && data['id'] == id) {
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

  /// Download a file from the host with resume support.
  ///
  /// Returns the downloaded file. The file is saved to a temp location
  /// and the path is returned via the callback or the returned Future.
  ///
  /// Note: Currently uses the legacy stream_start/stream_end path.
  /// TODO: integrate with new binary frame protocol.
  Future<File> download({
    required String id,
    required String remotePath,
    int resumeOffset = 0,
    TransferProgress? onProgress,
    required void Function(File file) onComplete,
  }) async {
    final completer = Completer<File>();

    final sub = client.commandResponseStream.listen((data) {
      if (data['type'] == 'download_end' && data['id'] == id) {
        // Legacy path completion — handled by FileTransferMixin instead.
        // This engine is primarily for the new resume-aware upload protocol.
      }
    });

    client.sendDcMsg({
      DcMsg.Key: DcMsg.DownloadInit,
      "id": id,
      "path": remotePath,
      "resume_offset": resumeOffset,
    });

    // For now, downloads still use the legacy stream_start/stream_end + IOSink path
    // in RtcMessageHandler. This method is a placeholder for future integration.
    // The actual file handling is done by FileTransferMixin's setupTransferListener.

    // Timeout
    try {
      await completer.future.timeout(const Duration(minutes: 10));
    } finally {
      sub.cancel();
    }

    return completer.future;
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
  void _onMessage(Map<String, dynamic> data) {
    final type = data['type'];
    final id = data['id'];
    if (id == null) return;

    final state = _activeTransfers[id];
    if (state == null) return;

    switch (type) {
      case 'transfer_ack':
        final offset = data['offset'] as int? ?? 0;
        final seq = data['seq'] as int? ?? 0;
        state.lastAckOffset = offset;
        state.lastAckSeq = seq;
        break;
      case 'transfer_complete':
        state.isComplete = true;
        break;
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
