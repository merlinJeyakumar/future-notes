import 'package:flutter_application_1/features/dashboard/widgets/attachment_viewer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/features/dashboard/models/attachment_job.dart';
import 'package:flutter_application_1/features/dashboard/widgets/content_area.dart';
import 'package:flutter_application_1/main.dart';

import 'support/editor_harness.dart';

void main() {
  testWidgets('inline unlock retries safely and returns focus to the editor', (
    tester,
  ) async {
    final harness = await EditorHarness.create();
    harness.seed(
      'protected',
      harness.note('protected', 'Synthetic body', locked: true),
    );
    await harness.editor.loadNote('protected');
    try {
      await tester.pumpWidget(
        MyApp(
          settings: harness.settings,
          home: Scaffold(
            body: ListenableBuilder(
              listenable: harness.editor,
              builder: (_, _) => ContentArea(viewModel: harness.editor),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(
        tester
            .widget<EditableText>(find.byType(EditableText))
            .focusNode
            .hasFocus,
        isTrue,
      );
      tester.testTextInput.enterText('synthetic-wrong');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(harness.editor.isLocked, isTrue);
      expect(find.textContaining('Could not unlock.'), findsOneWidget);
      expect(harness.files.writeAttempts, 0);
      tester.testTextInput.enterText('synthetic-password');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(harness.editor.isLocked, isFalse);
      expect(find.text('This note is locked'), findsNothing);
      expect(
        harness.editor.quillController.document.toPlainText(),
        contains('Synthetic body'),
      );
      expect(harness.editor.focusNode.hasFocus, isTrue);
      expect(harness.files.writeAttempts, 0);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      harness.disposeEditor();
      await tester.pump(const Duration(seconds: 3));
      await tester.runAsync(harness.dispose);
    }
  });

  for (final width in [1440.0, 700.0]) {
    testWidgets('locked controls follow unlock/relock at width $width', (
      tester,
    ) async {
      final harness = await EditorHarness.create();
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      harness.seed(
        'protected',
        harness.note(
          'protected',
          'body',
          locked: true,
          attachments: [
            {
              'id': 'completed',
              'fileName': 'synthetic-completed.txt',
              'size': 1,
            },
          ],
        ),
      );
      expect((await harness.editor.loadNote('protected')).isSuccess, isTrue);
      final jobs = [
        for (final phase in [
          AttachmentJobPhase.completed,
          AttachmentJobPhase.failed,
        ])
          AttachmentJobState(
            AttachmentJobSnapshot(
              id: phase.name,
              owner: harness.editor.draftSession.generation,
              fileName: 'synthetic-${phase.name}.txt',
              phase: phase,
            ),
          ),
      ];
      harness.editor.attachmentJobsNotifier.value = jobs;
      void expectLocked() {
        expect(find.text('This note is locked'), findsOneWidget);
        expect(find.text('Unlock'), findsOneWidget);
        expect(find.text('Save Note'), findsNothing);
        expect(find.byIcon(Icons.save_rounded), findsNothing);
        expect(find.byTooltip('Note actions'), findsNothing);
        expect(find.byTooltip('Attach file'), findsNothing);
        expect(find.text('Editing'), findsNothing);
        expect(find.textContaining('active operations'), findsNothing);
        expect(find.textContaining('synthetic-'), findsNothing);
        expect(find.byTooltip('Retry'), findsNothing);
        expect(find.text('Dismiss'), findsNothing);
        expect(find.byType(TextField), findsOneWidget);
        expect(
          tester.widget<TextField>(find.byType(TextField)).obscureText,
          isTrue,
        );
        expect(find.byType(Dialog), findsNothing);
        if (width >= 900) {
          expect(find.textContaining('Note date'), findsOneWidget);
        }
      }

      try {
        await tester.pumpWidget(
          MyApp(
            settings: harness.settings,
            home: Scaffold(
              body: ListenableBuilder(
                listenable: harness.editor,
                builder: (_, child) => ContentArea(viewModel: harness.editor),
              ),
            ),
          ),
        );
        expectLocked();
        expect(await harness.editor.unlockNote('wrong-password'), isFalse);
        await tester.pump();
        expectLocked();
        expect(await harness.editor.unlockNote('synthetic-password'), isTrue);
        // Failed jobs cannot originate in a locked session. Model a failure
        // belonging to the newly unlocked owner instead of a stale job.
        jobs.last.update(
          AttachmentJobSnapshot(
            id: 'failed',
            owner: harness.editor.draftSession.generation,
            fileName: 'synthetic-failed.txt',
            phase: AttachmentJobPhase.failed,
          ),
        );
        harness.editor.attachmentJobsNotifier.value = List.of(jobs);
        await tester.pump();
        expect(find.text('This note is locked'), findsNothing);
        expect(find.byTooltip('Note actions'), findsOneWidget);
        expect(find.byTooltip('Attach file'), findsOneWidget);
        expect(find.text('synthetic-completed.txt'), findsNothing);
        await tester.tap(find.textContaining('Attachments ('));
        await tester.pump();
        await tester.pumpAndSettle();
        expect(find.text('synthetic-completed.txt'), findsOneWidget);
        expect(find.text('synthetic-failed.txt'), findsOneWidget);
        expect(find.byTooltip('Retry'), findsOneWidget);
        expect(find.text('Dismiss'), findsNothing);
        expect(find.byType(AttachmentMoreButton), findsOneWidget);
        expect(
          tester.widget<TextField>(find.byType(TextField).first).readOnly,
          isFalse,
        );
        expect(find.text('Save Note'), findsOneWidget);
        expect((await harness.editor.manualLock()).isSuccess, isTrue);
        await tester.pump();
        expectLocked();
        expect(harness.files.writeAttempts, 0);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        harness.disposeEditor();
        await tester.pump(const Duration(seconds: 3));
        for (final job in jobs) {
          job.dispose();
        }
        await tester.runAsync(harness.dispose);
      }
    });
  }
}
