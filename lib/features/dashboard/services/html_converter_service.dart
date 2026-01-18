import 'package:flutter/foundation.dart';
import 'package:vsc_quill_delta_to_html/vsc_quill_delta_to_html.dart';
import 'package:universal_html/html.dart' as html;
import 'package:universal_html/parsing.dart';

/// Interface for HTML conversion service
abstract class IHtmlConverterService {
  /// Convert Quill Delta to clean, semantic HTML
  /// Returns HTML with minimal inline styles and semantic tags only
  Future<String> convertDeltaToSemanticHtml(List<dynamic> deltaJson);

  /// Clean up existing HTML to make it more semantic
  /// Removes redundant attributes and inline styles where possible
  Future<String> convertHtmlToCleanHtml(String rawHtml);
}

/// Service for converting Quill Delta to clean, semantic HTML
///
/// Generates standards-compliant HTML with:
/// - Native <input type="checkbox"> elements for checklists
/// - Semantic tags only (ul, ol, li, p, strong, em, a, img, pre, code)
/// - Minimal inline styles
/// - Proper nested list preservation
/// - Clean, readable output suitable for export or PDF generation
class SemanticHtmlConverterService implements IHtmlConverterService {
  @override
  Future<String> convertDeltaToSemanticHtml(List<dynamic> deltaJson) async {
    try {
      // Step 1: Use vsc_quill_delta_to_html for initial conversion
      final converter = QuillDeltaToHtmlConverter(
        deltaJson.cast<Map<String, dynamic>>(),
        ConverterOptions.forEmail(),
      );
      String htmlContent = converter.convert();

      // Step 2: Parse and clean the HTML
      htmlContent = await _cleanAndProcessHtml(htmlContent);

      return htmlContent;
    } catch (e) {
      debugPrint("Error converting Delta to semantic HTML: $e");
      rethrow;
    }
  }

  @override
  Future<String> convertHtmlToCleanHtml(String rawHtml) async {
    try {
      return await _cleanAndProcessHtml(rawHtml);
    } catch (e) {
      debugPrint("Error cleaning HTML: $e");
      rethrow;
    }
  }

  /// Clean and process HTML to make it semantic and standards-compliant
  Future<String> _cleanAndProcessHtml(String htmlContent) async {
    try {
      // Parse the HTML content to DOM
      final doc = parseHtmlDocument(htmlContent);

      // Process checkboxes
      _processCheckboxes(doc);

      // Process lists to ensure proper nesting
      _processLists(doc);

      // Process images
      _processImages(doc);

      // Process code blocks
      _processCodeBlocks(doc);

      // Remove empty elements
      _removeEmptyElements(doc);

      // Return the processed HTML body
      return doc.body?.innerHtml ?? htmlContent;
    } catch (e) {
      debugPrint("Error processing HTML: $e");
      return htmlContent; // Fallback to original
    }
  }

  /// Process checkboxes to use native HTML input elements
  void _processCheckboxes(html.Document doc) {
    // Find all list items that represent checkboxes (vsc_quill_delta_to_html uses data-checked)
    final checklistItems = doc.querySelectorAll('li[data-checked]');

    for (final li in checklistItems) {
      final isChecked = li.getAttribute('data-checked') == 'true';

      // Remove the data-checked attribute (not semantic)
      li.attributes.remove('data-checked');

      // Remove list-style to prevent bullets/markers
      li.style.listStyleType = 'none';

      // Create the native HTML checkbox
      final checkbox = html.CheckboxInputElement();
      checkbox.checked = isChecked;

      // Create a label to wrap the checkbox and content
      final label = html.LabelElement();
      label.append(checkbox);

      // Collect existing content nodes
      final children = List<html.Node>.from(li.nodes);
      li.nodes.clear();

      bool hasContent = false;

      for (final child in children) {
        // Skip empty BR tags as per requirements
        if (child is html.Element && child.tagName == 'BR') {
          final hasText = child.text?.trim().isNotEmpty ?? false;
          if (!hasText && child.children.isEmpty) {
            continue; // Skip empty BR tags
          }
        }

        // If the child is a nested list, it stays outside the label
        if (child is html.Element &&
            (child.tagName == 'UL' || child.tagName == 'OL')) {
          // Append the label if it hasn't been appended yet
          if (label.parent == null) {
            li.append(label);
          }
          // Append the nested list
          li.append(child);
        } else {
          // Append content to the label
          if (child is html.Text) {
            // For text nodes, preserve them even if whitespace
            // (they may contain important spacing between formatted elements)
            // But skip leading whitespace-only nodes
            final text = child.text ?? '';
            if (text.trim().isEmpty && !hasContent) {
              continue; // Skip leading whitespace
            }
            if (!hasContent && text.trim().isNotEmpty) {
              // Add space before first content
              label.appendText(' ');
              hasContent = true;
            }
            label.append(child);
          } else {
            // For other elements, add initial space if this is first content
            if (!hasContent) {
              label.appendText(' ');
              hasContent = true;
            }
            label.append(child);
          }
        }
      }

      // Ensure label is appended if there were no nested lists
      if (label.parent == null) {
        li.append(label);
      }
    }
  }

