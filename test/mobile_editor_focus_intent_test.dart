import 'package:code_text_field/code_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/core/theme/app_dialog.dart';
import 'package:flutter_application_1/features/dashboard/mobile/content_area.dart';
import 'package:flutter_application_1/features/dashboard/mobile/editor_focus.dart';
import 'package:flutter_application_1/features/dashboard/models/auto_save_policy.dart';
import 'package:flutter_application_1/features/dashboard/models/save_ui_state.dart';
import 'package:flutter_application_1/main.dart';
import 'support/editor_harness.dart';

void main() {
  Future<void> mount(WidgetTester tester, EditorHarness h) async {
    await tester.pumpWidget(
      MyApp(
        settings: h.settings,
        home: Scaffold(
          body: ListenableBuilder(
            listenable: h.editor,
            builder: (_, _) => MobileContentArea(viewModel: h.editor),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> cleanup(WidgetTester tester, EditorHarness h) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(h.dispose);
  }

  testWidgets('opening and controller changes wait for an actual editor tap', (
    tester,
  ) async {
    final h = await EditorHarness.create();
    h.seed('demo', h.note('demo', 'Synthetic writing'));
    await h.editor.loadNote('demo');
    final controller = h.editor.quillController;
    final document = controller.document;
    try {
      await mount(tester, h);
      expect(h.editor.focusNode.hasFocus, isFalse);
      expect(tester.testTextInput.isVisible, isFalse);
      controller.updateSelection(
        const TextSelection(baseOffset: 0, extentOffset: 9),
        ChangeSource.local,
      );
      await tester.pumpAndSettle();
      expect(h.editor.focusNode.hasFocus, isFalse);
      await tester.tap(find.byType(QuillEditor));
      await tester.pumpAndSettle();
      expect(h.editor.focusNode.hasFocus, isTrue);
      expect(tester.testTextInput.isVisible, isTrue);
      expect(controller.document, same(document));
    } finally {
      await cleanup(tester, h);
    }
  });

  for (final html in [false, true]) {
    testWidgets(
      'typing stays focused through updates and mobile autosave HTML=$html',
      (tester) async {
        final h = await EditorHarness.create(
          autoSavePolicy: AutoSavePolicy.mobile,
          deltaToHtml: (_) async => '<p>Synthetic editing</p>',
        );
        h.seed('demo', h.note('demo', 'Synthetic editing'));
        await h.editor.loadNote('demo');
        if (html) {
          expect(
            (await h.editor.setEditorMode(EditorMode.html)).isSuccess,
            isTrue,
          );
        }
        final document = h.editor.quillController.document;
        try {
          await mount(tester, h);
          final input = html
              ? find.byType(CodeField)
              : find.byType(QuillEditor);
          await tester.tapAt(tester.getTopLeft(input) + const Offset(70, 30));
          await tester.pumpAndSettle();
          final focus = html
              ? tester.widget<CodeField>(input).focusNode!
              : h.editor.focusNode;
          expect(focus.hasFocus, isTrue);
          const word = 'validation';
          for (var count = 1; count <= word.length; count++) {
            final value = html
                ? '<p>Synthetic editing ${word.substring(0, count)}</p>'
                : 'Synthetic editing ${word.substring(0, count)}\n';
            tester.testTextInput.updateEditingValue(
              TextEditingValue(
                text: value,
                selection: TextSelection.collapsed(
                  offset: value.length - (html ? 4 : 1),
                ),
              ),
            );
            await tester.pump();
            expect(focus.hasFocus, isTrue, reason: 'character $count');
            expect(
              tester.testTextInput.isVisible,
              isTrue,
              reason: 'character $count',
            );
            expect(
              html ? h.editor.htmlController.text : document.toPlainText(),
              value,
            );
            h.editor.notifyListeners();
            await tester.pump();
            expect(
              focus.hasFocus,
              isTrue,
              reason: 'model rebuild after character $count',
            );
          }
          expect(h.files.writeAttempts, 0);
          await tester.pump(const Duration(seconds: 15));
          await tester.pump();
          expect(h.files.writeAttempts, 1);
          expect(focus.hasFocus, isTrue, reason: 'autosave acknowledgement');
          expect(tester.testTextInput.isVisible, isTrue);
          expect(h.editor.quillController.document, same(document));
          final expected = html
              ? '<p>Synthetic editing validation</p>'
              : 'Synthetic editing validation\n';
          expect(
            html ? h.editor.htmlController.text : document.toPlainText(),
            expected,
          );
        } finally {
          await cleanup(tester, h);
        }
      },
    );
  }

  testWidgets('hardware typing survives a soft keyboard inset becoming zero', (
    tester,
  ) async {
    final h = await EditorHarness.create(autoSavePolicy: AutoSavePolicy.mobile);
    h.seed('demo', h.note('demo', 'Synthetic editing'));
    await h.editor.loadNote('demo');
    addTearDown(tester.view.resetViewInsets);
    try {
      await mount(tester, h);
      await tester.tap(find.byType(QuillEditor));
      await tester.pumpAndSettle();
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'Synthetic editing v\n',
          selection: TextSelection.collapsed(offset: 19),
        ),
      );
      await tester.pump();
      expect(h.editor.focusNode.hasFocus, isTrue);
      tester.view.viewInsets = FakeViewPadding.zero;
      await tester.pumpAndSettle();
      expect(
        h.editor.focusNode.hasFocus,
        isTrue,
        reason: 'hardware IME hide is not an outside interaction',
      );
      for (final text in [
        'Synthetic editing va\n',
        'Synthetic editing val\n',
        'Synthetic editing validation\n',
      ]) {
        tester.testTextInput.updateEditingValue(
          TextEditingValue(
            text: text,
            selection: TextSelection.collapsed(offset: text.length - 1),
          ),
        );
        await tester.pump();
        expect(h.editor.focusNode.hasFocus, isTrue);
        expect(h.editor.quillController.document.toPlainText(), text);
      }
    } finally {
      await cleanup(tester, h);
    }
  });

  for (final back in [false, true]) {
    testWidgets(
      'dialog ${back ? 'Back' : 'Close'} does not restore the editor',
      (tester) async {
        final h = await EditorHarness.create();
        h.seed('demo', h.note('demo', 'Synthetic writing'));
        await h.editor.loadNote('demo');
        try {
          await mount(tester, h);
          await tester.tap(find.byType(QuillEditor));
          await tester.pumpAndSettle();
          expect(h.editor.focusNode.hasFocus, isTrue);
          await tester.tap(find.byTooltip('Note actions'));
          await tester.pumpAndSettle();
          if (back) {
            await tester.binding.handlePopRoute();
          } else {
            await tester.tap(find.text('Close'));
          }
          await tester.pumpAndSettle();
          expect(h.editor.focusNode.hasFocus, isFalse);
          expect(tester.testTextInput.isVisible, isFalse);
          h.editor.quillController.updateSelection(
            const TextSelection.collapsed(offset: 3),
            ChangeSource.local,
          );
          await tester.pumpAndSettle();
          expect(h.editor.focusNode.hasFocus, isFalse);
          expect(tester.testTextInput.isVisible, isFalse);
        } finally {
          await cleanup(tester, h);
        }
      },
    );
  }

  testWidgets(
    'formatting with dismissed keyboard preserves selection quietly',
    (tester) async {
      final h = await EditorHarness.create();
      h.seed('demo', h.note('demo', 'Synthetic writing'));
      await h.editor.loadNote('demo');
      try {
        await mount(tester, h);
        const selection = TextSelection(baseOffset: 0, extentOffset: 9);
        h.editor.quillController.updateSelection(selection, ChangeSource.local);
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Bold'));
        await tester.pumpAndSettle();
        expect(h.editor.quillController.selection, selection);
        expect(
          h.editor.quillController.getSelectionStyle().attributes,
          contains('bold'),
        );
        await tester.tap(find.byTooltip('Expand formatting tools'));
        await tester.pumpAndSettle();
        expect(h.editor.focusNode.hasFocus, isFalse);
        expect(tester.testTextInput.isVisible, isFalse);
        expect(h.editor.quillController.selection, selection);
        expect(find.byTooltip('Collapse formatting tools'), findsOneWidget);
      } finally {
        await cleanup(tester, h);
      }
    },
  );

  testWidgets('returning from background requires a new editor tap', (
    tester,
  ) async {
    final h = await EditorHarness.create();
    h.seed('demo', h.note('demo', 'Synthetic writing'));
    await h.editor.loadNote('demo');
    try {
      await mount(tester, h);
      await tester.tap(find.byType(QuillEditor));
      await tester.pumpAndSettle();
      expect(h.editor.focusNode.hasFocus, isTrue);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(h.editor.focusNode.hasFocus, isFalse);
      expect(tester.testTextInput.isVisible, isFalse);
      await tester.tap(find.byType(QuillEditor));
      await tester.pumpAndSettle();
      expect(h.editor.focusNode.hasFocus, isTrue);
      expect(tester.testTextInput.isVisible, isTrue);
    } finally {
      if (tester.binding.lifecycleState != AppLifecycleState.resumed) {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
      }
      await cleanup(tester, h);
    }
  });

  testWidgets('HTML mode and formatting wait for its own input tap', (
    tester,
  ) async {
    final h = await EditorHarness.create(
      deltaToHtml: (_) async => '<p>Synthetic writing</p>',
    );
    h.seed('demo', h.note('demo', 'Synthetic writing'));
    await h.editor.loadNote('demo');
    try {
      await mount(tester, h);
      final htmlButton = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'HTML'),
      );
      await tester.runAsync(
        () async => await (htmlButton.onPressed as dynamic)(),
      );
      await tester.pumpAndSettle();
      final source = tester.widget<CodeField>(find.byType(CodeField));
      expect(source.focusNode!.hasFocus, isFalse);
      source.focusNode!.requestFocus();
      await tester.pumpAndSettle();
      expect(source.focusNode!.hasFocus, isFalse);
      expect(tester.testTextInput.isVisible, isFalse);
      final format = tester.widget<TextButton>(
        find.ancestor(
          of: find.text('Format HTML'),
          matching: find.byType(TextButton),
        ),
      );
      await tester.runAsync(() async => await (format.onPressed as dynamic)());
      await tester.pumpAndSettle();
      expect(source.focusNode!.hasFocus, isFalse);
      expect(tester.testTextInput.isVisible, isFalse);
      await tester.tapAt(
        tester.getTopLeft(find.byType(CodeField)) + const Offset(70, 30),
      );
      await tester.pumpAndSettle();
      expect(source.focusNode!.hasFocus, isTrue);
      expect(tester.testTextInput.isVisible, isTrue);
    } finally {
      await cleanup(tester, h);
    }
  });

  testWidgets('hardware Tab can deliberately enter the mounted mobile editor', (
    tester,
  ) async {
    final h = await EditorHarness.create();
    h.seed('demo', h.note('demo', 'Synthetic writing'));
    await h.editor.loadNote('demo');
    try {
      await mount(tester, h);
      await tester.tap(find.byType(TextField).first);
      await tester.pumpAndSettle();
      for (var step = 0; step < 40 && !h.editor.focusNode.hasFocus; step++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
      }
      expect(h.editor.focusNode.hasFocus, isTrue);
    } finally {
      await cleanup(tester, h);
    }
  });

  testWidgets('deliberate traversal and semantic input remain available', (
    tester,
  ) async {
    final node = FocusNode();
    final gate = MobileEditorFocus([node]);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              MobileEditorInputRegion(
                key: const ValueKey('input-region'),
                focus: gate,
                node: node,
                enabled: true,
                child: TextField(focusNode: node),
              ),
              Builder(
                builder: (context) => TextButton(
                  onPressed: () => showAppDialog<void>(
                    context: context,
                    builder: (_) => const AlertDialog(content: Text('Other')),
                  ),
                  child: const Text('Other control'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    node.requestFocus();
    await tester.pump();
    expect(node.hasFocus, isFalse);
    gate.allowTraversal();
    FocusScope.of(tester.element(find.byType(TextField))).nextFocus();
    await tester.pumpAndSettle();
    expect(node.hasFocus, isTrue);
    gate.dismiss();
    await tester.pumpAndSettle();
    final semantics = tester.widget<Semantics>(
      find
          .descendant(
            of: find.byKey(const ValueKey('input-region')),
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Semantics && widget.properties.onTap != null,
            ),
          )
          .first,
    );
    semantics.properties.onTap!();
    await tester.pumpAndSettle();
    expect(node.hasFocus, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    gate.dispose();
    expect(node.canRequestFocus, isTrue);
    node.dispose();
  });
}
