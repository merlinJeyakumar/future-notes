import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as html_dom;

/// Service for converting between HTML and Super Editor's MutableDocument.
///
/// This service handles bidirectional conversion:
/// - HTML → MutableDocument (for loading notes)
/// - MutableDocument → HTML (for saving notes)
class SuperEditorHtmlService {
  /// Convert HTML string to MutableDocument.
  MutableDocument htmlToDocument(String html) {
    if (html.trim().isEmpty) {
      return _createEmptyDocument();
    }

    try {
      final document = html_parser.parse(html);
      final body = document.body;
      if (body == null) {
        return _createDocumentFromPlainText(html);
      }

      final nodes = <DocumentNode>[];
      _parseHtmlNodes(body.nodes, nodes);

      if (nodes.isEmpty) {
        return _createEmptyDocument();
      }

      return MutableDocument(nodes: nodes);
    } catch (e) {
      debugPrint('Error parsing HTML: $e');
      return _createDocumentFromPlainText(html);
    }
  }

  /// Convert MutableDocument to HTML string.
  String documentToHtml(Document doc) {
    final buffer = StringBuffer();

    for (final node in doc) {
      if (node is ParagraphNode) {
        buffer.write(_paragraphToHtml(node));
      } else if (node is ListItemNode) {
        buffer.write(_listItemToHtml(node));
      } else if (node is TaskNode) {
        buffer.write(_taskToHtml(node));
      } else if (node is HorizontalRuleNode) {
        buffer.write('<hr>');
      } else if (node is ImageNode) {
        buffer.write('<img src="${node.imageUrl}" alt="">');
      } else {
        // Fallback for unknown node types
        if (node is TextNode) {
          buffer.write('<p>${_attributedTextToHtml(node.text)}</p>');
        }
      }
    }

    return buffer.toString();
  }

  void _parseHtmlNodes(
    List<html_dom.Node> htmlNodes,
    List<DocumentNode> docNodes,
  ) {
    bool inOrderedList = false;
    bool inUnorderedList = false;

    for (final htmlNode in htmlNodes) {
      if (htmlNode is html_dom.Text) {
        final text = htmlNode.text.trim();
        if (text.isNotEmpty) {
          docNodes.add(_createParagraphNode(text));
        }
      } else if (htmlNode is html_dom.Element) {
        switch (htmlNode.localName?.toLowerCase()) {
          case 'p':
            inOrderedList = false;
            inUnorderedList = false;
            docNodes.add(_parseParagraph(htmlNode));
            break;
          case 'h1':
            docNodes.add(_parseHeader(htmlNode, 1));
            break;
          case 'h2':
            docNodes.add(_parseHeader(htmlNode, 2));
            break;
          case 'h3':
            docNodes.add(_parseHeader(htmlNode, 3));
            break;
          case 'h4':
            docNodes.add(_parseHeader(htmlNode, 4));
            break;
          case 'h5':
            docNodes.add(_parseHeader(htmlNode, 5));
            break;
          case 'h6':
            docNodes.add(_parseHeader(htmlNode, 6));
            break;
          case 'ul':
            inUnorderedList = true;
            inOrderedList = false;
            _parseList(htmlNode, docNodes, ordered: false);
            break;
          case 'ol':
            inOrderedList = true;
            inUnorderedList = false;
            _parseList(htmlNode, docNodes, ordered: true);
            break;
          case 'li':
            // Handle orphan li elements
            docNodes.add(_parseListItem(htmlNode, ordered: inOrderedList));
            break;
          case 'blockquote':
            docNodes.add(_parseBlockquote(htmlNode));
            break;
          case 'pre':
          case 'code':
            docNodes.add(_parseCodeBlock(htmlNode));
            break;
          case 'hr':
            docNodes.add(HorizontalRuleNode(id: Editor.createNodeId()));
            break;
          case 'img':
            final src = htmlNode.attributes['src'] ?? '';
            if (src.isNotEmpty) {
              docNodes.add(ImageNode(id: Editor.createNodeId(), imageUrl: src));
            }
            break;
          case 'br':
            // Line break within content - handled by parent
            break;
          case 'div':
          case 'section':
          case 'article':
          case 'main':
          case 'header':
          case 'footer':
          case 'aside':
          case 'nav':
            // Container elements - recurse into children
            _parseHtmlNodes(htmlNode.nodes, docNodes);
            break;
          case 'label':
            // Check for checkbox inside label (task item)
            if (_containsCheckbox(htmlNode)) {
              docNodes.add(_parseTaskFromLabel(htmlNode));
            } else {
              docNodes.add(_parseParagraph(htmlNode));
            }
            break;
          case 'input':
            // Standalone checkbox
            if (htmlNode.attributes['type'] == 'checkbox') {
              final isChecked = htmlNode.attributes.containsKey('checked');
              docNodes.add(
                TaskNode(
                  id: Editor.createNodeId(),
                  text: AttributedText(''),
                  isComplete: isChecked,
                ),
              );
            }
            break;
          default:
            // Try to extract text content from unknown elements
            final text = htmlNode.text.trim();
            if (text.isNotEmpty) {
              docNodes.add(_createParagraphNode(text));
            }
        }
      }
    }
  }

