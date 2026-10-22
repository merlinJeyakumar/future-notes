import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_application_1/features/dashboard/widgets/macos_note_find_dialog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late QuillController controller;

  setUp(() {
    controller = QuillController.basic();
    controller.document.insert(0, 'Alpha alpha alphabet\n');
  });
  tearDown(() => controller.dispose());

  Future<EditableText> openFind(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates:
            FlutterQuillLocalizations.localizationsDelegates,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => MacosNoteFindDialog(controller: controller),
              ),
              child: const Text('Open Find'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open Find'));
    await tester.pumpAndSettle();
    return tester.widget<EditableText>(find.byType(EditableText));
  }

  testWidgets('Enter accepts the highlighted match without editing the note', (
    tester,
  ) async {
    await openFind(tester);
    final original = controller.document.toDelta();
    tester.testTextInput.enterText('alpha');
    await tester.pump(const Duration(milliseconds: 350));
    expect(
      controller.selection,
      const TextSelection(baseOffset: 0, extentOffset: 5),
    );
    for (final offset in [6, 12, 0]) {
      await tester.tap(find.byIcon(Icons.keyboard_arrow_down));
      await tester.pump();
      expect(controller.selection.baseOffset, offset);
    }
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.byType(MacosNoteFindDialog), findsNothing);
    expect(controller.selection.baseOffset, 0);
    expect(controller.document.toDelta(), original);
  });

  testWidgets('Done searches a pending query and keeps empty/no-match input', (
    tester,
  ) async {
    final field = await openFind(tester);
    tester.testTextInput.enterText('alpha');
    await tester.pump(const Duration(milliseconds: 350));
    expect(controller.selection.baseOffset, 0);
    expect(controller.selection.extentOffset, 5);
    tester.testTextInput.enterText('alphabet');
    await tester.tap(find.byIcon(Icons.keyboard_arrow_down));
    await tester.pump();
    expect(controller.selection.baseOffset, 12);
    expect(controller.selection.extentOffset, 20);
    for (final query in ['absent', '']) {
      tester.testTextInput.enterText(query);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump(const Duration(milliseconds: 350));
      expect(field.focusNode.hasFocus, isTrue);
      expect(field.controller.text, query);
      expect(controller.selection.isCollapsed, isTrue);
    }
    tester.testTextInput.enterText('alphabet');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.byType(MacosNoteFindDialog), findsNothing);
    expect(controller.selection.baseOffset, 12);
    expect(controller.selection.extentOffset, 20);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Find preserves case/whole-word options and previous navigation',
    (tester) async {
      await openFind(tester);
      tester.testTextInput.enterText('alpha');
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('1/3'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.keyboard_arrow_up));
      await tester.pump();
      expect(controller.selection.baseOffset, 12);
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pump();
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Case sensitive'));
      await tester.pump();
      expect(find.text('2/2'), findsOneWidget);
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Whole word'));
      await tester.pump();
      expect(find.text('1/1'), findsOneWidget);
      expect(controller.selection.baseOffset, 6);
    },
  );

  testWidgets(
    'Done preserves composing input and dispose cancels pending work',
    (tester) async {
      final field = await openFind(tester);
      const composing = TextEditingValue(
        text: 'alpha',
        selection: TextSelection.collapsed(offset: 5),
        composing: TextRange(start: 0, end: 5),
      );
      tester.testTextInput.updateEditingValue(composing);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(field.focusNode.hasFocus, isTrue);
      expect(field.controller.value, composing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 350));
      expect(tester.takeException(), isNull);
    },
  );
}
