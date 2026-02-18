import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:frankn/services/notification_service.dart';
import 'package:frankn/services/rtc/rtc.dart';
import 'package:frankn/utils/utils.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:crypto/crypto.dart';
import 'package:hex/hex.dart';

/// Mixin providing file transfer capabilities to any Stateful Widget.
///
/// This mixin handles the complex logic of chunked file transfer over WebRTC,
/// including progress tracking, notification updates, and integrity verification.
mixin FileTransferMixin<T extends StatefulWidget> on State<T> {
  RtcClient get client;

    bool isLoading = false;
    String transferMsg = "";
    double transferProgress = 0.0;
  
    // Tracks active downloads by ID
    final Map<String, int> _totalSizes = {};
    final Map<String, int> _downloadedSizes = {};
    
    // Destination directory for each transfer ID
    final Map<String, String> _downloadTargetDirs = {};
    
    // Controls whether notifications are shown for a transfer ID
    final Map<String, bool> _showNotificationMap = {};
    
    // Callback map for internal transfers (e.g. opening in editor)
    final Map<String, Function(File)> _onFileReceived = {};
  
    /// Initializes listeners for file transfer messages.
    /// Must be called in initState().
    void setupTransferListener() {
      client.commandResponseStream.listen((data) {
        if (!mounted) return;
        final type = data['type'];
  
        if (type == DcMsg.FileTransferStart) {
          _onDownloadStart(data);
        } else if (type == DcMsg.FileChunk) {
          _onDownloadChunk(data);
        } else if (type == DcMsg.FileTransferEnd) {
          if (data['completed'] == true) {
            handleInternalTransferComplete(data);
          } else {
            _onDownloadEnd(data);
          }
        } else {
          if (data.containsKey('message')) {
            _onGenericMessage(data['message'].toString());
          }
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
      if (data.containsKey('chunk_size')) {
        _downloadedSizes[id] =
            (_downloadedSizes[id] ?? 0) + (data['chunk_size'] as int);
        double progress = (_downloadedSizes[id]! / (_totalSizes[id] ?? 1));
  
        setState(() {
          transferProgress = progress;
        });
  
        // Throttle notification updates to avoid flooding the system
        if (showNotif && _downloadedSizes[id]! % (65536 * 10) == 0) {
          NotificationService().showProgressNotification(
            id.hashCode.abs() % 100000,
            "DOWNLOADING...",
            "${(progress * 100).round()}%",
            progress * 100,
          );
        }
      }
    }
  void _onDownloadEnd(Map<String, dynamic> data) {}

  /// Called when a transfer completes successfully.
  /// Delegates to _saveFile to persist the data.
  void handleInternalTransferComplete(Map<String, dynamic> data) {
    final id = data['id'] ?? "0";
    _saveFile(id, data['file_name'], data['bytes']);
  }

  void _onGenericMessage(String msg) {
    msg = msg.toLowerCase();
    if (msg.contains("deleted") ||
        msg.contains("uploaded") ||
        msg.contains("integrity")) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            msg,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          backgroundColor: msg.contains("failure")
              ? AppColors.errorRed
              : AppColors.matrixGreen,
        ),
      );
      refreshDirectory();
    }
  }

  /// Abstract method to refresh the UI after file operations.
  /// Implemented by consuming widgets (e.g. FileBrowserScreen).
  void refreshDirectory();

  /// Initiates a file download from the host.
  ///
  /// If [onComplete] is provided, the file is downloaded to temp storage
  /// and passed to the callback (for viewing/editing).
  /// Otherwise, it prompts the user for a download location.
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

  /// Streams editor content back to the host as a file upload.
  ///
  /// This bypasses local file selection and directly streams the string content
  /// as a UTF-8 encoded binary stream.
  Future<void> saveEditorContent(String remotePath, String content) async {
    final bytes = utf8.encode(content);
    final transferId = const Uuid().v4();
    final hash = HEX.encode(sha256.convert(bytes).bytes).toLowerCase();

    setState(() {
      isLoading = true;
      transferMsg = "SAVING TO HOST...";
    });

    client.sendUploadStart(
      id: transferId,
      path: remotePath,
      totalSize: bytes.length,
      hash: hash,
    );

    int offset = 0;
    const chunkSize = 16384;
    while (offset < bytes.length) {
      int end = (offset + chunkSize < bytes.length)
          ? offset + chunkSize
          : bytes.length;
      final chunkB64 = base64Encode(bytes.sublist(offset, end));
      client.sendUploadChunk(id: transferId, data: chunkB64);
      offset = end;
      await Future.delayed(const Duration(milliseconds: 1));
    }

    client.sendUploadEnd(id: transferId);
  }

  /// Uploads a local file to the host.
  ///
  /// Uses a file picker to select the source, then streams it in chunks.
  /// Includes SHA256 hash calculation for integrity verification on the host.
  Future<void> uploadFile(String currentRemotePath) async {
    FilePickerResult? result = await FilePicker.platform.pickFiles();
    if (result == null) return;

    final file = File(result.files.single.path!);
    final bytes = await file.readAsBytes();
    final totalSize = bytes.length;
    final transferId = const Uuid().v4();
    final targetPath = "$currentRemotePath${result.files.single.name}";

    final hash = HEX.encode(sha256.convert(bytes).bytes).toLowerCase();

    setState(() {
      isLoading = true;
      transferMsg = "UPLOADING: ${result.files.single.name}";
    });

    client.sendUploadStart(
      id: transferId,
      path: targetPath,
      totalSize: totalSize,
      hash: hash,
    );

    int offset = 0;
    const chunkSize = 16384;
    while (offset < bytes.length) {
      int end = (offset + chunkSize < bytes.length)
          ? offset + chunkSize
          : bytes.length;
      client.sendUploadChunk(
        id: transferId,
        data: base64Encode(bytes.sublist(offset, end)),
      );
      offset = end;
      await Future.delayed(const Duration(milliseconds: 1));
    }

    client.sendUploadEnd(id: transferId);
  }

  /// Persists downloaded data to disk.
  ///
  /// Handles both user-initiated downloads (to target dir) and internal
  /// downloads (to temp dir for viewing). Triggers completion notification.
  Future<void> _saveFile(
    String transferId,
    String fileName,
    List<int> bytes,
  ) async {
    try {
      final bool showNotif = _showNotificationMap[transferId] ?? true;
      setState(() => transferMsg = "SAVING...");

      String? targetDir = _downloadTargetDirs[transferId];
      if (targetDir == null) {
        final tempDir = await getTemporaryDirectory();
        final file = File("${tempDir.path}/$fileName");
        await file.writeAsBytes(bytes);
        if (_onFileReceived.containsKey(transferId)) {
          _onFileReceived[transferId]!(file);
          _onFileReceived.remove(transferId);
        }
        _showNotificationMap.remove(transferId);
        return;
      }

      final file = File("$targetDir/$fileName");
      await file.writeAsBytes(bytes);

      if (showNotif) {
        final notifId = transferId.hashCode.abs() % 100000;
        await NotificationService().showDownloadComplete(
          notifId,
          fileName,
          file.path,
        );
      }
      _showNotificationMap.remove(transferId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("SAVE FAILED: $e"),
            backgroundColor: AppColors.errorRed,
          ),
        );
      }
    } finally {
      setState(() {
        isLoading = false;
        transferMsg = "";
      });
    }
  }
}
