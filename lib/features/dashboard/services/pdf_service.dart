import 'package:flutter/foundation.dart';
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
/// Uses htmltopdfwidgets for comprehensive HTML element support
class PdfService implements IPdfService {
  @override
  Future<Uint8List> exportToPdf({
    required String htmlContent,
    required String title,
  }) async {
    debugPrint("DEBUG PDF: Starting HTML to PDF conversion...");

    final pdf = pw.Document();

    // Convert HTML to PDF widgets using htmltopdfwidgets library
    // Using the new Browser Rendering Engine for better CSS support
    final List<pw.Widget> contentWidgets = await HTMLToPdf().convert(
      htmlContent,
      useNewEngine: true,
    );

    // Create title widget
    final titleWidget = pw.Header(
      level: 0,
      child: pw.Text(
        title,
        style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
      ),
    );

    // Combine title with content
    final allWidgets = <pw.Widget>[
      titleWidget,
      pw.SizedBox(height: 16),
      ...contentWidgets,
    ];

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.copyWith(
          marginTop: 2.0 * PdfPageFormat.cm,
          marginBottom: 2.0 * PdfPageFormat.cm,
          marginLeft: 2.0 * PdfPageFormat.cm,
          marginRight: 2.0 * PdfPageFormat.cm,
        ),
        maxPages: 200,
        build: (context) => allWidgets,
      ),
    );

    final pdfBytes = await pdf.save();
    debugPrint("DEBUG PDF: Conversion completed, bytes: ${pdfBytes.length}");

    return pdfBytes;
  }
}
