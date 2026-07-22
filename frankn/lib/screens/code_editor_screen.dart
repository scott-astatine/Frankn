import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:frankn/screens/markdown_viewer_screen.dart';
import 'package:frankn/services/file_transfer_mixin.dart';
import 'package:frankn/services/isolate_protocol.dart';
import 'package:frankn/services/rtc_thin_client.dart';
import 'package:frankn/utils/dc_msg_util.dart';
import 'package:frankn/utils/utils.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/bash.dart';
import 'package:re_highlight/languages/cpp.dart';
import 'package:re_highlight/languages/dart.dart';
import 'package:re_highlight/languages/java.dart';
import 'package:re_highlight/languages/javascript.dart';
import 'package:re_highlight/languages/json.dart';
import 'package:re_highlight/languages/markdown.dart';
import 'package:re_highlight/languages/python.dart';
import 'package:re_highlight/languages/rust.dart';
import 'package:re_highlight/languages/xml.dart';
import 'package:re_highlight/languages/yaml.dart';
import 'package:re_highlight/styles/monokai-sublime.dart';
import 'package:share_plus/share_plus.dart';

class CodeEditorScreen extends StatefulWidget {
  final RtcThinClient? client;
  final String? remotePath;
  final String fileName;
  final String? localFilePath;

  const CodeEditorScreen({
    super.key,
    this.client,
    this.remotePath,
    required this.fileName,
    this.localFilePath,
  });

  @override
  State<CodeEditorScreen> createState() => _CodeEditorScreenState();
}

