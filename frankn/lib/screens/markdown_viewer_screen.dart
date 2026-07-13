import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_highlighter/flutter_highlighter.dart';
import 'package:flutter_highlighter/themes/monokai-sublime.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_markdown_latex/flutter_markdown_latex.dart';
import 'package:frankn/screens/code_editor_screen.dart';
import 'package:frankn/services/file_transfer_mixin.dart';
import 'package:frankn/services/isolate_protocol.dart';
import 'package:frankn/services/rtc_thin_client.dart';
import 'package:frankn/utils/dc_msg_util.dart';
import 'package:frankn/utils/utils.dart';
import 'package:frankn/widgets/dohee_chat/neo_latex_element_builder.dart';
import 'package:frankn/widgets/dohee_chat/neo_latex_inline_syntax.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:markdown/markdown.dart' as md;

class MarkdownViewerScreen extends StatefulWidget {
  final RtcThinClient client;
  final String remotePath;
  final String fileName;

  const MarkdownViewerScreen({
    super.key,
    required this.client,
    required this.remotePath,
    required this.fileName,
  });

  @override
  State<MarkdownViewerScreen> createState() => _MarkdownViewerScreenState();
}



class _MarkdownViewerScreenState extends State<MarkdownViewerScreen>
    with FileTransferMixin {
  String? _activeDownloadId;

  StreamSubscription? _transferSub;
  String _markdownContent = "";
  bool _isInitialized = false;
  bool _hasError = false;
  @override
  RtcThinClient get client => widget.client;

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
      client.log("MARKDOWN VIEWER: Cancelled background download due to exit");
    }
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
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
              _hasError = true;
            });
          }
        }
      }
    });

    _loadFile();
  }

  @override
  void refreshDirectory() {}

  Widget _buildBody(BuildContext context) {
    if (isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: AppColors.markdownPrimaryLight),
            const SizedBox(height: 16),
            Text(
              transferMsg.isEmpty ? "FETCHING DOCUMENT..." : transferMsg,
              style: GoogleFonts.jetBrainsMono(
                color: AppColors.markdownPrimaryLight,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    }

    if (_hasError) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              color: AppColors.accentError,
              size: 48,
            ),
            const SizedBox(height: 16),
            Text(
              "FAILED TO LOAD DOCUMENT",
              style: GoogleFonts.jetBrainsMono(
                color: AppColors.accentError,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadFile,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.surface,
                side: const BorderSide(color: AppColors.markdownPrimary, width: 0.5),
              ),
              child: Text(
                "RETRY CONNECTION",
                style: GoogleFonts.jetBrainsMono(
                  color: AppColors.markdownPrimaryLight,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (_markdownContent.isEmpty) {
      return Center(
        child: Text(
          "DOCUMENT EMPTY",
          style: GoogleFonts.jetBrainsMono(
            color: AppColors.textSecondary,
            fontSize: 11,
          ),
        ),
      );
    }

    return Markdown(
      controller: PrimaryScrollController.of(context),
      data: _markdownContent,
      selectable: true,
      builders: {
        'code': _ViewerCodeElementBuilder(),
        'latex': NeoLatexElementBuilder(),
      },
      extensionSet: md.ExtensionSet(
        [LatexBlockSyntax(), ...md.ExtensionSet.gitHubFlavored.blockSyntaxes],
        [
          LatexInlineSyntax(),
          NeoLatexInlineSyntax(),
          ...md.ExtensionSet.gitHubFlavored.inlineSyntaxes,
        ],
      ),
      styleSheet: MarkdownStyleSheet(
        p: GoogleFonts.inter(
          color: Colors.white.withValues(alpha: 0.95),
          fontSize: 15,
          height: 1.6,
        ),
        code: GoogleFonts.jetBrainsMono(
          backgroundColor: Colors.transparent,
          color: AppColors.markdownPrimaryLight,
        ),
        h1: GoogleFonts.inter(
          color: AppColors.markdownPrimaryLight,
          fontWeight: FontWeight.bold,
          fontSize: 22,
        ),
        h2: GoogleFonts.inter(
          color: AppColors.markdownPrimaryLight,
          fontWeight: FontWeight.bold,
          fontSize: 18,
        ),
        h3: GoogleFonts.inter(
          color: AppColors.markdownPrimaryLight,
          fontWeight: FontWeight.bold,
          fontSize: 16,
        ),
        listBullet: GoogleFonts.inter(color: AppColors.markdownAccent),
        horizontalRuleDecoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: AppColors.markdownPrimary.withValues(alpha: 0.25),
              width: 0.5,
            ),
          ),
        ),
        codeblockDecoration: const BoxDecoration(color: Colors.transparent),
        codeblockPadding: EdgeInsets.zero,
        tableHead: GoogleFonts.inter(
          color: AppColors.markdownPrimaryLight,
          fontWeight: FontWeight.bold,
          fontSize: 13,
        ),
        tableBody: GoogleFonts.inter(
          color: Colors.white.withValues(alpha: 0.85),
          fontSize: 13,
        ),
        tableCellsPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 10,
        ),
        tableBorder: TableBorder(
          horizontalInside: BorderSide(
            color: AppColors.markdownPrimary.withValues(alpha: 0.15),
            width: 0.5,
          ),
          verticalInside: BorderSide(
            color: AppColors.markdownPrimary.withValues(alpha: 0.15),
            width: 0.5,
          ),
          top: BorderSide(
            color: AppColors.markdownPrimary.withValues(alpha: 0.3),
            width: 1.0,
          ),
          bottom: BorderSide(
            color: AppColors.markdownPrimary.withValues(alpha: 0.3),
            width: 1.0,
          ),
          left: BorderSide(
            color: AppColors.markdownPrimary.withValues(alpha: 0.3),
            width: 1.0,
          ),
          right: BorderSide(
            color: AppColors.markdownPrimary.withValues(alpha: 0.3),
            width: 1.0,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        tableColumnWidth: const IntrinsicColumnWidth(),
      ),
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
                    Icons.edit,
                    color: AppColors.markdownPrimaryLight,
                    size: 18,
                  ),
                  onPressed: _switchToEditor,
                  style: IconButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(36, 36),
                    backgroundColor: AppColors.background.withValues(alpha: 0.5),
                    shape: const CircleBorder(),
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _loadFile() async {
    if (mounted) {
      setState(() {
        isLoading = true;
        _hasError = false;
      });
    }
    _activeDownloadId = await downloadFile(
      widget.remotePath,
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
          _markdownContent = content;
          _isInitialized = true;
          isLoading = false;
        });
      }
    } catch (e) {
      client.log("MARKDOWN VIEWER ERROR: Failed to read file: $e");
      if (mounted) {
        setState(() {
          _hasError = true;
          isLoading = false;
        });
      }
    }
  }

  void _switchToEditor() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => CodeEditorScreen(
          client: widget.client,
          remotePath: widget.remotePath,
          fileName: widget.fileName,
        ),
      ),
    );
  }
}

