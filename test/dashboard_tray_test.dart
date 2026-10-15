import 'dart:ui' show AppExitResponse;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/core/operations/operation_result.dart';
import 'package:flutter_application_1/features/dashboard/views/dashboard_screen.dart';
import 'package:flutter_application_1/features/dashboard/widgets/content_area.dart';
import 'package:flutter_application_1/main.dart';
import 'support/editor_harness.dart';
import 'attachment_strip_test.dart' show FakeDesktop, FakeOpenCache;

void main() {
  for (final fail in [false, true]) {
    testWidgets(
      'Close ${fail ? 'retains window after tray failure' : 'hides to tray without storage shutdown'}',
      (tester) async {
        final harness = await EditorHarness.create();
        final desktop = FakeDesktop()..failHide = fail;
        final cache = FakeOpenCache();
        var closeCalls = 0;
        try {
          await tester.pumpWidget(
            MyApp(
              settings: harness.settings,
              home: DashboardScreen(
                settings: harness.settings,
                fileService: harness.files,
                startBackgroundServices: false,
                desktopActions: desktop,
                attachmentOpenCache: cache,
                onClose: () async {
                  closeCalls++;
                  return const OperationResult.success();
                },
              ),
            ),
          );
          final exit = tester.binding.handleRequestAppExit();
          await tester.pump();
          expect(await exit, AppExitResponse.cancel);
          expect(desktop.hides, 1);
          expect(closeCalls, 0);
          expect(find.byType(ContentArea), findsOneWidget);
          if (fail) expect(find.text('Synthetic tray failure'), findsOneWidget);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          harness.disposeEditor();
          await tester.pump(const Duration(seconds: 3));
          await tester.runAsync(harness.dispose);
        }
      },
    );
  }
  testWidgets(
    'tray Exit bypasses minimize and follows the actual close request',
    (tester) async {
      final harness = await EditorHarness.create();
      final desktop = FakeDesktop();
      final cache = FakeOpenCache();
      var closed = 0;
      try {
        await tester.pumpWidget(
          MyApp(
            settings: harness.settings,
            home: DashboardScreen(
              settings: harness.settings,
              fileService: harness.files,
              startBackgroundServices: false,
              desktopActions: desktop,
              attachmentOpenCache: cache,
              requestApplicationExit: tester.binding.handleRequestAppExit,
              onClose: () async {
                closed++;
                return const OperationResult.success();
              },
            ),
          ),
        );
        desktop.controller.add('trayExit');
        for (var step = 0; step < 20 && closed == 0; step++) {
          await tester.runAsync(() async {
            await Future<void>.delayed(Duration.zero);
          });
          await tester.pump();
        }
        expect(closed, 1);
        expect(desktop.hides, 0);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        harness.disposeEditor();
        await tester.pump(const Duration(seconds: 3));
        await tester.runAsync(harness.dispose);
      }
    },
  );
}