  bool _containsCheckbox(html_dom.Element element) {
    for (final node in element.nodes) {
      if (node is html_dom.Element) {
        if (node.localName == 'input' &&
            node.attributes['type'] == 'checkbox') {
          return true;
        }
        if (_containsCheckbox(node)) return true;
      }
    }
    return false;
  }

  TaskNode _parseTaskFromLabel(html_dom.Element element) {
    bool isChecked = false;
    final textBuffer = StringBuffer();

    for (final node in element.nodes) {
      if (node is html_dom.Element) {
        if (node.localName == 'input' &&
            node.attributes['type'] == 'checkbox') {
          isChecked = node.attributes.containsKey('checked');
        } else {
          textBuffer.write(node.text);
        }
      } else if (node is html_dom.Text) {
        textBuffer.write(node.text);
      }
    }

    return TaskNode(
      id: Editor.createNodeId(),
      text: AttributedText(textBuffer.toString().trim()),
      isComplete: isChecked,
    );
  }

  ParagraphNode _createParagraphNode(String text) {
    return ParagraphNode(id: Editor.createNodeId(), text: AttributedText(text));
  }

  ParagraphNode _parseParagraph(html_dom.Element element) {
    final attributedText = _parseInlineContent(element);
    return ParagraphNode(id: Editor.createNodeId(), text: attributedText);
  }

  ParagraphNode _parseHeader(html_dom.Element element, int level) {
    final attributedText = _parseInlineContent(element);
    return ParagraphNode(
      id: Editor.createNodeId(),
      text: attributedText,
      metadata: {'blockType': _getHeaderAttribution(level)},
    );
  }

  Attribution _getHeaderAttribution(int level) {
    switch (level) {
      case 1:
        return header1Attribution;
      case 2:
        return header2Attribution;
      case 3:
        return header3Attribution;
      case 4:
        return header4Attribution;
      case 5:
        return header5Attribution;
      case 6:
        return header6Attribution;
      default:
        return header1Attribution;
    }
  }

  void _parseList(
    html_dom.Element element,
    List<DocumentNode> docNodes, {
    required bool ordered,
  }) {
    for (final child in element.children) {
      if (child.localName?.toLowerCase() == 'li') {
        docNodes.add(_parseListItem(child, ordered: ordered));
      }
    }
  }

  ListItemNode _parseListItem(
    html_dom.Element element, {
    required bool ordered,
  }) {
    final attributedText = _parseInlineContent(element);
    return ListItemNode(
      id: Editor.createNodeId(),
      itemType: ordered ? ListItemType.ordered : ListItemType.unordered,
      text: attributedText,
    );
  }

