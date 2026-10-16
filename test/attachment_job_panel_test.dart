import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/features/dashboard/models/attachment_job.dart';
import 'package:flutter_application_1/features/dashboard/widgets/attachment_job_panel.dart';
import 'support/editor_harness.dart';

void main() {
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
