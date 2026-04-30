import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:frankn/utils/utils.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:markdown/markdown.dart' as md;

class NeoLatexElementBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final String text = element.textContent;
    if (text.isEmpty) return const SizedBox();

    bool isDisplay = element.attributes['MathStyle'] == 'display';

    if (isDisplay) {
      return Container(
        width: double.infinity,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Math.tex(
            text,
            mathStyle: MathStyle.display,
            textStyle: GoogleFonts.inter(color: Colors.white, fontSize: 18),
            onErrorFallback: (err) => Text(
              text,
              style: const TextStyle(
                color: NeoColors.fuchsia,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ),
      );
    } else {
      // By returning a RichText containing a WidgetSpan, flutter_markdown's
      // internal parser (_getInlineSpanFromText) will extract the InlineSpan 
      // and seamlessly merge it with the surrounding text spans, preventing 
      // the layout from breaking into new lines via Wrap!
      return RichText(
        text: TextSpan(
          children: [
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Math.tex(
                text,
                mathStyle: MathStyle.text,
                textStyle: GoogleFonts.inter(color: Colors.white, fontSize: 15),
                onErrorFallback: (err) => Text(
                  text,
                  style: const TextStyle(
                    color: NeoColors.fuchsia,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }
  }
}
