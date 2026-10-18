import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/features/dashboard/mobile/content_area.dart';
import 'package:flutter_application_1/features/dashboard/models/attachment_job.dart';
import 'package:flutter_application_1/main.dart';
import 'support/editor_harness.dart';

void main() {
  testWidgets(
    'mobile editor presents each export once alongside protection work',
    (tester) async {
      final h = await EditorHarness.create();
      h.seed('demo', h.note('demo', 'Synthetic body'));
      await h.editor.loadNote('demo');
      final owner = h.editor.draftSession.generation;
      AttachmentJobSnapshot snapshot(AttachmentJobPhase phase, int bytes) =>
          AttachmentJobSnapshot(
            id: 'export',
            owner: owner,
            fileName: 'Export package',
            operation: AttachmentJobOperation.export,
            phase: phase,
            bytes: bytes,
            total: 100,
            detail: 'Assembling package · synthetic.mp4',
          );
      final export = AttachmentJobState(
        snapshot(AttachmentJobPhase.preparing, 50),
      );
      final protection = AttachmentJobState(
        AttachmentJobSnapshot(
          id: 'protection',
          owner: owner,
          fileName: 'Synthetic password change',
          operation: AttachmentJobOperation.protection,
          phase: AttachmentJobPhase.encrypting,
          bytes: 10,
          total: 100,
        ),
      );
      try {
        h.editor.attachmentJobsNotifier.value = [export, protection];
        await tester.pumpWidget(
          MyApp(
            settings: h.settings,
            home: Scaffold(body: MobileContentArea(viewModel: h.editor)),
          ),
        );
        await tester.pump();
        expect(find.text('Export package'), findsOneWidget);
        expect(find.text('Export: 1 active'), findsNothing);
        expect(find.text('Synthetic password change'), findsOneWidget);
        expect(find.byTooltip('Cancel attachment operation'), findsOneWidget);
        expect(find.text('50 B / 100 B · 50%'), findsOneWidget);
        export.update(snapshot(AttachmentJobPhase.preparing, 75));
        await tester.pump();
        expect(find.text('Export package'), findsOneWidget);
        expect(find.text('75 B / 100 B · 75%'), findsOneWidget);
        export.update(snapshot(AttachmentJobPhase.finalizing, 100));
        await tester.pump();
        expect(find.text('Export package'), findsOneWidget);
        expect(find.byTooltip('Cancel attachment operation'), findsNothing);
        export.update(snapshot(AttachmentJobPhase.completed, 100));
        h.editor.attachmentJobsNotifier.value = [export, protection];
        await tester.pump();
        expect(find.text('Export package'), findsNothing);
        expect(find.text('Synthetic password change'), findsOneWidget);
        expect(h.encryption.binaryDecryptCalls, 0);
        expect(h.files.writeAttempts, 0);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        h.disposeEditor();
        await tester.pump(const Duration(seconds: 3));
        export.dispose();
        protection.dispose();
        await tester.runAsync(h.dispose);
      }
    },
  );
}
