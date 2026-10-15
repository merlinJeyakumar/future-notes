import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/features/dashboard/services/office_preview_service.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:html/parser.dart' as html;
import 'package:flutter_application_1/features/dashboard/widgets/attachment_document_preview.dart';

void main() {
  test(
    'Office table styling preserves header roles and alternates existing rows',
    () {
      final source =
          '<table><tr><th>Actual heading</th></tr><tr><td>Value</td></tr><tr><td>42</td></tr></table>';
      final result = html.parse(sanitizeOfficePreview(source));
      final rows = result.querySelectorAll('tr');
      expect(rows.map((row) => row.text), ['Actual heading', 'Value', '42']);
      expect(result.querySelectorAll('th'), hasLength(1));
      expect(officePreviewStyles(rows[0])!['background-color'], '#ffffff');
      expect(officePreviewStyles(rows[1])!['background-color'], '#f5f7fa');
      expect(
        officePreviewStyles(result.querySelector('th')!)!['font-weight'],
        'bold',
      );
      expect(
        officePreviewStyles(
          result.querySelector('td')!,
        )!.containsKey('font-weight'),
        false,
      );
    },
  );
  final dll =
      Platform.environment['FN_OFFICE_PREVIEW_DLL'] ??
      'build/windows/x64/runner/Release/office_oxide.dll';
  test('HTML is passive, preserves text/tables and cannot load resources', () {
    final result = sanitizeOfficePreview(
      '<p onclick="bad()" style="font-weight:bold;background:url(https://invalid)">Hello</p><table><tr><td colspan="2">Cell</td></tr></table><a href="file:///private">&lt;img src=x&gt;</a><img src="https://invalid"><script>secret()</script><iframe src="https://invalid"></iframe>',
    );
    expect(result, contains('font-weight:bold'));
    expect(result, contains('<table>'));
    expect(result, contains('colspan="2"'));
    expect(result, contains('&lt;img src=x&gt;'));
    for (final text in [
      'onclick',
      'https:',
      'file:',
      '<img',
      '<script',
      '<iframe',
      'secret()',
    ]) {
      expect(result, isNot(contains(text)));
    }
  });

  test('oversized, empty and malformed inputs fail without native parsing', () {
    final root = Directory.systemTemp.createTempSync(
      'future-notes-validation-documents-',
    );
    try {
      final file = File('${root.path}/sample.docx')..writeAsBytesSync([]);
      expect(
        () => validateOfficePreviewSource(file.path),
        throwsA(isA<DocumentPreviewException>()),
      );
      file.openSync(mode: FileMode.write)
        ..truncateSync(OfficePreviewLimits.sourceBytes + 1)
        ..closeSync();
      expect(
        () => validateOfficePreviewSource(file.path),
        throwsA(isA<DocumentPreviewException>()),
      );
      file.writeAsStringSync('not a zip');
      expect(
        () => validateOfficePreviewSource(file.path),
        throwsA(isA<DocumentPreviewException>()),
      );
    } finally {
      root.deleteSync(recursive: true);
    }
  });

  test('expanded ZIP bounds are checked before inflation/native parsing', () {
    final root = Directory.systemTemp.createTempSync(
      'future-notes-validation-documents-',
    );
    try {
      final bytes = Uint8List.fromList(
        ZipEncoder().encode(
          Archive()
            ..addFile(ArchiveFile.string('word/document.xml', '<document/>')),
        ),
      );
      final data = ByteData.sublistView(bytes);
      for (var i = 0; i < bytes.length - 46; i++) {
        if (data.getUint32(i, Endian.little) == 0x02014b50) {
          data.setUint32(
            i + 24,
            OfficePreviewLimits.expandedBytes + 1,
            Endian.little,
          );
          break;
        }
      }
      final file = File('${root.path}/sample.docx')..writeAsBytesSync(bytes);
      expect(
        () => validateOfficePreviewSource(file.path),
        throwsA(isA<DocumentPreviewException>()),
      );
    } finally {
      root.deleteSync(recursive: true);
    }
  });

  for (final extension in ['doc', 'docx', 'xls', 'xlsx']) {
    test(
      'native $extension preview preserves source and reads a Unicode cache path',
      () async {
        final root = Directory.systemTemp.createTempSync(
          'future-notes-validation-documents-',
        );
        try {
          final input = File('test/fixtures/documents/sample.$extension');
          final file = input.copySync('${root.path}/synthetic-é.$extension');
          final before = sha256.convert(file.readAsBytesSync());
          final output = await OfficePreviewService(
            libraryPath: File(dll).absolute.path,
          ).load(file.path);
          expect(output, contains('Synthetic'));
          if (extension.contains('xls')) {
            expect(output, contains('42'));
            expect(output, contains('<table'));
          }
          if (extension == 'docx') expect(output, contains('Table cell'));
          expect(sha256.convert(file.readAsBytesSync()), before);
        } finally {
          root.deleteSync(recursive: true);
        }
      },
      skip: !Platform.isWindows,
    );
  }

  test(
    'native corrupt legacy document reports a preview error',
    () async {
      final root = Directory.systemTemp.createTempSync(
        'future-notes-validation-documents-',
      );
      try {
        final file = File('${root.path}/broken.doc')
          ..writeAsStringSync('broken');
        await expectLater(
          OfficePreviewService(
            libraryPath: File(dll).absolute.path,
          ).load(file.path),
          throwsA(isA<DocumentPreviewException>()),
        );
        expect(file.readAsStringSync(), 'broken');
      } finally {
        root.deleteSync(recursive: true);
      }
    },
    skip: !Platform.isWindows,
  );

  test(
    'missing PDF component fails before starting the engine worker',
    () async {
      await expectLater(
        initializeAttachmentPdf(libraryPath: 'D:/synthetic-missing/pdfium.dll'),
        throwsA(isA<DocumentPreviewException>()),
      );
    },
    skip: !Platform.isWindows,
  );

  test(
    'file-backed PDF renders both pages at bounded dimensions and releases handles',
    () async {
      final pdfium =
          Platform.environment['PDFIUM_PATH'] ??
          File('build/windows/x64/runner/Release/pdfium.dll').absolute.path;
      Pdfrx.pdfiumModulePath = pdfium;
      Pdfrx.getCacheDirectory = () => Directory.systemTemp.path;
      await initializeAttachmentPdf(libraryPath: pdfium);
      final root = Directory.systemTemp.createTempSync(
        'future-notes-validation-documents-',
      );
      final file = File(
        'test/fixtures/documents/sample.pdf',
      ).copySync('${root.path}/sample.pdf');
      try {
        final document = await PdfDocument.openFile(file.path);
        try {
          expect(document.pages.length, 2);
          for (final page in document.pages) {
            final pixels = await page.render(
              width: 256,
              height: 332,
              fullWidth: 256,
              fullHeight: 332,
            );
            expect(pixels, isNotNull);
            try {
              expect(pixels!.pixels.length, 256 * 332 * 4);
            } finally {
              pixels?.dispose();
            }
          }
        } finally {
          await document.dispose();
        }
        file.renameSync('${root.path}/released.pdf');
        await expectLater(
          PdfDocument.openFile('${root.path}/missing.pdf'),
          throwsA(isA<Exception>()),
        );
      } finally {
        root.deleteSync(recursive: true);
      }
    },
    skip: !Platform.isWindows,
  );
}
