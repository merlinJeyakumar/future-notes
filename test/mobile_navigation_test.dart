import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/features/dashboard/mobile/dashboard_screen.dart';
import 'package:flutter_application_1/features/dashboard/mobile/content_area.dart';
import 'package:flutter_application_1/features/dashboard/mobile/sidebar.dart';
import 'package:flutter_application_1/features/dashboard/mobile/export_progress_dialog.dart';
import 'package:flutter_application_1/features/dashboard/mobile/work_decision_dialog.dart';
import 'package:flutter_application_1/features/dashboard/models/attachment_job.dart';
import 'package:flutter_application_1/features/dashboard/models/note_list_ui_state.dart';
import 'package:flutter_application_1/features/dashboard/models/note_model.dart';
import 'package:flutter_application_1/main.dart';
import 'support/editor_harness.dart';

void main() {
  testWidgets(
    'exporting note opens read-only and list progress action reconnects to the job',
    (tester) async {
      final harness = await EditorHarness.create();
      harness.seed(
        'first',
        harness.note('first', 'Synthetic body'),
        encrypted: false,
      );
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      AttachmentJobState? job;
      try {
        await tester.pumpWidget(
          MyApp(
            settings: harness.settings,
            home: MobileDashboardScreen(
              mobileLayout: true,
              settings: harness.settings,
              fileService: harness.files,
              startBackgroundServices: false,
            ),
          ),
        );
        await tester.pumpAndSettle();
        final editor = tester
            .widget<MobileContentArea>(
              find.byType(MobileContentArea, skipOffstage: false),
            )
            .viewModel;
        final inventory = NoteListUiState(
          files: [
            RecentFile(
              path: 'first',
              fullPath: harness.files.reference('first').contentPath,
              title: 'Synthetic title first',
            ),
          ],
        );
        editor.noteListStateNotifier.value = inventory;
        await tester.pump();
        await tester.tap(
          find.byTooltip('More actions for Synthetic title first'),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Export'));
        await tester.pumpAndSettle();
        // Export from the list retains its note before a worker pins the owner.
        expect(find.text('Export Options'), findsOneWidget);
        expect(editor.currentFileName, 'first');
        expect(editor.quillController.readOnly, isTrue);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(editor.quillController.readOnly, isFalse);
        // This harness supplies inventory explicitly; its file service does not
        // run platform discovery after loading the retained editor.
        editor.noteListStateNotifier.value = inventory;
        final controller = editor.quillController;
        final generation = editor.draftSession.generation;
        final noteRow = find.descendant(
          of: find.byKey(
            ValueKey(harness.files.reference('first').contentPath),
          ),
          matching: find.byType(ListTile),
        );
        AttachmentJobSnapshot snapshot(AttachmentJobPhase phase) =>
            AttachmentJobSnapshot(
              id: 'same-export',
              owner: editor.draftSession.generation,
              fileName: 'Export package',
              operation: AttachmentJobOperation.export,
              phase: phase,
              bytes: phase == AttachmentJobPhase.preparing ? 50 : 0,
              total: phase == AttachmentJobPhase.preparing ? 100 : null,
              detail: phase == AttachmentJobPhase.preparing
                  ? 'Writing package · synthetic.mp4'
                  : null,
            );
        job = AttachmentJobState(snapshot(AttachmentJobPhase.preparing));
        editor.attachmentJobsNotifier.value = [job];
        await tester.pump();
        for (final phase in [
          AttachmentJobPhase.preparing,
          AttachmentJobPhase.finalizing,
        ]) {
          job.update(snapshot(phase));
          await tester.tap(noteRow);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(find.byType(MobileExportProgressDialog), findsNothing);
          expect(find.byTooltip('Back to notes'), findsOneWidget);
          expect(controller.readOnly, isTrue);
          expect(editor.quillController, same(controller));
          expect(editor.draftSession.generation, generation);
          expect(
            tester
                .widget<IconButton>(
                  find.byWidgetPredicate(
                    (widget) =>
                        widget is IconButton && widget.tooltip == 'Attach file',
                  ),
                )
                .onPressed,
            isNull,
          );
          expect(find.byType(MobileWorkDecisionDialog), findsNothing);
          expect(find.byType(SnackBar), findsNothing);
          expect(editor.currentFileName, 'first');
          expect(editor.attachmentJobsNotifier.value.single, same(job));
          await tester.tap(find.byTooltip('Back to notes'));
          await tester.pump(const Duration(milliseconds: 300));
          final progress = find.byTooltip('View export progress');
          expect(progress, findsOneWidget);
          expect(
            find.descendant(
              of: progress,
              matching: find.byType(CircularProgressIndicator),
            ),
            findsOneWidget,
          );
          await tester.tap(progress);
          await tester.pump(const Duration(milliseconds: 300));
          expect(find.byType(MobileExportProgressDialog), findsOneWidget);
          await tester.tap(find.text('Hide'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(find.byType(MobileExportProgressDialog), findsNothing);
          expect(job.progress.value.active, isTrue);
        }
        job.update(snapshot(AttachmentJobPhase.completed));
        editor.attachmentJobsNotifier.value = [];
        await tester.pump();
        expect(find.byTooltip('View export progress'), findsNothing);
        await tester.tap(noteRow);
        await tester.pumpAndSettle();
        expect(editor.currentFileName, 'first');
        expect(find.byTooltip('Back to notes'), findsOneWidget);
        // The editor's new Export action reconnects to the existing job too.
        job.update(snapshot(AttachmentJobPhase.preparing));
        editor.attachmentJobsNotifier.value = [job];
        await tester.tap(find.byTooltip('Note actions'));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.text('Export'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byType(MobileExportProgressDialog), findsOneWidget);
        expect(editor.attachmentJobsNotifier.value.single, same(job));
        expect(editor.currentFileName, 'first');
        await tester.tap(find.text('Hide'));
        await tester.pump(const Duration(milliseconds: 300));
        expect(editor.quillController.readOnly, isTrue);
        job.update(snapshot(AttachmentJobPhase.completed));
        editor.attachmentJobsNotifier.value = [];
        await tester.pump();
        expect(editor.quillController.readOnly, isFalse);
        expect(harness.files.writeAttempts, 0);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 3));
        job?.dispose();
        await tester.runAsync(harness.dispose);
      }
    },
  );
  testWidgets(
    'new editor draft Export asks to save and Cancel preserves the draft',
    (tester) async {
      final h = await EditorHarness.create();
      try {
        await tester.pumpWidget(
          MyApp(
            settings: h.settings,
            home: MobileDashboardScreen(
              mobileLayout: true,
              settings: h.settings,
              fileService: h.files,
              startBackgroundServices: false,
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('New note'));
        await tester.pumpAndSettle();
        final editor = tester
            .widget<MobileContentArea>(find.byType(MobileContentArea))
            .viewModel;
        editor.quillController.document.insert(0, 'Synthetic unsaved draft');
        final controller = editor.quillController;
        final body = controller.document.toPlainText();
        await tester.tap(find.byTooltip('Note actions'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Export'));
        await tester.pumpAndSettle();
        expect(find.text('Save before exporting?'), findsOneWidget);
        expect(find.text('Save & Export'), findsOneWidget);
        expect(controller.readOnly, isTrue);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(controller.readOnly, isFalse);
        expect(editor.currentFileName, isNull);
        expect(editor.quillController, same(controller));
        expect(controller.document.toPlainText(), body);
        expect(h.files.writeAttempts, 0);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 3));
        await tester.runAsync(h.dispose);
      }
    },
  );
  testWidgets(
    'phone list/editor navigation retains the editor and tablet splits',
    (tester) async {
      final harness = await EditorHarness.create();
      harness.seed(
        'first',
        harness.note('first', 'First synthetic body'),
        encrypted: false,
      );
      harness.seed(
        'second',
        harness.note('second', 'Second synthetic body'),
        encrypted: false,
      );
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      try {
        await tester.pumpWidget(
          MyApp(
            settings: harness.settings,
            home: MobileDashboardScreen(
              mobileLayout: true,
              settings: harness.settings,
              fileService: harness.files,
              startBackgroundServices: false,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(MobileNotesList), findsOneWidget);
        expect(tester.getSize(find.byType(MobileNotesList)).width, 390);
        final editorFinder = find.byType(
          MobileContentArea,
          skipOffstage: false,
        );
        final originalState = tester.state(editorFinder);
        final editor = tester.widget<MobileContentArea>(editorFinder).viewModel;
        // Discovery is deliberately disabled in this routing fixture. Publish its
        // immutable metadata projection without starting a filesystem worker.
        void publishInventory() {
          editor.noteListStateNotifier.value = NoteListUiState(
            files: [
              for (final name in ['first', 'second'])
                RecentFile(
                  path: name,
                  fullPath: harness.files.reference(name).contentPath,
                  title: 'Synthetic title $name',
                ),
            ],
          );
        }

        publishInventory();
        await tester.pumpAndSettle();
        await tester.tap(find.text('Synthetic title first'));
        await tester.pumpAndSettle();
        expect(find.byTooltip('Back to notes'), findsOneWidget);
        expect(find.byType(MobileNotesList), findsNothing);
        expect(editor.currentFileName, 'first');
        expect(
          tester.state(find.byType(MobileContentArea)),
          same(originalState),
        );
        await tester.tap(find.byKey(const ValueKey('formatting-touch-toggle')));
        await tester.pumpAndSettle();
        expect(find.byTooltip('Collapse formatting tools'), findsOneWidget);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        publishInventory();
        await tester.pump();
        expect(find.byType(MobileNotesList), findsOneWidget);
        expect(find.text('Less', skipOffstage: false), findsNothing);
        expect(editor.currentFileName, 'first');
        await tester.tap(find.text('Synthetic title second'));
        await tester.pumpAndSettle();
        expect(editor.currentFileName, 'second');
        tester.view.physicalSize = const Size(900, 1200);
        await tester.pumpAndSettle();
        expect(find.byType(MobileNotesList), findsOneWidget);
        expect(find.byType(MobileContentArea), findsOneWidget);
        expect(
          tester.state(find.byType(MobileContentArea)),
          same(originalState),
        );
        expect(
          tester.getRect(find.byType(MobileNotesList)).right,
          lessThanOrEqualTo(
            tester.getRect(find.byType(MobileContentArea)).left,
          ),
        );
        expect(tester.takeException(), isNull);
        expect(harness.files.writeAttempts, 0);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 3));
        await tester.runAsync(harness.dispose);
      }
    },
  );
}
