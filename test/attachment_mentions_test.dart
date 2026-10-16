import 'dart:convert';
import 'dart:ui' show PointerDeviceKind;
import 'package:code_text_field/code_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/core/routing/fnotes_uri.dart';
import 'package:flutter_application_1/features/dashboard/models/attachment_mention.dart';
import 'package:flutter_application_1/features/dashboard/models/note_model.dart';
import 'package:flutter_application_1/features/dashboard/widgets/content_area.dart';
import 'package:flutter_application_1/main.dart';
import 'support/editor_harness.dart';
import 'attachment_strip_test.dart' show FakeOpenCache;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'typed internal URI routing treats identity as opaque and rejects unsafe framing',
    () {
      final id = '../legacy / தமிழ் # ?';
      expect(FnotesTarget.parse(FnotesTarget.attachment(id))!.id, id);
      expect(
        FnotesTarget.parse('fnotes://note/id')!.resource,
        FnotesResource.unsupported,
      );
      for (final url in [
        'fnotes://attachment/',
        'fnotes://user@attachment/a',
        'fnotes://attachment:80/a',
        'fnotes://attachment/a/b',
        'fnotes://attachment/a?q=b',
        'fnotes://attachment/a#b',
        'fnotes://attachment/%00',
        'https://example.com',
      ]) {
        expect(FnotesTarget.parse(url), isNull, reason: url);
      }
      expect(FnotesTarget.sanitize('javascript:alert(1)'), isNull);
      expect(FnotesTarget.isInternal('FNOTES://other/id'), isTrue);
    },
  );

  test('paragraph matching supports spaces and Unicode but avoids emails', () {
    final query = AttachmentMentionQuery.find(
      'See @annual rep',
      15,
      offset: 20,
    )!;
    expect(query.start, 24);
    expect(query.text, 'annual rep');
    expect(
      query.match([AttachmentModel(id: 'a', fileName: 'Annual report.pdf')]),
      hasLength(1),
    );
    expect(AttachmentMentionQuery.find('x@example.com', 13), isNull);
    expect(AttachmentMentionQuery.find('@@', 2), isNull);
    expect(
      AttachmentMentionQuery.find('@தமிழ்', 6)!.match([
        AttachmentModel(id: 'a', fileName: 'தமிழ் file.pdf'),
        AttachmentModel(id: 'b', fileName: 'தமிழ் file.pdf', isLoading: true),
      ]),
      hasLength(1),
    );
  });

  test(
    'HTML context rejects attributes, comments, scripts, styles and existing links',
    () {
      for (final source in [
        '<a href="@rep',
        '<!-- @rep',
        '<script> @rep',
        '<style> @rep',
        '<a href="https://example.com"> @rep',
        '<div data-x="x> @rep',
      ]) {
        expect(
          htmlAllowsAttachmentMention(source, source.length),
          isFalse,
          reason: source,
        );
      }
      const source = '<p>See @report final';
      expect(htmlAllowsAttachmentMention(source, source.length), isTrue);
      expect(htmlAllowsAttachmentMention('<script>x</script>@', 19), isTrue);
      const operators =
          '<script>if (a < b) { x = "@hidden"; }</script><p>@report';
      expect(htmlAllowsAttachmentMention(operators, operators.length), isTrue);
      const style =
          '<STYLE> /* < @hidden */ a { color: red; } </STYLE> @report';
      expect(htmlAllowsAttachmentMention(style, style.length), isTrue);
    },
  );

  test(
    'mention insertion preserves formatting, one undo, identity and save/reopen',
    () async {
      final h = await EditorHarness.create();
      addTearDown(h.dispose);
      h.seed(
        'synthetic',
        h.note(
          'id',
          '@rep',
          attachments: [
            {
              'id': 'source',
              'fileName': 'report final.pdf',
              'size': 100,
              'unknown': true,
            },
          ],
        ),
      );
      await h.editor.loadNote('synthetic');
      final c = h.editor.quillController;
      c.updateSelection(
        const TextSelection.collapsed(offset: 4),
        ChangeSource.local,
      );
      c.formatSelection(Attribute.bold);
      final query = h.editor.attachmentMentionQuery()!;
      expect(
        h.editor
            .insertAttachmentMention(
              attachmentId: 'source',
              query: query,
              owner: h.editor.draftSession.generation,
              mode: h.editor.editorMode,
            )
            .isSuccess,
        isTrue,
      );
      expect(c.document.toPlainText(), '@report final.pdf \n');
      final operations = c.document.toDelta().toJson();
      expect(
        operations.first['attributes'],
        containsPair('link', 'fnotes://attachment/source'),
      );
      expect(operations.first['attributes'], containsPair('bold', true));
      expect(
        (operations[1]['attributes'] as Map?)?.containsKey('link') ?? false,
        isFalse,
      );
      expect(c.selection.start, 18);
      c.undo();
      expect(c.document.toPlainText(), '@rep\n');
      c.redo();
      expect(c.document.toPlainText(), '@report final.pdf \n');
      expect((await h.editor.saveNote()).isSuccess, isTrue);
      final saved = await h.decoded('synthetic');
      expect(saved['attachments'][0]['mentionId'], 'source');
      expect(saved['attachments'][0]['unknown'], isTrue);
      await h.editor.loadNote('synthetic');
      expect(
        h.editor.resolveInternalLink('fnotes://attachment/source').value!.id,
        'source',
      );
      expect(h.encryption.binaryDecryptCalls, 0);
    },
  );

  test(
    'conversion preserves mention URLs and does not weaken unrelated sanitization',
    () async {
      final h = await EditorHarness.create();
      addTearDown(h.dispose);
      h.seed(
        'synthetic',
        h.note(
          'id',
          jsonEncode([
            {
              'insert': '@report.pdf',
              'attributes': {'link': 'fnotes://attachment/stable'},
            },
            {
              'insert': 'unsafe',
              'attributes': {'link': 'javascript:alert(1)'},
            },
            {'insert': '\n'},
          ]),
          attachments: [
            {'id': 'storage', 'mentionId': 'stable', 'fileName': 'report.pdf'},
          ],
        ),
      );
      await h.editor.loadNote('synthetic');
      await h.editor.toggleEditorMode();
      expect(
        h.editor.htmlController.text,
        contains('href="fnotes://attachment/stable"'),
      );
      expect(
        h.editor.htmlController.text,
        contains('href="unsafe:javascript:'),
      );
      await h.editor.toggleEditorMode();
      expect(
        h.editor.quillController.document
            .toDelta()
            .toJson()
            .first['attributes'],
        containsPair('link', 'fnotes://attachment/stable'),
      );
      expect(
        h.editor.resolveInternalLink('fnotes://attachment/stable').value!.id,
        'storage',
      );
      expect(
        h.editor.resolveInternalLink('fnotes://future/id').message,
        'Unsupported internal link.',
      );
      expect(
        h.editor.resolveInternalLink('fnotes://attachment/missing').isSuccess,
        isFalse,
      );
    },
  );

  test(
    'old notes do not migrate on open; missing/ambiguous references and stale edits fail closed',
    () async {
      final h = await EditorHarness.create();
      addTearDown(h.dispose);
      h.seed(
        'synthetic',
        h.note(
          'id',
          '@rep',
          attachments: [
            {'id': 'one', 'fileName': 'report.pdf'},
            {'id': 'two', 'mentionId': 'one', 'fileName': 'another.pdf'},
          ],
        ),
      );
      await h.editor.loadNote('synthetic');
      expect(h.files.writeAttempts, 0);
      expect(
        h.editor.attachments.first.toJson().containsKey('mentionId'),
        isFalse,
      );
      final c = h.editor.quillController;
      c.updateSelection(
        const TextSelection.collapsed(offset: 4),
        ChangeSource.local,
      );
      final query = h.editor.attachmentMentionQuery()!;
      final owner = h.editor.draftSession.generation;
      final mode = h.editor.editorMode;
      expect(
        h.editor.resolveInternalLink('fnotes://attachment/one').isSuccess,
        isFalse,
      );
      expect(
        h.editor
            .insertAttachmentMention(
              attachmentId: 'one',
              query: query,
              owner: owner,
              mode: mode,
            )
            .isSuccess,
        isFalse,
      );
      expect(
        h.editor
            .insertAttachmentMention(
              attachmentId: 'missing',
              query: query,
              owner: owner,
              mode: mode,
            )
            .isSuccess,
        isFalse,
      );
      c.updateSelection(
        const TextSelection.collapsed(offset: 1),
        ChangeSource.local,
      );
      expect(
        h.editor
            .insertAttachmentMention(
              attachmentId: 'two',
              query: query,
              owner: owner,
              mode: mode,
            )
            .isSuccess,
        isFalse,
      );
      expect(c.document.toPlainText(), '@rep\n');
      await h.editor.reset();
      expect(
        h.editor
            .insertAttachmentMention(
              attachmentId: 'two',
              query: query,
              owner: owner,
              mode: mode,
            )
            .isSuccess,
        isFalse,
      );
    },
  );

  for (final html in [false, true]) {
    testWidgets(
      'caret popup keyboard/mouse, dismissal, metadata only; html=$html',
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
            'id',
            'Text ',
            attachments: [
              {'id': 'source-a', 'fileName': 'report.pdf', 'size': 100},
              {'id': 'source-b', 'fileName': 'report.pdf', 'size': 200},
              {'id': 'source-c', 'fileName': 'report final.docx', 'size': 300},
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
          final focus = html
              ? tester.widget<CodeField>(find.byType(CodeField)).focusNode!
              : h.editor.focusNode;
          focus.requestFocus();
          await tester.pumpAndSettle();
          void type(String text) {
            if (html) {
              h.editor.htmlController.value = TextEditingValue(
                text: text,
                selection: TextSelection.collapsed(offset: text.length),
              );
            } else {
              final c = h.editor.quillController;
              c.replaceText(
                0,
                c.document.length - 1,
                text,
                TextSelection.collapsed(offset: text.length),
              );
              c.formatText(0, text.length, const LinkAttribute(null));
            }
          }

          type('Text @rep');
          await tester.pumpAndSettle();
          final popup = find.byKey(const ValueKey('attachment-mention-popup'));
          expect(popup, findsOneWidget);
          expect(
            find.descendant(of: popup, matching: find.text('report.pdf')),
            findsNWidgets(2),
          );
          expect(focus.hasFocus, isTrue);
          expect(cache.opens, 0);
          expect(h.encryption.binaryDecryptCalls, 0);
          // Exercise the actual pinned editors' composition state, including
          // a composition-only notification without a document edit.
          if (html) {
            final value = h.editor.htmlController.value;
            h.editor.htmlController.value = value.copyWith(
              composing: const TextRange(start: 6, end: 9),
            );
          } else {
            final state =
                tester
                        .widget<QuillEditor>(find.byType(QuillEditor))
                        .config
                        .editorKey!
                        .currentState!
                    as QuillRawEditorState;
            state.composingRange.value = const TextRange(start: 6, end: 9);
          }
          await tester.pumpAndSettle();
          expect(popup, findsNothing);
          if (html) {
            h.editor.htmlController.value = h.editor.htmlController.value
                .copyWith(composing: TextRange.empty);
          } else {
            final state =
                tester
                        .widget<QuillEditor>(find.byType(QuillEditor))
                        .config
                        .editorKey!
                        .currentState!
                    as QuillRawEditorState;
            state.composingRange.value = TextRange.empty;
          }
          await tester.pumpAndSettle();
          expect(popup, findsOneWidget);
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pumpAndSettle();
          expect(popup, findsNothing);
          expect(focus.hasFocus, isTrue);
          if (html) {
            expect(
              h.editor.htmlController.text,
              contains('<a href="fnotes://attachment/'),
            );
            final inserted = h.editor.htmlController.text;
            await tester.pump(const Duration(milliseconds: 600));
            await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
            await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
            await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
            await tester.pumpAndSettle();
            expect(h.editor.htmlController.text, 'Text @rep');
            await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
            await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
            await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
            await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
            await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
            await tester.pumpAndSettle();
            expect(h.editor.htmlController.text, inserted);
          } else {
            expect(
              h.editor.quillController.document.toDelta().toJson().any(
                (op) => (op['attributes'] as Map?)?['link'] != null,
              ),
              isTrue,
            );
          }
          type('Text @report final');
          await tester.pumpAndSettle();
          expect(popup, findsOneWidget);
          await tester.tap(
            find.descendant(
              of: popup,
              matching: find.text('report final.docx'),
            ),
            kind: PointerDeviceKind.mouse,
          );
          await tester.pumpAndSettle();
          expect(focus.hasFocus, isTrue);
          type('Text @');
          await tester.pumpAndSettle();
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
          h.editor.attachmentCacheNotifier.value++;
          h.editor.notifyListeners();
          await tester.pumpAndSettle();
          expect(popup, findsNothing);
          type('No query');
          await tester.pumpAndSettle();
          type('Text @rep');
          await tester.pumpAndSettle();
          expect(popup, findsOneWidget);
          focus.unfocus();
          await tester.pumpAndSettle();
          expect(popup, findsNothing);
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
