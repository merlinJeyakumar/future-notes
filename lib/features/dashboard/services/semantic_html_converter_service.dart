import 'package:vsc_quill_delta_to_html/vsc_quill_delta_to_html.dart';

/// Service for converting Quill Delta to clean, semantic HTML.
/// Produces standards-compliant HTML with native checkboxes and semantic tags.
class SemanticHtmlConverterService {
  /// Convert Delta JSON to semantic HTML.
  ///
  /// Features:
  /// - Native `<input type="checkbox">` for checklists
  /// - Semantic tags: `<strong>`, `<em>`, `<u>`, `<s>`, `<code>`, `<blockquote>`
  /// - Proper structure: `<p>`, `<ul>`, `<ol>`, `<li>`, `<br>`
  /// - No inline styles or visual hacks
  String convertDeltaToHtml(List<dynamic> deltaJson) {
    final ops = deltaJson.cast<Map<String, dynamic>>();

    final converter = QuillDeltaToHtmlConverter(
      ops,
      ConverterOptions(
        converterOptions: OpConverterOptions(
          inlineStylesFlag: false, // Use tags instead of inline styles
          encodeHtml: true,
        ),
        sanitizerOptions: OpAttributeSanitizerOptions(),
      ),
    );

    // Custom rendering for checklist items
    converter.renderCustomWith = (DeltaInsertOp op, DeltaInsertOp? contextOp) {
      return ''; // Return empty string for non-custom ops (default handling)
    };

    // Before render callback for semantic transformations
    converter.beforeRender = (GroupType groupType, TDataGroup data) {
      return null; // Use default rendering, customize via afterRender
    };

    // After render for list items with checkbox attributes
    converter.afterRender = (GroupType groupType, String html) {
      return html;
    };

    String html = converter.convert();

    // Post-process for semantic cleanup and checkbox rendering
    html = _postProcessHtml(html);

    return html;
  }

  /// Post-process HTML to ensure semantic compliance and native checkboxes.
  String _postProcessHtml(String html) {
    // Convert data-checked list items to native checkboxes
    html = _convertChecklistsToNativeCheckboxes(html);

    // Ensure semantic tags are used
    html = _ensureSemanticTags(html);

    // Clean up empty paragraphs and normalize whitespace
    html = _cleanupHtml(html);

    return html;
  }

  /// Convert checklist items to native HTML checkboxes.
  /// Handles multiple Quill checklist formats:
  /// - <li data-checked="true|false">
  /// - <li data-list="checked|unchecked">
  /// - <li class="ql-checked|ql-unchecked">
  /// - Unicode checkbox symbols
  String _convertChecklistsToNativeCheckboxes(String html) {
    // Pattern 1: <li data-checked="true|false">content</li>
    html = html.replaceAllMapped(
      RegExp(
        r'<li\s+data-checked="(true|false)"[^>]*>(.*?)</li>',
        caseSensitive: false,
        dotAll: true,
      ),
      (match) {
        final isChecked = match.group(1) == 'true';
        final content = _cleanCheckboxContent(match.group(2) ?? '');
        final checkedAttr = isChecked ? ' checked' : '';
        return '<li><label><input type="checkbox"$checkedAttr>$content</label></li>';
      },
    );

    // Pattern 2: <li data-list="checked|unchecked">content</li>
    html = html.replaceAllMapped(
      RegExp(
        r'<li[^>]*data-list="(checked|unchecked)"[^>]*>(.*?)</li>',
        caseSensitive: false,
        dotAll: true,
      ),
      (match) {
        final isChecked = match.group(1) == 'checked';
        final content = _cleanCheckboxContent(match.group(2) ?? '');
        final checkedAttr = isChecked ? ' checked' : '';
        return '<li><label><input type="checkbox"$checkedAttr>$content</label></li>';
      },
    );

    // Pattern 3: <li class="...ql-checked..." or class="...ql-unchecked...">
    html = html.replaceAllMapped(
      RegExp(
        r'<li[^>]*class="[^"]*ql-(checked|unchecked)[^"]*"[^>]*>(.*?)</li>',
        caseSensitive: false,
        dotAll: true,
      ),
      (match) {
        final isChecked = match.group(1) == 'checked';
        final content = _cleanCheckboxContent(match.group(2) ?? '');
        final checkedAttr = isChecked ? ' checked' : '';
        return '<li><label><input type="checkbox"$checkedAttr>$content</label></li>';
      },
    );

    // Pattern 4: Clean up ul with data-list attribute
    html = html.replaceAllMapped(
      RegExp(r'<ul[^>]*data-list="[^"]*"[^>]*>', caseSensitive: false),
      (match) => '<ul>',
    );

    // Pattern 5: Unicode checkbox symbols within list items
    final unicodeUncheckedPattern = RegExp(r'[☐□]');
    final unicodeCheckedPattern = RegExp(r'[☑☒✓✔✅]');

    html = html.replaceAllMapped(
      RegExp(r'<li>((?:(?!</li>).)*)</li>', dotAll: true),
      (match) {
        var content = match.group(1) ?? '';
        // Skip if already has checkbox
        if (content.contains('<input type="checkbox"')) {
          return match.group(0)!;
        }
        if (unicodeUncheckedPattern.hasMatch(content)) {
          content = content.replaceAll(unicodeUncheckedPattern, '');
          return '<li><label><input type="checkbox">${_cleanCheckboxContent(content)}</label></li>';
        }
        if (unicodeCheckedPattern.hasMatch(content)) {
          content = content.replaceAll(unicodeCheckedPattern, '');
          return '<li><label><input type="checkbox" checked>${_cleanCheckboxContent(content)}</label></li>';
        }
        return match.group(0)!;
      },
    );

    return html;
  }

