import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:frankn/services/isolate_protocol.dart';
import 'package:frankn/services/rtc_thin_client.dart';
import 'package:frankn/utils/utils.dart';
import 'package:frankn/utils/dc_msg_util.dart';
import 'package:frankn/utils/file_browser/file_browser_utils.dart';
import 'package:uuid/uuid.dart';
import 'package:crypto/crypto.dart';
import 'package:hex/hex.dart';

/// Mixin providing file transfer capabilities to any Stateful Widget.
mixin FileTransferMixin<T extends StatefulWidget> on State<T> {
  RtcThinClient get client;

  bool isLoading = false;
  String transferMsg = "";

  void setupTransferListener() {
    client.genDcMsgStream.listen((msg) {
      if (!mounted) return;
      if (msg is HostMsgResponse) {
        final data = msg.data;
        if (data is Map && data.containsKey('message')) {
          _onGenericMessage(data['message'].toString());
        }
      }
    });

    client.transferProgressStream.listen((event) {
      if (!mounted) return;
      if (event is TransferProgressComplete) {
        setState(() {
          isLoading = false;
          transferMsg = "";
        });
        refreshDirectory();
      } else if (event is TransferProgressFailed) {
        setState(() {
          isLoading = false;
          transferMsg = "";
        });
      }
    });
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

  Future<String> downloadFile(
    String remotePath, {
    int? size, // Pass size for stable ID/resume
    bool showNotification = true,
    bool isTemporary = false,
  }) async {
    // Generate stable ID if size is known, otherwise fallback to random (fresh start)
    final requestId = size != null
        ? FileUtils.generateStableTransferId(remotePath, size)
        : const Uuid().v4();

    int resumeOffset = 0;
    final tempDir = globalTempDir;
    final partialFile = File('${tempDir.path}/$requestId.part');
    if (await partialFile.exists()) {
      resumeOffset = await partialFile.length();
      client.log("FS: Resuming download $requestId from offset $resumeOffset");
    }

    if (isTemporary) {
      client.sendDownloadInit(
        id: requestId,
        path: remotePath,
        resumeOffset: resumeOffset,
        targetDir: '', // Empty means temp dir only
        showNotification: showNotification,
      );
      return requestId;
    }

    String? selectedDir = await FilePicker.platform.getDirectoryPath(
      dialogTitle: "Select Destination",
    );

    if (selectedDir == null) return requestId;

    client.sendDownloadInit(
      id: requestId,
      path: remotePath,
      resumeOffset: resumeOffset,
      targetDir: selectedDir,
      showNotification: showNotification,
    );

    return requestId;
  }

  Future<void> saveEditorContent(String remotePath, String content) async {
    final tempDir = globalTempDir;
    final tempFile = File(
      '${tempDir.path}/temp_editor_${DateTime.now().millisecondsSinceEpoch}.txt',
    );
    await tempFile.writeAsString(content);

    final int size = await tempFile.length();
    final transferId = FileUtils.generateStableTransferId(remotePath, size);

    setState(() {
      isLoading = true;
      transferMsg = "PREPARING UPLOAD...";
    });

    final hash = await sha256.bind(tempFile.openRead()).first;
    final hashStr = HEX.encode(hash.bytes).toLowerCase();

    // Rename temp file to use the stable transferId for part tracking
    final finalFile = File('${tempDir.path}/$transferId.upload');
    if (await finalFile.exists()) await finalFile.delete();
    await tempFile.rename(finalFile.path);

    setState(() {
      transferMsg = "SAVING TO HOST...";
    });

    client.sendIntent(IsolateAction.uploadInit, {
      'id': transferId,
      'file_name': remotePath.split('/').last,
      'local_path': finalFile.path,
      'remote_path': remotePath,
      'hash': hashStr,
    });
  }

  Future<void> uploadFile(String currentRemotePath) async {
    FilePickerResult? result = await FilePicker.platform.pickFiles();
    if (result == null) return;

    final file = File(result.files.single.path!);
    final int size = await file.length();
    final targetPath = PathHelper.join(
      currentRemotePath,
      result.files.single.name,
    );
    final transferId = FileUtils.generateStableTransferId(targetPath, size);

    setState(() {
      isLoading = true;
      transferMsg = "PREPARING UPLOAD...";
    });

    final hash = await sha256.bind(file.openRead()).first;
    final hashStr = HEX.encode(hash.bytes).toLowerCase();

    setState(() {
      transferMsg = "UPLOADING: ${result.files.single.name}";
    });

    client.sendIntent(IsolateAction.uploadInit, {
      'id': transferId,
      'file_name': result.files.single.name,
      'local_path': file.path,
      'remote_path': targetPath,
      'hash': hashStr,
    });
  }
}
