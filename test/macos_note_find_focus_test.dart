import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_application_1/features/dashboard/widgets/content_area.dart';
import 'package:flutter_application_1/features/dashboard/widgets/macos_note_find_dialog.dart';
import 'package:flutter_application_1/main.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/editor_harness.dart';

void main() {
  for (final submit in [true, false]) {
    testWidgets(
      'Mac Find ${submit ? 'Enter' : 'Close'} returns primary focus and typing',
      (tester) async {
        final h = await EditorHarness.create();
        tester.view.physicalSize = const Size(1200, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        try {
          final document = h.editor.quillController.document;
          document.insert(0, 'Alpha alpha alphabet\n');
          await tester.pumpWidget(
            MyApp(
              settings: h.settings,
              home: Scaffold(body: ContentArea(viewModel: h.editor)),
            ),
          );
          h.editor.focusNode.requestFocus();
          await tester.pump();
          await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
          await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 350));
          final dialog = find.byType(MacosNoteFindDialog);
          expect(dialog, findsOneWidget);
          tester.testTextInput.enterText('alpha');
          await tester.pump(const Duration(milliseconds: 350));
          if (submit) {
            await tester.testTextInput.receiveAction(TextInputAction.done);
          } else {
            await tester.tap(
              find.descendant(of: dialog, matching: find.byIcon(Icons.close)),
            );
          }
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          await tester.pump();
          expect(dialog, findsNothing);
          expect(h.editor.focusNode.hasPrimaryFocus, isTrue);
          expect(h.editor.quillController.document, same(document));
          expect(h.files.writeAttempts, 0);
          // No tap, enterText finder, or extra requestFocus may reconnect input.
          final remote = tester.testTextInput.editingState!;
          final text = remote['text'] as String;
          final selection = h.editor.quillController.selection;
          expect(text, document.toPlainText());
          final updated = text.replaceRange(
            selection.start,
            selection.end,
            'typed',
          );
          tester.testTextInput.updateEditingValue(
            TextEditingValue(
              text: updated,
              selection: TextSelection.collapsed(offset: selection.start + 5),
            ),
          );
          await tester.pump();
          expect(document.toPlainText(), updated);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(seconds: 3));
          await tester.runAsync(h.dispose);
        }
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );
  }
}
