import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/features/dashboard/models/attachment_job.dart';
import 'package:flutter_application_1/features/dashboard/widgets/attachment_job_panel.dart';
import 'support/editor_harness.dart';

void main() {
  testWidgets(
    'export uses a compact full-width row and preserves job actions',
    (tester) async {
      final harness = await EditorHarness.create();
      final job = AttachmentJobState(
        const AttachmentJobSnapshot(
          id: 'export',
          owner: 0,
          fileName: 'Export package',
          phase: AttachmentJobPhase.queued,
          operation: AttachmentJobOperation.export,
        ),
      );
      harness.editor.attachmentJobsNotifier.value = [job];
      void update(AttachmentJobPhase phase, {String? error}) => job.update(
        AttachmentJobSnapshot(
          id: 'export',
          owner: 0,
          fileName: 'Export package',
          phase: phase,
          operation: AttachmentJobOperation.export,
          bytes: 512,
          total: 1024,
          error: error,
        ),
      );
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 600,
                child: AttachmentJobPanel(
                  viewModel: harness.editor,
                  auxiliaryOnly: true,
                ),
              ),
            ),
          ),
        );
        final card = find.byType(Card);
        expect(tester.getSize(card).width, closeTo(568, .5));
        expect(tester.getSize(card).height, lessThan(120));
        expect(find.text('Cancel'), findsOneWidget);
        expect(
          tester
              .widget<LinearProgressIndicator>(
                find.byType(LinearProgressIndicator),
              )
              .value,
          isNull,
        );

        update(AttachmentJobPhase.preparing);
        await tester.pump();
        expect(
          tester
              .widget<LinearProgressIndicator>(
                find.byType(LinearProgressIndicator),
              )
              .value,
          .5,
        );
        expect(find.text('512 B / 1.0 KiB'), findsOneWidget);
        expect(tester.getSize(card).height, lessThan(130));

        update(AttachmentJobPhase.finalizing);
        await tester.pump();
        expect(find.text('Cancel'), findsNothing);
        expect(find.text('Dismiss'), findsNothing);

        update(
          AttachmentJobPhase.failed,
          error: 'Synthetic destination unavailable',
        );
        await tester.pump();
        expect(find.text('Retry'), findsOneWidget);
        expect(find.text('Remove pending'), findsOneWidget);
        expect(find.text('Synthetic destination unavailable'), findsOneWidget);

        update(AttachmentJobPhase.completed);
        await tester.pump();
        expect(find.byType(LinearProgressIndicator), findsNothing);
        await tester.tap(find.text('Dismiss'));
        await tester.pump();
        expect(harness.editor.attachmentJobsNotifier.value, isEmpty);
        expect(harness.files.writeAttempts, 0);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        harness.disposeEditor();
        await tester.pump(const Duration(seconds: 3));
        job.dispose();
        await tester.runAsync(harness.dispose);
      }
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets(
      'operation rows wrap at narrow width with enlarged text: $brightness',
      (tester) async {
        final harness = await EditorHarness.create();
        final jobs = [
          for (var i = 0; i < 4; i++)
            AttachmentJobState(
              AttachmentJobSnapshot(
                id: 'job-$i',
                owner: 0,
                fileName: 'Synthetic export package $i',
                phase: AttachmentJobPhase.failed,
                operation: AttachmentJobOperation.export,
                error:
                    'Synthetic destination is unavailable. Choose another location.',
              ),
            ),
        ];
        harness.editor.attachmentJobsNotifier.value = jobs;
        try {
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(brightness: brightness),
              home: MediaQuery(
                data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
                child: Scaffold(
                  body: SizedBox(
                    width: 280,
                    child: AttachmentJobPanel(
                      viewModel: harness.editor,
                      auxiliaryOnly: true,
                    ),
                  ),
                ),
              ),
            ),
          );
          final cards = tester.getRect(find.byType(Card).first);
          final second = tester.getRect(find.byType(Card).at(1));
          expect(second.left, cards.left);
          expect(second.top, greaterThan(cards.bottom));
          expect(
            tester.getSize(find.byType(AttachmentJobPanel)).height,
            lessThan(320),
          );
          await tester.drag(
            find.byType(SingleChildScrollView),
            const Offset(0, -800),
          );
          await tester.pumpAndSettle();
          expect(
            find.text('Synthetic export package 3').hitTestable(),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          harness.disposeEditor();
          await tester.pump(const Duration(seconds: 3));
          for (final job in jobs) {
            job.dispose();
          }
          await tester.runAsync(harness.dispose);
        }
      },
    );
  }

  testWidgets('lock notifications hide job details without a parent rebuild', (
    tester,
  ) async {
    final harness = await EditorHarness.create();
    final job = AttachmentJobState(
      const AttachmentJobSnapshot(
        id: 'synthetic',
        owner: 0,
        fileName: 'synthetic-file.txt',
        phase: AttachmentJobPhase.completed,
      ),
    );
    harness.editor.attachmentJobsNotifier.value = [job];
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: AttachmentJobPanel(viewModel: harness.editor)),
        ),
      );
      expect(find.text('synthetic-file.txt'), findsOneWidget);
      harness.editor.isLockedNotifier.value = true;
      await tester.pump();
      expect(find.text('synthetic-file.txt'), findsNothing);
      expect(find.text('Completed'), findsNothing);
      expect(find.text('Dismiss'), findsNothing);
      harness.editor.isLockedNotifier.value = false;
      await tester.pump();
      expect(find.text('synthetic-file.txt'), findsOneWidget);
      expect(harness.files.writeAttempts, 0);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      harness.disposeEditor();
      await tester.pump(const Duration(seconds: 3));
      job.dispose();
      await tester.runAsync(harness.dispose);
    }
  });

  testWidgets(
    'progress preserves typing, remains visible when collapsed and separates Finalizing',
    (tester) async {
      final harness = await EditorHarness.create();
      final job = AttachmentJobState(
        const AttachmentJobSnapshot(
          id: 'synthetic',
          owner: 0,
          fileName: 'sample.txt',
          phase: AttachmentJobPhase.encrypting,
          bytes: 100,
          total: 100,
        ),
      );
      harness.editor.attachmentJobsNotifier.value = [job];
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  TextField(controller: harness.editor.titleController),
                  AttachmentJobPanel(viewModel: harness.editor),
                ],
              ),
            ),
          ),
        );
        expect(find.text('Encrypting'), findsOneWidget);
        await tester.enterText(find.byType(TextField), 'typing stays enabled');
        expect(harness.editor.titleController.text, 'typing stays enabled');
        job.update(
          const AttachmentJobSnapshot(
            id: 'synthetic',
            owner: 0,
            fileName: 'sample.txt',
            phase: AttachmentJobPhase.finalizing,
            bytes: 100,
            total: 100,
          ),
        );
        await tester.pump();
        expect(find.text('Finishing safely…'), findsOneWidget);
        expect(find.text('Completed'), findsNothing);
        expect(find.text('Cancel'), findsNothing);
        await tester.tap(find.text('Background operations: 1 active'));
        await tester.pump();
        await tester.pumpAndSettle();
        expect(find.text('Finishing'), findsOneWidget);
        expect(find.text('Finishing safely…'), findsNothing);
      } finally {
        harness.disposeEditor();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 3));
        job.dispose();
        await tester.runAsync(harness.dispose);
      }
    },
  );
}
