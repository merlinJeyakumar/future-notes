import 'dart:ui' show AppExitResponse;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/core/operations/operation_result.dart';
import 'package:flutter_application_1/features/dashboard/models/attachment_job.dart';
import 'package:flutter_application_1/features/dashboard/views/dashboard_screen.dart';
import 'package:flutter_application_1/features/dashboard/widgets/content_area.dart';
import 'package:flutter_application_1/main.dart';
import 'support/editor_harness.dart';
import 'support/fake_window_actions.dart';
import 'attachment_strip_test.dart' show FakeDesktop, FakeOpenCache;

void main() {
  for (final saved in [false, true]) {
    testWidgets(
      'idle ${saved ? 'saved note' : 'empty draft'} exits without a confirmation, including completed jobs',
      (tester) async {
        final harness = await EditorHarness.create();
        final desktop = FakeDesktop();
        final cache = FakeOpenCache();
        final completed = AttachmentJobState(
          const AttachmentJobSnapshot(
            id: 'completed-export',
            owner: 0,
            fileName: 'Export package',
            phase: AttachmentJobPhase.completed,
            operation: AttachmentJobOperation.export,
          ),
        );
        var closeCalls = 0;
        if (saved) {
          harness.seed(
            'note_idle',
            harness.note('idle', '<p>Synthetic saved note</p>'),
            encrypted: false,
          );
        }
        try {
          await tester.pumpWidget(
            MyApp(
              settings: harness.settings,
              home: DashboardScreen(
                settings: harness.settings,
                fileService: harness.files,
                startBackgroundServices: false,
                desktopActions: desktop,
                attachmentOpenCache: cache,
                onClose: () async {
                  closeCalls++;
                  return const OperationResult.success();
                },
              ),
            ),
          );
          final model = tester
              .widget<ContentArea>(find.byType(ContentArea))
              .viewModel;
          if (saved) {
            expect((await model.loadNote('note_idle')).isSuccess, isTrue);
            expect(model.hasUnsavedChanges, isFalse);
            await tester.pump();
          }
          model.attachmentJobsNotifier.value = [completed];
          expect(model.hasAttachmentJobs, isFalse);
          final exit = tester.binding.handleRequestAppExit();
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(find.byType(AlertDialog), findsNothing);
          await tester.pumpAndSettle();
          expect(await exit, AppExitResponse.exit);
          expect(closeCalls, 1);
          expect(find.byType(ContentArea), findsOneWidget);
          expect(harness.files.writeAttempts, 0);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          harness.disposeEditor();
          await tester.pump(const Duration(seconds: 3));
          completed.dispose();
          await tester.runAsync(harness.dispose);
        }
      },
    );
  }
  testWidgets(
    'in-app Close follows the same orderly exit without an idle confirmation',
    (tester) async {
      final harness = await EditorHarness.create();
      final desktop = FakeDesktop();
      final cache = FakeOpenCache();
      var closed = 0;
      final window = FakeWindowActions()
        ..onClose = () {
          tester.binding.handleRequestAppExit();
        };
      try {
        await tester.pumpWidget(
          MyApp(
            windowActions: window,
            settings: harness.settings,
            home: DashboardScreen(
              settings: harness.settings,
              fileService: harness.files,
              startBackgroundServices: false,
              desktopActions: desktop,
              attachmentOpenCache: cache,
              onClose: () async {
                closed++;
                return const OperationResult.success();
              },
            ),
          ),
        );
        await tester.tap(find.byTooltip('Close'));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        for (var step = 0; step < 20 && closed == 0; step++) {
          await tester.runAsync(() async {
            await Future<void>.delayed(Duration.zero);
          });
          await tester.pump();
        }
        expect(closed, 1);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        harness.disposeEditor();
        await tester.pump(const Duration(seconds: 3));
        await tester.runAsync(harness.dispose);
      }
    },
  );

  for (final discard in [false, true]) {
    testWidgets(
      'unsaved draft still offers ${discard ? 'Discard' : 'Cancel'} directly',
      (tester) async {
        final harness = await EditorHarness.create();
        var closed = 0;
        try {
          await tester.pumpWidget(
            MyApp(
              settings: harness.settings,
              home: DashboardScreen(
                settings: harness.settings,
                fileService: harness.files,
                startBackgroundServices: false,
                onClose: () async {
                  closed++;
                  return const OperationResult.success();
                },
              ),
            ),
          );
          final model = tester
              .widget<ContentArea>(find.byType(ContentArea))
              .viewModel;
          model.titleController.text = 'Synthetic unsaved draft';
          final exit = tester.binding.handleRequestAppExit();
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(find.text('Save this new note?'), findsOneWidget);
          expect(find.text('Exit Future Notes?'), findsNothing);
          expect(closed, 0);
          await tester.tap(
            find.widgetWithText(TextButton, discard ? 'Discard' : 'Cancel'),
          );
          await tester.pumpAndSettle();
          expect(
            await exit,
            discard ? AppExitResponse.exit : AppExitResponse.cancel,
          );
          expect(closed, discard ? 1 : 0);
          expect(harness.files.writeAttempts, 0);
          if (!discard) {
            expect(model.titleController.text, 'Synthetic unsaved draft');
          }
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          harness.disposeEditor();
          await tester.pump(const Duration(seconds: 3));
          await tester.runAsync(harness.dispose);
        }
      },
    );
  }

  testWidgets('active work still offers Keep running before cleanup', (
    tester,
  ) async {
    final harness = await EditorHarness.create();
    final job = AttachmentJobState(
      const AttachmentJobSnapshot(
        id: 'synthetic-active',
        owner: 0,
        fileName: 'Export package',
        phase: AttachmentJobPhase.preparing,
        operation: AttachmentJobOperation.export,
      ),
    );
    var closed = 0;
    try {
      await tester.pumpWidget(
        MyApp(
          settings: harness.settings,
          home: DashboardScreen(
            settings: harness.settings,
            fileService: harness.files,
            startBackgroundServices: false,
            onClose: () async {
              closed++;
              return const OperationResult.success();
            },
          ),
        ),
      );
      final model = tester
          .widget<ContentArea>(find.byType(ContentArea))
          .viewModel;
      model.attachmentJobsNotifier.value = [job];
      final exit = tester.binding.handleRequestAppExit();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Attachment processing'), findsOneWidget);
      expect(find.text('Exit Future Notes?'), findsNothing);
      await tester.tap(find.text('Keep running'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(await exit, AppExitResponse.cancel);
      expect(closed, 0);
      expect(model.hasAttachmentJobs, isTrue);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      harness.disposeEditor();
      await tester.pump(const Duration(seconds: 3));
      job.dispose();
      await tester.runAsync(harness.dispose);
    }
  });
}
