import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:frankn/services/file_transfer_mixin.dart';
import 'package:frankn/services/rtc/rtc.dart';
import 'package:frankn/utils/utils.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/dart.dart';
import 'package:re_highlight/languages/rust.dart';
import 'package:re_highlight/languages/python.dart';
import 'package:re_highlight/languages/javascript.dart';
import 'package:re_highlight/languages/bash.dart';
import 'package:re_highlight/languages/json.dart';
import 'package:re_highlight/languages/yaml.dart';
import 'package:re_highlight/languages/markdown.dart';
import 'package:re_highlight/languages/cpp.dart';
import 'package:re_highlight/languages/java.dart';
import 'package:re_highlight/languages/xml.dart';
import 'package:re_highlight/styles/monokai-sublime.dart';
import 'package:share_plus/share_plus.dart';

class CodeEditorScreen extends StatefulWidget {
  final RtcClient client;
  final String remotePath;
  final String fileName;

  const CodeEditorScreen({
    super.key,
    required this.client,
    required this.remotePath,
    required this.fileName,
  });

  @override
  State<CodeEditorScreen> createState() => _CodeEditorScreenState();
}

class _CodeEditorScreenState extends State<CodeEditorScreen> with FileTransferMixin {
  @override
  RtcClient get client => widget.client;

  late CodeLineEditingController _controller;
  File? _localFile;
  bool _isInitialized = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _controller = CodeLineEditingController();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    setupTransferListener();
    _loadFile();
  }

  @override
  void refreshDirectory() {}

  void _loadFile() {
    downloadFile(
      widget.remotePath,
      showNotification: false,
      onComplete: (file) async {
        final content = await file.readAsString();
        setState(() {
          _localFile = file;
          _controller.text = content;
          _isInitialized = true;
        });
      },
    );
  }

  Future<void> _handleSave() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    
    try {
      await saveEditorContent(widget.remotePath, _controller.text);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("FILE SAVED TO HOST", style: TextStyle(fontWeight: FontWeight.bold)),
            backgroundColor: AppColors.matrixGreen,
          ),
        );
      }
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
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isKeyboardVisible = MediaQuery.of(context).viewInsets.bottom > 0;

    return Scaffold(
      backgroundColor: AppColors.voidBlack,
      body: Stack(
        children: [
          Positioned.fill(
            child: SafeArea(
              bottom: false,
              top: false,
              child: _buildBody(),
            ),
          ),
          
          if (!isKeyboardVisible && _isInitialized)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _buildTinyStatusBar(),
            ),
        ],
      ),
    );
  }

  Widget _buildTinyStatusBar() {
    return Container(
      height: 32,
      decoration: BoxDecoration(
        color: AppColors.deepSpace.withValues(alpha: 0.8),
        border: const Border(top: BorderSide(color: AppColors.neonCyan, width: 0.5)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: const Icon(Icons.chevron_left, color: AppColors.neonCyan, size: 18),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              "${widget.fileName}  —  ${widget.remotePath}",
              style: const TextStyle(
                color: AppColors.textGrey,
                fontSize: 10,
                fontFamily: 'Courier',
                fontWeight: FontWeight.bold,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            icon: const Icon(Icons.share, color: AppColors.neonCyan, size: 16),
            onPressed: () {
              if (_localFile != null) {
                SharePlus.instance.share(ShareParams(
                  files: [XFile(_localFile!.path)],
                  text: widget.fileName,
                ));
              }
            },
          ),
          const SizedBox(width: 8),
          if (_isSaving)
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.neonCyan),
            )
          else
            IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              icon: const Icon(Icons.save, color: AppColors.neonCyan, size: 16),
              onPressed: _handleSave,
            ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (!_isInitialized) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: AppColors.neonCyan),
            const SizedBox(height: 16),
            Text(transferMsg.isEmpty ? "LOADING FILE..." : transferMsg, 
              style: const TextStyle(color: AppColors.neonCyan, fontSize: 12, fontWeight: FontWeight.bold)),
          ],
        ),
      );
    }

    final String lang = _detectLanguage();

    return CodeEditor(
      controller: _controller,
      style: CodeEditorStyle(
        fontSize: 13,
        fontFamily: 'JetBrainsMonoNerdFont',
        codeTheme: CodeHighlightTheme(
          languages: {
            lang: CodeHighlightThemeMode(mode: _getLangMode(lang)),
          },
          theme: monokaiSublimeTheme,
        ),
      ),
      indicatorBuilder: (context, editingController, chunkController, notifier) {
        return Row(
          children: [
            DefaultCodeLineNumber(
              controller: editingController,
              notifier: notifier,
            ),
            DefaultCodeChunkIndicator(
              width: 20,
              controller: chunkController,
              notifier: notifier,
            ),
          ],
        );
      },
    );
  }

  String _detectLanguage() {
    final ext = widget.fileName.split('.').last.toLowerCase();
    switch (ext) {
      case 'dart': return 'dart';
      case 'rs': return 'rust';
      case 'py': return 'python';
      case 'js': return 'javascript';
      case 'sh': return 'bash';
      case 'json': return 'json';
      case 'yaml': case 'yml': return 'yaml';
      case 'md': return 'markdown';
      case 'cpp': case 'hpp': case 'h': case 'c': return 'cpp';
      case 'java': return 'java';
      case 'xml': case 'html': return 'xml';
      default: return 'bash';
    }
  }

  dynamic _getLangMode(String lang) {
    switch (lang) {
      case 'dart': return langDart;
      case 'rust': return langRust;
      case 'python': return langPython;
      case 'javascript': return langJavascript;
      case 'bash': return langBash;
      case 'json': return langJson;
      case 'yaml': return langYaml;
      case 'markdown': return langMarkdown;
      case 'cpp': return langCpp;
      case 'java': return langJava;
      case 'xml': return langXml;
      default: return langBash;
    }
  }
}
