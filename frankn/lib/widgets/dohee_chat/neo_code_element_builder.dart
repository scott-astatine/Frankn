import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_highlighter/flutter_highlighter.dart';
import 'package:flutter_highlighter/themes/monokai-sublime.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:frankn/screens/dohee_chat_screen.dart';
import 'package:frankn/utils/utils.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:markdown/markdown.dart' as md;

class NeoCodeElementBuilder extends MarkdownElementBuilder {
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

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: NeoColors.background,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: NeoColors.darkZinc,
              border: const Border(bottom: BorderSide(color: Colors.white10)),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(4),
                topRight: Radius.circular(4),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.code_rounded,
                      color: NeoColors.cyan,
                      size: 14,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      language.isEmpty ? "TERMINAL" : language.toUpperCase(),
                      style: GoogleFonts.jetBrainsMono(
                        color: NeoColors.cyan,
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
                    color: NeoColors.zinc,
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
              theme: monokaiSublimeTheme,
              padding: const EdgeInsets.all(16),
              textStyle: GoogleFonts.jetBrainsMono(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
