import 'dart:ui' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/features/dashboard/widgets/hover_formatting_bar.dart';

Future<void> hoverToolbar(WidgetTester tester) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(
    location: tester.getCenter(
      find.byKey(const ValueKey('formatting-hover-strip')),
    ),
  );
  addTearDown(mouse.removePointer);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'unopened toolbar disposes safely; an open toolbar is revoked on removal',
    (tester) async {
      Widget page({required bool visible}) => MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              if (visible)
                HoverFormattingBar(
                  primaryToolbar: const SizedBox(
                    height: 48,
                    child: Text("Primary controls"),
                  ),
                  restoreEditorFocus: () {},
                  toolbar: const Material(
                    child: SizedBox(
                      height: 60,
                      child: Text('Private controls'),
                    ),
                  ),
                ),
              const Expanded(child: SizedBox()),
            ],
          ),
        ),
      );
      await tester.pumpWidget(page(visible: true));
      await tester.pumpWidget(page(visible: false));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(page(visible: true));
      await tester.pumpAndSettle();
      await tester.pumpAndSettle();
      await hoverToolbar(tester);
      await tester.pumpAndSettle();
      expect(find.text('Private controls'), findsOneWidget);
      await tester.pumpWidget(page(visible: false));
      // No outgoing toolbar or focusable controls survive removal for an animation.
      expect(find.text('Private controls'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );
  for (final reduced in [false, true]) {
    testWidgets(
      'hover reveals an overlay without moving or unfocusing text; reduced=$reduced',
      (tester) async {
        final focus = FocusNode();
        final controller = TextEditingController(text: 'Synthetic writing');
        addTearDown(focus.dispose);
        addTearDown(controller.dispose);
        Widget page() => MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: reduced),
            child: Scaffold(
              body: Column(
                children: [
                  HoverFormattingBar(
                    primaryToolbar: const SizedBox(
                      height: 48,
                      child: Text("Primary controls"),
                    ),
                    restoreEditorFocus: focus.requestFocus,
                    toolbar: Material(
                      key: const ValueKey('synthetic-toolbar'),
                      child: SizedBox(
                        height: 80,
                        child: TextButton(
                          onPressed: focus.requestFocus,
                          child: const Text('Style'),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: TextField(
                      key: const ValueKey('writing'),
                      controller: controller,
                      focusNode: focus,
                      maxLines: null,
                      expands: true,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpWidget(page());
        focus.requestFocus();
        controller.selection = const TextSelection(
          baseOffset: 0,
          extentOffset: 9,
        );
        await tester.pumpAndSettle();
        final editor = find.byKey(const ValueKey('writing'));
        final before = tester.getRect(editor);
        final toolbar = find.byKey(const ValueKey('synthetic-toolbar'));
        expect(toolbar, findsNothing);
        expect(find.text("Primary controls"), findsOneWidget);
        expect(
          tester
              .getSize(find.byKey(const ValueKey('formatting-hover-strip')))
              .height,
          greaterThanOrEqualTo(48),
        );
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: const Offset(790, 590));
        await mouse.moveTo(
          tester.getCenter(
            find.byKey(const ValueKey('formatting-hover-strip')),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 130));
        expect(toolbar, findsOneWidget);
        final card = find.byKey(const ValueKey('formatting-card'));
        expect(card, findsOneWidget);
        expect(
          find.ancestor(of: find.text('Primary controls'), matching: card),
          findsOneWidget,
        );
        expect(find.ancestor(of: toolbar, matching: card), findsOneWidget);
        expect(tester.getRect(editor), before);
        expect(focus.hasFocus, isTrue);
        expect(
          controller.selection,
          const TextSelection(baseOffset: 0, extentOffset: 9),
        );
        await mouse.moveTo(tester.getCenter(toolbar));
        await tester.pump(const Duration(milliseconds: 400));
        expect(toolbar, findsOneWidget);
        await mouse.moveTo(const Offset(790, 590));
        await tester.pump(const Duration(milliseconds: 185));
        if (!reduced) {
          // Re-enter during the short exit: reverse in place, never queue.
          await tester.pump(const Duration(milliseconds: 30));
          await mouse.moveTo(
            tester.getCenter(
              find.byKey(const ValueKey('formatting-hover-strip')),
            ),
          );
          await tester.pumpAndSettle();
          expect(toolbar, findsOneWidget);
          await mouse.moveTo(const Offset(790, 590));
        }
        await tester.pumpAndSettle(const Duration(milliseconds: 100));
        expect(toolbar, findsNothing);
        expect(tester.getRect(editor), before);
        expect(focus.hasFocus, isTrue);
        expect(controller.text, 'Synthetic writing');
        await mouse.removePointer();
        await tester.pumpWidget(const SizedBox.shrink());
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'keyboard access and Escape restore writing; outside tap dismisses',
    (tester) async {
      final editorFocus = FocusNode();
      addTearDown(editorFocus.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                HoverFormattingBar(
                  primaryToolbar: SizedBox(
                    height: 48,
                    child: TextButton(
                      onPressed: () {},
                      child: const Text("Primary controls"),
                    ),
                  ),
                  restoreEditorFocus: editorFocus.requestFocus,
                  toolbar: const Material(
                    child: SizedBox(height: 80, child: Text('Controls')),
                  ),
                ),
                Expanded(
                  child: TextField(
                    focusNode: editorFocus,
                    expands: true,
                    maxLines: null,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(find.text('Controls'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Controls'), findsNothing);
      expect(editorFocus.hasFocus, isTrue);
      await hoverToolbar(tester);
      await tester.pumpAndSettle();
      expect(find.text('Controls'), findsOneWidget);
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      expect(find.text('Controls'), findsNothing);
      expect(editorFocus.hasFocus, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('dropdown can be chosen after leaving the toolbar hover region', (
    tester,
  ) async {
    final editorFocus = FocusNode();
    addTearDown(editorFocus.dispose);
    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              HoverFormattingBar(
                primaryToolbar: const SizedBox(
                  height: 48,
                  child: Text("Primary controls"),
                ),
                restoreEditorFocus: editorFocus.requestFocus,
                toolbar: Material(
                  child: SizedBox(
                    height: 60,
                    child: DropdownButton<String>(
                      hint: const Text('Size'),
                      items: const [
                        DropdownMenuItem(value: 'small', child: Text('Small')),
                        DropdownMenuItem(value: 'large', child: Text('Large')),
                      ],
                      onChanged: (value) {
                        selected = value;
                        editorFocus.requestFocus();
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 180),
              TextField(focusNode: editorFocus),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await hoverToolbar(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Large'), findsOneWidget);
    await tester.tap(find.text('Large'));
    await tester.pumpAndSettle();
    expect(selected, 'large');
    expect(editorFocus.hasFocus, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });
}
