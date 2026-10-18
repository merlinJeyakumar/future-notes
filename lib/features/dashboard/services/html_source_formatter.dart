/// Indent HTML structure and explicit line breaks without rewriting tags,
/// attributes, entities, inline word boundaries or whitespace-sensitive content.
/// Incomplete/ambiguous markup is rejected, leaving the editor's source intact.
String formatHtmlSource(String source, {bool expandTextBlocks = false}) {
  if (source.length > 32 * 1024 * 1024) {
    throw const FormatException('HTML is too large to format.');
  }
  final root = _HtmlPart(0, '#root', 0)..end = source.length;
  final stack = [root];
  var position = 0;
  while (position < source.length) {
    final start = source.indexOf('<', position);
    if (start < 0) {
      stack.last.children.add(_HtmlPart.text(position, source.length));
      break;
    }
    if (start > position) {
      stack.last.children.add(_HtmlPart.text(position, start));
    }
    if (source.startsWith('<!--', start)) {
      final close = source.indexOf('-->', start + 4);
      if (close < 0) throw const FormatException('Incomplete HTML comment.');
      stack.last.children.add(
        _HtmlPart(start, '!comment', close + 3)..end = close + 3,
      );
      position = close + 3;
      continue;
    }
    final end = _tagEnd(source, start);
    final tag = source.substring(start, end);
    final name = RegExp(r'^<\s*(/?)\s*([A-Za-z][\w:-]*)').firstMatch(tag);
    if (name == null) {
      if (!tag.startsWith('<!') && !tag.startsWith('<?')) {
        throw const FormatException('Incomplete HTML tag.');
      }
      stack.last.children.add(_HtmlPart(start, '!declaration', end)..end = end);
    } else {
      final label = name[2]!.toLowerCase();
      if (name[1] == '/') {
        if (stack.length == 1 || stack.last.name != label) {
          throw const FormatException('HTML tags are not balanced.');
        }
        stack.removeLast()
          ..closingStart = start
          ..end = end;
      } else {
        final part = _HtmlPart(start, label, end)..end = end;
        stack.last.children.add(part);
        if (!_voidTags.contains(label) && !tag.trimRight().endsWith('/>')) {
          if (_rawTags.contains(label)) {
            final closes = RegExp(
              '</${RegExp.escape(label)}\\s*>',
              caseSensitive: false,
            ).allMatches(source, end).iterator;
            if (!closes.moveNext()) {
              throw const FormatException('Incomplete raw HTML element.');
            }
            part.end = closes.current.end;
            position = part.end;
            continue;
          }
          if (stack.length >= 256) {
            throw const FormatException('HTML nesting is too deep.');
          }
          stack.add(part);
        }
      }
    }
    position = end;
  }
  if (stack.length != 1) {
    throw const FormatException('Incomplete HTML element.');
  }
  return _renderHtml(root, source, 0, expandTextBlocks);
}

/// Mobile code view expands text blocks; desktop keeps its established output.
String formatExpandedHtmlSource(String source) =>
    formatHtmlSource(source, expandTextBlocks: true);

int _tagEnd(String source, int start) {
  int? quote;
  for (var i = start + 1; i < source.length; i++) {
    final code = source.codeUnitAt(i);
    if (quote != null) {
      if (code == quote) quote = null;
    } else if (code == 34 || code == 39) {
      quote = code;
    } else if (code == 62) {
      return i + 1;
    }
  }
  throw const FormatException('Incomplete HTML tag.');
}

String _renderHtml(_HtmlPart part, String source, int depth, bool expandText) {
  final isRoot = part.name == '#root';
  final indent = '  ' * depth;
  final children = part.children
      .where(
        (child) =>
            child.name != null ||
            !RegExp(
              r'^[ \t\r\n\f]*$',
            ).hasMatch(source.substring(child.start, child.end)),
      )
      .toList();
  final raw = source.substring(part.start, part.end);
  final canIndent =
      children.isNotEmpty &&
      children.every(
        (child) =>
            child.name != null &&
            (_blockTags.contains(child.name) || child.name!.startsWith('!')),
      );
  final sensitive =
      _rawTags.contains(part.name) ||
      (!isRoot &&
          RegExp(
            r'white-space\s*:\s*(?:pre|break-spaces)',
            caseSensitive: false,
          ).hasMatch(source.substring(part.start, part.openingEnd)));
  if (sensitive) return isRoot ? raw : '$indent$raw';
  if (!canIndent) {
    // A rich-text paragraph is usually mixed inline content, not a block-only
    // tree. Keep adjacent inline runs together (no inserted word spaces), but
    // structure its container and split after explicit HTML line breaks.
    if (!isRoot &&
        _blockTags.contains(part.name) &&
        (expandText && children.isNotEmpty ||
            part.children.any((child) => child.name != null))) {
      return _renderMixedBlock(part, source, depth, expandText);
    }
    return isRoot ? raw : '$indent$raw';
  }
  if (isRoot) {
    return source.substring(0, children.first.start) +
        children
            .map((child) => _renderHtml(child, source, 0, expandText))
            .join('\n') +
        source.substring(children.last.end);
  }
  return '$indent${source.substring(part.start, part.openingEnd)}\n'
      '${children.map((child) => _renderHtml(child, source, depth + 1, expandText)).join('\n')}\n'
      '$indent${source.substring(part.closingStart, part.end)}';
}

