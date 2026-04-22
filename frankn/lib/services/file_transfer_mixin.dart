import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:frankn/services/notification_service.dart';
import 'package:frankn/services/rtc/rtc.dart';
import 'package:frankn/services/transfer_engine.dart';
import 'package:frankn/utils/utils.dart';
import 'package:frankn/utils/file_browser/file_browser_utils.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:crypto/crypto.dart';
import 'package:hex/hex.dart';

/// Mixin providing file transfer capabilities to any Stateful Widget.
mixin FileTransferMixin<T extends StatefulWidget> on State<T> {
  RtcClient get client;

  bool isLoading = false;
  String transferMsg = "";
  double transferProgress = 0.0;

  final Map<String, int> _totalSizes = {};
  final Map<String, int> _downloadedSizes = {};
  final Map<String, String> _downloadTargetDirs = {};
  final Map<String, bool> _showNotificationMap = {};
  final Map<String, Function(File)> _onFileReceived = {};
  final Map<String, Timer> _transferTimeouts = {};
  final Map<String, int> _downloadResumeOffsets = {};
  final Map<String, String> _downloadFileNames = {};

  /// Cleans up all tracking state for a transfer ID.
  /// Called when a transfer completes or times out.
  void _cleanupTransfer(String id) {
    _totalSizes.remove(id);
    _downloadedSizes.remove(id);
    _downloadTargetDirs.remove(id);
    _showNotificationMap.remove(id);
    _onFileReceived.remove(id);
    _transferTimeouts[id]?.cancel();
    _transferTimeouts.remove(id);
    _downloadResumeOffsets.remove(id);
    _downloadFileNames.remove(id);
  }

  void setupTransferListener() {
    client.commandResponseStream.listen((data) {
      if (!mounted) return;
      final type = data['type'];

      if (type == DcMsg.StreamStart || type == 'download_start') {
        _onDownloadStart(data);
      } else if (type == DcMsg.FileChunk) {
        _onDownloadChunk(data);
      } else if (type == DcMsg.StreamEnd || type == 'download_end') {
        if (type == DcMsg.StreamEnd) {
          if (data['completed'] == true) {
            _onDownloadComplete(data);
          }
        } else {
          // download_end from new protocol — always trigger completion
          _onDownloadComplete({
            'type': DcMsg.StreamEnd,
            'id': data['id'],
            'temp_path': data['temp_path'] ?? '',
            'file_name': data['file_name'] ?? '',
            'completed': true,
            'hash': data['hash'],
          });
        }
      } else if (data.containsKey('message')) {
        _onGenericMessage(data['message'].toString());
      }
    });
  }

  void _onDownloadStart(Map<String, dynamic> data) {
    final id = data['id'];
    final bool showNotif = _showNotificationMap[id] ?? false;
    _totalSizes[id] = data['total_size'];

    // For resume-aware downloads, the host tells us what offset it started from.
    // We track this so progress reflects total bytes (not just new bytes).
    final hostOffset = data['offset'] as int? ?? 0;
    _downloadResumeOffsets[id] = hostOffset;
    _downloadedSizes[id] = hostOffset;
    _downloadFileNames[id] = data['file_name'] ?? "File";

    // Set a 5-minute timeout to clean up stalled transfers
    _transferTimeouts[id]?.cancel();
    _transferTimeouts[id] = Timer(const Duration(minutes: 5), () {
      client.log("FS TIMEOUT: Download $id stalled — cleaning up.");
      _cleanupTransfer(id);
      if (mounted) {
        setState(() {
          isLoading = false;
          transferMsg = "";
        });
      }
    });

    setState(() {
      isLoading = true;
      transferProgress = hostOffset / (_totalSizes[id] ?? 1);
      transferMsg = "DOWNLOADING: ${data['file_name']}";
    });

    if (showNotif) {
      NotificationService().showProgressNotification(
        id.hashCode.abs() % 100000,
        "Downloading '${data['file_name']}'...",
        "${(transferProgress * 100).toStringAsFixed(1)}%",
        transferProgress * 100,
      );
    }
  }

  void _onDownloadChunk(Map<String, dynamic> data) {
    final id = data['id'];
    final bool showNotif = _showNotificationMap[id] ?? true;
    final chunkSize = data['chunk_size'] as int;

    // Extended frames provide total_received directly; legacy frames need incrementing.
    final totalReceived =
        data['total_received'] as int? ??
        (_downloadedSizes[id] ?? 0) + chunkSize;
    _downloadedSizes[id] = totalReceived;
    final totalSize = _totalSizes[id] ?? 1;

    double progress = (totalReceived / totalSize).clamp(0.0, 1.0);

    setState(() {
      transferProgress = progress;
    });

    // Notification update every 1MB
    if (showNotif &&
        (totalReceived % (1024 * 1024) < chunkSize ||
            totalReceived == totalSize)) {
      NotificationService().showProgressNotification(
        id.hashCode.abs() % 100000,
        "Dowonloading ...",
        "${(progress * 100).toStringAsFixed(1)}%",
        progress * 100,
      );
    }
  }

  Future<void> _moveFile(File source, String destPath) async {
    try {
      await source.rename(destPath);
    } catch (e) {
      // Fallback for cross-device link error (errno 18)
      if (e is FileSystemException && e.osError?.errorCode == 18) {
        await source.copy(destPath);
        await source.delete();
      } else {
        rethrow;
      }
    }
  }

  Future<void> _onDownloadComplete(Map<String, dynamic> data) async {
    final id = data['id'] ?? "0";
    final tempPath = data['temp_path'] as String;
    final fileName = data['file_name'] as String;
    final bool showNotif = _showNotificationMap[id] ?? true;

    try {
      setState(() => transferMsg = "FINALIZING...");
      final tempFile = File(tempPath);
      String? targetDir = _downloadTargetDirs[id];

      if (targetDir == null) {
        // No target dir — user picked a directory via FilePicker
        final appDocDir = await getApplicationDocumentsDirectory();
        final destPath = "${appDocDir.path}/$fileName";
        await _moveFile(tempFile, destPath);

        if (_onFileReceived.containsKey(id)) {
          _onFileReceived[id]!(File(destPath));
          _onFileReceived.remove(id);
        }
      } else if (targetDir.isEmpty) {
        // Empty string means "keep in temp" — used by onComplete callbacks
        if (_onFileReceived.containsKey(id)) {
          _onFileReceived[id]!(tempFile);
          _onFileReceived.remove(id);
        }
        // Don't delete — caller owns the temp file now
      } else {
        final destPath = "$targetDir/$fileName";
        await _moveFile(tempFile, destPath);

        if (showNotif) {
          final notifId = id.hashCode.abs() % 100000;
          await NotificationService().showDownloadComplete(
            notifId,
            fileName,
            destPath,
          );
        }
      }
    } catch (e) {
      client.log("FS ERROR: Finalization failed: $e");
    } finally {
      _cleanupTransfer(id);
      setState(() {
        isLoading = false;
        transferMsg = "";
      });
    }
  }

  void _onGenericMessage(String msg) {
    if (msg.toLowerCase().contains("deleted") ||
        msg.toLowerCase().contains("neural stream finalized")) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            msg,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          backgroundColor: AppColors.matrixGreen,
        ),
      );
      refreshDirectory();
    }
  }

  void refreshDirectory();

  /// Waits until the FS channel's buffered amount drains below the given threshold.
  /// Prevents UploadEnd from racing ahead of pending data chunks.
  Future<void> _drainFsBuffer({
    int threshold = 0,
    int maxWaitMs = 10000,
  }) async {
    final start = DateTime.now();
    while ((client.fsDC?.bufferedAmount ?? 0) > threshold) {
      if (DateTime.now().difference(start).inMilliseconds > maxWaitMs) {
        client.log("FS WARN: Buffer drain timed out — proceeding anyway.");
        break;
      }
      await Future.delayed(const Duration(milliseconds: 10));
    }
  }

  Future<void> downloadFile(
    String remotePath, {
    Function(File)? onComplete,
    bool showNotification = true,
  }) async {
    final requestId = const Uuid().v4();
    _showNotificationMap[requestId] = showNotification;

    // Determine resume offset by checking for existing partial file
    int resumeOffset = 0;
    final tempDir = globalTempDir;
    final partialFile = File('${tempDir.path}/$requestId.part');
    if (await partialFile.exists()) {
      resumeOffset = await partialFile.length();
      client.log("FS: Resuming download $requestId from offset $resumeOffset");
    }

    if (onComplete != null) {
      _onFileReceived[requestId] = onComplete;
      // Keep the file in the temp directory — the callback decides what to do with it.
      // Setting an empty string targetDir signals _onDownloadComplete to skip relocation.
      _downloadTargetDirs[requestId] = '';
      client.sendDownloadInit(
        id: requestId,
        path: remotePath,
        resumeOffset: resumeOffset,
      );
      return;
    }

    String? selectedDir = await FilePicker.platform.getDirectoryPath(
      dialogTitle: "SELECT DESTINATION",
    );

    if (selectedDir == null) return;
    _downloadTargetDirs[requestId] = selectedDir;

    client.sendDownloadInit(
      id: requestId,
      path: remotePath,
      resumeOffset: resumeOffset,
    );
  }

  Future<void> saveEditorContent(String remotePath, String content) async {
    final bytes = utf8.encode(content);
    final transferId = const Uuid().v4();
    final hash = HEX.encode(sha256.convert(bytes).bytes).toLowerCase();

    setState(() {
      isLoading = true;
      transferMsg = "SAVING TO HOST...";
    });

    // Use new transfer protocol
    client.sendTransferInit(
      id: transferId,
      path: remotePath,
      totalSize: bytes.length,
      hash: hash,
    );

    int offset = 0;
    int seq = 0;
    const chunkSize = 61440; // 60KB
    const bufferThreshold = 1024 * 1024; // 1MB

    while (offset < bytes.length) {
      if ((client.fsDC?.bufferedAmount ?? 0) > bufferThreshold) {
        await Future.delayed(const Duration(milliseconds: 10));
        continue;
      }
      int end = (offset + chunkSize < bytes.length)
          ? offset + chunkSize
          : bytes.length;
      final chunk = Uint8List.fromList(bytes.sublist(offset, end));
      final isFinal = end >= bytes.length;
      client.sendUploadChunkRaw(
        id: transferId,
        data: chunk,
        offset: offset,
        seq: seq,
        flags: (isFinal ? 0x02 : 0) | (seq % 50 == 0 ? 0x04 : 0),
      );
      offset = end;
      seq++;
      if (mounted) setState(() => transferProgress = offset / bytes.length);
    }
    // Drain all buffered data before final chunk is processed
    await _drainFsBuffer();
  }

  Future<void> uploadFile(String currentRemotePath) async {
    FilePickerResult? result = await FilePicker.platform.pickFiles();
    if (result == null) return;

    final file = File(result.files.single.path!);
    final transferId = const Uuid().v4();
    final targetPath = PathHelper.join(
      currentRemotePath,
      result.files.single.name,
    );

    setState(() {
      isLoading = true;
      transferMsg = "PREPARING UPLOAD...";
      transferProgress = 0.0;
    });

    // Compute hash efficiently by streaming from disk
    final hash = await sha256.bind(file.openRead()).first;
    final hashStr = HEX.encode(hash.bytes).toLowerCase();

    setState(() {
      transferMsg = "UPLOADING: ${result.files.single.name}";
    });
    
    NotificationService().showProgressNotification(
      transferId.hashCode.abs() % 100000,
      "Uploading '${result.files.single.name}'...",
      "0.0%",
      0.0,
    );

    try {
      final engine = TransferEngine(client);
      await engine.upload(
        id: transferId,
        remotePath: targetPath,
        file: file,
        hash: hashStr,
        onProgress: ({required progress, required bytesTransferred, required totalBytes}) {
          if (mounted) {
            setState(() {
              transferProgress = progress;
            });
          }
          
          // Update notification every 1MB or on completion
          if (bytesTransferred % (1024 * 1024) < 61440 || bytesTransferred == totalBytes) {
            NotificationService().showProgressNotification(
              transferId.hashCode.abs() % 100000,
              "Uploading '${result.files.single.name}'...",
              "${(progress * 100).toStringAsFixed(1)}%",
              progress * 100,
            );
          }
        },
      );
      engine.dispose();
      
      NotificationService().showProgressNotification(
        transferId.hashCode.abs() % 100000,
        "Upload Complete",
        "'${result.files.single.name}' uploaded successfully.",
        100.0,
      );
      
      client.log("FS: Upload complete for $targetPath");
      refreshDirectory();
    } catch (e) {
      NotificationService().showProgressNotification(
        transferId.hashCode.abs() % 100000,
        "Upload Failed",
        "'${result.files.single.name}' failed to upload.",
        100.0, // Finish progress to let it be dismissed
      );
      client.log("FS ERROR: Upload failed - $e");
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
          transferMsg = "";
        });
      }
    }
  }
}
