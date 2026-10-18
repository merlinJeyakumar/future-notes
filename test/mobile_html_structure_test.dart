import 'package:code_text_field/code_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/features/dashboard/mobile/content_area.dart';
import 'package:flutter_application_1/features/dashboard/models/save_ui_state.dart';
import 'package:flutter_application_1/main.dart';
import 'support/editor_harness.dart';

void main() {
  testWidgets(
    'mobile HTML selection structures source and preserves rich-text round trip',
    (tester) async {
      final h = await EditorHarness.create(
        deltaToHtml: (_) async => '<p>Synthetic body</p>',
      );
      h.seed('demo', h.note('demo', 'Synthetic body'));
      await h.editor.loadNote('demo');
      final before = h.editor.quillController.document.toDelta().toJson();
      try {
        await tester.pumpWidget(
          MyApp(
            settings: h.settings,
            home: Scaffold(
              body: ListenableBuilder(
                listenable: h.editor,
                builder: (_, __) => MobileContentArea(viewModel: h.editor),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final html = tester.widget<TextButton>(
          find.widgetWithText(TextButton, 'HTML'),
        );
        await tester.runAsync(() async => await (html.onPressed as dynamic)());
        await tester.pumpAndSettle();
        expect(h.editor.htmlController.text, '<p>\n  Synthetic body\n</p>');
        final code = tester.widget<CodeField>(find.byType(CodeField));
        expect(code.textStyle!.fontFamily, 'monospace');
        expect(code.wrap, isFalse);
        expect(code.horizontalScroll, isTrue);
        expect(code.smartQuotesType, SmartQuotesType.disabled);
        expect(code.controller, same(h.editor.htmlController));
        await tester.runAsync(() async {
          expect(
            (await h.editor.setEditorMode(EditorMode.richText)).isSuccess,
            isTrue,
          );
        });
        await tester.pumpAndSettle();
        expect(h.editor.quillController.document.toDelta().toJson(), before);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(h.dispose);
      }
    },
  );
}
