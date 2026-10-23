import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_quill/flutter_quill.dart' show QuillEditor;
import 'package:flutter_application_1/features/dashboard/mobile/content_area.dart';
import 'package:flutter_application_1/features/dashboard/mobile/editor_panels.dart';
import 'package:flutter_application_1/features/dashboard/mobile/expanding_formatting_bar.dart';
import 'package:flutter_application_1/features/dashboard/models/attachment_job.dart';
import 'package:flutter_application_1/main.dart';
import 'support/editor_harness.dart';

void main() {
  testWidgets(
    'format has no idle timeout and owned picker preserves disclosure',
    (tester) async {
      final panels = MobileEditorPanels();
      final focus = FocusNode();
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Column(
                children: [
                  MobileFormattingBar(
                    panels: panels,
                    restoreEditorFocus: () =>
                        panels.restoreFocus(focus.requestFocus),
                    expandedChild: TextButton(
                      onPressed: () => showDialog<void>(
                        context: context,
                        builder: (context) => AlertDialog(
                          content: TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Choose color'),
                          ),
                        ),
                      ),
                      child: const Text('Color picker'),
                    ),
                    child: const Text('Tools'),
                  ),
                  TextField(key: const ValueKey('writer'), focusNode: focus),
                  const TextField(key: ValueKey('other')),
                ],
              ),
            ),
          ),
        ),
      );
      focus.requestFocus();
      await tester.pump();
      await tester.tap(find.byTooltip('Expand formatting tools'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(minutes: 2));
      expect(panels.value, MobileEditorPanel.formatting);
      await tester.tap(find.text('Color picker'));
      await tester.pumpAndSettle();
      expect(panels.value, MobileEditorPanel.formatting);
      await tester.tap(find.text('Choose color'));
      await tester.pumpAndSettle();
      expect(panels.value, MobileEditorPanel.formatting);
      await tester.tap(find.byKey(const ValueKey('other')));
      await tester.pumpAndSettle();
      expect(panels.value, isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      panels.dispose();
      focus.dispose();
    },
  );

  testWidgets(
    'mobile editor disclosures reverse, survive progress, and collapse on editing or lock',
    (tester) async {
      final h = await EditorHarness.create();
      h.seed(
        'demo',
        h.note(
          'demo',
          'Synthetic body',
          attachments: [
            {'id': 'synthetic-id', 'fileName': 'demo.txt', 'size': 128},
          ],
        ),
      );
      await h.editor.loadNote('demo');
      final document = h.editor.quillController.document;
      await tester.pumpWidget(
        MyApp(
          settings: h.settings,
          home: Scaffold(body: MobileContentArea(viewModel: h.editor)),
        ),
      );
      await tester.pumpAndSettle();
      final format = find.byKey(const ValueKey('formatting-touch-toggle'));
      final attachments = find.byKey(
        const ValueKey('attachment-expand-toggle'),
      );
      await tester.tap(format);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Collapse formatting tools'), findsOneWidget);
      await tester.tap(attachments);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Collapse formatting tools'), findsNothing);
      expect(
        find.byKey(
          ValueKey((
            'attachment-expanded-list',
            h.editor.draftSession.generation,
          )),
        ),
        findsOneWidget,
      );
      await tester.tap(format);
      await tester.pumpAndSettle();
      expect(
        find.byKey(
          ValueKey((
            'attachment-expanded-list',
            h.editor.draftSession.generation,
          )),
        ),
        findsNothing,
      );
      final job = AttachmentJobState(
        AttachmentJobSnapshot(
          id: 'job',
          owner: h.editor.draftSession.generation,
          fileName: 'Synthetic file',
          phase: AttachmentJobPhase.encrypting,
        ),
      );
      h.editor.attachmentJobsNotifier.value = [job];
      await tester.pump();
      job.update(
        AttachmentJobSnapshot(
          id: 'job',
          owner: h.editor.draftSession.generation,
          fileName: 'Synthetic file',
          phase: AttachmentJobPhase.encrypting,
          bytes: 100,
          total: 200,
        ),
      );
      await tester.pump();
      expect(find.byTooltip('Collapse formatting tools'), findsOneWidget);
      await tester.tap(find.byType(QuillEditor));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Collapse formatting tools'), findsNothing);
      await tester.tap(format);
      await tester.pumpAndSettle();
      h.editor.quillController.replaceText(
        0,
        0,
        'Typed ',
        const TextSelection.collapsed(offset: 6),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('Collapse formatting tools'), findsNothing);
      expect(identical(document, h.editor.quillController.document), isTrue);
      await tester.tap(format);
      await tester.pumpAndSettle();
      h.editor.isLockedNotifier.value = true;
      await tester.pump();
      expect(find.byKey(const ValueKey('formatting-card')), findsNothing);
      h.editor.attachmentJobsNotifier.value = [];
      await tester.pumpWidget(const SizedBox.shrink());
      job.dispose();
      await tester.runAsync(h.dispose);
    },
  );
}
