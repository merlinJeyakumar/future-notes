import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as html_dom;

/// Service for converting between HTML and AppFlowy EditorState.
class AppFlowyHtmlService {
  /// Convert HTML string to EditorState.
  EditorState htmlToEditorState(String html) {
    if (html.trim().isEmpty) {
      return EditorState.blank();
    }

    try {
      final document = html_parser.parse(html);
      final body = document.body;
      if (body == null) return EditorState.blank();

      final nodes = <Node>[];

      for (final child in body.nodes) {
        nodes.addAll(_parseNode(child));
      }

      if (nodes.isEmpty) return EditorState.blank();

      return EditorState(
        document: Document(
          root: Node(type: 'page', children: nodes),
        ),
      );
    } catch (e) {
      return EditorState.blank();
    }
  }

  /// Convert EditorState to HTML string.
  String editorStateToHtml(EditorState state) {
    final buffer = StringBuffer();
    final doc = state.document;

    // Iterate over children of root (assuming root is 'page')
    for (final node in doc.root.children) {
      buffer.write(_nodeToHtml(node));
    }

    return buffer.toString();
  }

  List<Node> _parseNode(html_dom.Node node) {
    if (node is html_dom.Element) {
      final tag = node.localName?.toLowerCase();

      switch (tag) {
        case 'p':
          return [paragraphNode(delta: _parseInlineContent(node))];
        case 'h1':
          return [headingNode(delta: _parseInlineContent(node), level: 1)];
        case 'h2':
          return [headingNode(delta: _parseInlineContent(node), level: 2)];
        case 'h3':
          return [headingNode(delta: _parseInlineContent(node), level: 3)];
        case 'h4':
          return [headingNode(delta: _parseInlineContent(node), level: 4)];
        case 'h5':
          return [headingNode(delta: _parseInlineContent(node), level: 5)];
        case 'h6':
          return [headingNode(delta: _parseInlineContent(node), level: 6)];
        case 'blockquote':
          return [quoteNode(delta: _parseInlineContent(node))];
        case 'ul':
        case 'ol':
          final listNodes = <Node>[];
          final isOrdered = tag == 'ol';
          for (final child in node.children) {
            if (child.localName == 'li') {
              final delta = _parseInlineContent(child);
              if (isOrdered) {
                listNodes.add(numberedListNode(delta: delta));
              } else {
                listNodes.add(bulletedListNode(delta: delta));
              }
            }
          }
          return listNodes;
        case 'div':
          final divNodes = <Node>[];
          for (final child in node.nodes) {
            divNodes.addAll(_parseNode(child));
          }
          return divNodes;
        case 'img':
          final src = node.attributes['src'] ?? '';
          return [imageNode(url: src)];
        case 'input':
          if (node.attributes['type'] == 'checkbox') {
            final checked = node.attributes.containsKey('checked');
            return [todoListNode(delta: Delta(), checked: checked)];
          }
          return [];
        default:
          if (node.text.trim().isNotEmpty) {
            return [paragraphNode(delta: _parseInlineContent(node))];
          }
          return [];
      }
    } else if (node is html_dom.Text) {
      final text = node.text.trim();
      if (text.isNotEmpty) {
        return [paragraphNode(delta: Delta()..insert(text))];
      }
    }
    return [];
  }

  Delta _parseInlineContent(html_dom.Element element) {
    final delta = Delta();
    for (final child in element.nodes) {
      _recurseInline(child, {}, delta);
    }
    return delta;
  }

  void _recurseInline(
    html_dom.Node node,
    Map<String, dynamic> attributes,
    Delta delta,
  ) {
    if (node is html_dom.Text) {
      if (node.text.isNotEmpty) {
        delta.insert(
          node.text,
          attributes: attributes.isEmpty ? null : attributes,
        );
      }
    } else if (node is html_dom.Element) {
      final newAttrs = Map<String, dynamic>.from(attributes);
      final tag = node.localName?.toLowerCase();

      if (tag == 'b' || tag == 'strong') newAttrs['bold'] = true;
      if (tag == 'i' || tag == 'em') newAttrs['italic'] = true;
      if (tag == 'u' || tag == 'ins') newAttrs['underline'] = true;
      if (tag == 's' || tag == 'del' || tag == 'strike')
        newAttrs['strikethrough'] = true;
      if (tag == 'code') newAttrs['code'] = true;
      if (tag == 'a') {
        final href = node.attributes['href'];
        if (href != null) newAttrs['href'] = href;
      }

      // Basic color parsing from style
      if (tag == 'span' || node.attributes.containsKey('style')) {
        final style = node.attributes['style'] ?? '';
        // Simple regex for hex color
        final colorMatch = RegExp(
          r'color:\s*(#[0-9a-fA-F]{3,6})',
        ).firstMatch(style);
        if (colorMatch != null) {
          newAttrs['color'] = colorMatch.group(1);
        }
      }

      for (final child in node.nodes) {
        _recurseInline(child, newAttrs, delta);
      }
    }
  }

  String _nodeToHtml(Node node) {
    final type = node.type;
    final delta = node.delta;

    switch (type) {
      case 'paragraph':
        return '<p>${_deltaToHtml(delta)}</p>\n';
      case 'heading':
        final level = node.attributes['level'] ?? 1;
        return '<h$level>${_deltaToHtml(delta)}</h$level>\n';
      case 'bulleted_list':
        return '<ul><li>${_deltaToHtml(delta)}</li></ul>\n';
      case 'numbered_list':
        return '<ol><li>${_deltaToHtml(delta)}</li></ol>\n';
      case 'todo_list':
        final checked = node.attributes['checked'] == true;
        final checkedStr = checked ? ' checked' : '';
        return '<div><input type="checkbox"$checkedStr> ${_deltaToHtml(delta)}</div>\n';
      case 'quote':
        return '<blockquote>${_deltaToHtml(delta)}</blockquote>\n';
      case 'image':
        final src = node.attributes['url'] ?? '';
        return '<img src="$src">\n';
      default:
        return '<p>${_deltaToHtml(delta)}</p>\n';
    }
  }

  String _deltaToHtml(Delta? delta) {
    if (delta == null) return '';
    final buffer = StringBuffer();
    // Use toList() to iterate
    for (final op in delta.toList()) {
      if ((op as dynamic).isInsert == true) {
        final text = (op as dynamic).data;
        if (text is String) {
          final attrs = (op as dynamic).attributes as Map<String, dynamic>?;
          String span = text;
          span = span
              .replaceAll('&', '&amp;')
              .replaceAll('<', '&lt;')
              .replaceAll('>', '&gt;');

          if (attrs != null) {
            if (attrs['color'] != null) {
              span = '<span style="color: ${attrs['color']} ">$span</span>';
            }
            if (attrs['bold'] == true) span = '<b>$span</b>';
            if (attrs['italic'] == true) span = '<i>$span</i>';
            if (attrs['underline'] == true) span = '<u>$span</u>';
            if (attrs['strikethrough'] == true) span = '<s>$span</s>';
            if (attrs['code'] == true) span = '<code>$span</code>';
            if (attrs['href'] != null) {
              span = '<a href="${attrs['href']}">$span</a>';
            }
          }
          buffer.write(span);
        }
      }
    }
    return buffer.toString();
  }
}
