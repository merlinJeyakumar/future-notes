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
  for (final confirm in [false, true]) {
    testWidgets(
      'Close ${confirm ? 'confirms actual exit' : 'cancels without closing storage'}',
      (tester) async {
        final harness = await EditorHarness.create();
        final desktop = FakeDesktop();
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
          await tester.pump(const Duration(milliseconds: 300));
          expect(find.text('Exit Future Notes?'), findsOneWidget);
          expect(closeCalls, 0);
          await tester.tap(find.text(confirm ? 'Exit' : 'Keep open'));
          await tester.pumpAndSettle();
          expect(
            await exit,
            confirm ? AppExitResponse.exit : AppExitResponse.cancel,
          );
          expect(desktop.hides, 0);
          expect(closeCalls, confirm ? 1 : 0);
          expect(find.byType(ContentArea), findsOneWidget);
          expect(harness.files.writeAttempts, 0);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          harness.disposeEditor();
          await tester.pump(const Duration(seconds: 3));
          await tester.runAsync(harness.dispose);
        }
      },
    );
  }
  testWidgets('tray Exit confirms then follows the same actual close request', (
    tester,
  ) async {
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
      await tester.pumpAndSettle();
      expect(find.text('Exit Future Notes?'), findsOneWidget);
      expect(closed, 0);
      await tester.tap(find.text('Exit'));
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
  });
}
