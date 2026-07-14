import 'dart:async';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:frankn/services/isolate_protocol.dart';
import 'package:frankn/services/rtc_thin_client.dart';
import 'package:frankn/utils/file_browser/file_browser_utils.dart';
import 'package:frankn/utils/utils.dart';
import 'package:hex/hex.dart';

import 'package:frankn/widgets/cyber_alert_dialog.dart';
import 'package:frankn/widgets/settings/remote_dir_selector.dart';

class SharingService with WidgetsBindingObserver {
  static const _channel = MethodChannel('frankn/sharing');
  final RtcThinClient client;
  final GlobalKey<NavigatorState> navigatorKey;
  bool _isDialogShowing = false;

  SharingService({required this.client, required this.navigatorKey}) {
    WidgetsBinding.instance.addObserver(this);

    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onSharedDataReceived') {
        final List<dynamic>? data = call.arguments;
        if (data != null) {
          _processSharedData(data);
        }
      }
    });

    // Check initial sharing with a slight delay to ensure UI mounting
    Future.delayed(const Duration(milliseconds: 600), () {
      _checkInitialSharing();
    });
  }

  Future<void> _checkInitialSharing() async {
    try {
      final List<dynamic>? data = await _channel.invokeMethod('getSharedData');
      if (data != null) {
        _processSharedData(data);
      }
    } catch (e) {
      client.log("SHARING: Error checking initial sharing: $e");
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkInitialSharing();
    }
  }

  void _processSharedData(List<dynamic> data) {
    final List<Map<String, String>> parsed = data.map((item) {
      return Map<String, String>.from(item as Map);
    }).toList();

    if (parsed.isEmpty) return;

    // Check if authenticated to a WebRTC host
    if (client.currentHostState == HostConnectionState.authenticated) {
      _promptUpload(parsed);
    }
  }

  void _promptUpload(List<Map<String, String>> items) {
    if (_isDialogShowing) return;

    final context = navigatorKey.currentContext;
    if (context == null) return;

    _isDialogShowing = true;

    showDialog(
      context: context,
      builder: (BuildContext dialogCtx) {
        return CyberAlertDialog(
          title: "SHARED CONTENT DETECTED",
          borderColor: AppColors.accentPrimary,
          titleColor: AppColors.accentPrimary,
          content: Text(
            "Do you want to upload ${items.length} shared item(s) to ${client.currentHostName}?",
          ),
          actions: [
            TextButton(
              onPressed: () {
                _isDialogShowing = false;
                Navigator.pop(dialogCtx);
              },
              child: const Text(
                "CANCEL",
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            TextButton(
              onPressed: () async {
                _isDialogShowing = false;
                Navigator.pop(dialogCtx);
                await Future.delayed(const Duration(milliseconds: 250));
                _executeUpload(items);
              },
              child: const Text(
                "UPLOAD",
                style: TextStyle(
                  color: AppColors.accentPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    ).then((_) {
      _isDialogShowing = false;
    });
  }

  void _executeUpload(List<Map<String, String>> items) async {
    final context = navigatorKey.currentContext;
    if (context == null) return;

    // Show the remote directory selector modal on the host
    final String? targetDir = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => RemoteDirSelector(
        client: client,
        initialPath: FileBrowserConstants.defaultPath,
      ),
    );

    if (targetDir == null || targetDir.isEmpty) return;

    for (var item in items) {
      final type = item['type'];
      final value = item['value'];
      if (type == 'file' && value != null) {
        final file = File(value);
        if (!await file.exists()) continue;

        final int size = await file.length();
        final fileName = value.split(Platform.pathSeparator).last;
        final targetPath = PathHelper.join(targetDir, fileName);
        final transferId = FileUtils.generateStableTransferId(targetPath, size);

        final hash = await sha256.bind(file.openRead()).first;
        final hashStr = HEX.encode(hash.bytes).toLowerCase();

        client.sendIntent(IsolateAction.uploadInit, {
          'id': transferId,
          'file_name': fileName,
          'local_path': file.path,
          'remote_path': targetPath,
          'hash': hashStr,
        });

        _showStatusMessage("⚡ UPLOADING: ${fileName.toUpperCase()}");
      } else if (type == 'text' && value != null) {
        final tempDir = globalTempDir;
        final tempFile = File(
          '${tempDir.path}/shared_text_${DateTime.now().millisecondsSinceEpoch}.txt',
        );
        await tempFile.writeAsString(value);

        final int size = await tempFile.length();
        const fileName = "shared_link.txt";
        final targetPath = PathHelper.join(targetDir, fileName);
        final transferId = FileUtils.generateStableTransferId(targetPath, size);

        final hash = await sha256.bind(tempFile.openRead()).first;
        final hashStr = HEX.encode(hash.bytes).toLowerCase();

        client.sendIntent(IsolateAction.uploadInit, {
          'id': transferId,
          'file_name': fileName,
          'local_path': tempFile.path,
          'remote_path': targetPath,
          'hash': hashStr,
        });

        _showStatusMessage("⚡ UPLOADING SHARED LINK");
      }
    }
  }

  void _showStatusMessage(String msg) {
    final context = navigatorKey.currentContext;
    if (context == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          msg,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: AppColors.accentPrimary,
          ),
        ),
        backgroundColor: AppColors.background,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
  }
}
