import 'dart:async';
import 'dart:io';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
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
    'native PDF zoom stays centered, preserves pan and Fit restores the full page',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(900, 680);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
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
        final transform = find.byKey(const ValueKey('pdf-viewport-transform'));
        final viewport = find
            .ancestor(of: transform, matching: find.byType(GestureDetector))
            .first;
        final controller =
            tester.widget<AnimatedBuilder>(transform).listenable
                as TransformationController;
        Offset sceneCenter() =>
            controller.toScene(tester.getSize(viewport).center(Offset.zero));
        void expectOffset(Offset actual, Offset expected) {
          expect(actual.dx, closeTo(expected.dx, .01));
          expect(actual.dy, closeTo(expected.dy, .01));
        }

        void expectFit() {
          final area = tester.getRect(viewport).deflate(12);
          final page = tester.getRect(find.byType(RawImage));
          expectOffset(page.center, area.center);
          expect(page.left, greaterThanOrEqualTo(area.left - .01));
          expect(page.top, greaterThanOrEqualTo(area.top - .01));
          expect(page.right, lessThanOrEqualTo(area.right + .01));
          expect(page.bottom, lessThanOrEqualTo(area.bottom + .01));
          expect(controller.value.getMaxScaleOnAxis(), closeTo(1, .0001));
        }

        expectFit();
        final initialCenter = sceneCenter();
        for (var i = 0; i < 3; i++) {
          await tester.tap(find.byTooltip('Zoom in'));
          await tester.pump();
          expectOffset(sceneCenter(), initialCenter);
          expectOffset(
            tester.getRect(find.byType(RawImage)).center,
            tester.getRect(viewport).center,
          );
        }
        expect(controller.value.getMaxScaleOnAxis(), greaterThan(1));
        await tester.drag(viewport, const Offset(-30, -20));
        await tester.pumpAndSettle();
        final pannedCenter = sceneCenter();
        expect((pannedCenter - initialCenter).distance, greaterThan(1));
        for (final button in ['Zoom in', 'Zoom out']) {
          await tester.tap(find.byTooltip(button));
          await tester.pump();
          expectOffset(sceneCenter(), pannedCenter);
        }
        // Windows can deliver two-finger scrolling as a mouse-style wheel.
        // Both wheel encodings must pan once, without changing magnification.
        for (final kind in [
          PointerDeviceKind.mouse,
          PointerDeviceKind.trackpad,
        ]) {
          final pointer = TestPointer(20 + kind.index, kind);
          await tester.sendEventToBinding(
            pointer.hover(tester.getCenter(viewport)),
          );
          final scaleBefore = controller.value.getMaxScaleOnAxis();
          final before = controller.value.getTranslation();
          await tester.sendEventToBinding(pointer.scroll(const Offset(12, 18)));
          await tester.pump();
          final after = controller.value.getTranslation();
          expect(
            controller.value.getMaxScaleOnAxis(),
            closeTo(scaleBefore, .001),
          );
          expect(after.x, closeTo(before.x - 12, .01));
          expect(after.y, closeTo(before.y - 18, .01));
          await tester.sendEventToBinding(pointer.scroll(const Offset(9, 0)));
          await tester.pump();
          expect(
            controller.value.getTranslation().x,
            closeTo(after.x - 9, .01),
          );
        }
        final offCenter = tester.getTopLeft(viewport) + const Offset(70, 65);
        final discretePinch = TestPointer(40, PointerDeviceKind.trackpad);
        await tester.sendEventToBinding(discretePinch.hover(offCenter));
        final beforeDiscrete = sceneCenter();
        final beforeDiscreteScale = controller.value.getMaxScaleOnAxis();
        await tester.sendEventToBinding(discretePinch.scale(1.2));
        await tester.pump();
        expect(
          controller.value.getMaxScaleOnAxis(),
          closeTo(beforeDiscreteScale * 1.2, .001),
        );
        expectOffset(sceneCenter(), beforeDiscrete);
        final nativePinch = TestPointer(41, PointerDeviceKind.trackpad);
        final beforePinch = sceneCenter();
        final beforePinchScale = controller.value.getMaxScaleOnAxis();
        await tester.sendEventToBinding(nativePinch.panZoomStart(offCenter));
        // Hardware pinches can begin as a pan, then report simultaneous scale
        // and sizeable centroid movement. None of that should pull zoom aside.
        await tester.sendEventToBinding(
          nativePinch.panZoomUpdate(offCenter, pan: const Offset(-8, 3)),
        );
        final transformCenters = <Offset>[];
        void recordTransform() => transformCenters.add(sceneCenter());
        controller.addListener(recordTransform);
        for (final update in [
          (scale: 1.1, pan: const Offset(-80, 20)),
          (scale: 1.35, pan: const Offset(-170, 35)),
          (scale: 1.35, pan: const Offset(-220, 40)),
          (scale: .95, pan: const Offset(-260, 45)),
          (scale: 1.0, pan: const Offset(-290, 50)),
          (scale: 1.05, pan: const Offset(-310, 55)),
        ]) {
          await tester.sendEventToBinding(
            nativePinch.panZoomUpdate(
              offCenter,
              scale: update.scale,
              pan: update.pan,
            ),
          );
          await tester.pump();
          expectOffset(sceneCenter(), beforePinch);
          expect(
            controller.value.getMaxScaleOnAxis(),
            closeTo(beforePinchScale * update.scale, .001),
          );
          // Wheel-style signals can be interleaved with native updates. They
          // must neither pan a pinch nor reset its cumulative scale/anchor.
          final interleaved = TestPointer(44, PointerDeviceKind.trackpad);
          await tester.sendEventToBinding(interleaved.hover(offCenter));
          await tester.sendEventToBinding(
            interleaved.scroll(const Offset(70, 15)),
          );
          await tester.pump();
          expectOffset(sceneCenter(), beforePinch);
          for (final center in transformCenters) {
            expectOffset(center, beforePinch);
          }
          transformCenters.clear();
        }
        controller.removeListener(recordTransform);
        await tester.sendEventToBinding(nativePinch.panZoomEnd());
        await tester.pumpAndSettle();
        expect(
          controller.value.getMaxScaleOnAxis(),
          closeTo(beforePinchScale * 1.05, .001),
        );
        expectOffset(sceneCenter(), beforePinch);
        final nativePan = TestPointer(42, PointerDeviceKind.trackpad);
        final beforePan = controller.value.getTranslation();
        final beforePanScale = controller.value.getMaxScaleOnAxis();
        await tester.sendEventToBinding(nativePan.panZoomStart(offCenter));
        await tester.sendEventToBinding(
          nativePan.panZoomUpdate(offCenter, pan: const Offset(-10, -15)),
        );
        await tester.sendEventToBinding(
          nativePan.panZoomUpdate(offCenter, pan: const Offset(-35, -45)),
        );
        await tester.sendEventToBinding(nativePan.panZoomEnd());
        await tester.pumpAndSettle();
        expect(
          controller.value.getMaxScaleOnAxis(),
          closeTo(beforePanScale, .001),
        );
        expect(controller.value.getTranslation().x, lessThan(beforePan.x));
        expect(controller.value.getTranslation().y, lessThan(beforePan.y));
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        try {
          final beforeControl = sceneCenter();
          final beforeControlScale = controller.value.getMaxScaleOnAxis();
          final wheel = TestPointer(43, PointerDeviceKind.mouse);
          await tester.sendEventToBinding(wheel.hover(offCenter));
          await tester.sendEventToBinding(wheel.scroll(const Offset(0, -20)));
          await tester.pump();
          expect(
            controller.value.getMaxScaleOnAxis(),
            greaterThan(beforeControlScale),
          );
          expectOffset(sceneCenter(), beforeControl);
        } finally {
          await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        }
        for (var i = 0; i < 8; i++) {
          await tester.tap(find.byTooltip('Zoom in'));
          await tester.pump();
        }
        expect(controller.value.getMaxScaleOnAxis(), closeTo(5, .0001));
        final atLimit = sceneCenter();
        await tester.tap(find.byTooltip('Zoom in'));
        await tester.pump();
        expectOffset(sceneCenter(), atLimit);
        await tester.tap(find.text('Fit page'));
        await tester.pump();
        expectFit();
        await tester.tap(find.byTooltip('Zoom out'));
        await tester.pump();
        expectFit();
        // Fit follows the current viewport rather than an old dialog size.
        for (final size in [const Size(360, 640), const Size(1200, 500)]) {
          tester.view.physicalSize = size;
          await tester.pumpAndSettle();
          await tester.tap(find.byTooltip('Zoom in'));
          await tester.pump();
          await tester.tap(find.text('Fit page'));
          await tester.pump();
          expectFit();
        }
        await tester.tap(find.byTooltip('Zoom in'));
        await tester.pump();
        await tester.runAsync(() => renderer.goToPage(2));
        await tester.pump();
        expect(find.text('2 / 2'), findsOneWidget);
        expectFit();
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
