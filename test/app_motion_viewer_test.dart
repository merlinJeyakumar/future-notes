import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/features/dashboard/widgets/attachment_strip.dart';
import 'package:flutter_application_1/features/dashboard/widgets/attachment_viewer.dart';
import 'support/editor_harness.dart';
import 'attachment_strip_test.dart' show FakeOpenCache, FakeDesktop;

class _Player implements AttachmentMediaPlayer {
  int pauses = 0;
  int disposals = 0;
  @override
  Widget build(BuildContext context) => const Text('Synthetic player surface');
  @override
  Future<void> play() async {}
  @override
  Future<void> pause() async {
    pauses++;
  }

  @override
  Future<void> dispose() async {
    disposals++;
  }
}

void main() {
  for (final revokeDuringClose in [false, true]) {
    testWidgets(
      'viewer pauses on dismissal; security removal during reverse=$revokeDuringClose',
      (tester) async {
        final cache = FakeOpenCache();
        final desktop = FakeDesktop();
        final player = _Player();
        final h = await EditorHarness.create(
          attachmentOpenCache: cache,
          desktopActions: desktop,
        );
        h.seed(
          'synthetic',
          h.note(
            'synthetic',
            'body',
            attachments: [
              {'id': 'video', 'fileName': 'synthetic.mp4', 'size': 9000000},
            ],
          ),
        );
        await h.editor.loadNote('synthetic');
        try {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: AttachmentStrip(
                  viewModel: h.editor,
                  playerFactory: (_) => player,
                ),
              ),
            ),
          );
          await tester.tap(find.byKey(const ValueKey('attachment-open-video')));
          await tester.pumpAndSettle();
          expect(cache.opens, 1);
          await tester.tap(find.byTooltip('Close preview'));
          await tester.pump();
          expect(player.pauses, 1);
          expect(player.disposals, 0);
          await tester.pump(const Duration(milliseconds: 60));
          expect(find.text('Synthetic player surface'), findsOneWidget);
          if (revokeDuringClose) {
            await h.editor.closeAttachmentCache();
            await tester.pump();
            expect(find.text('Synthetic player surface'), findsNothing);
          }
          await tester.pumpAndSettle();
          expect(player.disposals, 1);
          expect(find.byType(AttachmentViewer), findsNothing);
          expect(h.files.writeAttempts, 0);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          h.disposeEditor();
          await tester.pump(const Duration(seconds: 3));
          await tester.runAsync(h.dispose);
        }
      },
    );
  }
}