  ParagraphNode _parseBlockquote(html_dom.Element element) {
    final attributedText = _parseInlineContent(element);
    return ParagraphNode(
      id: Editor.createNodeId(),
      text: attributedText,
      metadata: {'blockType': blockquoteAttribution},
    );
  }

  ParagraphNode _parseCodeBlock(html_dom.Element element) {
    // For code blocks, preserve whitespace
    final text = element.text;
    return ParagraphNode(
      id: Editor.createNodeId(),
      text: AttributedText(text),
      metadata: {'blockType': codeAttribution},
    );
  }

  /// Parse inline content with formatting (bold, italic, etc.)
  AttributedText _parseInlineContent(html_dom.Element element) {
    final text = StringBuffer();
    final attributions = <SpanMarker>[];

    void parseNode(html_dom.Node node, Set<Attribution> activeAttributions) {
      if (node is html_dom.Text) {
        final startOffset = text.length;
        text.write(node.text);
        final endOffset = text.length;

        // Apply all active attributions to this text span
        for (final attr in activeAttributions) {
          if (startOffset < endOffset) {
            attributions.add(
              SpanMarker(
                attribution: attr,
                offset: startOffset,
                markerType: SpanMarkerType.start,
              ),
            );
            attributions.add(
              SpanMarker(
                attribution: attr,
                offset: endOffset - 1,
                markerType: SpanMarkerType.end,
              ),
            );
          }
        }
      } else if (node is html_dom.Element) {
        final newAttributions = Set<Attribution>.from(activeAttributions);

        switch (node.localName?.toLowerCase()) {
          case 'strong':
          case 'b':
            newAttributions.add(boldAttribution);
            break;
          case 'em':
          case 'i':
            newAttributions.add(italicsAttribution);
            break;
          case 'u':
            newAttributions.add(underlineAttribution);
            break;
          case 's':
          case 'strike':
          case 'del':
            newAttributions.add(strikethroughAttribution);
            break;
          case 'code':
            newAttributions.add(codeAttribution);
            break;
          case 'a':
            final href = node.attributes['href'];
            if (href != null) {
              newAttributions.add(LinkAttribution(href));
            }
            break;
          case 'span':
            // Parse style attribute for colors
            final style = node.attributes['style'] ?? '';
            _parseStyleAttributions(style, newAttributions);
            break;
          case 'sub':
            // Subscript - Super Editor may not support this directly
            break;
          case 'sup':
            // Superscript - Super Editor may not support this directly
            break;
          case 'br':
            text.write('\n');
            return;
        }

        for (final child in node.nodes) {
          parseNode(child, newAttributions);
        }
      }
    }

    parseNode(element, {});

    return AttributedText(
      text.toString(),
      AttributedSpans(attributions: attributions),
    );
  }

  void _parseStyleAttributions(String style, Set<Attribution> attributions) {
    // Parse inline CSS styles
    final properties = style.split(';');
    for (final prop in properties) {
      final parts = prop.split(':');
      if (parts.length == 2) {
        final name = parts[0].trim().toLowerCase();
        final value = parts[1].trim();

        switch (name) {
          case 'font-weight':
            if (value == 'bold' || value == '700') {
              attributions.add(boldAttribution);
            }
            break;
          case 'font-style':
            if (value == 'italic') {
              attributions.add(italicsAttribution);
            }
            break;
          case 'text-decoration':
            if (value.contains('underline')) {
              attributions.add(underlineAttribution);
            }
            if (value.contains('line-through')) {
              attributions.add(strikethroughAttribution);
            }
            break;
          case 'color':
            final color = _parseColor(value);
            if (color != null) {
              attributions.add(ColorAttribution(color));
            }
            break;
          case 'background-color':
            final color = _parseColor(value);
            if (color != null) {
              attributions.add(BackgroundColorAttribution(color));
            }
            break;
        }
      }
    }
  }

