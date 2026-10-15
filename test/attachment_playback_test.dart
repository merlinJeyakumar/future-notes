import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/core/storage/attachment_open_cache.dart';
import 'package:flutter_application_1/features/dashboard/models/note_model.dart';
import 'package:flutter_application_1/features/dashboard/widgets/attachment_viewer.dart';
import 'package:flutter_application_1/features/dashboard/widgets/attachment_document_preview.dart';
import 'support/editor_harness.dart';

class _PlaybackSpy implements AttachmentMediaPlayer {
  _PlaybackSpy({this.audio = false, this.fail = false, this.gate});
  final bool audio;
  final bool fail;
  final Completer<void>? gate;
  final playing = ValueNotifier(false);
  int starts = 0;
  int pauses = 0;
  int disposals = 0;
  @override
  Future<void> play() async {
    starts++;
    if (gate != null) await gate!.future;
    if (fail) throw StateError('Synthetic playback failure');
    if (disposals == 0) playing.value = true;
  }

  @override
  Future<void> pause() async {
    pauses++;
    playing.value = false;
  }

  @override
  Future<void> dispose() async {
    if (disposals == 0) {
      disposals++;
      playing.value = false;
    }
  }

  @override
  Widget build(BuildContext context) => audio
      ? ValueListenableBuilder<bool>(
          valueListenable: playing,
          builder: (context, value, _) => AudioAttachmentThumbnail(
            playing: value,
            onToggle: () => unawaited(value ? pause() : play()),
          ),
        )
      : const Text('Synthetic media surface');
}

class _DocumentStub implements AttachmentDocumentRenderer {
  @override
  Future<void> load() async {}
  @override
  Future<void> dispose() async {}
  @override
  Widget build(BuildContext context) => const Text('Document preview');
}

Future<void> _show(
  WidgetTester tester,
  EditorHarness h,
  String name,
  AttachmentPlayerFactory factory, {
  String? filePath,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: TextButton(
          onPressed: () => showDialog<void>(
            context: tester.element(find.text('Open fixture')),
            builder: (_) => AttachmentViewer(
              viewModel: h.editor,
              attachment: AttachmentModel(
                id: 'synthetic',
                fileName: name,
                size: 1024,
              ),
              file: CachedAttachmentFile(
                filePath ?? 'D:/synthetic-cache/$name',
                1024,
                'synthetic',
              ),
              playerFactory: factory,
              documentFactory: (_, _, _) => _DocumentStub(),
            ),
          ),
          child: const Text('Open fixture'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open fixture'));
  await tester.pumpAndSettle();
}

void main() {
  for (final name in ['sample.mp4', 'sample.wav', 'sample.mp3']) {
    testWidgets(
      'Open requests autoplay once for $name and cleanup stops its player',
      (tester) async {
        final h = await EditorHarness.create();
        final audio = name.endsWith('.wav') || name.endsWith('.mp3');
        final player = _PlaybackSpy(audio: audio);
        var creations = 0;
        try {
          await _show(tester, h, name, (_) {
            creations++;
            return player;
          });
          expect(creations, 1);
          expect(player.starts, 1);
          expect(player.playing.value, isTrue);
          if (audio) {
            expect(find.byIcon(Icons.music_note), findsOneWidget);
            expect(find.byTooltip('Pause audio'), findsOneWidget);
            final thumbnail = find.byKey(
              const ValueKey('audio-playback-thumbnail'),
            );
            await tester.tapAt(tester.getCenter(thumbnail));
            await tester.pumpAndSettle();
            expect(player.pauses, 1);
            expect(find.byTooltip('Play audio'), findsOneWidget);
            await tester.tapAt(tester.getCenter(thumbnail));
            await tester.pumpAndSettle();
            expect(player.starts, 2);
            expect(find.byTooltip('Pause audio'), findsOneWidget);
          }
          await h.editor.pauseAttachmentViewers();
          await tester.pump();
          expect(player.playing.value, isFalse);
          await h.editor.closeAttachmentCache();
          await tester.pumpAndSettle();
          expect(player.disposals, 1);
          expect(find.byType(AttachmentViewer), findsNothing);
          expect(h.files.writeAttempts, 0);
          expect(h.encryption.binaryDecryptCalls, 0);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          h.disposeEditor();
          await tester.pump(const Duration(seconds: 3));
          player.playing.dispose();
          await tester.runAsync(h.dispose);
        }
      },
    );
  }
  for (final name in ['sample.png', 'sample.pdf']) {
    testWidgets('$name never starts a media player', (tester) async {
      final h = await EditorHarness.create();
      var creations = 0;
      final file = File('${h.run.path}/$name');
      if (name.endsWith('png'))
        file.writeAsBytesSync(
          base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=',
          ),
        );
      try {
        await _show(tester, h, name, (_) {
          creations++;
          return _PlaybackSpy();
        }, filePath: file.path);
        expect(creations, 0);
        expect(h.files.writeAttempts, 0);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        h.disposeEditor();
        await tester.pump(const Duration(seconds: 3));
        await tester.runAsync(h.dispose);
      }
    });
  }
  testWidgets(
    'autoplay failure is actionable and keeps attachment actions available',
    (tester) async {
      final h = await EditorHarness.create();
      final player = _PlaybackSpy(fail: true);
      try {
        await _show(tester, h, 'sample.mp4', (_) => player);
        expect(find.text('Playback unavailable.'), findsOneWidget);
        expect(find.text('Open in system app'), findsOneWidget);
        expect(find.byType(AttachmentMoreButton), findsOneWidget);
        await tester.tap(find.byTooltip('Close preview'));
        await tester.pumpAndSettle();
        expect(player.disposals, 1);
        expect(tester.takeException(), isNull);
        expect(h.files.writeAttempts, 0);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        h.disposeEditor();
        await tester.pump(const Duration(seconds: 3));
        player.playing.dispose();
        await tester.runAsync(h.dispose);
      }
    },
  );
  testWidgets(
    'late start failure after close cannot reopen or replace the editor',
    (tester) async {
      final h = await EditorHarness.create();
      final gate = Completer<void>();
      final player = _PlaybackSpy(gate: gate);
      try {
        await _show(tester, h, 'sample.mp4', (_) => player);
        expect(player.starts, 1);
        await h.editor.closeAttachmentCache();
        await tester.pumpAndSettle();
        gate.completeError(StateError('Synthetic late start failure'));
        await tester.pumpAndSettle();
        expect(find.byType(AttachmentViewer), findsNothing);
        expect(find.text('Playback unavailable.'), findsNothing);
        expect(player.disposals, 1);
        expect(tester.takeException(), isNull);
        expect(h.files.writeAttempts, 0);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        h.disposeEditor();
        await tester.pump(const Duration(seconds: 3));
        player.playing.dispose();
        await tester.runAsync(h.dispose);
      }
    },
  );
}
