import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/core/platform/mobile_job_binding.dart';
import 'package:flutter_application_1/features/dashboard/mobile/job_notifications.dart';
import 'package:flutter_application_1/features/dashboard/widgets/app_overflow_menu.dart';
import 'package:flutter_application_1/features/dashboard/models/attachment_job.dart';
import 'support/editor_harness.dart';

void main() {
  testWidgets(
    'removing an active job clears its open-panel progress snapshot',
    (tester) async {
      final h = await EditorHarness.create();
      const channel = MethodChannel('future_notes/jobs');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (call) async => call.method == 'interruptedJobs' ? '[]' : null,
          );
      final state = AttachmentJobState(
        const AttachmentJobSnapshot(
          id: 'removed',
          owner: 1,
          fileName: 'Synthetic removed task',
          phase: AttachmentJobPhase.preparing,
          bytes: 1,
          total: 10,
        ),
      );
      h.editor.attachmentJobsNotifier.value = [state];
      final binding = MobileJobBinding(h.editor);
      await binding.interrupted;
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: MobileJobNotifications(jobs: binding, model: h.editor),
          ),
        );
        await tester.pump();
        expect(find.byType(LinearProgressIndicator), findsOneWidget);
        h.editor.attachmentJobsNotifier.value = [];
        await tester.pumpAndSettle();
        expect(find.byType(LinearProgressIndicator), findsNothing);
        expect(find.byTooltip('Cancel this job'), findsNothing);
        expect(find.text('No pending jobs.'), findsOneWidget);
        expect(binding.activeCount.value, 0);
        expect(h.files.writes, isEmpty);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        binding.dispose();
        state.dispose();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
        await tester.runAsync(h.dispose);
      }
    },
  );
  testWidgets(
    'notification dismissal preserves recovery and acknowledgement removes only its record',
    (tester) async {
      final h = await EditorHarness.create();
      const channel = MethodChannel('future_notes/jobs');
      final records = <Map<String, dynamic>>[
        {'id': 'old-a', 'fileName': 'Synthetic one', 'operation': 'export'},
        {'id': 'old-b', 'fileName': 'Synthetic two', 'operation': 'add'},
      ];
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            if (call.method == 'interruptedJobs') return jsonEncode(records);
            if (call.method == 'dismissInterruptedNotification') {
              for (final record in records) {
                if ((call.arguments['ids'] as List).contains(record['id']))
                  record['notificationDismissed'] = true;
              }
            }
            if (call.method == 'acknowledgeInterrupted') {
              records.removeWhere(
                (record) =>
                    (call.arguments['ids'] as List).contains(record['id']),
              );
            }
            return null;
          });
      final binding = MobileJobBinding(h.editor);
      await binding.interrupted;
      try {
        expect(binding.notificationCount.value, 2);
        expect(binding.activeCount.value, 0);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  AppOverflowMenu(onBackgroundTasks: () {}),
                  Expanded(
                    child: MobileJobNotifications(
                      jobs: binding,
                      model: h.editor,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        expect(find.byType(AppOverflowMenu), findsOneWidget);
        expect(find.byType(Badge), findsNothing);
        expect(find.byType(LinearProgressIndicator), findsNothing);
        await tester.tap(find.byTooltip('Dismiss notification').first);
        await tester.pumpAndSettle();
        expect(binding.retained.value, hasLength(2));
        expect(binding.retained.value.first['notificationDismissed'], isTrue);
        expect(binding.notificationCount.value, 2);
        expect(find.text('Synthetic one'), findsOneWidget);
        expect(find.byTooltip('Notification dismissed'), findsOneWidget);
        expect(h.files.writes, isEmpty);
        await binding.acknowledgeInterrupted('old-a');
        await tester.pumpAndSettle();
        expect(binding.retained.value.single['id'], 'old-b');
        expect(binding.notificationCount.value, 1);
        expect(binding.activeCount.value, 0);
        expect(
          calls
              .where((call) => call.method == 'acknowledgeInterrupted')
              .single
              .arguments,
          {
            'ids': ['old-a'],
          },
        );
        expect(find.text('Synthetic one'), findsNothing);
        expect(find.text('Synthetic two'), findsOneWidget);
        expect(
          calls.where(
            (call) =>
                call.method != 'update' &&
                call.method != 'interruptedJobs' &&
                call.method != 'dismissInterruptedNotification' &&
                call.method != 'acknowledgeInterrupted',
          ),
          isEmpty,
        );
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        binding.dispose();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
        await tester.runAsync(h.dispose);
      }
    },
  );

  testWidgets(
    'active count clears on termination without a standalone header badge',
    (tester) async {
      final h = await EditorHarness.create();
      const channel = MethodChannel('future_notes/jobs');
      final updates = <List<dynamic>>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'interruptedJobs') return '[{"id":"old"}]';
            if (call.method == 'update')
              updates.add(call.arguments['jobs'] as List);
            return null;
          });
      final state = AttachmentJobState(
        const AttachmentJobSnapshot(
          id: 'active',
          owner: 1,
          fileName: 'Synthetic',
          phase: AttachmentJobPhase.queued,
        ),
      );
      h.editor.attachmentJobsNotifier.value = [state];
      final binding = MobileJobBinding(h.editor);
      await binding.interrupted;
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: AppOverflowMenu(onBackgroundTasks: () {})),
          ),
        );
        expect(binding.activeCount.value, 1);
        expect(find.byType(Badge), findsNothing);
        for (final terminal in [
          AttachmentJobPhase.cancelled,
          AttachmentJobPhase.completed,
          AttachmentJobPhase.failed,
        ]) {
          state.update(
            AttachmentJobSnapshot(
              id: 'active',
              owner: 1,
              fileName: 'Synthetic',
              phase: terminal,
            ),
          );
          await tester.pumpAndSettle();
          expect(binding.activeCount.value, 0);
          expect(find.byType(Badge), findsNothing);
          expect(find.byType(AppOverflowMenu), findsOneWidget);
          expect(updates.last, isEmpty);
          state.update(
            const AttachmentJobSnapshot(
              id: 'active',
              owner: 1,
              fileName: 'Synthetic',
              phase: AttachmentJobPhase.preparing,
            ),
          );
          await tester.pump();
        }
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        binding.dispose();
        state.dispose();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
        await tester.runAsync(h.dispose);
      }
    },
  );
}
