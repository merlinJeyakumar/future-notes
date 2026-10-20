import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/features/dashboard/widgets/attachment_strip.dart';
import 'support/editor_harness.dart';

void main() {
  testWidgets(
    'desktop range selection, filtered all, Escape and confirmed removal use IDs without decrypting',
    (tester) async {
      final h = await EditorHarness.create();
      h.seed(
        'demo',
        h.note(
          'demo',
          'Synthetic body',
          attachments: [
            for (var i = 0; i < 5; i++)
              {
                'id': 'item-$i',
                'fileName': i < 2 ? 'same.txt' : 'file-$i.txt',
                'size': 100,
              },
          ],
        ),
      );
      await h.editor.loadNote('demo');
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  const Spacer(),
                  AttachmentStrip(viewModel: h.editor),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Show all'));
        await tester.pumpAndSettle();
        final dialog = find.byType(AlertDialog).last;
        Finder card(int i) => find.descendant(
          of: dialog,
          matching: find.byKey(ValueKey('attachment-open-item-$i')),
        );
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.tap(card(0));
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pumpAndSettle();
        expect(find.text('1 selected'), findsOneWidget);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.tap(card(3));
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.pumpAndSettle();
        expect(find.text('4 selected'), findsOneWidget);
        final search = find.byKey(const ValueKey('attachment-filename-search'));
        await tester.enterText(search, 'same');
        await tester.pumpAndSettle();
        expect(find.text(' · 2 hidden'), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.text('All attachments'), findsOneWidget);
        expect(find.text('4 selected'), findsNothing);
        await tester.tap(find.text('Select'));
        await tester.pumpAndSettle();
        await tester.tap(find.byType(Checkbox).first);
        await tester.pumpAndSettle();
        expect(find.text('2 selected'), findsOneWidget);
        expect(h.encryption.binaryDecryptCalls, 0);
        await tester.tap(find.text('Remove selected'));
        await tester.pumpAndSettle();
        expect(find.text('Remove 2 attachments?'), findsOneWidget);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(h.editor.attachments, hasLength(5));
        await tester.tap(find.text('Remove selected'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Remove').last);
        await tester.pumpAndSettle();
        expect(h.editor.attachments.map((a) => a.id), [
          'item-2',
          'item-3',
          'item-4',
        ]);
        expect(h.encryption.binaryDecryptCalls, 0);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(h.dispose);
      }
    },
  );
}
