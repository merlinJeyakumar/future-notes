import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:universal_html/parsing.dart';

/// Interface for PDF export service
abstract class IPdfService {
  Future<Uint8List> exportToPdf({
    required String htmlContent,
    required String title,
  });
}

/// Service for generating PDF documents from HTML content
/// Uses the pdf package directly for cross-platform PDF generation
class PdfService implements IPdfService {
  @override
  Future<Uint8List> exportToPdf({
    required String htmlContent,
    required String title,
  }) async {
    print("DEBUG PDF: Starting HTML to PDF conversion...");

    final pdf = pw.Document();

    // Parse HTML and convert to PDF widgets
    final widgets = _htmlToPdfWidgets(htmlContent, title);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.copyWith(
          marginTop: 2.0 * PdfPageFormat.cm,
          marginBottom: 2.0 * PdfPageFormat.cm,
          marginLeft: 2.0 * PdfPageFormat.cm,
          marginRight: 2.0 * PdfPageFormat.cm,
        ),
        build: (context) => widgets,
      ),
    );

    final pdfBytes = await pdf.save();
    print("DEBUG PDF: Conversion completed, bytes: ${pdfBytes.length}");

    return pdfBytes;
  }

  /// Convert HTML content to PDF widgets
  List<pw.Widget> _htmlToPdfWidgets(String html, String title) {
    final widgets = <pw.Widget>[];

    // Add title
    widgets.add(
      pw.Header(
        level: 0,
        child: pw.Text(
          title,
          style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
        ),
      ),
    );
    widgets.add(pw.SizedBox(height: 16));

    // Parse HTML and extract content
    final document = parseHtmlDocument(html);
    final body = document.body;

    if (body != null) {
      _processNode(body, widgets);
    } else {
      // Fallback: treat as plain text
      widgets.add(pw.Text(html.replaceAll(RegExp(r'<[^>]*>'), '')));
    }

    return widgets;
  }

  /// Recursively process HTML nodes and convert to PDF widgets
  void _processNode(dynamic node, List<pw.Widget> widgets) {
    if (node.nodeType == 3) {
      // Text node
      final text = node.text?.trim() ?? '';
      if (text.isNotEmpty) {
        widgets.add(pw.Text(text));
      }
      return;
    }

    final tagName = (node.localName ?? '').toLowerCase();

    switch (tagName) {
      case 'h1':
        widgets.add(pw.Header(level: 1, text: _getTextContent(node)));
        break;
      case 'h2':
        widgets.add(pw.Header(level: 2, text: _getTextContent(node)));
        break;
      case 'h3':
        widgets.add(pw.Header(level: 3, text: _getTextContent(node)));
        break;
      case 'p':
        final content = _buildInlineContent(node);
        if (content.isNotEmpty) {
          widgets.add(pw.Paragraph(text: content));
        }
        break;
      case 'br':
        widgets.add(pw.SizedBox(height: 8));
        break;
      case 'ul':
        _processListItems(node, widgets, ordered: false);
        break;
      case 'ol':
        _processListItems(node, widgets, ordered: true);
        break;
      case 'li':
        // Check for checkbox
        final dataChecked = node.getAttribute('data-checked');
        String prefix = '• ';
        if (dataChecked == 'true') {
          prefix = '[x] ';
        } else if (dataChecked == 'false') {
          prefix = '[ ] ';
        }
        widgets.add(
          pw.Padding(
            padding: const pw.EdgeInsets.only(left: 16, bottom: 4),
            child: pw.Text('$prefix${_getTextContent(node)}'),
          ),
        );
        break;
      case 'blockquote':
        widgets.add(
          pw.Container(
            decoration: const pw.BoxDecoration(
              border: pw.Border(
                left: pw.BorderSide(width: 3, color: PdfColors.grey400),
              ),
            ),
            padding: const pw.EdgeInsets.only(left: 12),
            margin: const pw.EdgeInsets.symmetric(vertical: 8),
            child: pw.Text(
              _getTextContent(node),
              style: pw.TextStyle(
                fontStyle: pw.FontStyle.italic,
                color: PdfColors.grey700,
              ),
            ),
          ),
        );
        break;
      case 'pre':
      case 'code':
        widgets.add(
          pw.Container(
            decoration: pw.BoxDecoration(
              color: PdfColors.grey100,
              borderRadius: pw.BorderRadius.circular(4),
            ),
            padding: const pw.EdgeInsets.all(8),
            margin: const pw.EdgeInsets.symmetric(vertical: 8),
            child: pw.Text(
              _getTextContent(node),
              style: pw.TextStyle(font: pw.Font.courier(), fontSize: 10),
            ),
          ),
        );
        break;
      case 'strong':
      case 'b':
        widgets.add(
          pw.Text(
            _getTextContent(node),
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          ),
        );
        break;
      case 'em':
      case 'i':
        widgets.add(
          pw.Text(
            _getTextContent(node),
            style: pw.TextStyle(fontStyle: pw.FontStyle.italic),
          ),
        );
        break;
      case 'input':
        // Handle checkbox inputs
        final type = node.getAttribute('type');
        if (type == 'checkbox') {
          final checked = node.hasAttribute('checked');
          widgets.add(pw.Text(checked ? '[x] ' : '[ ] '));
        }
        break;
      case 'div':
      case 'span':
      case 'body':
      case 'html':
        // Process children
        for (final child in node.children) {
          _processNode(child, widgets);
        }
        break;
      default:
        // Try to extract text content for unknown elements
        final text = _getTextContent(node);
        if (text.isNotEmpty) {
          widgets.add(pw.Text(text));
        }
    }
  }

  /// Process list items (ordered or unordered)
  void _processListItems(
    dynamic listNode,
    List<pw.Widget> widgets, {
    required bool ordered,
  }) {
    int index = 1;
    for (final child in listNode.children) {
      if ((child.localName ?? '').toLowerCase() == 'li') {
        final dataChecked = child.getAttribute('data-checked');
        String prefix;
        if (dataChecked == 'true') {
          prefix = '[x] ';
        } else if (dataChecked == 'false') {
          prefix = '[ ] ';
        } else if (ordered) {
          prefix = '$index. ';
          index++;
        } else {
          prefix = '• ';
        }

        widgets.add(
          pw.Padding(
            padding: const pw.EdgeInsets.only(left: 16, bottom: 4),
            child: pw.Text('$prefix${_getTextContent(child)}'),
          ),
        );
      }
    }
  }

  /// Get text content from a node, stripping HTML tags
  String _getTextContent(dynamic node) {
    if (node.nodeType == 3) {
      return node.text ?? '';
    }
    final buffer = StringBuffer();
    for (final child in node.nodes) {
      buffer.write(_getTextContent(child));
    }
    return buffer.toString().trim();
  }

  /// Build inline content for paragraph-like elements
  String _buildInlineContent(dynamic node) {
    return _getTextContent(node);
  }
}
