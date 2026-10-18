import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/features/dashboard/mobile/export_progress_dialog.dart';
import 'package:flutter_application_1/features/dashboard/models/attachment_job.dart';
import 'package:flutter_application_1/features/dashboard/mobile/mobile_theme.dart';
import 'mobile_export_ready_test.dart' show ReadyModel, ReadyFile;
import 'mobile_attachment_presentation_test.dart' show captureSyntheticScreen;
import 'support/editor_harness.dart';

void main() {
  for (final scenario in [
    (const Size(390, 844), 1.0, TargetPlatform.android, Brightness.dark, 48.0),
    (const Size(320, 568), 1.0, TargetPlatform.android, Brightness.light, 48.0),
    (const Size(320, 568), 2.0, TargetPlatform.android, Brightness.dark, 48.0),
    (const Size(844, 390), 1.3, TargetPlatform.android, Brightness.light, 24.0),
    (const Size(280, 480), 2.0, TargetPlatform.iOS, Brightness.dark, 34.0),
    (const Size(1024, 768), 1.0, TargetPlatform.iOS, Brightness.light, 34.0),
    (const Size(800, 600), 1.5, TargetPlatform.windows, Brightness.light, 0.0),
    (const Size(600, 400), 1.0, TargetPlatform.macOS, Brightness.dark, 0.0),
  ]) {
    testWidgets('ready actions remain reachable: $scenario', (tester) async {
      tester.view.physicalSize = scenario.$1;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final h = await EditorHarness.create();
      final model = ReadyModel(h, ReadyFile('/synthetic/Workshop notes.fnote'));
      final job = AttachmentJobState(
        const AttachmentJobSnapshot(
          id: 'ready',
          owner: 0,
          fileName: 'Export package',
          phase: AttachmentJobPhase.completed,
          operation: AttachmentJobOperation.export,
        ),
      );
      try {
        await tester.pumpWidget(
          MaterialApp(
            theme:
                (scenario.$4 == Brightness.dark
                        ? MobileTheme.dark
                        : MobileTheme.light)
                    .copyWith(platform: scenario.$3),
            builder: (context, child) => RepaintBoundary(
              key: const ValueKey('synthetic-attachment-screen'),
              child: MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(scenario.$2),
                  padding: EdgeInsets.fromLTRB(0, 24, 0, scenario.$5),
                  viewPadding: EdgeInsets.fromLTRB(0, 24, 0, scenario.$5),
                ),
                child: child!,
              ),
            ),
            home: Scaffold(
              body: MobileExportProgressDialog(
                model: model,
                existingJob: job,
                noteTitle: 'Do not repeat this title',
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Export ready'), findsOneWidget);
        expect(find.text('Export complete'), findsNothing);
        expect(find.text('Do not repeat this title'), findsNothing);
        expect(
          find.text('Choose where to save or share this file.'),
          findsNothing,
        );
        for (final label in ['Save', 'Share', 'Close']) {
          final button = find.ancestor(
            of: find.text(label),
            matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
          );
          expect(button, findsOneWidget);
          expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
          final rect = tester.getRect(button);
          expect(rect.top, greaterThanOrEqualTo(24));
          expect(
            rect.bottom,
            lessThanOrEqualTo(scenario.$1.height - scenario.$5),
          );
          expect(find.text(label).hitTestable(), findsOneWidget);
        }
        if (scenario.$1.width == 390)
          await captureSyntheticScreen(tester, 'ready-polished-dark');
        if (scenario.$1.width == 320 && scenario.$2 == 1)
          await captureSyntheticScreen(tester, 'ready-polished-narrow');
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        model.dispose();
        job.dispose();
        await tester.runAsync(h.dispose);
      }
    });
  }
}
