import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/features/dashboard/mobile/dashboard_screen.dart';
import 'package:flutter_application_1/features/dashboard/mobile/content_area.dart';
import 'package:flutter_application_1/features/dashboard/mobile/sidebar.dart';
import 'package:flutter_application_1/features/dashboard/models/note_list_ui_state.dart';
import 'package:flutter_application_1/features/dashboard/models/note_model.dart';
import 'package:flutter_application_1/main.dart';
import 'support/editor_harness.dart';

void main() {
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
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        publishInventory();
        await tester.pump();
        expect(find.byType(MobileNotesList), findsOneWidget);
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
