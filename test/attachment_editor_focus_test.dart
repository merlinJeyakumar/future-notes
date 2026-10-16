import 'package:code_text_field/code_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/features/dashboard/widgets/content_area.dart';
import 'package:flutter_application_1/main.dart';
import 'support/editor_harness.dart';
import 'attachment_strip_test.dart' show FakeOpenCache;

void main() {
  for (final html in [false, true]) {
    testWidgets(
      'editor focus collapses the dock without changing content or cache; html=$html',
      (tester) async {
        final cache = FakeOpenCache();
        final h = await EditorHarness.create(attachmentOpenCache: cache);
        tester.view.physicalSize = const Size(1440, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        h.seed(
          'synthetic',
          h.note(
            'synthetic',
            'Synthetic body',
            attachments: [
              {'id': 'file', 'fileName': 'sample.mp4', 'size': 100},
            ],
          ),
        );
        await h.editor.loadNote('synthetic');
        if (html) await tester.runAsync(h.editor.toggleEditorMode);
        try {
          await tester.pumpWidget(
            MyApp(
              settings: h.settings,
              home: Scaffold(
                body: ListenableBuilder(
                  listenable: h.editor,
                  builder: (_, _) => ContentArea(viewModel: h.editor),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final dock = find.byKey(const ValueKey('attachment-dock-items'));
          final editor = html
              ? find.byType(CodeField)
              : find.byType(QuillEditor);
          final editorState = tester.state(editor);
          final focus = html
              ? tester.widget<CodeField>(editor).focusNode!
              : h.editor.focusNode;
          final richController = h.editor.quillController;
          final body = richController.document.toPlainText();
          final source = h.editor.htmlController.text;
          final writes = h.files.writeAttempts;
          await tester.tap(find.text('Attachments (1)'));
          await tester.pumpAndSettle();
          expect(tester.getSize(dock).height, 104);
          h.editor.attachmentCacheNotifier.value++;
          await tester.pump();
          expect(tester.getSize(dock).height, 104);
          focus.requestFocus();
          await tester.pumpAndSettle();
          expect(focus.hasFocus, isTrue);
          expect(tester.getSize(dock).height, 36);

          // Expand without moving focus, then click the already-focused editor.
          final toggle = find.ancestor(
            of: find.text('Attachments (1)'),
            matching: find.byType(TextButton),
          );
          tester.widget<TextButton>(toggle).onPressed!();
          await tester.pumpAndSettle();
          expect(focus.hasFocus, isTrue);
          expect(tester.getSize(dock).height, 104);
          await tester.tapAt(tester.getTopLeft(editor) + const Offset(25, 25));
          await tester.pumpAndSettle();
          expect(tester.getSize(dock).height, 36);
          expect(tester.state(editor), same(editorState));
          expect(h.editor.quillController, same(richController));
          expect(richController.document.toPlainText(), body);
          expect(h.editor.htmlController.text, source);
          expect(h.files.writeAttempts, writes);
          expect(cache.opens, 0);
          expect(cache.invalidations, 0);
          expect(h.encryption.binaryDecryptCalls, 0);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          h.disposeEditor();
          await tester.pump(const Duration(seconds: 3));
          await tester.runAsync(h.dispose);
        }
      },
    );
  }
}
