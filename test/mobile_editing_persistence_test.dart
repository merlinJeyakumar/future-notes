import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_application_1/features/dashboard/models/auto_save_policy.dart';
import 'package:flutter_application_1/features/dashboard/models/attachment_job.dart';
import 'package:flutter_application_1/features/dashboard/mobile/content_area.dart';
import 'package:flutter_application_1/features/dashboard/mobile/attachment_strip.dart';
import 'package:flutter_application_1/main.dart';
import 'support/editor_harness.dart';

void main() {
  Future<EditorHarness> open() async {
    final h = await EditorHarness.create(autoSavePolicy: AutoSavePolicy.mobile);
    h.seed(
      'demo',
      h.note(
        'demo',
        'Synthetic body',
        attachments: [
          {'id': 'synthetic', 'fileName': 'demo.txt', 'size': 128},
        ],
      ),
    );
    await h.editor.loadNote('demo');
    return h;
  }

  testWidgets(
    'background/file-picker lifecycle retains dirty edits without library writes',
    (tester) async {
      final h = await open();
      addTearDown(h.dispose);
      h.editor.titleController.text = 'Unsaved while picker open';
      h.editor.setAutomaticSavingActive(false);
      await tester.pump(const Duration(minutes: 2));
      expect(h.files.writeAttempts, 0);
      expect(h.editor.draftSession.isDirty, true);
      h.editor.setAutomaticSavingActive(true);
      await tester.pump(const Duration(seconds: 14));
      expect(h.files.writeAttempts, 0);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(h.files.writeAttempts, 1);
      h.disposeEditor();
    },
  );

  testWidgets(
    'mobile saves only after editing idle and respects write cadence',
    (tester) async {
      final h = await open();
      addTearDown(h.dispose);
      h.editor.titleController.text = 'First edit';
      await tester.pump(const Duration(seconds: 10));
      expect(h.files.writeAttempts, 0);
      h.editor.titleController.text = 'Continued typing';
      await tester.pump(const Duration(seconds: 14));
      expect(h.files.writeAttempts, 0);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(h.files.writeAttempts, 1);
      h.editor.titleController.text = 'Next edit';
      await tester.pump(const Duration(seconds: 15));
      expect(h.files.writeAttempts, 1);
      await tester.pump(const Duration(seconds: 15));
      await tester.pump();
      expect(h.files.writeAttempts, 2);
      await tester.pump(const Duration(minutes: 2));
      expect(h.files.writeAttempts, 2);
      h.disposeEditor();
    },
  );

  testWidgets(
    'active work defers mobile autosave without queueing, explicit Save still works',
    (tester) async {
      final h = await open();
      addTearDown(h.dispose);
      h.editor.titleController.text = 'Dirty before job';
      final job = AttachmentJobState(
        const AttachmentJobSnapshot(
          id: 'synthetic-job',
          owner: 1,
          fileName: 'demo.bin',
          phase: AttachmentJobPhase.encrypting,
        ),
      );
      h.editor.attachmentJobsNotifier.value = [job];
      await tester.pump(const Duration(seconds: 20));
      expect(h.files.writeAttempts, 0);
      expect(h.editor.isSavingNotifier.value, false);
      h.editor.titleController.text = 'Edit while attaching';
      await tester.pump(const Duration(minutes: 1));
      expect(h.files.writeAttempts, 0);
      expect((await h.editor.saveNote()).isSuccess, true);
      expect(h.files.writeAttempts, 1);
      h.editor.attachmentJobsNotifier.value = [];
      h.disposeEditor();
      job.dispose();
    },
  );

  testWidgets('selection, job progress and rebuilding never create a save', (
    tester,
  ) async {
    final h = await open();
    addTearDown(h.dispose);
    await tester.pumpWidget(
      MyApp(
        settings: h.settings,
        home: Scaffold(body: MobileContentArea(viewModel: h.editor)),
      ),
    );
    await tester.pumpAndSettle();
    h.editor.quillController.updateSelection(
      const TextSelection.collapsed(offset: 2),
      ChangeSource.local,
    );
    h.editor.notifyListeners();
    await tester.pump(const Duration(minutes: 1));
    expect(h.files.writeAttempts, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    h.disposeEditor();
  });

  testWidgets(
    'keyboard removes attachment shelf from typing viewport and restores same editor',
    (tester) async {
      final h = await open();
      addTearDown(h.dispose);
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      final document = h.editor.quillController.document;
      await tester.pumpWidget(
        MyApp(
          settings: h.settings,
          home: Scaffold(body: MobileContentArea(viewModel: h.editor)),
        ),
      );
      await tester.pumpAndSettle();
      final state = tester.state(find.byType(AttachmentStrip));
      expect(find.text('Attachments'), findsOneWidget);
      tester.view.viewInsets = const FakeViewPadding(bottom: 320);
      await tester.pumpAndSettle();
      expect(find.text('Attachments'), findsNothing);
      expect(h.editor.quillController.document, same(document));
      tester.view.viewInsets = FakeViewPadding.zero;
      await tester.pumpAndSettle();
      expect(find.text('Attachments'), findsOneWidget);
      expect(tester.state(find.byType(AttachmentStrip)), same(state));
      expect(h.files.writeAttempts, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      h.disposeEditor();
    },
  );
}
