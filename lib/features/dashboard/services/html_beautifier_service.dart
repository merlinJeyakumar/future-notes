import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as html_dom;

/// Interface for HTML beautification service.
abstract class IHtmlBeautifierService {
  String beautify(String htmlContent);
}

/// Service for beautifying HTML content with proper indentation.
class HtmlBeautifierService implements IHtmlBeautifierService {
  @override
  String beautify(String htmlContent) {
    if (htmlContent.trim().isEmpty) return '';

    try {
      final document = html_parser.parseFragment(htmlContent);
      final buffer = StringBuffer();
      _formatNode(document, buffer, 0);
      return buffer.toString().trim();
    } catch (e) {
      return htmlContent;
    }
  }

  void _formatNode(html_dom.Node node, StringBuffer buffer, int indent) {
    final inlineElements = {
      'strong',
      'em',
      'u',
      's',
      'span',
      'a',
      'code',
      'b',
      'i',
      'small',
      'sub',
      'sup',
      'mark',
    };
    final selfClosing = {'br', 'img', 'input', 'hr', 'meta', 'link'};

    if (node.nodeType == html_dom.Node.TEXT_NODE) {
      final text = node.text?.trim() ?? '';
      if (text.isNotEmpty) buffer.write(text);
    } else if (node.nodeType == html_dom.Node.ELEMENT_NODE) {
      final element = node as html_dom.Element;
      final tag = element.localName ?? '';
      final isInline = inlineElements.contains(tag);
      final isSelfClose = selfClosing.contains(tag);

      if (!isInline && buffer.isNotEmpty && !buffer.toString().endsWith('\n')) {
        buffer.writeln();
      }
      if (!isInline) buffer.write('  ' * indent);

      buffer.write('<$tag');
      element.attributes.forEach((k, v) {
        buffer.write(' $k="${v.replaceAll('"', '&quot;')}"');
      });

      if (isSelfClose && element.nodes.isEmpty) {
        buffer.write('>');
        if (!isInline) buffer.writeln();
      } else {
        buffer.write('>');

        final hasBlockChildren = element.nodes.any(
          (c) => c is html_dom.Element && !inlineElements.contains(c.localName),
        );

        if (hasBlockChildren && !isInline) buffer.writeln();

        for (final child in element.nodes) {
          _formatNode(child, buffer, isInline ? indent : indent + 1);
        }

        if (hasBlockChildren &&
            !isInline &&
            !buffer.toString().endsWith('\n')) {
          buffer.writeln();
        }
        if (hasBlockChildren && !isInline) buffer.write('  ' * indent);

        buffer.write('</$tag>');
        if (!isInline) buffer.writeln();
      }
    } else {
      for (final child in node.nodes) {
        _formatNode(child, buffer, indent);
      }
    }
  }
}

/// Top-level function for compute() isolate.
String beautifyHtmlTask(String htmlContent) {
  return HtmlBeautifierService().beautify(htmlContent);
}
