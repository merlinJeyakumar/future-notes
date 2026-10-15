import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/core/operations/operation_result.dart';
import 'package:flutter_application_1/core/storage/attachment_open_cache.dart';
import 'package:flutter_application_1/core/storage/note_reference.dart';
import 'package:flutter_application_1/features/dashboard/models/note_model.dart';
import 'package:flutter_application_1/features/dashboard/widgets/attachment_strip.dart';
import 'package:flutter_application_1/features/dashboard/widgets/attachment_viewer.dart';
import 'support/editor_harness.dart';

class _GifCache extends AttachmentOpenCache {
  _GifCache(this.path)
    : super(
        rootResolver: () async => throw StateError('No native cache'),
        sourceResolver: (_, _) async => throw StateError('No native source'),
      );
  final String path;
  CachedAttachmentFile? file;
  int prepares = 0;
  @override
  Future<void> initialize() async {}
  @override
  Future<OperationResult<CachedAttachmentFile>> prepare(
    NoteReference reference,
    AttachmentModel attachment,
    int credentialGeneration, {
    String? password,
    dynamic onProgress,
  }) async {
    prepares++;
    file = CachedAttachmentFile(path, 129, 'synthetic');
    return OperationResult.success(file);
  }

  @override
  CachedAttachmentFile? peek(
    NoteReference reference,
    String id,
    int credentials,
  ) => file;
  @override
  Future<CacheCleanupResult> close() async {
    file = null;
    return const CacheCleanupResult(0);
  }
}

Finder _rawInside(Finder parent) =>
    find.descendant(of: parent, matching: find.byType(RawImage));
Future<void> _decodeReady(WidgetTester tester, Finder parent) async {
  for (var i = 0; i < 100; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
    final raw = _rawInside(parent);
    if (raw.evaluate().isNotEmpty &&
        tester.widget<RawImage>(raw.first).image != null)
      return;
  }
  fail('Synthetic GIF did not decode within the bounded wait.');
}

Future<String> _pixel(WidgetTester tester, Finder parent) async {
  final image = tester
      .widget<RawImage>(_rawInside(parent).first)
      .image!
      .clone();
  try {
    final bytes = await tester.runAsync(
      () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
    );
    return '${bytes!.getUint8(0)},${bytes.getUint8(1)},${bytes.getUint8(2)}';
  } finally {
    image.dispose();
  }
}

Future<void> _advance(WidgetTester tester, Duration duration) async {
  await tester.pump(duration);
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 10)),
  );
  await tester.pump();
}

Future<void> _expectChanged(
  WidgetTester tester,
  Finder parent,
  String before,
) async {
  for (var i = 0; i < 30; i++) {
    await _advance(tester, const Duration(milliseconds: 50));
    if (await _pixel(tester, parent) != before) return;
  }
  fail('Opened synthetic GIF did not advance a decoded frame.');
}

void main() {
  testWidgets(
    'GIF thumbnail stays still; opened GIF really animates, pauses and resumes without video backend',
    (tester) async {
      final cache = _GifCache(
        File('test/fixtures/animated-two-frame.gif').absolute.path,
      );
      final h = await EditorHarness.create(attachmentOpenCache: cache);
      h.seed(
        'synthetic',
        h.note(
          'synthetic',
          'body',
          attachments: [
            {'id': 'gif', 'fileName': 'sample.GIF', 'size': 129},
          ],
        ),
      );
      await h.editor.loadNote('synthetic');
      try {
        // Prime only the completed file cache, just as after a previous Open.
        await h.editor.openAttachment(h.editor.attachments.single);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AttachmentStrip(
                viewModel: h.editor,
                playerFactory: (_) =>
                    throw StateError('GIF must never use native video backend'),
              ),
            ),
          ),
        );
        final strip = find.byType(AttachmentStrip);
        await _decodeReady(tester, strip);
        final thumbnail = await _pixel(tester, strip);
        for (var i = 0; i < 6; i++)
          await _advance(tester, const Duration(milliseconds: 100));
        expect(await _pixel(tester, strip), thumbnail);
        expect(cache.prepares, 1);
        await tester.tap(find.byKey(const ValueKey('attachment-open-gif')));
        await tester.pump(const Duration(milliseconds: 250));
        final viewer = find.byType(AttachmentViewer);
        await _decodeReady(tester, viewer);
        expect(find.byTooltip('Pause GIF'), findsOneWidget);
        final provider =
            tester
                    .widget<Image>(
                      find.descendant(of: viewer, matching: find.byType(Image)),
                    )
                    .image
                as ResizeImage;
        expect(provider.width, inInclusiveRange(1, 2048));
        expect(provider.height, inInclusiveRange(1, 2048));
        final initial = await _pixel(tester, viewer);
        await _expectChanged(tester, viewer, initial);
        expect(await _pixel(tester, strip), thumbnail);
        await tester.tap(find.byKey(const ValueKey('gif-playback-preview')));
        await tester.pump();
        expect(find.byTooltip('Play GIF'), findsOneWidget);
        final paused = await _pixel(tester, viewer);
        for (var i = 0; i < 6; i++)
          await _advance(tester, const Duration(milliseconds: 100));
        expect(await _pixel(tester, viewer), paused);
        await tester.tap(find.byKey(const ValueKey('gif-playback-preview')));
        await tester.pump();
        await _expectChanged(tester, viewer, paused);
        await h.editor.pauseAttachmentViewers();
        await tester.pump();
        final hiddenPause = await _pixel(tester, viewer);
        await _advance(tester, const Duration(milliseconds: 500));
        expect(await _pixel(tester, viewer), hiddenPause);
        await h.editor.closeAttachmentCache();
        await tester.pumpAndSettle();
        expect(find.byType(AttachmentViewer), findsNothing);
        expect(h.files.writeAttempts, 0);
        expect(h.encryption.binaryDecryptCalls, 0);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        h.disposeEditor();
        await tester.pump(const Duration(seconds: 3));
        await tester.runAsync(h.dispose);
      }
    },
  );
  testWidgets('corrupt GIF reports preview failure with system fallback', (
    tester,
  ) async {
    final h = await EditorHarness.create();
    final file = File('${h.run.path}/invalid.gif')
      ..writeAsStringSync('Synthetic invalid GIF');
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AttachmentViewer(
              viewModel: h.editor,
              attachment: AttachmentModel(id: 'gif', fileName: 'sample.gif'),
              file: CachedAttachmentFile(
                file.path,
                file.lengthSync(),
                'synthetic',
              ),
              playerFactory: (_) => throw StateError('No video for GIF'),
            ),
          ),
        ),
      );
      for (
        var i = 0;
        i < 100 && find.text('GIF preview unavailable.').evaluate().isEmpty;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      expect(find.text('GIF preview unavailable.'), findsOneWidget);
      expect(find.text('Open in system app'), findsOneWidget);
      expect(h.files.writeAttempts, 0);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      h.disposeEditor();
      await tester.pump(const Duration(seconds: 3));
      await tester.runAsync(h.dispose);
    }
  });
}
