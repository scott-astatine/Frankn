import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:frankn/utils/utils.dart';
import 'package:google_fonts/google_fonts.dart';

class NeoThinkBlock extends StatefulWidget {
  final String content;
  final bool isStreaming;
  const NeoThinkBlock({super.key, required this.content, required this.isStreaming});

  @override
  State<NeoThinkBlock> createState() => _NeoThinkBlockState();
}

class _NeoThinkBlockState extends State<NeoThinkBlock> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: NeoColors.background,
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  const Icon(
                    Icons.psychology_outlined,
                    color: NeoColors.zinc,
                    size: 16,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    "REASONING_TRACE",
                    style: GoogleFonts.jetBrainsMono(
                      color: NeoColors.zinc,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    _isExpanded ? Icons.expand_less : Icons.expand_more,
                    color: NeoColors.zinc,
                    size: 16,
                  ),
                ],
              ),
            ),
          ),
          if (_isExpanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: MarkdownBody(
                data: widget.content.split('\n').map((l) => "> $l").join('\n'),
                styleSheet: MarkdownStyleSheet(
                  p: GoogleFonts.inter(
                    color: NeoColors.zinc,
                    fontSize: 12,
                    height: 1.5,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
