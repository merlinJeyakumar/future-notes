import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/features/dashboard/mobile/content_area.dart';
import 'package:flutter_application_1/features/dashboard/models/attachment_job.dart';
import 'package:flutter_application_1/main.dart';
import 'support/editor_harness.dart';

void main() {
  testWidgets(
    'password remains usable during export and content stays read-only',
    (tester) async {
      final h = await EditorHarness.create();
      h.seed('protected', h.note('protected', 'Synthetic body', locked: true));
      await h.editor.loadNote('protected');
      final owner = h.editor.draftSession.generation;
      AttachmentJobSnapshot snapshot(AttachmentJobPhase phase) =>
          AttachmentJobSnapshot(
            id: 'export',
            owner: owner,
            fileName: 'Export package',
            operation: AttachmentJobOperation.export,
            phase: phase,
            bytes: 50,
            total: 100,
          );
      final job = AttachmentJobState(snapshot(AttachmentJobPhase.preparing));
      h.editor.attachmentJobsNotifier.value = [job];
      try {
        await tester.pumpWidget(
          MyApp(
            settings: h.settings,
            home: Scaffold(body: MobileContentArea(viewModel: h.editor)),
          ),
        );
        await tester.pump();
        final password = find.byKey(const ValueKey('note-unlock-password'));
        await tester.tap(password);
        await tester.enterText(password, 'wrong-password');
        await tester.tap(find.widgetWithText(FilledButton, 'Unlock'));
        await tester.pump(const Duration(milliseconds: 250));
        expect(h.editor.isLocked, isTrue);
        expect(h.editor.draftSession.generation, owner);
        expect(find.textContaining('Could not unlock.'), findsOneWidget);
        await tester.enterText(password, 'synthetic-password');
        await tester.tap(find.widgetWithText(FilledButton, 'Unlock'));
        await tester.pump(const Duration(milliseconds: 250));
        expect(h.editor.isLocked, isFalse);
        expect(h.editor.draftSession.generation, owner);
        expect(
          h.editor.quillController.document.toPlainText(),
          'Synthetic body\n',
        );
        expect(h.editor.quillController.readOnly, isTrue);
        expect(h.editor.focusNode.hasFocus, isFalse);
        expect(job.progress.value.active, isTrue);
        expect(find.text('Export package'), findsOneWidget);
        expect(
          tester
              .widget<IconButton>(
                find.byWidgetPredicate(
                  (w) => w is IconButton && w.tooltip == 'Attach file',
                ),
              )
              .onPressed,
          isNull,
        );
        job.update(snapshot(AttachmentJobPhase.completed));
        h.editor.attachmentJobsNotifier.value = [job];
        await tester.pump(const Duration(milliseconds: 250));
        expect(h.editor.quillController.readOnly, isFalse);
        expect(h.files.writeAttempts, 0);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        h.disposeEditor();
        await tester.pump(const Duration(seconds: 3));
        job.dispose();
        await tester.runAsync(h.dispose);
      }
    },
  );

  test('read-only unlock refuses foreign export ownership', () async {
    final h = await EditorHarness.create();
    h.seed('protected', h.note('protected', 'Synthetic body', locked: true));
    await h.editor.loadNote('protected');
    final owner = h.editor.draftSession.generation;
    final job = AttachmentJobState(
      AttachmentJobSnapshot(
        id: 'foreign-export',
        owner: owner + 1,
        fileName: 'Export package',
        operation: AttachmentJobOperation.export,
        phase: AttachmentJobPhase.preparing,
      ),
    );
    h.editor.attachmentJobsNotifier.value = [job];
    try {
      expect(
        await h.editor.unlockNote('synthetic-password', readOnlyExport: true),
        isFalse,
      );
      expect(h.editor.isLocked, isTrue);
      expect(h.editor.draftSession.generation, owner);
      expect(h.files.writeAttempts, 0);
    } finally {
      h.disposeEditor();
      job.dispose();
      await h.dispose();
    }
  });
}
