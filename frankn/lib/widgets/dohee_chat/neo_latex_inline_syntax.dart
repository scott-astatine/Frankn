import 'package:markdown/markdown.dart';

final List<Map<String, dynamic>> _delimiterList = [
  {'left': r'$$', 'right': r'$$', 'display': true},
  {'left': r'$', 'right': r'$', 'display': false},
  {'left': r'\pu{', 'right': '}', 'display': false},
  {'left': r'\ce{', 'right': '}', 'display': false},
  {'left': r'\(', 'right': r'\)', 'display': false},
  {'left': '( ', 'right': ' )', 'display': false},
  {'left': r'\[', 'right': r'\]', 'display': true},
  {'left': '[ ', 'right': ' ]', 'display': true},
];

String _escapeRegex(String string) {
  return string.replaceAllMapped(RegExp(r'[-\/\\^$*+?.()|[\]{}]'), (match) {
    return '\\${match.group(0)}';
  });
}

String _generateRegexRules(List<Map<String, dynamic>> delimiters) {
  List<String> inlinePatterns = [];
  for (var delimiter in delimiters) {
    String left = delimiter['left'];
    String right = delimiter['right'];
    String escapedLeft = _escapeRegex(left);
    String escapedRight = _escapeRegex(right);

    // The original flutter_markdown_latex pattern appended a strict lookahead which broke matching
    // inline math that was followed by a parenthesis ')' or dash '-'.
    // We remove the trailing lookahead to make it correctly parse symbols like `($\sigma$)` or `$x$-plane`
    inlinePatterns.add(
        '$escapedLeft((?:\\\\.|[^\\\\\\n])*?(?:\\\\.|[^\\\\\\n]|(?!$escapedRight)))$escapedRight');
  }
  return '(${inlinePatterns.join("|")})';
}

final _neoLatexPattern = _generateRegexRules(_delimiterList);

class NeoLatexInlineSyntax extends InlineSyntax {
  NeoLatexInlineSyntax() : super(_neoLatexPattern);

  @override
  bool onMatch(InlineParser parser, Match match) {
    String raw = match.group(0) ?? '';

    int delimiterLength = 1;
    String mathStyle = 'text';

    for (var delimiter in _delimiterList) {
      if (raw.startsWith(delimiter['left']) &&
          raw.endsWith(delimiter['right'])) {
        mathStyle = delimiter['display'] ? 'display' : 'text';
        delimiterLength = delimiter['left'].length;
        break;
      }
    }

    final equation =
        raw.substring(delimiterLength, raw.length - delimiterLength);

    final element = Element.text('latex', equation);
    element.attributes['MathStyle'] = mathStyle;
    parser.addNode(element);

    return true;
  }
}
