import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/features/dashboard/models/attachment_job.dart';
import 'package:flutter_application_1/features/dashboard/widgets/content_area.dart';
import 'package:flutter_application_1/main.dart';

import 'support/editor_harness.dart';

void main() {
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
        harness.note('protected', 'body', locked: true),
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
        expect(find.byTooltip('Settings'), findsNothing);
        expect(find.byTooltip('Attach file'), findsNothing);
        expect(find.text('Editing'), findsNothing);
        expect(find.textContaining('active operations'), findsNothing);
        expect(find.textContaining('synthetic-'), findsNothing);
        expect(find.text('Retry'), findsNothing);
        expect(find.text('Dismiss'), findsNothing);
        expect(
          tester.widget<TextField>(find.byType(TextField).first).readOnly,
          isTrue,
        );
        if (width >= 900) {
          expect(find.text('Locked'), findsOneWidget);
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
        await tester.pump();
        expect(find.text('This note is locked'), findsNothing);
        expect(find.byTooltip('Settings'), findsOneWidget);
        expect(find.byTooltip('Attach file'), findsOneWidget);
        expect(find.text('synthetic-completed.txt'), findsOneWidget);
        expect(find.text('synthetic-failed.txt'), findsOneWidget);
        expect(find.text('Retry'), findsOneWidget);
        expect(find.text('Dismiss'), findsOneWidget);
        expect(
          tester.widget<TextField>(find.byType(TextField).first).readOnly,
          isFalse,
        );
        expect(
          width >= 900
              ? find.text('Save Note')
              : find.byIcon(Icons.save_rounded),
          findsOneWidget,
        );
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