class _CodeEditorScreenState extends State<CodeEditorScreen>
    with FileTransferMixin {
  late CodeLineEditingController _controller;

  File? _localFile;
  bool _isInitialized = false;
  bool _isSaving = false;
  String? _activeDownloadId;
  StreamSubscription? _transferSub;

  @override
  RtcThinClient get client => widget.client ?? RtcThinClient();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: NestedScrollView(
        headerSliverBuilder: (BuildContext context, bool innerBoxIsScrolled) {
          return <Widget>[
            SliverAppBar(
              floating: true,
              snap: true,
              pinned: false,
              primary: false,
              backgroundColor: Colors.transparent,
              elevation: 0,
              automaticallyImplyLeading: false,
              titleSpacing: 0,
              toolbarHeight: 64,
              title: _buildHeader(innerBoxIsScrolled),
            ),
          ];
        },
        body: Builder(builder: (context) => _buildBody(context)),
      ),
    );
  }

  @override
  void dispose() {
    _transferSub?.cancel();
    if (!_isInitialized && _activeDownloadId != null) {
      client.sendIntent(IsolateAction.cancelTransfer, {
        'id': _activeDownloadId,
      });
      client.log("CODE EDITOR: Cancelled background download due to exit");
    }
    _controller.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _controller = CodeLineEditingController();
    if (widget.localFilePath != null) {
      _readLocalFile(widget.localFilePath!);
    } else {
      setupTransferListener();

      _transferSub = client.transferProgressStream.listen((msg) {
        if (msg is TransferProgressComplete) {
          if (msg.id == _activeDownloadId || msg.fileName == widget.fileName) {
            final String? path = msg.finalPath;
            if (path != null) {
              _readLocalFile(path);
            }
          }
        } else if (msg is TransferProgressFailed) {
          if (msg.id == _activeDownloadId) {
            if (mounted) {
              setState(() {
                isLoading = false;
              });
            }
          }
        }
      });

      _loadFile();
    }
  }

  @override
  void refreshDirectory() {}

  Widget _buildBody(BuildContext context) {
    if (!_isInitialized) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: AppColors.accentPrimary),
            const SizedBox(height: 16),
            Text(
              transferMsg.isEmpty ? "LOADING FILE..." : transferMsg,
              style: const TextStyle(
                color: AppColors.accentPrimary,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    }

    final String lang = _detectLanguage();

    return CodeEditor(
      controller: _controller,
      scrollController: CodeScrollController(
        verticalScroller: PrimaryScrollController.of(context),
      ),
      style: CodeEditorStyle(
        fontSize: 13,
        fontFamily: 'JetBrainsMonoNerdFont',
        codeTheme: CodeHighlightTheme(
          languages: {lang: CodeHighlightThemeMode(mode: _getLangMode(lang))},
          theme: monokaiSublimeTheme,
        ),
      ),
      indicatorBuilder:
          (context, editingController, chunkController, notifier) {
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

  Widget _buildHeader(bool innerBoxIsScrolled) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
        child: Container(
          height: 64,
          decoration: BoxDecoration(
            color: innerBoxIsScrolled
                ? AppColors.surface.withValues(alpha: 0.6)
                : AppColors.surface.withValues(alpha: 0.9),
            border: Border(
              bottom: BorderSide(
                color: innerBoxIsScrolled
                    ? Colors.transparent
                    : AppColors.markdownPrimary.withValues(alpha: 0.3),
                width: 0.5,
              ),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Padding(
            padding: const EdgeInsets.only(top: 18),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(
                    Icons.chevron_left,
                    color: AppColors.markdownPrimaryLight,
                    size: 24,
                  ),
                  onPressed: () => Navigator.pop(context),
                ),
                Expanded(
                  child: Text(
                    widget.fileName,
                    style: GoogleFonts.jetBrainsMono(
                      color: AppColors.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(
                    Icons.share,
                    color: AppColors.markdownPrimaryLight,
                    size: 18,
                  ),
                  onPressed: () {
                    if (_localFile != null) {
                      SharePlus.instance.share(
                        ShareParams(
                          files: [XFile(_localFile!.path)],
                          text: widget.fileName,
                        ),
                      );
                    }
                  },
                  style: IconButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(36, 36),
                    backgroundColor: AppColors.background.withValues(
                      alpha: 0.5,
                    ),
                    shape: const CircleBorder(),
                  ),
                ),
                if (widget.fileName.endsWith('.md') ||
                    widget.fileName.endsWith('.markdown')) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(
                      Icons.visibility,
                      color: AppColors.markdownPrimaryLight,
                      size: 18,
                    ),
                    onPressed: () {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (_) => MarkdownViewerScreen(
                            client: widget.client,
                            remotePath: widget.remotePath,
                            fileName: widget.fileName,
                            localFilePath: widget.localFilePath,
                          ),
                        ),
                      );
                    },
                    style: IconButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(36, 36),
                      backgroundColor: AppColors.background.withValues(
                        alpha: 0.5,
                      ),
                      shape: const CircleBorder(),
                    ),
                  ),
                ],
                const SizedBox(width: 8),
                if (_isSaving)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.markdownPrimaryLight,
                    ),
                  )
                else
                  IconButton(
                    icon: const Icon(
                      Icons.save,
                      color: AppColors.markdownPrimaryLight,
                      size: 18,
                    ),
                    onPressed: _handleSave,
                    style: IconButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(36, 36),
                      backgroundColor: AppColors.background.withValues(
                        alpha: 0.5,
                      ),
                      shape: const CircleBorder(),
                    ),
                  ),
                if (widget.localFilePath != null) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(
                      Icons.cloud_upload_outlined,
                      color: AppColors.accentPrimary,
                      size: 18,
                    ),
                    tooltip: "Upload to Remote Host",
                    onPressed: () async {
                      if (_localFile != null) {
                        await _localFile!.writeAsString(_controller.text);
                      }
                      uploadSpecificLocalFile(widget.localFilePath!);
                    },
                    style: IconButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(36, 36),
                      backgroundColor: AppColors.background.withValues(
                        alpha: 0.5,
                      ),
                      shape: const CircleBorder(),
                    ),
                  ),
                ],
                const SizedBox(width: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _detectLanguage() {
    final ext = widget.fileName.split('.').last.toLowerCase();
    switch (ext) {
      case 'dart':
        return 'dart';
      case 'rs':
        return 'rust';
      case 'py':
        return 'python';
      case 'js':
        return 'javascript';
      case 'sh':
        return 'bash';
      case 'json':
        return 'json';
      case 'yaml':
      case 'yml':
        return 'yaml';
      case 'md':
        return 'markdown';
      case 'cpp':
      case 'hpp':
      case 'h':
      case 'c':
        return 'cpp';
      case 'java':
        return 'java';
      case 'xml':
      case 'html':
        return 'xml';
      default:
        return 'bash';
    }
  }

  dynamic _getLangMode(String lang) {
    switch (lang) {
      case 'dart':
        return langDart;
      case 'rust':
        return langRust;
      case 'python':
        return langPython;
      case 'javascript':
        return langJavascript;
      case 'bash':
        return langBash;
      case 'json':
        return langJson;
      case 'yaml':
        return langYaml;
      case 'markdown':
        return langMarkdown;
      case 'cpp':
        return langCpp;
      case 'java':
        return langJava;
      case 'xml':
        return langXml;
      default:
        return langBash;
    }
  }

  Future<void> _handleSave() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    try {
      if (widget.localFilePath != null) {
        final file = File(widget.localFilePath!);
        await file.writeAsString(_controller.text);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                "FILE SAVED LOCALLY",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              backgroundColor: AppColors.accentSuccess,
            ),
          );
        }
      } else if (widget.remotePath != null) {
        await saveEditorContent(widget.remotePath!, _controller.text);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                "FILE SAVED TO HOST",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              backgroundColor: AppColors.accentSuccess,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("SAVE FAILED: $e"),
            backgroundColor: AppColors.accentError,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _loadFile() async {
    if (widget.remotePath == null) return;
    _activeDownloadId = await downloadFile(
      widget.remotePath!,
      showNotification: false,
      isTemporary: true,
    );
  }

  Future<void> _readLocalFile(String path) async {
    try {
      final file = File(path);
      final content = await file.readAsString();
      if (mounted) {
        setState(() {
          _localFile = file;
          _controller.text = content;
          _isInitialized = true;
        });
      }
    } catch (e) {
      client.log("EDITOR ERROR: Failed to read file: $e");
    }
  }
}
