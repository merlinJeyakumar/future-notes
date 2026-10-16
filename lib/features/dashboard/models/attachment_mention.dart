import 'note_model.dart';

class AttachmentMentionQuery {
  const AttachmentMentionQuery(this.start, this.end, this.text);
  final int start;
  final int end;
  final String text;

  /// [paragraph] is only the current paragraph; offsets remain document based.
  static AttachmentMentionQuery? find(
    String paragraph,
    int caret, {
    int offset = 0,
  }) {
    if (caret < 0 || caret > paragraph.length) return null;
    final at = paragraph.lastIndexOf('@', caret == 0 ? 0 : caret - 1);
    if (at < 0 || at >= caret) return null;
    if (at > 0 && !RegExp(r'[\s(\[{]').hasMatch(paragraph[at - 1])) return null;
    final text = paragraph.substring(at + 1, caret);
    if (text.contains(RegExp(r'[@\r\n\uFFFC]'))) return null;
    return AttachmentMentionQuery(offset + at, offset + caret, text);
  }

  List<AttachmentModel> match(Iterable<AttachmentModel> attachments) {
    final query = text.toLowerCase();
    return attachments
        .where((a) => !a.isLoading && a.fileName.toLowerCase().contains(query))
        .toList()
      ..sort((a, b) {
        final ap = a.fileName.toLowerCase().startsWith(query);
        final bp = b.fileName.toLowerCase().startsWith(query);
        return ap == bp
            ? a.fileName.compareTo(b.fileName)
            : ap
            ? -1
            : 1;
      });
  }
}

/// Lexical context only: source remains editable, and parsing never reads payloads.
/// Scan the existing source without copying/serializing a document or allocating a DOM.
bool htmlAllowsAttachmentMention(String source, int caret) {
  if (caret < 0 || caret > source.length) return false;
  var index = 0;
  String? raw;
  var links = 0;
  while (index < caret) {
    // Raw HTML text is not markup: e.g. `if (a < b)` inside a script.
    // Only the matching end tag exits script/style context.
    if (raw != null) {
      final closing = RegExp(
        '</\\s*$raw\\s*>',
        caseSensitive: false,
      ).firstMatch(source.substring(index, caret));
      if (closing == null) return false;
      index += closing.end;
      raw = null;
      continue;
    }
    if (source.startsWith('<!--', index)) {
      final end = source.indexOf('-->', index + 4);
      if (end < 0 || end + 3 > caret) return false;
      index = end + 3;
      continue;
    }
    if (source[index] != '<') {
      index++;
      continue;
    }
    final start = index++;
    String? quote;
    while (index < caret) {
      final c = source[index++];
      if (quote != null) {
        if (c == quote) quote = null;
      } else if (c == '"' || c == "'") {
        quote = c;
      } else if (c == '>') {
        break;
      }
    }
    if (index == caret && source[index - 1] != '>') return false;
    final tag = RegExp(
      r'^<\s*(/?)\s*([a-zA-Z][\w:-]*)',
    ).firstMatch(source.substring(start, index));
    if (tag == null) continue;
    final closing = tag[1] == '/';
    final name = tag[2]!.toLowerCase();
    if (!closing && (name == 'script' || name == 'style')) {
      raw = name;
    } else if (name == 'a') {
      links = closing ? (links > 0 ? links - 1 : 0) : links + 1;
    }
  }
  return raw == null && links == 0;
}