  /// Process lists to ensure proper nesting and remove unnecessary attributes
  void _processLists(html.Document doc) {
    final lists = doc.querySelectorAll('ul, ol');

    for (final list in lists) {
      // Remove inline styles that are not semantic
      list.attributes.remove('style');

      // Process list items
      final items = list.querySelectorAll('li');
      for (final item in items) {
        // Remove inline styles unless they're for checkboxes
        if (!item.attributes.containsKey('data-checked') &&
            item.style.listStyleType != 'none') {
          item.attributes.remove('style');
        }
      }
    }
  }

  /// Process images to ensure clean src attributes
  void _processImages(html.Document doc) {
    final images = doc.querySelectorAll('img');

    for (final img in images) {
      // Remove inline styles - let CSS handle sizing
      img.attributes.remove('style');

      // Ensure alt attribute exists (accessibility)
      if (!img.attributes.containsKey('alt')) {
        img.attributes['alt'] = 'Image';
      }

      // Note: We preserve src as-is (URLs or file paths)
      // Avoid base64 conversion - keep original paths
    }
  }

  /// Process code blocks to use semantic pre/code tags
  void _processCodeBlocks(html.Document doc) {
    // Find pre elements
    final preElements = doc.querySelectorAll('pre');

    for (final pre in preElements) {
      // Remove inline styles (no syntax highlighting, keep semantic)
      pre.attributes.remove('style');

      // Ensure code tag is nested inside pre
      if (pre.children.isEmpty || pre.children.first.tagName != 'CODE') {
        final code = html.Element.tag('code');
        // Move all children into code element
        final children = List<html.Node>.from(pre.nodes);
        pre.nodes.clear();
        for (final child in children) {
          code.append(child);
        }
        pre.append(code);
      }
    }
  }

  /// Remove empty elements that don't contribute to content
  void _removeEmptyElements(html.Document doc) {
    // Remove empty BR tags
    final brElements = doc.querySelectorAll('br');
    for (final br in brElements.toList()) {
      final parent = br.parent;
      if (parent != null) {
        // Check if BR is truly empty (no attributes, no meaningful siblings)
        final hasAttributes = br.attributes.isNotEmpty;
        if (!hasAttributes) {
          final siblings = parent.children;
          // Only remove if it's a standalone BR with no purpose
          if (siblings.length == 1 && siblings.first == br) {
            br.remove();
          }
        }
      }
    }

    // Remove empty labels (should not exist per requirements)
    final labels = doc.querySelectorAll('label');
    for (final label in labels.toList()) {
      final isEmpty = label.text?.trim().isEmpty ?? true;
      final hasOnlyCheckbox =
          label.children.length == 1 &&
          label.children.first is html.InputElement;

      if (isEmpty && !hasOnlyCheckbox) {
        label.remove();
      }
    }

    // Remove empty paragraphs
    final paragraphs = doc.querySelectorAll('p');
    for (final p in paragraphs.toList()) {
      final isEmpty = p.text?.trim().isEmpty ?? true;
      final hasNoChildren = p.children.isEmpty;

      if (isEmpty && hasNoChildren) {
        p.remove();
      }
    }
  }
}
