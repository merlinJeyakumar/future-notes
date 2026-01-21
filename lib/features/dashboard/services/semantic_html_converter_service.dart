import 'package:flutter/foundation.dart';
import 'package:vsc_quill_delta_to_html/vsc_quill_delta_to_html.dart';

/// Service for converting Quill Delta to clean, semantic HTML.
///
/// This service produces standards-compliant HTML output with:
/// - Semantic formatting tags: `<strong>`, `<em>`, `<u>`, `<s>`
/// - Proper structure: `<p>`, `<ul>`, `<ol>`, `<li>`, `<br>`
/// - No inline styles or visual hacks
/// - Preserved line breaks and content order
class SemanticHtmlConverterService {
  /// Convert Quill Delta JSON to semantic HTML.
  String convert(List<dynamic> deltaJson) {
    if (deltaJson.isEmpty) {
      return '';
    }

    try {
      // Safely convert delta operations to the expected format
      final ops = <Map<String, dynamic>>[];
      for (final op in deltaJson) {
        if (op is Map<String, dynamic>) {
          ops.add(op);
        } else if (op is Map) {
          ops.add(Map<String, dynamic>.from(op));
        }
      }

      if (ops.isEmpty) {
        return '';
      }

      // Configure converter to preserve inline styles (colors, backgrounds, etc.)
      final converter = QuillDeltaToHtmlConverter(
        ops,
        ConverterOptions(
          converterOptions: OpConverterOptions(
            inlineStylesFlag:
                true, // Enable to preserve colors and inline styles
            encodeHtml: true,
          ),
        ),
      );

      // Get raw HTML from converter
      String html = converter.convert();

      // Apply semantic transformations
      html = _transformToSemanticHtml(html);

      return html;
    } catch (e) {
      debugPrint('SemanticHtmlConverterService.convert error: $e');
      // Fallback: try to extract plain text from delta
      return _fallbackConvert(deltaJson);
    }
  }

  /// Fallback conversion when the main converter fails.
  String _fallbackConvert(List<dynamic> deltaJson) {
    final buffer = StringBuffer();
    for (final op in deltaJson) {
      if (op is Map) {
        final insert = op['insert'];
        if (insert is String) {
          buffer.write(insert);
        }
      }
    }
    final text = buffer.toString().trim();
    if (text.isEmpty) {
      return '';
    }
    // Wrap in paragraph and escape HTML
    final escaped = text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('\n', '<br>');
    return '<p>$escaped</p>';
  }

  /// Transform HTML to use semantic tags.
  String _transformToSemanticHtml(String html) {
    // Step 1: Convert presentational tags to semantic tags
    html = _convertToSemanticTags(html);

    // Step 2: Clean up unnecessary elements
    html = _cleanup(html);

    return html;
  }

  /// Convert presentational HTML tags to semantic equivalents.
  String _convertToSemanticTags(String html) {
    // <b> -> <strong>
    html = html.replaceAllMapped(
      RegExp(r'<b(\s[^>]*)?>'),
      (m) => '<strong${m.group(1) ?? ''}>',
    );
    html = html.replaceAll('</b>', '</strong>');

    // <i> -> <em>
    html = html.replaceAllMapped(
      RegExp(r'<i(\s[^>]*)?>'),
      (m) => '<em${m.group(1) ?? ''}>',
    );
    html = html.replaceAll('</i>', '</em>');

    // <strike> -> <s>
    html = html.replaceAllMapped(
      RegExp(r'<strike(\s[^>]*)?>'),
      (m) => '<s${m.group(1) ?? ''}>',
    );
    html = html.replaceAll('</strike>', '</s>');

    // Convert inline style spans to semantic tags
    html = _convertInlineStylesToTags(html);

    return html;
  }

  /// Convert inline style spans to semantic tags, but preserve color attributes.
  String _convertInlineStylesToTags(String html) {
    // Note: We now preserve color and background-color inline styles
    // Only convert weight/style/decoration to semantic tags when they're the ONLY style

    // font-weight: bold -> <strong> (only if no color/background)
    html = html.replaceAllMapped(
      RegExp(
        r'<span[^>]*style="[^"]*font-weight:\s*(?:bold|700)[^"]*"[^>]*>([\s\S]*?)</span>',
      ),
      (m) {
        final fullMatch = m.group(0)!;
        // Preserve if it has color or background-color
        if (fullMatch.contains('color:')) {
          return fullMatch;
        }
        return '<strong>${m.group(1)}</strong>';
      },
    );

    // font-style: italic -> <em> (only if no color/background)
    html = html.replaceAllMapped(
      RegExp(
        r'<span[^>]*style="[^"]*font-style:\s*italic[^"]*"[^>]*>([\s\S]*?)</span>',
      ),
      (m) {
        final fullMatch = m.group(0)!;
        if (fullMatch.contains('color:')) {
          return fullMatch;
        }
        return '<em>${m.group(1)}</em>';
      },
    );

    // text-decoration: underline -> <u> (only if no color/background)
    html = html.replaceAllMapped(
      RegExp(
        r'<span[^>]*style="[^"]*text-decoration:\s*underline[^"]*"[^>]*>([\s\S]*?)</span>',
      ),
      (m) {
        final fullMatch = m.group(0)!;
        if (fullMatch.contains('color:')) {
          return fullMatch;
        }
        return '<u>${m.group(1)}</u>';
      },
    );

    // text-decoration: line-through -> <s> (only if no color/background)
    html = html.replaceAllMapped(
      RegExp(
        r'<span[^>]*style="[^"]*text-decoration:\s*line-through[^"]*"[^>]*>([\s\S]*?)</span>',
      ),
      (m) {
        final fullMatch = m.group(0)!;
        if (fullMatch.contains('color:')) {
          return fullMatch;
        }
        return '<s>${m.group(1)}</s>';
      },
    );

    return html;
  }

  /// Clean up HTML: remove empty elements, normalize whitespace.
  String _cleanup(String html) {
    // Remove empty paragraphs
    html = html.replaceAll(RegExp(r'<p>\s*</p>'), '');

    // Remove only truly empty spans (no style attribute or empty style)
    // Preserve spans with style attributes (colors, backgrounds, etc.)
    html = html.replaceAllMapped(RegExp(r'<span([^>]*)>\s*</span>'), (match) {
      final attributes = match.group(1) ?? '';
      // Keep span if it has a non-empty style attribute
      if (attributes.contains('style=') &&
          !attributes.contains('style=""') &&
          !attributes.contains("style=''")) {
        return match.group(0)!; // Keep the span
      }
      return ''; // Remove empty span
    });

    // Normalize consecutive <br> tags (max 2)
    html = html.replaceAllMapped(RegExp(r'(<br\s*/?>){3,}'), (_) => '<br><br>');

    return html.trim();
  }
}

/// Top-level function for use with compute() isolate.
/// This is the public API used by ContentViewModel.
/// Must be synchronous for compute() to work correctly.
String semanticDeltaToHtmlTask(List<dynamic> deltaJson) {
  return SemanticHtmlConverterService().convert(deltaJson);
}
