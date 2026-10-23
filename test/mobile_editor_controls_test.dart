import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart'
    show ChangeSource, QuillEditor;
import 'package:flutter_test/flutter_test.dart';
import 'package:code_text_field/code_text_field.dart';
import 'package:flutter_application_1/features/dashboard/models/attachment_job.dart';
import 'package:flutter_application_1/features/dashboard/models/save_ui_state.dart';
import 'package:flutter_application_1/features/dashboard/mobile/expanding_formatting_bar.dart';
import 'package:flutter_application_1/features/dashboard/widgets/mention_popup_layout.dart';
import 'package:flutter_application_1/features/dashboard/mobile/content_area.dart';
import 'package:flutter_application_1/main.dart';
import 'support/editor_harness.dart';

void main() {
  testWidgets(
    'mobile compact tools swipe without moving disclosure or editor selection',
    (tester) async {
      final h = await EditorHarness.create();
      h.seed('demo', h.note('demo', 'Synthetic writing'));
      await h.editor.loadNote('demo');
      final controller = h.editor.quillController;
      final document = controller.document;
      try {
        await tester.pumpWidget(
          MyApp(
            settings: h.settings,
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: 340,
                  child: MobileContentArea(viewModel: h.editor),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.byType(QuillEditor));
        controller.updateSelection(
          const TextSelection(baseOffset: 0, extentOffset: 9),
          ChangeSource.local,
        );
        await tester.pumpAndSettle();
        final scroll = find.byKey(
          const ValueKey('formatting-horizontal-scroll'),
        );
        final toggle = find.byKey(const ValueKey('formatting-touch-toggle'));
        final toggleRect = tester.getRect(toggle);
        final card = find.byKey(const ValueKey('formatting-card'));
        final height = tester.getSize(card).height;
        final scrollState = tester.state<ScrollableState>(
          find.descendant(of: scroll, matching: find.byType(Scrollable)).first,
        );
        expect(scrollState.position.maxScrollExtent, greaterThan(600));
        await tester.drag(scroll, const Offset(-900, 0));
        await tester.pumpAndSettle();
        expect(scrollState.position.pixels, greaterThan(0));
        expect(tester.getRect(toggle), toggleRect);
        expect(tester.getSize(card).height, height);
        expect(h.editor.focusNode.hasFocus, isTrue);
        expect(
          controller.selection,
          const TextSelection(baseOffset: 0, extentOffset: 9),
        );
        expect(identical(controller.document, document), isTrue);
        await tester.tap(toggle);
        await tester.pumpAndSettle();
        expect(find.byTooltip('Collapse formatting tools'), findsOneWidget);
        await tester.tap(toggle);
        await tester.pumpAndSettle();
        expect(tester.getSize(card).height, height);
        expect(
          controller.selection,
          const TextSelection(baseOffset: 0, extentOffset: 9),
        );
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(h.dispose);
      }
    },
  );
  for (final html in [false, true]) {
    for (final terminal in [
      AttachmentJobPhase.completed,
      AttachmentJobPhase.cancelled,
      AttachmentJobPhase.failed,
    ]) {
      testWidgets(
        'export locks editor through Hide and restores on $terminal (HTML=$html)',
        (tester) async {
          final h = await EditorHarness.create(
            deltaToHtml: (_) async => '<p>Synthetic body</p>',
          );
          final requests = ValueNotifier<int>(0);
          AttachmentJobState? job;
          h.seed('demo', h.note('demo', 'Synthetic body'));
          await h.editor.loadNote('demo');
          if (html) await h.editor.setEditorMode(EditorMode.html);
          final controller = h.editor.quillController;
          final document = controller.document;
          final body = document.toPlainText();
          final delta = document.toDelta().toJson();
          final source = h.editor.htmlController.text;
          AttachmentJobSnapshot snapshot(AttachmentJobPhase phase) =>
              AttachmentJobSnapshot(
                id: 'read-only-export',
                owner: h.editor.draftSession.generation,
                fileName: 'Synthetic package',
                phase: phase,
                operation: AttachmentJobOperation.export,
              );
          try {
            await tester.pumpWidget(
              MyApp(
                settings: h.settings,
                home: Scaffold(
                  body: MobileContentArea(
                    viewModel: h.editor,
                    exportRequests: requests,
                    onExport: () async {},
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            final title = find.byType(TextField).first;
            expect(tester.widget<TextField>(title).readOnly, isFalse);
            expect(controller.readOnly, isFalse);
            requests.value =
                1; // Export options/preparation, before a worker exists.
            await tester.pump();
            expect(tester.widget<TextField>(title).readOnly, isTrue);
            expect(controller.readOnly, isTrue);
            expect(
              tester
                  .widget<IconButton>(
                    find.byWidgetPredicate(
                      (w) => w is IconButton && w.tooltip == 'Attach file',
                    ),
                  )
                  .onPressed,
              isNull,
            );
            expect(
              tester
                  .widget<TextButton>(
                    find.widgetWithText(TextButton, 'Rich text'),
                  )
                  .onPressed,
              isNull,
            );
            expect(
              tester
                  .widget<TextButton>(find.widgetWithText(TextButton, 'HTML'))
                  .onPressed,
              isNull,
            );
            if (html) {
              expect(
                tester.widget<CodeField>(find.byType(CodeField)).readOnly,
                isTrue,
              );
              expect(
                tester
                    .widget<TextButton>(
                      find
                          .ancestor(
                            of: find.text('Format HTML'),
                            matching: find.byWidgetPredicate(
                              (w) => w is TextButton,
                            ),
                          )
                          .first,
                    )
                    .onPressed,
                isNull,
              );
            } else {
              final bar = find.byKey(const ValueKey('formatting-card'));
              final before = tester.getSize(bar);
              await tester.tap(
                find.byKey(const ValueKey('formatting-touch-toggle')),
                warnIfMissed: false,
              );
              await tester.pump(const Duration(milliseconds: 250));
              expect(tester.getSize(bar), before);
              expect(h.editor.focusNode.hasFocus, isFalse);
              h.editor.focusNode.requestFocus();
              await tester.pump();
              expect(h.editor.focusNode.hasFocus, isFalse);
              await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
              await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
              await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
              expect(document.toDelta().toJson(), delta);
            }
            job = AttachmentJobState(snapshot(AttachmentJobPhase.preparing));
            h.editor.attachmentJobsNotifier.value = [job];
            requests.value =
                0; // Hidden/reconnected presentation must not unlock it.
            await tester.pump();
            expect(controller.readOnly, isTrue);
            expect(tester.widget<TextField>(title).readOnly, isTrue);
            await tester.tap(find.byTooltip('Note actions'));
            await tester.pump(const Duration(milliseconds: 300));
            expect(
              tester
                  .widget<ListTile>(
                    find.widgetWithText(ListTile, 'Set Password'),
                  )
                  .enabled,
              isFalse,
            );
            expect(
              tester
                  .widget<ListTile>(
                    find.widgetWithText(ListTile, 'Delete File'),
                  )
                  .enabled,
              isFalse,
            );
            expect(
              tester
                  .widget<ListTile>(find.widgetWithText(ListTile, 'Export'))
                  .enabled,
              isTrue,
            );
            job.update(snapshot(terminal));
            h.editor.attachmentJobsNotifier.value = List.of(
              h.editor.attachmentJobsNotifier.value,
            );
            await tester.pump(const Duration(milliseconds: 300));
            // An already-open actions menu also restores without being recreated.
            expect(
              tester
                  .widget<ListTile>(
                    find.widgetWithText(ListTile, 'Set Password'),
                  )
                  .enabled,
              isTrue,
            );
            await tester.tap(find.text('Close'));
            await tester.pumpAndSettle();
            expect(controller.readOnly, isFalse);
            expect(tester.widget<TextField>(title).readOnly, isFalse);
            expect(
              tester
                  .widget<IconButton>(
                    find.byWidgetPredicate(
                      (w) => w is IconButton && w.tooltip == 'Attach file',
                    ),
                  )
                  .onPressed,
              isNotNull,
            );
            expect(h.editor.quillController, same(controller));
            expect(controller.document, same(document));
            expect(document.toPlainText(), body);
            expect(h.editor.htmlController.text, source);
            expect(h.editor.isHtmlMode, html);
            expect(h.files.writeAttempts, 0);
            expect(h.encryption.binaryDecryptCalls, 0);
            expect(tester.takeException(), isNull);
          } finally {
            await tester.pumpWidget(const SizedBox.shrink());
            h.editor.attachmentJobsNotifier.value = [];
            job?.dispose();
            requests.dispose();
            await tester.runAsync(h.dispose);
          }
        },
      );
    }
  }
  testWidgets(
    'cancelled export setup preserves an existing read-only controller',
    (tester) async {
      final h = await EditorHarness.create();
      final requests = ValueNotifier<int>(0);
      h.editor.quillController.readOnly = true;
      try {
        await tester.pumpWidget(
          MyApp(
            settings: h.settings,
            home: Scaffold(
              body: MobileContentArea(
                viewModel: h.editor,
                exportRequests: requests,
              ),
            ),
          ),
        );
        requests.value = 1;
        await tester.pump();
        requests.value = 0;
        await tester.pump();
        expect(h.editor.quillController.readOnly, isTrue);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        requests.dispose();
        await tester.runAsync(h.dispose);
      }
    },
  );
  for (final locked in [false, true]) {
    testWidgets(
      'editor action menu exposes Export without changing note state (locked=$locked)',
      (tester) async {
        final h = await EditorHarness.create();
        h.seed('demo', h.note('demo', 'Synthetic body', locked: locked));
        await h.editor.loadNote('demo');
        var exports = 0;
        final controller = h.editor.quillController;
        final body = controller.document.toPlainText();
        try {
          await tester.pumpWidget(
            MyApp(
              settings: h.settings,
              home: Scaffold(
                body: MobileContentArea(
                  viewModel: h.editor,
                  onExport: () async {
                    exports++;
                  },
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byTooltip('Note actions'));
          await tester.pumpAndSettle();
          expect(find.text('Export').hitTestable(), findsOneWidget);
          await tester.tap(find.text('Export'));
          await tester.pumpAndSettle();
          expect(exports, 1);
          expect(find.byType(AlertDialog), findsNothing);
          expect(h.editor.isLocked, locked);
          expect(h.editor.quillController, same(controller));
          expect(controller.document.toPlainText(), body);
          expect(h.files.writeAttempts, 0);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.runAsync(h.dispose);
        }
      },
    );
  }
  test('mention popup stays above changing IME and inside safe bounds', () {
    for (final keyboard in [0.0, 240.0, 360.0]) {
      for (final caretY in [80.0, 280.0, 500.0]) {
        final rect = mentionPopupBounds(
          caret: Rect.fromLTWH(350, caretY, 2, 20),
          overlay: const Size(390, 844),
          insets: EdgeInsets.only(bottom: keyboard),
          safeArea: const EdgeInsets.only(top: 24, bottom: 24),
          matches: 12,
        );
        expect(rect.left, greaterThanOrEqualTo(8));
        expect(rect.right, lessThanOrEqualTo(382));
        expect(rect.top, greaterThanOrEqualTo(32));
        expect(
          rect.bottom,
          lessThanOrEqualTo(844 - (keyboard > 24 ? keyboard : 24) - 8),
        );
      }
    }
  });

  testWidgets(
    'touch More reveals every tool in layout and preserves selection',
    (tester) async {
      final focus = FocusNode();
      final controller = TextEditingController(text: 'Synthetic writing');
      addTearDown(focus.dispose);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 360,
              child: Column(
                children: [
                  MobileFormattingBar(
                    restoreEditorFocus: focus.requestFocus,
                    expandedChild: Wrap(
                      children: List.generate(
                        20,
                        (index) => SizedBox(
                          width: 80,
                          height: 48,
                          child: TextButton(
                            onPressed: focus.requestFocus,
                            child: Text('Tool $index'),
                          ),
                        ),
                      ),
                    ),
                    child: const SizedBox(
                      width: 1200,
                      height: 48,
                      child: Text('Compact tools'),
                    ),
                  ),
                  Expanded(
                    child: TextField(
                      key: const ValueKey('writing'),
                      focusNode: focus,
                      controller: controller,
                      expands: true,
                      maxLines: null,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      focus.requestFocus();
      controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 9,
      );
      await tester.pumpAndSettle();
      final toggle = find.byKey(const ValueKey('formatting-touch-toggle'));
      final card = find.byKey(const ValueKey('formatting-card'));
      final initialHeight = tester.getSize(card).height;
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(tester.getSize(card).height, greaterThan(initialHeight));
      expect(
        tester.getBottomLeft(card).dy,
        lessThanOrEqualTo(
          tester.getTopLeft(find.byKey(const ValueKey('writing'))).dy,
        ),
      );
      expect(focus.hasFocus, isTrue);
      expect(
        controller.selection,
        const TextSelection(baseOffset: 0, extentOffset: 9),
      );
      await tester.scrollUntilVisible(
        find.text('Tool 19'),
        120,
        scrollable: find
            .byWidgetPredicate(
              (widget) => widget is Scrollable && widget.axis == Axis.vertical,
            )
            .first,
      );
      expect(find.text('Tool 19').hitTestable(), findsOneWidget);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(tester.getSize(card).height, initialHeight);
      expect(focus.hasFocus, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
