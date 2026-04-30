import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_markdown_latex/flutter_markdown_latex.dart';
import 'package:frankn/screens/dohee_chat_screen.dart';
import 'package:frankn/utils/utils.dart';
import 'package:frankn/widgets/dohee_chat/chat_message.dart';
import 'package:frankn/widgets/dohee_chat/neo_code_element_builder.dart';
import 'package:frankn/widgets/dohee_chat/neo_latex_element_builder.dart';
import 'package:frankn/widgets/dohee_chat/neo_latex_inline_syntax.dart';
import 'package:frankn/widgets/dohee_chat/neo_think_block.dart';
import 'package:frankn/widgets/dohee_chat/scanline_painter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:markdown/markdown.dart' as md;

class MessageBubble extends StatelessWidget {
  final ChatMessage message;
  const MessageBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    if (message.role == ChatRole.system) {
      return _buildSystem(context);
    }
    return message.role == ChatRole.operator
        ? _buildOperator(context)
        : _buildAssistant(context);
  }

  Widget _buildAssistant(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Row(
              children: [
                Text(
                  "[ DHI_RX ]",
                  style: GoogleFonts.jetBrainsMono(
                    color: NeoColors.fuchsia,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  message.timestamp,
                  style: GoogleFonts.jetBrainsMono(
                    color: NeoColors.zinc,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.85,
            ),
            decoration: const BoxDecoration(
              color: NeoColors.darkZinc,
              border: Border(
                left: BorderSide(color: NeoColors.fuchsia, width: 2),
              ),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(4),
                topRight: Radius.circular(16),
                bottomRight: Radius.circular(16),
              ),
            ),
            child: ValueListenableBuilder<String>(
              valueListenable: message.contentNotifier,
              builder: (context, content, _) => ValueListenableBuilder<bool>(
                valueListenable: message.isStreamingNotifier,
                builder: (context, isStreaming, _) =>
                    _buildAssistantContent(content, isStreaming),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAssistantContent(String content, bool isStreaming) {
    String mainContent = content;
    String? thinkContent;

    int thinkStart = content.indexOf('<think>');
    if (thinkStart != -1) {
      int thinkEnd = content.indexOf('</think>', thinkStart);
      if (thinkEnd != -1) {
        thinkContent = content.substring(thinkStart + 7, thinkEnd).trim();
        mainContent =
            "${content.substring(0, thinkStart)}\n\n${content.substring(thinkEnd + 8)}"
                .trim();
      } else {
        thinkContent = content.substring(thinkStart + 7).trim();
        mainContent = content.substring(0, thinkStart).trim();
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (thinkContent != null && thinkContent.isNotEmpty)
          NeoThinkBlock(
            content: thinkContent,
            isStreaming:
                isStreaming &&
                content.contains('<think>') &&
                !content.contains('</think>'),
          ),
        if (mainContent.isNotEmpty ||
            (isStreaming && !content.contains('<think>')))
          MarkdownBody(
            data:
                mainContent +
                (isStreaming &&
                        (!content.contains('<think>') ||
                            content.contains('</think>'))
                    ? " █"
                    : ""),
            selectable: true,
            builders: {
              'code': NeoCodeElementBuilder(),
              'latex': NeoLatexElementBuilder(),
            },
            extensionSet: md.ExtensionSet(
              [
                LatexBlockSyntax(),
                ...md.ExtensionSet.gitHubFlavored.blockSyntaxes,
              ],
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
                color: NeoColors.cyan,
              ),
              h1: GoogleFonts.inter(
                color: NeoColors.cyan,
                fontWeight: FontWeight.bold,
              ),
              h2: GoogleFonts.inter(
                color: NeoColors.cyan,
                fontWeight: FontWeight.bold,
              ),
              listBullet: GoogleFonts.inter(color: NeoColors.fuchsia),
              tableColumnWidth: const IntrinsicColumnWidth(),
            ),
          ),
      ],
    );
  }

  Widget _buildOperator(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  message.timestamp,
                  style: GoogleFonts.jetBrainsMono(
                    color: NeoColors.zinc,
                    fontSize: 10,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  "[ OPR_TX ]",
                  style: GoogleFonts.jetBrainsMono(
                    color: NeoColors.cyan,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Stack(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 14,
                ),
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.8,
                ),
                decoration: const BoxDecoration(
                  color: NeoColors.darkZinc,
                  border: Border(
                    right: BorderSide(color: NeoColors.cyan, width: 2),
                  ),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(4),
                    bottomLeft: Radius.circular(16),
                  ),
                ),
                child: ValueListenableBuilder<String>(
                  valueListenable: message.contentNotifier,
                  builder: (context, content, _) => SelectableText(
                    content,
                    style: GoogleFonts.inter(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 15,
                      height: 1.4,
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(4),
                    bottomLeft: Radius.circular(16),
                  ),
                  child: IgnorePointer(
                    child: CustomPaint(painter: ScanlinePainter()),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSystem(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          const Icon(
            Icons.verified_user_outlined,
            color: NeoColors.cyan,
            size: 20,
          ),
          const SizedBox(height: 12),
          ValueListenableBuilder<String>(
            valueListenable: message.contentNotifier,
            builder: (context, content, _) => Text(
              content.toUpperCase(),
              textAlign: TextAlign.center,
              style: GoogleFonts.jetBrainsMono(
                color: NeoColors.cyan.withValues(alpha: 0.6),
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
