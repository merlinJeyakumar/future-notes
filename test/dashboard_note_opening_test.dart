import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/features/dashboard/views/dashboard_screen.dart';
import 'package:flutter_application_1/features/dashboard/widgets/content_area.dart';
import 'package:flutter_application_1/features/dashboard/widgets/sidebar.dart';
import 'package:flutter_application_1/main.dart';
import 'support/editor_harness.dart';

void main() {
  for (final damaged in [false, true]) {
    testWidgets(
      'note opening retains undimmed dashboard and busy guards; damaged=$damaged',
      (tester) async {
        final h = await EditorHarness.create();
        h.seed(
          'first',
          h.note('first', 'First synthetic body'),
          encrypted: false,
        );
        h.seed(
          'second',
          h.note('second', 'Second synthetic body'),
          encrypted: false,
        );
        if (damaged) {
          h.files.seed('second', '{"id":"synthetic-invalid-schema"}');
        }
        final pause = PausePoint();
        tester.view.physicalSize = const Size(1440, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        try {
          await tester.pumpWidget(
            MyApp(
              settings: h.settings,
              home: DashboardScreen(
                settings: h.settings,
                fileService: h.files,
                startBackgroundServices: false,
              ),
            ),
          );
          final editor = tester
              .widget<ContentArea>(find.byType(ContentArea))
              .viewModel;
          expect((await editor.loadNote('first')).isSuccess, isTrue);
          await tester.pumpAndSettle();
          final contentState = tester.state(find.byType(ContentArea));
          final sidebarElement = tester.element(find.byType(Sidebar));
          final before = tester.getRect(find.byType(ContentArea));
          h.files.readPauses['second'] = pause;
          final opening = editor.loadNote('second');
          await pause.started.future;
          await tester.pump();
          expect(editor.isBusy, isTrue);
          expect(find.text('Processing...'), findsNothing);
          expect(find.byType(CircularProgressIndicator), findsNothing);
          expect(find.byType(LinearProgressIndicator), findsNothing);
          await tester.tap(find.text('New Note'), warnIfMissed: false);
          expect(editor.currentFileName, 'first');
          await tester.pump(const Duration(milliseconds: 200));
          expect(find.text('Processing...'), findsNothing);
          expect(find.byType(LinearProgressIndicator), findsOneWidget);
          expect(tester.getRect(find.byType(ContentArea)), before);
          expect(tester.state(find.byType(ContentArea)), same(contentState));
          expect(tester.element(find.byType(Sidebar)), same(sidebarElement));
          pause.resume();
          expect((await opening).isSuccess, !damaged);
          await tester.pump();
          expect(editor.currentFileName, damaged ? 'first' : 'second');
          expect(editor.isBusy, isFalse);
          expect(find.byType(LinearProgressIndicator), findsNothing);
          editor.setBusy(true);
          await tester.pump();
          expect(find.text('Processing...'), findsOneWidget);
          editor.setBusy(false);
          await tester.pump();
          expect(h.files.writeAttempts, 0);
        } finally {
          pause.resume();
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(seconds: 3));
          await tester.runAsync(h.dispose);
        }
      },
    );
  }
}
