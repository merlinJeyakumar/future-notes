import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/foundation.dart';
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
      debugPrint('--- [DEBUG HTML IMPORT] ---');
      debugPrint(html);
      debugPrint('--- [DEBUG HTML IMPORT END] ---');

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
      debugPrint('Error parsing HTML: $e');
      return EditorState.blank();
    }
  }

  /// Convert EditorState to HTML string using official AppFlowy API.
  /// This provides organic, semantic HTML output with proper formatting.
  String editorStateToHtml(EditorState state) {
    // Use official AppFlowy documentToHTML function for organic HTML export
    final html = documentToHTML(state.document);
    debugPrint('--- [DEBUG HTML START] ---');
    debugPrint(html);
    debugPrint('--- [DEBUG HTML END] ---');
    return html;
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
          // Special handling: AppFlowy exports todo as <div><input type="checkbox"/>label text</div>
          // Check if this div contains a checkbox
          html_dom.Element? checkboxElement;
          for (final child in node.children) {
            if (child.localName == 'input' &&
                child.attributes['type'] == 'checkbox') {
              checkboxElement = child;
              break;
            }
          }

          if (checkboxElement != null) {
            // This is a todo list item - extract checkbox state and remaining text
            final checked = checkboxElement.attributes.containsKey('checked');
            // Parse remaining nodes (excluding the checkbox) for the label
            final delta = Delta();
            for (final child in node.nodes) {
              if (child == checkboxElement)
                continue; // Skip the checkbox element
              if (child is html_dom.Text) {
                final text = child.text;
                if (text.isNotEmpty) {
                  delta.insert(text);
                }
              } else if (child is html_dom.Element) {
                // Handle formatted inline elements within the label
                _recurseInline(child, {}, delta);
              }
            }
            return [todoListNode(delta: delta, checked: checked)];
          }

          // Regular div - flatten children
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
          // Attempt to parse children even if tag is unknown (like span at block level?)
          // But usually top-level unknown tags with text are paragraphs.
          // If it has children elements, we might want to recurs.
          // For safety matching previous logic: return empty if no text.
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
      if (tag == 's' || tag == 'del' || tag == 'strike') {
        newAttrs['strikethrough'] = true;
      }
      if (tag == 'code') newAttrs['code'] = true;
      if (tag == 'a') {
        final href = node.attributes['href'];
        if (href != null) newAttrs['href'] = href;
      }

      // Parse CSS styles from style attribute
      if (tag == 'span' || node.attributes.containsKey('style')) {
        final style = node.attributes['style'] ?? '';

        // Parse font-weight: bold
        if (RegExp(r'font-weight:\s*bold').hasMatch(style) ||
            RegExp(r'font-weight:\s*[5-9]\d{2}').hasMatch(style)) {
          newAttrs[AppFlowyRichTextKeys.bold] = true;
        }

        // Parse text-decoration (underline and/or line-through)
        final textDecorationMatch = RegExp(
          r'text-decoration:\s*([^;]+)',
        ).firstMatch(style);
        if (textDecorationMatch != null) {
          final decorations = textDecorationMatch.group(1)!.toLowerCase();
          if (decorations.contains('underline')) {
            newAttrs[AppFlowyRichTextKeys.underline] = true;
          }
          if (decorations.contains('line-through')) {
            newAttrs[AppFlowyRichTextKeys.strikethrough] = true;
          }
        }

        // Parse font-style: italic
        if (RegExp(r'font-style:\s*italic').hasMatch(style)) {
          newAttrs[AppFlowyRichTextKeys.italic] = true;
        }

        // Parse color
        String? hexColor;

        // Try Hex
        final hexMatch = RegExp(
          r'color:\s*(#[0-9a-fA-F]{3,8})',
        ).firstMatch(style);
        if (hexMatch != null) {
          hexColor = hexMatch.group(1);
        } else {
          // Try RGB/RGBA
          // Matches: color: rgb(255, 0, 0) or color: rgba(255, 0, 0, 1)
          final rgbMatch = RegExp(
            r'color:\s*rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)(?:,\s*([\d\.]+))?\s*\)',
          ).firstMatch(style);
          if (rgbMatch != null) {
            final r = int.parse(rgbMatch.group(1)!);
            final g = int.parse(rgbMatch.group(2)!);
            final b = int.parse(rgbMatch.group(3)!);
            // Ignore alpha for now as editor seems to use #RRGGBB
            hexColor =
                '#${r.toRadixString(16).padLeft(2, '0')}${g.toRadixString(16).padLeft(2, '0')}${b.toRadixString(16).padLeft(2, '0')}';
          }
        }

        if (hexColor != null) {
          // Use the correct key from the library
          newAttrs[AppFlowyRichTextKeys.textColor] = hexColor;
        }
      }

      for (final child in node.nodes) {
        _recurseInline(child, newAttrs, delta);
      }
    }
  }
}
