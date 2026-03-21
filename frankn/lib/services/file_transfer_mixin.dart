import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:frankn/services/notification_service.dart';
import 'package:frankn/services/rtc/rtc.dart';
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

  void setupTransferListener() {
    client.commandResponseStream.listen((data) {
      if (!mounted) return;
      final type = data['type'];

      if (type == DcMsg.StreamStart) {
        _onDownloadStart(data);
      } else if (type == DcMsg.FileChunk) {
        _onDownloadChunk(data);
      } else if (type == DcMsg.StreamEnd) {
        if (data['completed'] == true) {
          _onDownloadComplete(data);
        }
      } else if (data.containsKey('message')) {
        _onGenericMessage(data['message'].toString());
      }
    });
  }

  void _onDownloadStart(Map<String, dynamic> data) {
    final id = data['id'];
    final bool showNotif = _showNotificationMap[id] ?? true;
    _totalSizes[id] = data['total_size'];
    _downloadedSizes[id] = 0;

    setState(() {
      isLoading = true;
      transferProgress = 0.0;
      transferMsg = "DOWNLOADING: ${data['file_name']}";
    });

    if (showNotif) {
      NotificationService().showProgressNotification(
        id.hashCode.abs() % 100000,
        "DOWNLOADING...",
        data['file_name'],
        0,
      );
    }
  }

  void _onDownloadChunk(Map<String, dynamic> data) {
    final id = data['id'];
    final bool showNotif = _showNotificationMap[id] ?? true;
    final chunkSize = data['chunk_size'] as int;
    
    _downloadedSizes[id] = (_downloadedSizes[id] ?? 0) + chunkSize;
    final currentTotal = _downloadedSizes[id]!;
    final totalSize = _totalSizes[id] ?? 1;
    
    double progress = (currentTotal / totalSize);

    setState(() {
      transferProgress = progress;
    });

    // Notification update every 1MB
    if (showNotif && (currentTotal % (1024 * 1024) < chunkSize || currentTotal == totalSize)) {
      NotificationService().showProgressNotification(
        id.hashCode.abs() % 100000,
        "DOWNLOADING...",
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
        final appDocDir = await getApplicationDocumentsDirectory();
        final destPath = "${appDocDir.path}/$fileName";
        await _moveFile(tempFile, destPath);
        
        if (_onFileReceived.containsKey(id)) {
          _onFileReceived[id]!(File(destPath));
          _onFileReceived.remove(id);
        }
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
      _showNotificationMap.remove(id);
      _downloadTargetDirs.remove(id);
      _totalSizes.remove(id);
      _downloadedSizes.remove(id);
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
          content: Text(msg, style: const TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: AppColors.matrixGreen,
        ),
      );
      refreshDirectory();
    }
  }

  void refreshDirectory();

  Future<void> downloadFile(
    String remotePath, {
    Function(File)? onComplete,
    bool showNotification = true,
  }) async {
    final requestId = const Uuid().v4();
    _showNotificationMap[requestId] = showNotification;

    if (onComplete != null) {
      _onFileReceived[requestId] = onComplete;
      client.sendDcMsg({
        "id": requestId,
        DcMsg.Key: DcMsg.GetFile,
        "path": remotePath,
      });
      return;
    }

    String? selectedDir = await FilePicker.platform.getDirectoryPath(
      dialogTitle: "SELECT DESTINATION",
    );

    if (selectedDir == null) return;
    _downloadTargetDirs[requestId] = selectedDir;

    client.sendDcMsg({
      "id": requestId,
      DcMsg.Key: DcMsg.GetFile,
      "path": remotePath,
    });
  }

  Future<void> saveEditorContent(String remotePath, String content) async {
    final bytes = utf8.encode(content);
    final transferId = const Uuid().v4();
    final hash = HEX.encode(sha256.convert(bytes).bytes).toLowerCase();

    setState(() {
      isLoading = true;
      transferMsg = "SAVING TO HOST...";
    });

    client.sendUploadStart(id: transferId, path: remotePath, totalSize: bytes.length);

    int offset = 0;
    const chunkSize = 61440; // 60KB
    const bufferThreshold = 1024 * 1024; // 1MB

    while (offset < bytes.length) {
      if ((client.fsDC?.bufferedAmount ?? 0) > bufferThreshold) {
        await Future.delayed(const Duration(milliseconds: 10));
        continue;
      }
      int end = (offset + chunkSize < bytes.length) ? offset + chunkSize : bytes.length;
      client.sendUploadChunkRaw(id: transferId, data: Uint8List.fromList(bytes.sublist(offset, end)));
      offset = end;
      if (mounted) setState(() => transferProgress = offset / bytes.length);
    }
    client.sendUploadEnd(id: transferId, hash: hash);
  }

  Future<void> uploadFile(String currentRemotePath) async {
    FilePickerResult? result = await FilePicker.platform.pickFiles();
    if (result == null) return;

    final file = File(result.files.single.path!);
    final bytes = await file.readAsBytes();
    final totalSize = bytes.length;
    final transferId = const Uuid().v4();
    final targetPath = PathHelper.join(currentRemotePath, result.files.single.name);
    final hash = HEX.encode(sha256.convert(bytes).bytes).toLowerCase();

    setState(() {
      isLoading = true;
      transferMsg = "UPLOADING: ${result.files.single.name}";
    });

    client.sendUploadStart(id: transferId, path: targetPath, totalSize: totalSize);

    int offset = 0;
    const chunkSize = 61440; // 60KB
    const bufferThreshold = 1024 * 1024; // 1MB

    while (offset < bytes.length) {
      if ((client.fsDC?.bufferedAmount ?? 0) > bufferThreshold) {
        await Future.delayed(const Duration(milliseconds: 10));
        continue;
      }
      int end = (offset + chunkSize < bytes.length) ? offset + chunkSize : bytes.length;
      client.sendUploadChunkRaw(id: transferId, data: Uint8List.fromList(bytes.sublist(offset, end)));
      offset = end;
      if (mounted) setState(() => transferProgress = offset / bytes.length);
    }
    client.sendUploadEnd(id: transferId, hash: hash);
  }
}