  Color? _parseColor(String value) {
    value = value.trim().toLowerCase();

    // Hex color
    if (value.startsWith('#')) {
      try {
        String hex = value.substring(1);
        if (hex.length == 3) {
          hex = '${hex[0]}${hex[0]}${hex[1]}${hex[1]}${hex[2]}${hex[2]}';
        }
        if (hex.length == 6) {
          return Color(int.parse('FF$hex', radix: 16));
        }
        if (hex.length == 8) {
          return Color(int.parse(hex, radix: 16));
        }
      } catch (e) {
        return null;
      }
    }

    // RGB/RGBA
    if (value.startsWith('rgb')) {
      final match = RegExp(
        r'rgba?\((\d+),\s*(\d+),\s*(\d+)(?:,\s*([\d.]+))?\)',
      ).firstMatch(value);
      if (match != null) {
        final r = int.parse(match.group(1)!);
        final g = int.parse(match.group(2)!);
        final b = int.parse(match.group(3)!);
        final a = match.group(4) != null
            ? (double.parse(match.group(4)!) * 255).round()
            : 255;
        return Color.fromARGB(a, r, g, b);
      }
    }

    // Named colors (basic support)
    const namedColors = <String, Color>{
      'red': Colors.red,
      'green': Colors.green,
      'blue': Colors.blue,
      'black': Colors.black,
      'white': Colors.white,
      'yellow': Colors.yellow,
      'orange': Colors.orange,
      'purple': Colors.purple,
      'pink': Colors.pink,
      'grey': Colors.grey,
      'gray': Colors.grey,
    };

    return namedColors[value];
  }

  // HTML generation methods

  String _paragraphToHtml(ParagraphNode node) {
    final blockType = node.metadata['blockType'];
    final content = _attributedTextToHtml(node.text);

    if (blockType == header1Attribution) {
      return '<h1>$content</h1>';
    } else if (blockType == header2Attribution) {
      return '<h2>$content</h2>';
    } else if (blockType == header3Attribution) {
      return '<h3>$content</h3>';
    } else if (blockType == header4Attribution) {
      return '<h4>$content</h4>';
    } else if (blockType == header5Attribution) {
      return '<h5>$content</h5>';
    } else if (blockType == header6Attribution) {
      return '<h6>$content</h6>';
    } else if (blockType == blockquoteAttribution) {
      return '<blockquote>$content</blockquote>';
    } else if (blockType == codeAttribution) {
      return '<pre><code>$content</code></pre>';
    }

    return '<p>$content</p>';
  }

  String _listItemToHtml(ListItemNode node) {
    final content = _attributedTextToHtml(node.text);
    final tag = node.type == ListItemType.ordered ? 'ol' : 'ul';
    return '<$tag><li>$content</li></$tag>';
  }

  String _taskToHtml(TaskNode node) {
    final content = _attributedTextToHtml(node.text);
    final checked = node.isComplete ? ' checked' : '';
    return '<label><input type="checkbox"$checked> $content</label>';
  }

  String _attributedTextToHtml(AttributedText text) {
    if (text.length == 0) return '';

    final buffer = StringBuffer();
    final spans = text.spans;

    // Get all attribution changes
    final changes = <int, List<_AttributionChange>>{};

    for (final marker in spans.markers) {
      changes.putIfAbsent(marker.offset, () => []);
      changes[marker.offset]!.add(
        _AttributionChange(
          attribution: marker.attribution,
          isStart: marker.markerType == SpanMarkerType.start,
        ),
      );
    }

    // Build HTML with proper tag ordering
    for (int i = 0; i < text.length; i++) {
      final markerChanges = changes[i];

      if (markerChanges != null) {
        // Close tags (reverse order)
        final closeTags = markerChanges
            .where((c) => !c.isStart)
            .map((c) => _getClosingTag(c.attribution))
            .toList()
            .reversed;
        for (final tag in closeTags) {
          buffer.write(tag);
        }

        // Open tags
        final openTags = markerChanges
            .where((c) => c.isStart)
            .map((c) => _getOpeningTag(c.attribution));
        for (final tag in openTags) {
          buffer.write(tag);
        }
      }

      // Write the character (escaped)
      buffer.write(_escapeHtml(text.text[i]));
    }

    // Close any remaining open tags at the end
    final endChanges = changes[text.length - 1];
    if (endChanges != null) {
      final closeTags = endChanges
          .where((c) => !c.isStart)
          .map((c) => _getClosingTag(c.attribution))
          .toList()
          .reversed;
      for (final tag in closeTags) {
        buffer.write(tag);
      }
    }

    return buffer.toString();
  }

