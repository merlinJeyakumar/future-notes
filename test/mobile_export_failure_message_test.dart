import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/features/dashboard/mobile/export_progress_dialog.dart';
import 'package:flutter_application_1/features/dashboard/models/attachment_job.dart';
import 'support/editor_harness.dart';

void main() {
  testWidgets('unavailable export output gives an actionable mobile result', (
    tester,
  ) async {
    final h = await EditorHarness.create();
    final job = AttachmentJobState(
      const AttachmentJobSnapshot(
        id: 'synthetic-export',
        owner: 1,
        fileName: 'Export package',
        operation: AttachmentJobOperation.export,
        phase: AttachmentJobPhase.failed,
        error: 'Owned output changed before acknowledgement.',
      ),
    );
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MobileExportProgressDialog(model: h.editor, existingJob: job),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Owned output changed before acknowledgement.'),
        findsNothing,
      );
      expect(
        find.text(
          'The export file became unavailable before it was ready. '
          'Your note and attachments are unchanged. Try exporting again.',
        ),
        findsOneWidget,
      );
      expect(find.text('Close'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(h.files.writeAttempts, 0);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      job.dispose();
      await tester.runAsync(h.dispose);
    }
  });
}
