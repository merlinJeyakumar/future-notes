import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_application_1/features/dashboard/views/dashboard_screen.dart';
import 'package:flutter_application_1/features/dashboard/widgets/content_area.dart';
import 'package:flutter_application_1/features/dashboard/widgets/sidebar.dart';
import 'package:flutter_application_1/main.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/editor_harness.dart';

void main() {
  for (final width in [800.0, 1200.0]) {
    for (final fromEditor in [true, false]) {
      testWidgets(
        'search shortcut at width $width fromEditor=$fromEditor',
        (tester) async {
          final h = await EditorHarness.create();
          tester.view.physicalSize = Size(width, 900);
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
                  confirmExit: () async => false,
                ),
              ),
            );
            final area = tester.widget<ContentArea>(find.byType(ContentArea));
            final document = area.viewModel.quillController.document;
            if (fromEditor) {
              area.viewModel.focusNode.requestFocus();
            } else {
              await tester.tap(
                find.descendant(
                  of: find.byType(ContentArea),
                  matching: find.byType(TextField),
                ),
              );
            }
            await tester.pump();
            if (fromEditor) {
              expect(
                area.viewModel.focusNode.hasFocus,
                isTrue,
                reason:
                    'The editor must own keyboard focus before the shortcut.',
              );
            }
            final modifier = Platform.isMacOS
                ? LogicalKeyboardKey.metaLeft
                : LogicalKeyboardKey.controlLeft;
            Future<void> searchShortcut() async {
              await tester.sendKeyDownEvent(modifier);
              await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
              await tester.sendKeyUpEvent(modifier);
              await tester.pump();
              await tester.pump(const Duration(milliseconds: 350));
              await tester.pump();
            }

            await searchShortcut();
            if (fromEditor) {
              // Find inside the note owns its input, without a mouse click.
              final searchRow = find.ancestor(
                of: find.byIcon(Icons.keyboard_arrow_up),
                matching: find.byType(Row),
              );
              final input = find.descendant(
                of: searchRow,
                matching: find.byType(EditableText),
              );
              expect(input, findsOneWidget);
              final field = tester.widget<EditableText>(input);
              expect(field.focusNode.hasFocus, isTrue);
              tester.testTextInput.enterText('synthetic query');
              await tester.pump(const Duration(milliseconds: 500));
              expect(field.controller.text, 'synthetic query');
              expect(field.focusNode.hasFocus, isTrue);
              await tester.tap(
                find.descendant(
                  of: searchRow,
                  matching: find.byIcon(Icons.close),
                ),
              );
              await tester.pump();
              await tester.pump(const Duration(milliseconds: 350));
              await tester.pump();
              expect(area.viewModel.focusNode.hasFocus, isTrue);
              expect(area.viewModel.quillController.document, same(document));
              expect(h.files.writeAttempts, 0);
              expect(tester.takeException(), isNull);
              return;
            }
            final search = find.descendant(
              of: find.byType(Sidebar),
              matching: find.byType(TextField),
            );
            expect(search, findsOneWidget);
            final field = tester.widget<TextField>(search);
            expect(field.focusNode!.hasFocus, isTrue);
            // Send keyboard input without tapping or programmatically focusing it.
            tester.testTextInput.enterText('synthetic query');
            await tester.pump(const Duration(milliseconds: 500));
            expect(field.controller!.text, 'synthetic query');
            expect(field.focusNode!.hasFocus, isTrue);
            await searchShortcut();
            expect(field.focusNode!.hasFocus, isTrue);
            expect(field.controller!.text, 'synthetic query');
            expect(area.viewModel.quillController.document, same(document));
            expect(h.files.writeAttempts, 0);
            expect(tester.takeException(), isNull);
          } finally {
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pump(const Duration(seconds: 3));
            await tester.runAsync(h.dispose);
          }
        },
        variant: TargetPlatformVariant.only(
          Platform.isMacOS ? TargetPlatform.macOS : TargetPlatform.windows,
        ),
      );
    }
  }
}