  String _getOpeningTag(Attribution attribution) {
    if (attribution == boldAttribution) return '<strong>';
    if (attribution == italicsAttribution) return '<em>';
    if (attribution == underlineAttribution) return '<u>';
    if (attribution == strikethroughAttribution) return '<s>';
    if (attribution == codeAttribution) return '<code>';
    if (attribution is LinkAttribution) {
      return '<a href="${attribution.url}">';
    }
    if (attribution is ColorAttribution) {
      final color = attribution.color;
      final hex =
          '#${color.value.toRadixString(16).padLeft(8, '0').substring(2)}';
      return '<span style="color: $hex;">';
    }
    if (attribution is BackgroundColorAttribution) {
      final color = attribution.color;
      final hex =
          '#${color.value.toRadixString(16).padLeft(8, '0').substring(2)}';
      return '<span style="background-color: $hex;">';
    }
    return '';
  }

  String _getClosingTag(Attribution attribution) {
    if (attribution == boldAttribution) return '</strong>';
    if (attribution == italicsAttribution) return '</em>';
    if (attribution == underlineAttribution) return '</u>';
    if (attribution == strikethroughAttribution) return '</s>';
    if (attribution == codeAttribution) return '</code>';
    if (attribution is LinkAttribution) return '</a>';
    if (attribution is ColorAttribution) return '</span>';
    if (attribution is BackgroundColorAttribution) return '</span>';
    return '';
  }

  String _escapeHtml(String char) {
    switch (char) {
      case '<':
        return '&lt;';
      case '>':
        return '&gt;';
      case '&':
        return '&amp;';
      case '"':
        return '&quot;';
      case '\n':
        return '<br>';
      default:
        return char;
    }
  }

  MutableDocument _createEmptyDocument() {
    return MutableDocument(
      nodes: [
        ParagraphNode(id: Editor.createNodeId(), text: AttributedText('')),
      ],
    );
  }

  MutableDocument _createDocumentFromPlainText(String text) {
    final lines = text.split('\n');
    final nodes = <DocumentNode>[];

    for (final line in lines) {
      nodes.add(
        ParagraphNode(id: Editor.createNodeId(), text: AttributedText(line)),
      );
    }

    if (nodes.isEmpty) {
      return _createEmptyDocument();
    }

    return MutableDocument(nodes: nodes);
  }
}

class _AttributionChange {
  final Attribution attribution;
  final bool isStart;

  _AttributionChange({required this.attribution, required this.isStart});
}

/// Custom attribution for text color
class ColorAttribution implements Attribution {
  final Color color;

  const ColorAttribution(this.color);

  @override
  String get id => 'color_${color.value}';

  @override
  bool canMergeWith(Attribution other) {
    return other is ColorAttribution && other.color == color;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ColorAttribution && color == other.color;

  @override
  int get hashCode => color.hashCode;
}

/// Custom attribution for background color
class BackgroundColorAttribution implements Attribution {
  final Color color;

  const BackgroundColorAttribution(this.color);

  @override
  String get id => 'bg_color_${color.value}';

  @override
  bool canMergeWith(Attribution other) {
    return other is BackgroundColorAttribution && other.color == color;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BackgroundColorAttribution && color == other.color;

  @override
  int get hashCode => color.hashCode;
}