  /// Clean checkbox content: trim whitespace, remove leading/trailing br tags
  String _cleanCheckboxContent(String content) {
    content = content.trim();
    // Remove leading <br> or <br/>
    content = content.replaceFirst(RegExp(r'^<br\s*/?>'), '');
    // Remove trailing <br> or <br/>
    content = content.replaceFirst(RegExp(r'<br\s*/?>$'), '');
    content = content.trim();
    // Add space prefix if content exists
    return content.isEmpty ? '' : ' $content';
  }

  /// Ensure semantic HTML tags are used instead of inline styles.
  String _ensureSemanticTags(String html) {
    // Convert inline style bold to <strong>
    html = html.replaceAllMapped(
      RegExp(
        r'<span[^>]*style="[^"]*font-weight:\s*bold[^"]*"[^>]*>(.*?)</span>',
        dotAll: true,
      ),
      (m) => '<strong>${m.group(1)}</strong>',
    );

    // Convert inline style italic to <em>
    html = html.replaceAllMapped(
      RegExp(
        r'<span[^>]*style="[^"]*font-style:\s*italic[^"]*"[^>]*>(.*?)</span>',
        dotAll: true,
      ),
      (m) => '<em>${m.group(1)}</em>',
    );

    // Convert inline style underline to <u>
    html = html.replaceAllMapped(
      RegExp(
        r'<span[^>]*style="[^"]*text-decoration:\s*underline[^"]*"[^>]*>(.*?)</span>',
        dotAll: true,
      ),
      (m) => '<u>${m.group(1)}</u>',
    );

    // Convert inline style strikethrough to <s>
    html = html.replaceAllMapped(
      RegExp(
        r'<span[^>]*style="[^"]*text-decoration:\s*line-through[^"]*"[^>]*>(.*?)</span>',
        dotAll: true,
      ),
      (m) => '<s>${m.group(1)}</s>',
    );

    // Convert <b> to <strong> for semantics
    html = html.replaceAll(RegExp(r'<b>'), '<strong>');
    html = html.replaceAll(RegExp(r'</b>'), '</strong>');

    // Convert <i> to <em> for semantics
    html = html.replaceAll(RegExp(r'<i>'), '<em>');
    html = html.replaceAll(RegExp(r'</i>'), '</em>');

    // Convert <strike> to <s>
    html = html.replaceAll(RegExp(r'<strike>'), '<s>');
    html = html.replaceAll(RegExp(r'</strike>'), '</s>');

    return html;
  }

  /// Clean up HTML: remove empty elements, normalize whitespace.
  String _cleanupHtml(String html) {
    // Remove empty paragraphs (but preserve intentional breaks)
    html = html.replaceAll(RegExp(r'<p>\s*</p>'), '');

    // Remove empty spans
    html = html.replaceAll(RegExp(r'<span[^>]*>\s*</span>'), '');

    // Normalize multiple consecutive <br> tags (keep max 2 for paragraph breaks)
    html = html.replaceAllMapped(RegExp(r'(<br\s*/?>){3,}'), (m) => '<br><br>');

    // Remove trailing whitespace within tags
    html = html.replaceAllMapped(RegExp(r'>\s+<'), (m) => '><');

    // Trim the final output
    return html.trim();
  }

  /// Convert Delta to HTML in an isolate-safe manner (static method).
  static String convertSync(List<dynamic> deltaJson) {
    return SemanticHtmlConverterService().convertDeltaToHtml(deltaJson);
  }
}

/// Top-level function for use with compute() isolate.
Future<String> semanticDeltaToHtmlTask(List<dynamic> deltaJson) async {
  return SemanticHtmlConverterService.convertSync(deltaJson);
}
