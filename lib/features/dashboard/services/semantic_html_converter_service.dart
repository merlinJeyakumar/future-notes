import 'package:vsc_quill_delta_to_html/vsc_quill_delta_to_html.dart';

/// Service for converting Quill Delta to clean, semantic HTML.
///
/// This service produces standards-compliant HTML output with:
/// - Semantic formatting tags: `<strong>`, `<em>`, `<u>`, `<s>`
/// - Proper structure: `<p>`, `<ul>`, `<ol>`, `<li>`, `<br>`
/// - Native checkboxes: `<input type="checkbox">` wrapped in `<label>`
/// - No inline styles or visual hacks
/// - Preserved line breaks and content order
class SemanticHtmlConverterService {
  /// Convert Quill Delta JSON to semantic HTML.
  String convert(List<dynamic> deltaJson) {
    if (deltaJson.isEmpty) {
      return '';
    }

    final ops = deltaJson.cast<Map<String, dynamic>>();

    // Configure converter for semantic output
    final converter = QuillDeltaToHtmlConverter(
      ops,
      ConverterOptions(
        converterOptions: OpConverterOptions(
          inlineStylesFlag: false,
          encodeHtml: true,
        ),
      ),
    );

    // Get raw HTML from converter
    String html = converter.convert();

    // Apply semantic transformations
    html = _transformToSemanticHtml(html);

    return html;
  }

  /// Transform HTML to use semantic tags and native checkboxes.
  String _transformToSemanticHtml(String html) {
    // Step 1: Convert checklists to native checkboxes
    html = _convertChecklists(html);

    // Step 2: Convert presentational tags to semantic tags
    html = _convertToSemanticTags(html);

    // Step 3: Clean up unnecessary elements
    html = _cleanup(html);

    return html;
  }

  /// Convert Quill checklist format to native HTML checkboxes.
  ///
  /// Quill outputs checklists as:
  /// - `<li data-checked="true|false">content</li>`
  /// - `<li data-list="checked|unchecked">content</li>`
  String _convertChecklists(String html) {
    // Pattern: <li data-checked="true|false">
    html = _replaceChecklistPattern(
      html,
      RegExp(
        r'<li\s+data-checked="(true|false)"[^>]*>([\s\S]*?)</li>',
        caseSensitive: false,
      ),
      (isChecked, content) => _buildCheckboxLi(isChecked, content),
    );

    // Pattern: <li data-list="checked|unchecked">
    html = _replaceChecklistPattern(
      html,
      RegExp(
        r'<li[^>]*\s+data-list="(checked|unchecked)"[^>]*>([\s\S]*?)</li>',
        caseSensitive: false,
      ),
      (value, content) => _buildCheckboxLi(value == 'checked', content),
    );

    // Pattern: <li class="...ql-checked..." or ql-unchecked>
    html = _replaceChecklistPattern(
      html,
      RegExp(
        r'<li[^>]*\s+class="[^"]*ql-(checked|unchecked)[^"]*"[^>]*>([\s\S]*?)</li>',
        caseSensitive: false,
      ),
      (value, content) => _buildCheckboxLi(value == 'checked', content),
    );

    // Clean data-list attributes from <ul> tags
    html = html.replaceAll(RegExp(r'\s+data-list="[^"]*"'), '');

    return html;
  }

  /// Helper to replace checklist patterns with native checkboxes.
  String _replaceChecklistPattern(
    String html,
    RegExp pattern,
    String Function(dynamic value, String content) builder,
  ) {
    return html.replaceAllMapped(pattern, (match) {
      final value = match.group(1);
      final content = match.group(2) ?? '';
      return builder(value, content);
    });
  }

  /// Build a list item with native checkbox.
  String _buildCheckboxLi(bool isChecked, String content) {
    final checkedAttr = isChecked ? ' checked' : '';
    final cleanContent = _cleanContent(content);

    if (cleanContent.isEmpty) {
      return '<li><label><input type="checkbox"$checkedAttr></label></li>';
    }

    return '<li><label><input type="checkbox"$checkedAttr> $cleanContent</label></li>';
  }

  /// Clean content: remove empty br tags at start/end, trim whitespace.
  String _cleanContent(String content) {
    content = content.trim();

    // Remove leading <br> or <br/>
    content = content.replaceFirst(
      RegExp(r'^(<br\s*/?>)+', caseSensitive: false),
      '',
    );

    // Remove trailing <br> or <br/>
    content = content.replaceFirst(
      RegExp(r'(<br\s*/?>)+$', caseSensitive: false),
      '',
    );

    return content.trim();
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

  /// Convert inline style spans to semantic tags.
  String _convertInlineStylesToTags(String html) {
    // font-weight: bold -> <strong>
    html = html.replaceAllMapped(
      RegExp(
        r'<span[^>]*style="[^"]*font-weight:\s*(?:bold|700)[^"]*"[^>]*>([\s\S]*?)</span>',
      ),
      (m) => '<strong>${m.group(1)}</strong>',
    );

    // font-style: italic -> <em>
    html = html.replaceAllMapped(
      RegExp(
        r'<span[^>]*style="[^"]*font-style:\s*italic[^"]*"[^>]*>([\s\S]*?)</span>',
      ),
      (m) => '<em>${m.group(1)}</em>',
    );

    // text-decoration: underline -> <u>
    html = html.replaceAllMapped(
      RegExp(
        r'<span[^>]*style="[^"]*text-decoration:\s*underline[^"]*"[^>]*>([\s\S]*?)</span>',
      ),
      (m) => '<u>${m.group(1)}</u>',
    );

    // text-decoration: line-through -> <s>
    html = html.replaceAllMapped(
      RegExp(
        r'<span[^>]*style="[^"]*text-decoration:\s*line-through[^"]*"[^>]*>([\s\S]*?)</span>',
      ),
      (m) => '<s>${m.group(1)}</s>',
    );

    return html;
  }

  /// Clean up HTML: remove empty elements, normalize whitespace.
  String _cleanup(String html) {
    // Remove empty paragraphs
    html = html.replaceAll(RegExp(r'<p>\s*</p>'), '');

    // Remove empty spans
    html = html.replaceAll(RegExp(r'<span[^>]*>\s*</span>'), '');

    // Normalize consecutive <br> tags (max 2)
    html = html.replaceAllMapped(RegExp(r'(<br\s*/?>){3,}'), (_) => '<br><br>');

    return html.trim();
  }
}

/// Top-level function for use with compute() isolate.
/// This is the public API used by ContentViewModel.
Future<String> semanticDeltaToHtmlTask(List<dynamic> deltaJson) async {
  return SemanticHtmlConverterService().convert(deltaJson);
}
