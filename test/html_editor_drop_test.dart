import 'dart:async';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:code_text_field/code_text_field.dart';
import 'package:flutter_application_1/core/operations/operation_result.dart';
import 'package:flutter_application_1/features/dashboard/models/save_ui_state.dart';
import 'package:flutter_application_1/features/dashboard/widgets/content_area.dart';
import 'package:flutter_application_1/features/dashboard/widgets/desktop_attachment_drop_zone.dart';
import 'package:flutter_application_1/main.dart';
import 'support/editor_harness.dart';

void main() {
  testWidgets(
    'HTML code surface highlights syntax and formats without losing typing',
    (tester) async {
      const markup = '<section class="sample"><p>Sample</p></section>';
      final h = await EditorHarness.create(deltaToHtml: (_) async => markup);
      try {
        await h.editor.setEditorMode(EditorMode.html);
        await tester.pumpWidget(
          MyApp(
            settings: h.settings,
            home: Scaffold(body: ContentArea(viewModel: h.editor)),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Format HTML'), findsOneWidget);
        final code = tester.widget<CodeField>(find.byType(CodeField));
        expect(code.lineNumbers, isTrue);
        expect(code.textStyle!.fontFamily, 'Consolas');
        final context = tester.element(
          find
              .descendant(
                of: find.byType(CodeField),
                matching: find.byType(EditableText),
              )
              .first,
        );
        final spans = h.editor.htmlController.buildTextSpan(
          context: context,
          style: code.textStyle,
          withComposing: false,
        );
        final syntaxColors = <Color>{};
        void visit(InlineSpan span) {
          if (span.style?.color case final Color color) syntaxColors.add(color);
          if (span is TextSpan) {
            for (final child in span.children ?? <InlineSpan>[]) {
              visit(child);
            }
          }
        }

        visit(spans);
        expect(spans.toPlainText(), markup);
        expect(syntaxColors.length, greaterThanOrEqualTo(3));
        await tester.runAsync(() async {
          expect((await h.editor.formatHtml()).isSuccess, isTrue);
        });
        await tester.pump();
        expect(
          h.editor.htmlController.text,
          '<section class="sample">\n  <p>Sample</p>\n</section>',
        );
        expect(h.editor.saveStateNotifier.value.phase, SavePhase.unsavedDraft);
        await tester.runAsync(() async {
          final formatting = h.editor.formatHtml();
          h.editor.htmlController.text = '<p>Latest typing</p>';
          expect((await formatting).outcome, OperationOutcome.cancelled);
        });
        expect(h.editor.htmlController.text, '<p>Latest typing</p>');
        h.editor.htmlController.text = '<div>unfinished';
        await tester.runAsync(() async {
          expect((await h.editor.formatHtml()).isSuccess, isFalse);
        });
        expect(h.editor.htmlController.text, '<div>unfinished');
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        h.disposeEditor();
        await tester.pump(const Duration(seconds: 3));
        await tester.runAsync(h.dispose);
      }
    },
  );

  testWidgets(
    'drop surface shows hover, passes paths and rejects double drops and disabled state',
    (tester) async {
      final completed = Completer<void>();
      final received = <List<String>>[];
      var enabled = true;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                return DesktopAttachmentDropZone(
                  enabled: enabled,
                  onDrop: (paths) {
                    received.add(paths);
                    return completed.future;
                  },
                  child: const Text('Draft stays visible'),
                );
              },
            ),
          ),
        ),
      );
      DropTarget target() => tester.widget<DropTarget>(find.byType(DropTarget));
      target().onDragEntered!(
        DropEventDetails(
          localPosition: Offset.zero,
          globalPosition: Offset.zero,
        ),
      );
      await tester.pump();
      expect(find.text('Drop files to attach'), findsOneWidget);
      expect(find.text('Draft stays visible'), findsOneWidget);
      final drop = DropDoneDetails(
        files: [DropItemFile('C:/synthetic/file.txt')],
        localPosition: Offset.zero,
        globalPosition: Offset.zero,
      );
      target().onDragDone!(drop);
      target().onDragDone!(drop);
      await tester.pump();
      expect(received, [
        ['C:/synthetic/file.txt'],
      ]);
      expect(target().enable, isFalse);
      expect(find.text('Drop files to attach'), findsNothing);
      completed.complete();
      await tester.pump();
      update(() => enabled = false);
      await tester.pump();
      target().onDragDone!(drop);
      await tester.pump();
      expect(received.length, 1);
      expect(target().enable, isFalse);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'a modal route disables external drops behind it',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => DesktopAttachmentDropZone(
                enabled: true,
                onDrop: (_) async {},
                child: TextButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => const AlertDialog(title: Text('Modal')),
                  ),
                  child: const Text('Show modal'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Show modal'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<DropTarget>(find.byType(DropTarget)).enable,
        isFalse,
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
}
