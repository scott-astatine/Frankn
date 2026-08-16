import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:frankn/screens/code_editor_screen.dart';
import 'package:frankn/screens/markdown_viewer_screen.dart';
import 'package:frankn/screens/pdf_viewer_screen.dart';

class FileViewerService with WidgetsBindingObserver {
  static const _channel = MethodChannel('frankn/file_viewer');
  final GlobalKey<NavigatorState> navigatorKey;
  String? _lastOpenedPath;

  FileViewerService({required this.navigatorKey}) {
    WidgetsBinding.instance.addObserver(this);

    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onOpenFile') {
        final Map<dynamic, dynamic>? data = call.arguments;
        if (data != null) {
          _processFileData(Map<String, String>.from(data));
        }
      }
    });

    // Check pending file with a slight delay to ensure UI mounting
    Future.delayed(const Duration(milliseconds: 600), () {
      _checkPendingFile();
    });
  }

  Future<void> _checkPendingFile() async {
    try {
      final Map<dynamic, dynamic>? data =
          await _channel.invokeMethod('getPendingFile');
      if (data != null) {
        _processFileData(Map<String, String>.from(data));
      }
    } catch (e) {
      debugPrint("FILE_VIEWER: Error checking pending file: $e");
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPendingFile();
    }
  }

  void _processFileData(Map<String, String> data) {
    final path = data['path'];
    final name = data['name'] ?? 'Document';

    if (path == null || path.isEmpty) return;
    if (_lastOpenedPath == path) return; // Prevent duplicate navigation

    _lastOpenedPath = path;

    final navState = navigatorKey.currentState;
    if (navState != null) {
      final isMd = name.toLowerCase().endsWith('.md') ||
          name.toLowerCase().endsWith('.markdown');
      final isPdf = name.toLowerCase().endsWith('.pdf');

      Widget buildViewer() {
        if (isMd) {
          return MarkdownViewerScreen(
            fileName: name,
            localFilePath: path,
          );
        } else if (isPdf) {
          return PdfViewerScreen(
            fileName: name,
            localFilePath: path,
          );
        } else {
          return CodeEditorScreen(
            fileName: name,
            localFilePath: path,
          );
        }
      }

      navState.push(
        MaterialPageRoute(
          builder: (_) => buildViewer(),
        ),
      ).then((_) {
        _lastOpenedPath = null;
      });
    }
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
  }
}
