import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/features/dashboard/widgets/expanding_formatting_bar.dart';

void main() {
  testWidgets(
    'collapsed card follows control height without surplus vertical space',
    (tester) async {
      for (final height in [32.0, 48.0, 72.0]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  ExpandingFormattingBar(
                    restoreEditorFocus: () {},
                    expandedChild: const SizedBox(height: 120),
                    child: SizedBox(
                      width: 1200,
                      height: height,
                      child: const Text('Synthetic controls'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester.getSize(find.byKey(const ValueKey('formatting-card'))).height,
          height + 2,
        );
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final reduced in [false, true]) {
    testWidgets(
      'hover wraps in flow, leaves collapse, selection preserved; reduced=$reduced',
      (tester) async {
        final focus = FocusNode();
        final text = TextEditingController(text: 'Synthetic writing');
        addTearDown(focus.dispose);
        addTearDown(text.dispose);
        List<Widget> tools() => List.generate(
          12,
          (i) => SizedBox(
            width: 64,
            height: 40,
            child: TextButton(
              onPressed: focus.requestFocus,
              child: Text('Tool $i'),
            ),
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(disableAnimations: reduced),
              child: Scaffold(
                body: Column(
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 340),
                      child: ExpandingFormattingBar(
                        restoreEditorFocus: focus.requestFocus,
                        expandedChild: Wrap(children: tools()),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: tools(),
                        ),
                      ),
                    ),
                    Expanded(
                      child: TextField(
                        key: const ValueKey('writing'),
                        focusNode: focus,
                        controller: text,
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
        text.selection = const TextSelection(baseOffset: 0, extentOffset: 9);
        await tester.pumpAndSettle();
        final card = find.byKey(const ValueKey('formatting-card'));
        final editor = find.byKey(const ValueKey('writing'));
        final resting = tester.getRect(editor);
        final restingWidth = tester.getSize(card).width;
        expect(tester.getSize(card).height, 42);
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: const Offset(790, 590));
        await mouse.moveTo(tester.getCenter(card));
        for (final ms in [0, 60, 200]) {
          await tester.pump(Duration(milliseconds: ms));
          expect(tester.getSize(card).width, restingWidth);
          expect(
            tester.getBottomLeft(card).dy,
            lessThanOrEqualTo(tester.getTopLeft(editor).dy),
          );
        }
        expect(tester.getSize(card).height, greaterThan(42));
        expect(find.text('Tool 11').hitTestable(), findsOneWidget);
        expect(
          find.descendant(
            of: card,
            matching: find.byType(SingleChildScrollView),
          ),
          findsNothing,
        );
        expect(focus.hasFocus, isTrue);
        expect(
          text.selection,
          const TextSelection(baseOffset: 0, extentOffset: 9),
        );
        await mouse.moveTo(const Offset(790, 590));
        await tester.pump(const Duration(milliseconds: 185));
        if (!reduced) {
          await tester.pump(const Duration(milliseconds: 30));
          await mouse.moveTo(tester.getCenter(card));
          await tester.pumpAndSettle();
          expect(tester.getSize(card).height, greaterThan(42));
          await mouse.moveTo(const Offset(790, 590));
          await tester.pump(const Duration(milliseconds: 185));
        }
        await tester.pumpAndSettle();
        expect(tester.getRect(editor), resting);
        expect(text.text, 'Synthetic writing');
        await mouse.removePointer();
        await tester.pumpWidget(const SizedBox.shrink());
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'keyboard focus reveals controls without a chevron; Escape returns to writing',
    (tester) async {
      final focus = FocusNode();
      addTearDown(focus.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                ExpandingFormattingBar(
                  restoreEditorFocus: focus.requestFocus,
                  expandedChild: const SizedBox(
                    height: 120,
                    child: Text('All controls'),
                  ),
                  child: const Text('Compact controls'),
                ),
                TextField(focusNode: focus),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('formatting-expand')), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(find.text('All controls'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Compact controls'), findsOneWidget);
      expect(focus.hasFocus, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'hover dropdown remains available outside the card; removal revokes controls',
    (tester) async {
      final focus = FocusNode();
      addTearDown(focus.dispose);
      String? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                ExpandingFormattingBar(
                  restoreEditorFocus: focus.requestFocus,
                  expandedChild: DropdownButton<String>(
                    hint: const Text('Size'),
                    items: const [
                      DropdownMenuItem(value: 'large', child: Text('Large')),
                    ],
                    onChanged: (value) {
                      selected = value;
                      focus.requestFocus();
                    },
                  ),
                  child: const SizedBox(height: 64, child: Text('Compact')),
                ),
                const SizedBox(height: 160),
                TextField(focusNode: focus),
              ],
            ),
          ),
        ),
      );
      focus.requestFocus();
      await tester.pumpAndSettle();
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(790, 590));
      await mouse.moveTo(
        tester.getCenter(find.byKey(const ValueKey('formatting-card'))),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();
      await mouse.moveTo(const Offset(790, 590));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Large'), findsOneWidget);
      await tester.tap(find.text('Large').last);
      await tester.pumpAndSettle();
      expect(selected, 'large');
      expect(focus.hasFocus, isTrue);
      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox.shrink());
      expect(find.byKey(const ValueKey('formatting-card')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