class _ViewerCodeElementBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    var language = '';
    if (element.attributes['class'] != null) {
      String lgPattern = 'language-';
      if (element.attributes['class']!.startsWith(lgPattern)) {
        language = element.attributes['class']!.substring(lgPattern.length);
      }
    }

    if (language.isEmpty && !element.textContent.contains('\n')) {
      return null;
    }

    final customTheme = Map<String, TextStyle>.from(monokaiSublimeTheme);
    customTheme['root'] = (customTheme['root'] ?? const TextStyle()).copyWith(
      backgroundColor: Colors.transparent,
    );

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: Colors.transparent, // Fade in with the background
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: AppColors.markdownPrimary.withValues(alpha: 0.3),
          width: 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: AppColors.markdownPrimary.withValues(alpha: 0.15),
                  width: 0.5,
                ),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.code_rounded,
                      color: AppColors.markdownPrimaryLight,
                      size: 14,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      language.isEmpty ? "TERMINAL" : language.toUpperCase(),
                      style: GoogleFonts.jetBrainsMono(
                        color: AppColors.markdownPrimaryLight,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
                GestureDetector(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: element.textContent));
                  },
                  child: const Icon(
                    Icons.copy_all_rounded,
                    color: AppColors.textSecondary,
                    size: 16,
                  ),
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: HighlightView(
              element.textContent,
              language: language.isEmpty ? 'bash' : language,
              theme: customTheme,
              padding: const EdgeInsets.all(16),
              textStyle: GoogleFonts.jetBrainsMono(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
