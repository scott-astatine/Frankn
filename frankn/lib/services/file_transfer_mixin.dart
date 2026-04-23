import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:frankn/services/rtc_thin_client.dart';
import 'package:frankn/utils/utils.dart';
import 'package:frankn/utils/file_browser/file_browser_utils.dart';
import 'package:uuid/uuid.dart';
import 'package:crypto/crypto.dart';
import 'package:hex/hex.dart';

/// Mixin providing file transfer capabilities to any Stateful Widget.
mixin FileTransferMixin<T extends StatefulWidget> on State<T> {
  RtcThinClient get client;

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

    client.transferProgressStream.listen((data) {
      if (!mounted) return;
      final type = data['type'];

      if (type == 'complete') {
        setState(() {
          isLoading = false;
          transferMsg = "";
        });
        refreshDirectory();
      } else if (type == 'failed') {
        setState(() {
          isLoading = false;
          transferMsg = "";
        });
      } else if (data['progress'] != null) {
        // Safe progress update
        setState(() {
          transferProgress = (data['progress'] as num).toDouble();
        });
      }
    });
  }

  void _onDownloadStart(Map<String, dynamic> data) {
    final id = data['id'];
    _totalSizes[id] = data['total_size'];

    final hostOffset = data['offset'] as int? ?? 0;
    _downloadResumeOffsets[id] = hostOffset;
    _downloadedSizes[id] = hostOffset;
    _downloadFileNames[id] = data['file_name'] ?? "File";

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
  }

  void _onDownloadChunk(Map<String, dynamic> data) {
    final id = data['id'];
    final chunkSize = data['chunk_size'] as int;

    final totalReceived =
        data['total_received'] as int? ??
        (_downloadedSizes[id] ?? 0) + chunkSize;
    _downloadedSizes[id] = totalReceived;
    final totalSize = _totalSizes[id] ?? 1;

    double progress = (totalReceived / totalSize).clamp(0.0, 1.0);

    setState(() {
      transferProgress = progress;
    });
  }

  Future<void> _onDownloadComplete(Map<String, dynamic> data) async {
    final id = data['id'] ?? "0";

    try {
      setState(() => transferMsg = "DOWNLOAD COMPLETE");
    } catch (e) {
      client.log("FS ERROR: Notification failed: $e");
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

  Future<void> downloadFile(
    String remotePath, {
    Function(File)? onComplete,
    bool showNotification = true,
    bool isTemporary = false,
  }) async {
    final requestId = const Uuid().v4();
    _showNotificationMap[requestId] = showNotification;

    int resumeOffset = 0;
    final tempDir = globalTempDir;
    final partialFile = File('${tempDir.path}/$requestId.part');
    if (await partialFile.exists()) {
      resumeOffset = await partialFile.length();
      client.log("FS: Resuming download $requestId from offset $resumeOffset");
    }

    if (onComplete != null || isTemporary) {
      if (onComplete != null) _onFileReceived[requestId] = onComplete;
      _downloadTargetDirs[requestId] = '';
      client.sendDownloadInit(
        id: requestId,
        path: remotePath,
        resumeOffset: resumeOffset,
        targetDir: '', // Empty means temp dir only
        showNotification: showNotification,
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
      targetDir: selectedDir,
      showNotification: showNotification,
    );
  }

  Future<void> saveEditorContent(String remotePath, String content) async {
    final transferId = const Uuid().v4();

    setState(() {
      isLoading = true;
      transferMsg = "PREPARING UPLOAD...";
      transferProgress = 0.0;
    });

    final tempDir = globalTempDir;
    final file = File('${tempDir.path}/$transferId.txt');
    await file.writeAsString(content);

    final hash = await sha256.bind(file.openRead()).first;
    final hashStr = HEX.encode(hash.bytes).toLowerCase();

    setState(() {
      transferMsg = "SAVING TO HOST...";
    });

    client.sendIntent('upload_init', {
      'id': transferId,
      'file_name': remotePath.split('/').last,
      'local_path': file.path,
      'remote_path': remotePath,
      'hash': hashStr,
    });
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

    final hash = await sha256.bind(file.openRead()).first;
    final hashStr = HEX.encode(hash.bytes).toLowerCase();

    setState(() {
      transferMsg = "UPLOADING: ${result.files.single.name}";
    });

    client.sendIntent('upload_init', {
      'id': transferId,
      'file_name': result.files.single.name,
      'local_path': file.path,
      'remote_path': targetPath,
      'hash': hashStr,
    });
  }
}