String _renderMixedBlock(
  _HtmlPart part,
  String source,
  int depth,
  bool expandText,
) {
  final content = source.substring(part.openingEnd, part.closingStart);
  final inline = _renderInline(part, source, depth + 1);
  // Literal leading/trailing text spaces remain next to the container tags.
  // Separating them onto their own source line would let HTML converters trim
  // them. Whitespace already containing a newline is formatting whitespace.
  final leadingTextSpace =
      content.isNotEmpty && RegExp(r'^[^\S\n]+[^\n]').hasMatch(content);
  final trailingTextSpace =
      content.isNotEmpty && RegExp(r'[^\n][^\S\n]+$').hasMatch(content);
  if (!inline.contains('\n') &&
      (leadingTextSpace || (!expandText && part.children.first.name == null))) {
    return '${'  ' * depth}${source.substring(part.start, part.end)}';
  }
  var body = inline;
  if (!leadingTextSpace) body = body.replaceFirst(RegExp(r'^[ \t\r\n\f]+'), '');
  if (!trailingTextSpace) {
    body = body.replaceFirst(RegExp(r'[ \t\r\n\f]+$'), '');
  }
  final prefix = '  ' * depth;
  return '$prefix${source.substring(part.start, part.openingEnd)}'
      '${leadingTextSpace ? '' : '\n${'  ' * (depth + 1)}'}'
      '$body'
      '${trailingTextSpace ? '' : '\n$prefix'}'
      '${source.substring(part.closingStart, part.end)}';
}

String _renderInline(_HtmlPart part, String source, int depth) {
  final output = StringBuffer();
  var afterBreak = false;
  for (final child in part.children) {
    var raw = source.substring(child.start, child.end);
    if (afterBreak) {
      if (child.name == null) {
        // Only remove indentation belonging to an existing source newline.
        // Literal same-line spaces after <br> remain part of the text run.
        raw = raw.replaceFirst(RegExp(r'^(?:\r?\n[ \t]*)+'), '');
        if (raw.isEmpty) continue;
      }
      if (child.name != null || !RegExp(r'^[^\S\n]').hasMatch(raw)) {
        output.write('\n${'  ' * depth}');
      }
      afterBreak = false;
    }
    final sensitive =
        _rawTags.contains(child.name) ||
        RegExp(
          r'white-space\s*:\s*(?:pre|break-spaces)',
          caseSensitive: false,
        ).hasMatch(source.substring(child.start, child.openingEnd));
    if (child.children.isNotEmpty && !sensitive) {
      output.write(source.substring(child.start, child.openingEnd));
      output.write(_renderInline(child, source, depth));
      output.write(source.substring(child.closingStart, child.end));
    } else {
      output.write(raw);
    }
    afterBreak = child.name == 'br';
  }
  return output.toString();
}

class _HtmlPart {
  _HtmlPart(this.start, this.name, this.openingEnd);
  _HtmlPart.text(this.start, this.end) : name = null, openingEnd = start;
  final int start;
  final String? name;
  final int openingEnd;
  int end = 0;
  int closingStart = 0;
  final children = <_HtmlPart>[];
}

const _rawTags = {'pre', 'code', 'textarea', 'script', 'style'};
const _voidTags = {
  'area',
  'base',
  'br',
  'col',
  'embed',
  'hr',
  'img',
  'input',
  'link',
  'meta',
  'param',
  'source',
  'track',
  'wbr',
};
const _blockTags = {
  'html',
  'head',
  'body',
  'title',
  'meta',
  'link',
  'style',
  'script',
  'main',
  'section',
  'article',
  'aside',
  'header',
  'footer',
  'nav',
  'div',
  'p',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'ul',
  'ol',
  'li',
  'table',
  'thead',
  'tbody',
  'tfoot',
  'tr',
  'th',
  'td',
  'caption',
  'colgroup',
  'col',
  'blockquote',
  'pre',
  'hr',
  'form',
  'fieldset',
  'legend',
  'figure',
  'figcaption',
  'dl',
  'dt',
  'dd',
};
