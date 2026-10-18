import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/core/operations/operation_result.dart';
import 'package:flutter_application_1/core/theme/app_dialog.dart';
import 'package:flutter_application_1/core/platform/mobile_job_binding.dart';
import 'package:flutter_application_1/features/dashboard/mobile/job_notifications.dart';
import 'package:flutter_application_1/features/dashboard/mobile/export_progress_dialog.dart';
import 'package:flutter_application_1/features/dashboard/mobile/work_decision_dialog.dart';
import 'package:flutter_application_1/features/dashboard/mobile/mobile_theme.dart';
import 'package:flutter_application_1/features/dashboard/models/attachment_job.dart';
import 'package:flutter_application_1/features/dashboard/models/draft_transition.dart';
import 'support/editor_harness.dart';
import 'mobile_attachment_presentation_test.dart' show captureSyntheticScreen;

AttachmentJobSnapshot snapshot(
  AttachmentJobPhase phase, {
  int bytes = 0,
  int? total,
}) => AttachmentJobSnapshot(
  id: 'synthetic-export',
  owner: 1,
  fileName: 'Export package',
  operation: AttachmentJobOperation.export,
  phase: phase,
  bytes: bytes,
  total: total,
  detail: phase == AttachmentJobPhase.preparing
      ? 'Writing package · Workshop.mp4'
      : phase == AttachmentJobPhase.verifying
      ? 'Validating exported backup (required)'
      : null,
);

