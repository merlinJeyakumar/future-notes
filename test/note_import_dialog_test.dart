import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/core/operations/operation_result.dart';
import 'package:flutter_application_1/features/dashboard/models/attachment_job.dart';
import 'package:flutter_application_1/features/dashboard/models/note_import.dart';
import 'package:flutter_application_1/features/dashboard/widgets/attachment_job_panel.dart';
import 'package:flutter_application_1/features/dashboard/widgets/note_import_dialog.dart';

import 'note_replacement_dialog_test.dart' show conflict;
import 'support/editor_harness.dart';

void main() {
  for (final identical in [false, true]) {
    for (final decision in NoteImportDecision.values) {
      testWidgets(
        'dedicated import dialog identical=$identical waits for ${decision.name} then Done',
        (tester) async {
          final jobs = ValueNotifier<List<AttachmentJobState>>([]);
          NoteImportDecision? chosen;
          OperationResult<NoteImportResult>? returned;
          await tester.pumpWidget(
            MaterialApp(
              home: Builder(
                builder: (context) => TextButton(
                  onPressed: () async {
                    returned =
                        await showDialog<OperationResult<NoteImportResult>>(
                          context: context,
                          barrierDismissible: false,
                          builder: (_) => NoteImportDialog(
                            fileName: 'Synthetic export.fnote',
                            jobs: jobs,
                            cancelJob: (_) async {},
                            startImport: (resolve) async {
                              chosen = await resolve(conflict(identical));
                              return OperationResult.success(
                                NoteImportResult(switch (chosen!) {
                                  NoteImportDecision.duplicate =>
                                    NoteImportDisposition.duplicated,
                                  NoteImportDecision.replace =>
                                    NoteImportDisposition.replaced,
                                  NoteImportDecision.ignore =>
                                    NoteImportDisposition.ignored,
                                }, 'synthetic'),
                              );
                            },
                          ),
                        );
                  },
                  child: const Text('Import'),
                ),
              ),
            ),
          );
          await tester.tap(find.text('Import'));
          await tester.pumpAndSettle();
          expect(chosen, isNull);
          expect(returned, isNull);
          expect(find.byType(Dialog), findsOneWidget);
          expect(find.text('This note already exists'), findsOneWidget);
          expect(find.text('Synthetic export.fnote'), findsOneWidget);
          expect(find.byType(SnackBar), findsNothing);
          await tester.tap(
            find.text(switch (decision) {
              NoteImportDecision.duplicate => 'Duplicate',
              NoteImportDecision.replace => 'Back up & Replace',
              NoteImportDecision.ignore => 'Ignore',
            }),
          );
          await tester.pumpAndSettle();
          expect(chosen, decision);
          expect(
            returned,
            isNull,
          ); // The visible result awaits acknowledgement.
          expect(find.byType(Dialog), findsOneWidget);
          expect(
            find.text(switch (decision) {
              NoteImportDecision.duplicate => 'Duplicate created',
              NoteImportDecision.replace => 'Note replaced',
              NoteImportDecision.ignore => 'Import ignored',
            }),
            findsOneWidget,
          );
          await tester.tap(find.text('Done'));
          await tester.pumpAndSettle();
          expect(returned!.isSuccess, isTrue);
          expect(find.byType(Dialog), findsNothing);
          await tester.pumpWidget(const SizedBox.shrink());
          jobs.dispose();
        },
      );
    }
  }

  testWidgets(
    'Cancel waits for the import outcome and does not dismiss active progress',
    (tester) async {
      final jobs = ValueNotifier<List<AttachmentJobState>>([]);
      final job = AttachmentJobState(
        const AttachmentJobSnapshot(
          id: 'import',
          owner: 0,
          fileName: 'Synthetic export.fnote',
          phase: AttachmentJobPhase.preparing,
          operation: AttachmentJobOperation.import,
        ),
      );
      final completion = Completer<OperationResult<NoteImportResult>>();
      var cancellations = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: NoteImportDialog(
            fileName: 'Synthetic export.fnote',
            jobs: jobs,
            startImport: (_) {
              jobs.value = [job];
              return completion.future;
            },
            cancelJob: (_) async {
              cancellations++;
            },
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      expect(cancellations, 1);
      expect(find.text('Cancelling import…'), findsOneWidget);
      expect(find.text('Done'), findsNothing);
      completion.complete(
        const OperationResult.failure(
          OperationOutcome.cancelled,
          'Import cancelled.',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Import cancelled'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      jobs.dispose();
      job.dispose();
    },
  );

  testWidgets(
    'Finalizing disables cancellation and Escape cannot dismiss an active import',
    (tester) async {
      final jobs = ValueNotifier<List<AttachmentJobState>>([]);
      final job = AttachmentJobState(
        const AttachmentJobSnapshot(
          id: 'import',
          owner: 0,
          fileName: 'Synthetic export.fnote',
          phase: AttachmentJobPhase.finalizing,
          operation: AttachmentJobOperation.import,
        ),
      );
      final completion = Completer<OperationResult<NoteImportResult>>();
      var cancellations = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () {
                showDialog<void>(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) => NoteImportDialog(
                    fileName: 'Synthetic export.fnote',
                    jobs: jobs,
                    startImport: (_) {
                      jobs.value = [job];
                      return completion.future;
                    },
                    cancelJob: (_) async {
                      cancellations++;
                    },
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Finishing…'), findsOneWidget);
      final button = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Finishing…'),
      );
      expect(button.onPressed, isNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.byType(Dialog), findsOneWidget);
      expect(cancellations, 0);
      completion.complete(
        const OperationResult.success(
          NoteImportResult(NoteImportDisposition.replaced, 'synthetic'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Note replaced'), findsOneWidget);
      expect(find.textContaining('verified recovery copy'), findsOneWidget);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      jobs.dispose();
      job.dispose();
    },
  );

  testWidgets('a failure stays in the import dialog until acknowledged', (
    tester,
  ) async {
    final jobs = ValueNotifier<List<AttachmentJobState>>([]);
    await tester.pumpWidget(
      MaterialApp(
        home: NoteImportDialog(
          fileName: 'Synthetic export.fnote',
          jobs: jobs,
          startImport: (_) async => const OperationResult.failure(
            OperationOutcome.rejectedInput,
            'Package is incomplete.',
          ),
          cancelJob: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Import needs attention'), findsOneWidget);
    expect(find.text('Package is incomplete.'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    jobs.dispose();
  });

  testWidgets('Exit cancellation releases a pending duplicate decision', (
    tester,
  ) async {
    final jobs = ValueNotifier<List<AttachmentJobState>>([]);
    final job = AttachmentJobState(
      const AttachmentJobSnapshot(
        id: 'import',
        owner: 0,
        fileName: 'Synthetic export.fnote',
        phase: AttachmentJobPhase.verifying,
        operation: AttachmentJobOperation.import,
      ),
    );
    NoteImportDecision? choice;
    await tester.pumpWidget(
      MaterialApp(
        home: NoteImportDialog(
          fileName: 'Synthetic export.fnote',
          jobs: jobs,
          startImport: (resolve) async {
            jobs.value = [job];
            choice = await resolve(conflict(true));
            return const OperationResult.failure(
              OperationOutcome.cancelled,
              'Import cancelled.',
            );
          },
          cancelJob: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('This note already exists'), findsOneWidget);
    job.update(
      const AttachmentJobSnapshot(
        id: 'import',
        owner: 0,
        fileName: 'Synthetic export.fnote',
        phase: AttachmentJobPhase.cancelling,
        operation: AttachmentJobOperation.import,
      ),
    );
    await tester.pumpAndSettle();
    expect(choice, NoteImportDecision.ignore);
    expect(find.text('Import cancelled'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    jobs.dispose();
    job.dispose();
  });

  for (final phase in [
    AttachmentJobPhase.preparing,
    AttachmentJobPhase.completed,
  ]) {
    testWidgets('import $phase never becomes an attachment-style bottom card', (
      tester,
    ) async {
      final h = await EditorHarness.create();
      final job = AttachmentJobState(
        AttachmentJobSnapshot(
          id: 'import',
          owner: 0,
          fileName: 'Import package',
          phase: phase,
          operation: AttachmentJobOperation.import,
        ),
      );
      h.editor.attachmentJobsNotifier.value = [job];
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AttachmentJobPanel(
                viewModel: h.editor,
                auxiliaryOnly: true,
              ),
            ),
          ),
        );
        await tester.pump();
        expect(find.text('Import package'), findsNothing);
        expect(find.text('Dismiss'), findsNothing);
        expect(find.byType(Card), findsNothing);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        h.disposeEditor();
        await tester.pump(const Duration(seconds: 3));
        await tester.runAsync(h.dispose);
        job.dispose();
      }
    });
  }
}
