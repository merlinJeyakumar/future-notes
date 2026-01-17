import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:htmltopdfwidgets/htmltopdfwidgets.dart';

/// Interface for PDF export service
abstract class IPdfService {
  Future<Uint8List> exportToPdf({
    required String htmlContent,
    required String title,
  });
}

/// Service for generating PDF documents from HTML content
/// Uses htmltopdfwidgets for pure Dart cross-platform HTML to PDF conversion
class PdfService implements IPdfService {
  @override
  Future<Uint8List> exportToPdf({
    required String htmlContent,
    required String title,
  }) async {
    print("DEBUG PDF: Starting HTML to PDF conversion...");

    final pdf = pw.Document();

    // Preprocess HTML to handle checkboxes properly
    final processedHtml = _preprocessHtml(htmlContent);

    // Wrap content with title for conversion
    final fullHtml = '<h1>$title</h1>\n$processedHtml';

    // Convert HTML to PDF widgets
    final widgets = await HTMLToPdf().convert(fullHtml);

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

  /// Preprocess HTML to convert checkbox inputs to text symbols
  /// This is necessary because PDF converters don't render HTML checkboxes
  String _preprocessHtml(String html) {
    String processed = html;

    // Convert checked checkboxes to [x]
    // Pattern: <input type="checkbox" checked> or <input checked type="checkbox">
    final checkedPattern1 = RegExp(
      r'<input[^>]*type\s*=\s*["\x27]checkbox["\x27][^>]*checked[^>]*/?>',
      caseSensitive: false,
    );
    final checkedPattern2 = RegExp(
      r'<input[^>]*checked[^>]*type\s*=\s*["\x27]checkbox["\x27][^>]*/?>',
      caseSensitive: false,
    );

    processed = processed.replaceAll(checkedPattern1, '<b>[x]</b>');
    processed = processed.replaceAll(checkedPattern2, '<b>[x]</b>');

    // Convert unchecked checkboxes to [ ]
    final uncheckedPattern = RegExp(
      r'<input[^>]*type\s*=\s*["\x27]checkbox["\x27][^>]*/?>',
      caseSensitive: false,
    );
    processed = processed.replaceAll(uncheckedPattern, '<b>[ ]</b>');

    // Handle data-checked attribute (used by Quill editor)
    final dataCheckedTrue = RegExp(
      r'<li[^>]*data-checked\s*=\s*["\x27]true["\x27][^>]*>',
      caseSensitive: false,
    );
    final dataCheckedFalse = RegExp(
      r'<li[^>]*data-checked\s*=\s*["\x27]false["\x27][^>]*>',
      caseSensitive: false,
    );

    processed = processed.replaceAll(dataCheckedTrue, '<li><b>[x]</b> ');
    processed = processed.replaceAll(dataCheckedFalse, '<li><b>[ ]</b> ');

    return processed;
  }
}
