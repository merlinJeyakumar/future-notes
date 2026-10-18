import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/main.dart';
import 'package:flutter_application_1/features/dashboard/mobile/content_area.dart';
import 'package:flutter_application_1/features/dashboard/widgets/content_area.dart';
import 'package:flutter_application_1/features/dashboard/widgets/sidebar.dart';
import 'package:flutter_application_1/features/dashboard/widgets/app_overflow_menu.dart';
import 'package:flutter_application_1/features/dashboard/widgets/background_tasks_dialog.dart';
import 'support/editor_harness.dart';

void main() {
  testWidgets('idle overflow opens tasks with a standard menu icon', (
    tester,
  ) async {
    var opened = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppOverflowMenu(onBackgroundTasks: () => opened++),
        ),
      ),
    );
    expect(find.byIcon(Icons.pending_actions), findsNothing);
    expect(find.byType(Badge), findsNothing);
    await tester.tap(find.byTooltip('More actions'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.pending_actions), findsOneWidget);
    await tester.tap(find.text('Background tasks'));
    await tester.pumpAndSettle();
    expect(opened, 1);
    expect(find.text('Background tasks'), findsNothing);
  });

  testWidgets(
    'desktop sidebar exposes background tasks without a standalone button',
    (tester) async {
      var opened = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Sidebar(
              onFileSelected: (_) {},
              onOpenFolder: (_) {},
              onDelete: (_) {},
              onNewNote: () {},
              onBackgroundTasks: () => opened++,
            ),
          ),
        ),
      );
      await tester.tap(find.byTooltip('More actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Background tasks'));
      await tester.pumpAndSettle();
      expect(opened, 1);
      expect(find.byIcon(Icons.pause_circle_outline), findsNothing);
    },
  );

  for (final mobile in [false, true]) {
    testWidgets('editor overflow preserves editing state (mobile=$mobile)', (
      tester,
    ) async {
      final h = await EditorHarness.create();
      h.seed('demo', h.note('demo', 'Synthetic text'));
      await h.editor.loadNote('demo');
      final controller = h.editor.quillController;
      final document = controller.document;
      var opened = 0;
      try {
        await tester.pumpWidget(
          MyApp(
            settings: h.settings,
            home: Scaffold(
              body: mobile
                  ? MobileContentArea(
                      viewModel: h.editor,
                      onJobNotifications: () => opened++,
                    )
                  : ContentArea(
                      viewModel: h.editor,
                      onBackgroundTasks: () => opened++,
                    ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byIcon(Icons.pending_actions), findsNothing);
        await tester.tap(find.byTooltip('Note actions'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Background tasks'));
        await tester.pumpAndSettle();
        expect(opened, 1);
        expect(find.byType(AlertDialog), findsNothing);
        expect(h.editor.quillController, same(controller));
        expect(controller.document, same(document));
        expect(h.files.writes, isEmpty);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(h.dispose);
      }
    });
  }

  testWidgets('shared task dialog works without a mobile runtime', (
    tester,
  ) async {
    final h = await EditorHarness.create();
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: BackgroundTasksDialog(model: h.editor, selectExportJobs: false),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('No pending jobs.'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
      expect(h.files.writes, isEmpty);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(h.dispose);
    }
  });
}