void main() {
  testWidgets(
    'locking removes progress presentation immediately without cancelling its job',
    (tester) async {
      final h = await EditorHarness.create();
      h.seed('protected', h.note('protected', 'Synthetic body', locked: true));
      await h.editor.loadNote('protected');
      expect(await h.editor.unlockNote('synthetic-password'), isTrue);
      final job = AttachmentJobState(snapshot(AttachmentJobPhase.preparing));
      Future<OperationResult<void>>? operation;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () {
                operation = showMobileExportProgress(
                  context: context,
                  model: h.editor,
                  existingJob: job,
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
      expect(find.byType(MobileExportProgressDialog), findsOneWidget);
      expect((await tester.runAsync(h.editor.manualLock))!.isSuccess, isTrue);
      await tester.pump();
      expect(find.byType(MobileExportProgressDialog), findsNothing);
      expect((await operation!).outcome, OperationOutcome.cancelled);
      expect(job.progress.value.active, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      job.dispose();
      await tester.runAsync(h.dispose);
    },
  );

  testWidgets(
    'open task panel retains terminal snapshots without persistent history',
    (tester) async {
      final h = await EditorHarness.create();
      const channel = MethodChannel('future_notes/jobs');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (call) async => call.method == 'interruptedJobs' ? '[]' : null,
          );
      final job = AttachmentJobState(snapshot(AttachmentJobPhase.preparing));
      h.editor.attachmentJobsNotifier.value = [job];
      final jobs = MobileJobBinding(h.editor);
      await jobs.interrupted;
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: MobileJobNotifications(
              key: const ValueKey(1),
              jobs: jobs,
              model: h.editor,
            ),
          ),
        );
        job.update(snapshot(AttachmentJobPhase.completed));
        h.editor.attachmentJobsNotifier.value = [];
        await tester.pumpAndSettle();
        expect(find.text('Export · Completed'), findsOneWidget);
        expect(find.byType(LinearProgressIndicator), findsNothing);
        await tester.pumpWidget(
          MaterialApp(
            home: MobileJobNotifications(
              key: const ValueKey(2),
              jobs: jobs,
              model: h.editor,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('No pending jobs.'), findsOneWidget);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        jobs.dispose();
        job.dispose();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
        await tester.runAsync(h.dispose);
      }
    },
  );

  for (final phase in [
    AttachmentJobPhase.cancelled,
    AttachmentJobPhase.failed,
  ]) {
    testWidgets(
      'terminal export $phase remains visible without blocking completion',
      (tester) async {
        final h = await EditorHarness.create();
        final job = AttachmentJobState(snapshot(AttachmentJobPhase.preparing));
        Future<OperationResult<void>>? operation;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () {
                  operation = showMobileExportProgress(
                    context: context,
                    model: h.editor,
                    existingJob: job,
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
        job.update(snapshot(phase));
        await tester.pumpAndSettle();
        expect((await operation!).isSuccess, isFalse);
        expect(find.byType(MobileExportProgressDialog), findsOneWidget);
        expect(find.text('Cancel export'), findsNothing);
        expect(find.byType(LinearProgressIndicator), findsNothing);
        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();
        expect(find.byType(MobileExportProgressDialog), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
        job.dispose();
        await tester.runAsync(h.dispose);
      },
    );
  }

  testWidgets(
    'active export notification is selectable without cancelling the job',
    (tester) async {
      final h = await EditorHarness.create();
      const channel = MethodChannel('future_notes/jobs');
      final updates = <Map>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'update') updates.add(call.arguments as Map);
            return call.method == 'interruptedJobs' ? '[]' : null;
          });
      final job = AttachmentJobState(
        snapshot(AttachmentJobPhase.preparing, bytes: 50, total: 100),
      );
      h.editor.attachmentJobsNotifier.value = [job];
      final jobs = MobileJobBinding(h.editor);
      await jobs.interrupted;
      Future<String?>? selected;
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  child: const Text('Notifications'),
                  onPressed: () {
                    selected = showAppDialog<String>(
                      context: context,
                      builder: (_) =>
                          MobileJobNotifications(jobs: jobs, model: h.editor),
                    );
                  },
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Notifications'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        job.update(snapshot(AttachmentJobPhase.verifying));
        await tester.pump(const Duration(milliseconds: 600));
        expect(
          find.text('Export · Validating exported backup (required)'),
          findsOneWidget,
        );
        expect(
          updates.any(
            (update) => (update['jobs'] as List).any(
              (record) =>
                  record['detail'] == 'Validating exported backup (required)',
            ),
          ),
          isTrue,
        );
        await tester.tap(find.text('Export package'));
        await tester.pump(const Duration(milliseconds: 300));
        expect(await selected, job.progress.value.id);
        expect(job.progress.value.active, isTrue);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        jobs.dispose();
        job.dispose();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
        await tester.runAsync(h.dispose);
      }
    },
  );
  testWidgets(
    'dialog mounts before export; Hide preserves job and unrelated routes',
    (tester) async {
      final h = await EditorHarness.create();
      final job = AttachmentJobState(snapshot(AttachmentJobPhase.queued));
      final completion = Completer<OperationResult<void>>();
      Future<OperationResult<void>>? operation;
      var calls = 0;
      var visibleAtStart = false;
      var hidden = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                child: const Text('Start export'),
                onPressed: () {
                  operation = showMobileExportProgress(
                    context: context,
                    model: h.editor,
                    noteTitle: 'Synthetic project notes',
                    onHidden: () => hidden = true,
                    start: () {
                      calls++;
                      visibleAtStart = find
                          .byType(MobileExportProgressDialog)
                          .evaluate()
                          .isNotEmpty;
                      h.editor.attachmentJobsNotifier.value = [job];
                      return completion.future;
                    },
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Start export'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(visibleAtStart, isTrue);
      expect(calls, 1);
      expect(find.text('Export note'), findsOneWidget);
      job.update(
        snapshot(
          AttachmentJobPhase.preparing,
          bytes: 350 * 1024 * 1024,
          total: 700 * 1024 * 1024,
        ),
      );
      await tester.pump();
      expect(find.text('Writing package · Workshop.mp4'), findsOneWidget);
      expect(find.text('350 MiB / 700 MiB · 50%'), findsOneWidget);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        .5,
      );
      await tester.tap(find.text('Hide'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(hidden, isTrue);
      expect(job.progress.value.active, isTrue);
      final context = tester.element(find.text('Start export'));
      final other = showAppDialog<void>(
        context: context,
        builder: (_) => const AlertDialog(title: Text('Unrelated dialog')),
      );
      await tester.pump(const Duration(milliseconds: 300));
      job.update(snapshot(AttachmentJobPhase.completed));
      completion.complete(const OperationResult.success());
      await tester.pump();
      expect((await operation!).isSuccess, isTrue);
      expect(find.text('Unrelated dialog'), findsOneWidget);
      Navigator.of(tester.element(find.text('Unrelated dialog'))).pop();
      await other;
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(h.encryption.binaryDecryptCalls, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      job.dispose();
      await tester.runAsync(h.dispose);
    },
  );

  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'reopen existing export, finalization and completion at scale $scale',
      (tester) async {
        tester.view.physicalSize = const Size(360, 780);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final h = await EditorHarness.create();
        final job = AttachmentJobState(
          snapshot(
            AttachmentJobPhase.preparing,
            bytes: 350 * 1024 * 1024,
            total: 700 * 1024 * 1024,
          ),
        );
        h.editor.attachmentJobsNotifier.value = [job];
        Future<OperationResult<void>>? operation;
        await tester.pumpWidget(
          MaterialApp(
            theme: scale == 2 ? MobileTheme.light : MobileTheme.dark,
            builder: (context, child) => RepaintBoundary(
              key: const ValueKey('synthetic-attachment-screen'),
              child: MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
            ),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  child: const Text('Show export'),
                  onPressed: () {
                    operation = showMobileExportProgress(
                      context: context,
                      model: h.editor,
                      existingJob: job,
                    );
                  },
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Show export'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('Cancel export').hitTestable(), findsOneWidget);
        await captureSyntheticScreen(tester, 'export-dialog-${scale.toInt()}x');
        job.update(snapshot(AttachmentJobPhase.finalizing));
        await tester.pump();
        expect(find.text('Finishing export…'), findsOneWidget);
        expect(find.text('Cancel export'), findsNothing);
        job.update(snapshot(AttachmentJobPhase.completed));
        await tester.pumpAndSettle();
        expect((await operation!).isSuccess, isTrue);
        expect(find.byType(MobileExportProgressDialog), findsOneWidget);
        expect(find.text('Export complete'), findsOneWidget);
        expect(find.byType(LinearProgressIndicator), findsNothing);
        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();
        expect(find.byType(MobileExportProgressDialog), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        job.dispose();
        await tester.runAsync(h.dispose);
      },
    );
  }

  testWidgets('failed start retains its result and releases the operation', (
    tester,
  ) async {
    final h = await EditorHarness.create();
    final pending = AttachmentJobState(snapshot(AttachmentJobPhase.queued));
    Future<OperationResult<void>>? operation;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              child: const Text('Start export'),
              onPressed: () {
                operation = showMobileExportProgress(
                  context: context,
                  model: h.editor,
                  start: () async {
                    h.editor.attachmentJobsNotifier.value = [pending];
                    throw StateError('Synthetic failure');
                  },
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Start export'));
    await tester.pumpAndSettle();
    expect((await operation!).outcome, OperationOutcome.ioFailure);
    expect(find.byType(MobileExportProgressDialog), findsOneWidget);
    expect(
      find.text(
        'Export could not be completed. The original note was retained.',
      ),
      findsOneWidget,
    );
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text('Cancel export'), findsNothing);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(MobileExportProgressDialog), findsNothing);
    expect(h.files.writeAttempts, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    h.editor.attachmentJobsNotifier.value = [];
    pending.dispose();
    await tester.runAsync(h.dispose);
  });

  testWidgets(
    'export decision uses accurate copy and unchanged decision values',
    (tester) async {
      final h = await EditorHarness.create();
      final job = AttachmentJobState(snapshot(AttachmentJobPhase.queued));
      h.editor.attachmentJobsNotifier.value = [job];
      Future<DraftDecision?>? decision;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                child: const Text('Open note'),
                onPressed: () {
                  decision = showAppDialog<DraftDecision>(
                    context: context,
                    builder: (_) => MobileWorkDecisionDialog(
                      model: h.editor,
                      transition: DraftTransition.navigation,
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open note'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Export in progress'), findsOneWidget);
      expect(find.text('Attachment processing'), findsNothing);
      expect(find.text('Keep editing'), findsNothing);
      await tester.tap(find.text('Keep exporting'));
      await tester.pumpAndSettle();
      expect(await decision, DraftDecision.cancel);
      await tester.tap(find.text('Open note'));
      await tester.pump(const Duration(milliseconds: 300));
      job.update(snapshot(AttachmentJobPhase.finalizing));
      await tester.pump();
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      job.update(snapshot(AttachmentJobPhase.completed));
      await tester.pump();
      expect(find.text('Work finished'), findsOneWidget);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(await decision, DraftDecision.discard);
      await tester.pumpWidget(const SizedBox.shrink());
      job.dispose();
      await tester.runAsync(h.dispose);
    },
  );
}
