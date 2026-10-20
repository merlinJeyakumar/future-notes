import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/features/dashboard/mobile/import_flow_dialog.dart';

void main() {
  for (final required in [false, true]) {
    for (final cancel in [false, true]) {
      testWidgets(
        'compact import required=$required cancel=$cancel preserves explicit choice',
        (tester) async {
          tester.view.physicalSize = const Size(320, 568);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          String? result = 'not closed';
          await tester.pumpWidget(
            MaterialApp(
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: const TextScaler.linear(2),
                  viewInsets: const EdgeInsets.only(bottom: 180),
                ),
                child: child!,
              ),
              home: Builder(
                builder: (context) => TextButton(
                  onPressed: () async {
                    result = await showDialog<String>(
                      context: context,
                      builder: (_) => MobileImportSetupDialog(
                        fileName:
                            'Synthetic travel notes with Unicode 音声.fnote',
                        size: 2048,
                        fileType: 'Binary Note Package',
                        isPackage: true,
                        passwordRequired: required,
                      ),
                    );
                  },
                  child: const Text('Start'),
                ),
              ),
            ),
          );
          await tester.tap(find.text('Start'));
          await tester.pumpAndSettle();
          expect(find.text('Import note'), findsOneWidget);
          if (!required) {
            expect(find.byType(TextField), findsNothing);
            await tester.ensureVisible(find.text('Package has a password'));
            await tester.tap(find.text('Package has a password'));
            await tester.pumpAndSettle();
          }
          if (!cancel) {
            if (required) {
              await tester.ensureVisible(find.text('Import'));
              await tester.tap(find.text('Import'));
              await tester.pumpAndSettle();
              expect(find.text('Enter the package password.'), findsOneWidget);
            }
            await tester.ensureVisible(find.byType(TextField));
            await tester.enterText(
              find.byType(TextField),
              'synthetic-password',
            );
            await tester.pumpAndSettle();
          }
          await tester.ensureVisible(find.text(cancel ? 'Cancel' : 'Import'));
          await tester.pumpAndSettle();
          await tester.tap(find.text(cancel ? 'Cancel' : 'Import'));
          await tester.pumpAndSettle();
          expect(result, cancel ? isNull : 'synthetic-password');
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  testWidgets('passwordless import stays one step and returns empty password', (
    tester,
  ) async {
    String? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showDialog<String>(
                context: context,
                builder: (_) => const MobileImportSetupDialog(
                  fileName: 'Synthetic.fnote',
                  size: 128,
                  fileType: 'ZIP Note Package',
                  isPackage: true,
                  passwordRequired: false,
                ),
              );
            },
            child: const Text('Start'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import'));
    await tester.pumpAndSettle();
    expect(result, '');
    expect(tester.takeException(), isNull);
  });
}
