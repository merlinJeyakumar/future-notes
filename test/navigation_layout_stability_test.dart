import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/core/theme/app_motion.dart';
import 'package:flutter_application_1/features/dashboard/models/note_list_ui_state.dart';
import 'package:flutter_application_1/features/dashboard/models/note_model.dart';
import 'package:flutter_application_1/features/dashboard/widgets/sidebar.dart';
import 'package:flutter_application_1/features/dashboard/widgets/content_area.dart';
import 'package:flutter_application_1/main.dart';
import 'support/editor_harness.dart';

void main() {
  testWidgets(
    'refresh and selection preserve sidebar row geometry and scroll position',
    (tester) async {
      final files = List.generate(
        50,
        (i) => RecentFile(
          path: 'note$i',
          fullPath: 'D:/synthetic/note$i',
          title: 'Synthetic note $i',
        ),
      );
      var scanning = false;
      var selected = files.first.fullPath;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return Scaffold(
                body: Sidebar(
                  listState: NoteListUiState(
                    files: files,
                    isScanning: scanning,
                    selectedContentPath: selected,
                  ),
                  onFileSelected: (_) {},
                  onOpenFolder: (_) {},
                  onDelete: (_) {},
                  onNewNote: () {},
                  onRefresh: () {},
                  onRecentFileSelected: (file) =>
                      update(() => selected = file.fullPath),
                ),
              );
            },
          ),
        ),
      );
      final list = find.byType(CustomScrollView);
      await tester.drag(list, const Offset(0, -400));
      await tester.pumpAndSettle();
      final scroll = tester.state<ScrollableState>(
        find.descendant(of: list, matching: find.byType(Scrollable)),
      );
      final row = find.byKey(ValueKey(files[6].fullPath));
      final originalY = tester.getTopLeft(row).dy;
      final originalOffset = scroll.position.pixels;
      update(() => scanning = true);
      await tester.pump();
      expect(tester.getTopLeft(row).dy, closeTo(originalY, .01));
      expect(scroll.position.pixels, originalOffset);
      update(() => scanning = false);
      await tester.pump();
      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(row).dy, closeTo(originalY, .01));
      expect(scroll.position.pixels, originalOffset);
    },
  );

  testWidgets(
    'note selection publishes the new editor geometry once without a vertical bounce',
    (tester) async {
      final h = await EditorHarness.create();
      h.seed(
        'first',
        h.note(
          'first',
          'First synthetic body',
          attachments: [
            {'id': 'file', 'fileName': 'synthetic.txt', 'size': 10},
          ],
        ),
      );
      h.seed('second', h.note('second', 'Second synthetic body'));
      await h.editor.loadNote('first');
      try {
        await tester.pumpWidget(
          MyApp(
            settings: h.settings,
            home: Scaffold(
              body: ListenableBuilder(
                listenable: h.editor,
                builder: (_, _) => ContentArea(viewModel: h.editor),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Attachments (1)'));
        await tester.pumpAndSettle();
        final editorState = tester.state(find.byType(QuillEditor));
        await h.editor.loadNote('second');
        await tester.pump();
        final editorRect = tester.getRect(find.byType(QuillEditor));
        final entrance = find.byType(AppEntrance);
        double lift() => tester
            .widget<Transform>(
              find
                  .descendant(of: entrance, matching: find.byType(Transform))
                  .first,
            )
            .transform
            .storage[13];
        expect(lift(), 0);
        expect(
          tester
              .widget<Opacity>(
                find
                    .descendant(of: entrance, matching: find.byType(Opacity))
                    .first,
              )
              .opacity,
          1,
        );
        for (final ms in [40, 80, 160]) {
          await tester.pump(Duration(milliseconds: ms));
          expect(tester.getRect(find.byType(QuillEditor)), editorRect);
          expect(lift(), 0);
          expect(
            tester
                .widget<Opacity>(
                  find
                      .descendant(of: entrance, matching: find.byType(Opacity))
                      .first,
                )
                .opacity,
            1,
          );
          expect(tester.state(find.byType(QuillEditor)), same(editorState));
        }
        expect(h.files.writeAttempts, 0);
        await tester.runAsync(h.editor.toggleEditorMode);
        await tester.pumpAndSettle();
        await h.editor.loadNote('first');
        await tester.pump();
        // Mode conversion is an actual edit and may be saved on navigation.
        // Animation frames themselves must not schedule any further write.
        final writesAfterNavigation = h.files.writeAttempts;
        final richRect = tester.getRect(find.byType(QuillEditor));
        for (final ms in [40, 80, 160]) {
          await tester.pump(Duration(milliseconds: ms));
          expect(tester.getRect(find.byType(QuillEditor)), richRect);
          expect(lift(), 0);
        }
        expect(h.files.writeAttempts, writesAfterNavigation);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        h.disposeEditor();
        await tester.pump(const Duration(seconds: 3));
        await tester.runAsync(h.dispose);
      }
    },
  );
}
