import 'dart:async';
import 'dart:io';
import 'package:pdfrx/pdfrx.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/core/storage/attachment_open_cache.dart';
import 'package:flutter_application_1/features/dashboard/models/note_model.dart';
import 'package:flutter_application_1/features/dashboard/widgets/attachment_document_preview.dart';
import 'package:flutter_application_1/features/dashboard/widgets/attachment_viewer.dart';
import 'package:flutter_application_1/features/dashboard/services/office_preview_service.dart';
import 'support/editor_harness.dart';

class _DocumentSpy implements AttachmentDocumentRenderer {
  _DocumentSpy({this.fail = false, this.gate});
  final bool fail;
  final Completer<void>? gate;
  int loads = 0;
  int disposals = 0;
  Future<void>? _disposal;
  @override
  Future<void> load() async {
    loads++;
    await gate?.future;
    if (fail) throw StateError('Synthetic parse failure');
  }

  @override
  Future<void> dispose() => _disposal ??= () async {
    disposals++;
    await gate?.future;
  }();
  @override
  Widget build(BuildContext context) =>
      const Text('Synthetic document surface');
}

Future<void> _show(
  WidgetTester tester,
  EditorHarness h,
  String name,
  AttachmentDocumentFactory factory,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => AttachmentViewer(
                viewModel: h.editor,
                attachment: AttachmentModel(
                  id: 'synthetic-document',
                  fileName: name,
                  size: 1024,
                ),
                file: CachedAttachmentFile(
                  'D:/synthetic-cache/$name',
                  1024,
                  'synthetic',
                ),
                documentFactory: factory,
                playerFactory: (_) =>
                    throw StateError('Documents cannot create a player'),
              ),
            ),
            child: const Text('Open document'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open document'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'native PDF surface supports pages zoom and joined disposal',
    (tester) async {
      final dll =
          Platform.environment['PDFIUM_PATH'] ??
          File('build/windows/x64/runner/Release/pdfium.dll').absolute.path;
      Pdfrx.getCacheDirectory = () => Directory.systemTemp.path;
      await tester.runAsync(() => initializeAttachmentPdf(libraryPath: dll));
      final renderer = NativeAttachmentDocument(
        File('test/fixtures/documents/sample.pdf').absolute.path,
        'sample.pdf',
        () async {},
      );
      try {
        await tester.runAsync(renderer.load);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: Builder(builder: renderer.build)),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('1 / 2'), findsOneWidget);
        expect(find.byType(RawImage), findsOneWidget);
        await tester.runAsync(() => renderer.goToPage(2));
        await tester.pump();
        expect(find.text('2 / 2'), findsOneWidget);
        await tester.tap(find.byTooltip('Zoom in'));
        await tester.pump();
        expect(
          tester
              .widget<InteractiveViewer>(find.byType(InteractiveViewer))
              .transformationController!
              .value
              .getMaxScaleOnAxis(),
          greaterThan(1),
        );
        await tester.runAsync(renderer.dispose);
        await tester.pump();
        expect(find.byType(RawImage), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(renderer.dispose);
      }
    },
    skip: !Platform.isWindows,
  );
  for (final name in [
    'sample.pdf',
    'sample.docx',
    'sample.doc',
    'sample.xls',
    'sample.XLSX',
  ]) {
    testWidgets('$name opens a document surface only after explicit Open', (
      tester,
    ) async {
      final h = await EditorHarness.create();
      final document = _DocumentSpy();
      try {
        var factories = 0;
        await _show(tester, h, name, (path, fileName, openSystem) {
          factories++;
          expect(fileName, name);
          return document;
        });
        expect(factories, 1);
        expect(document.loads, 1);
        expect(find.text('Synthetic document surface'), findsOneWidget);
        expect(find.byType(AttachmentMoreButton), findsOneWidget);
        expect(h.encryption.binaryDecryptCalls, 0);
        expect(h.files.writeAttempts, 0);
        await h.editor.closeAttachmentCache();
        await tester.pumpAndSettle();
        expect(find.byType(AttachmentViewer), findsNothing);
        expect(document.disposals, 1);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        h.disposeEditor();
        await tester.pump(const Duration(seconds: 3));
        await tester.runAsync(h.dispose);
      }
    });
  }

  testWidgets(
    'parse failure is distinct from decryption and preserves More actions',
    (tester) async {
      final h = await EditorHarness.create();
      final document = _DocumentSpy(fail: true);
      try {
        await _show(tester, h, 'bad.doc', (_, _, _) => document);
        expect(find.text('Document preview unavailable.'), findsOneWidget);
        expect(find.text('Open in system app'), findsOneWidget);
        expect(find.byType(AttachmentMoreButton), findsOneWidget);
        expect(h.files.writeAttempts, 0);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        h.disposeEditor();
        await tester.pump(const Duration(seconds: 3));
        await tester.runAsync(h.dispose);
      }
    },
  );

  testWidgets(
    'lock cleanup joins pending parsing and stale completion cannot reopen',
    (tester) async {
      final h = await EditorHarness.create();
      final gate = Completer<void>();
      final document = _DocumentSpy(gate: gate);
      try {
        await _show(tester, h, 'sample.docx', (_, _, _) => document);
        var completed = false;
        final closing = h.editor.closeAttachmentCache().then(
          (_) => completed = true,
        );
        await tester.pump();
        expect(document.disposals, 1);
        expect(completed, false);
        gate.complete();
        await closing;
        await tester.pumpAndSettle();
        expect(completed, true);
        expect(find.byType(AttachmentViewer), findsNothing);
        expect(document.loads, 1);
        expect(tester.takeException(), isNull);
      } finally {
        if (!gate.isCompleted) gate.complete();
        await tester.pumpWidget(const SizedBox.shrink());
        h.disposeEditor();
        await tester.pump(const Duration(seconds: 3));
        await tester.runAsync(h.dispose);
      }
    },
  );

  testWidgets(
    'native Word surface renders text/table and disposes without source writes',
    (tester) async {
      final dll =
          Platform.environment['FN_OFFICE_PREVIEW_DLL'] ??
          File(
            'build/windows/x64/runner/Release/office_oxide.dll',
          ).absolute.path;
      final renderer = NativeAttachmentDocument(
        File('test/fixtures/documents/sample.docx').absolute.path,
        'sample.docx',
        () async {},
        office: OfficePreviewService(libraryPath: dll),
      );
      try {
        await tester.runAsync(renderer.load);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: Builder(builder: renderer.build)),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester
              .getSize(find.byKey(const ValueKey('office-preview-paper')))
              .width,
          lessThanOrEqualTo(760),
        );
        expect(find.byType(Scrollbar), findsNWidgets(2));
        expect(
          find.textContaining('Synthetic document preview', findRichText: true),
          findsOneWidget,
        );
        expect(
          find.textContaining('Table cell', findRichText: true),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.runAsync(renderer.dispose);
        await tester.pump();
        expect(
          find.textContaining('Synthetic document preview', findRichText: true),
          findsNothing,
        );
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(renderer.dispose);
      }
    },
    skip: !Platform.isWindows,
  );
}
