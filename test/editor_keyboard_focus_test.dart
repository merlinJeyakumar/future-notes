import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/core/theme/app_theme.dart';
import 'package:flutter_application_1/core/platform/windows_navigation_shortcuts.dart';
import 'package:flutter_application_1/features/dashboard/widgets/content_area.dart';
import 'package:flutter_application_1/features/dashboard/views/dashboard_screen.dart';
import 'package:flutter_application_1/main.dart';
import 'support/editor_harness.dart';

void main() {
  testWidgets(
    'Windows Num Lock off keypad navigation reaches title and editor',
    (tester) async {
      final h = await EditorHarness.create();
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      try {
        await tester.pumpWidget(
          MyApp(
            settings: h.settings,
            home: DashboardScreen(
              settings: h.settings,
              fileService: h.files,
              startBackgroundServices: false,
              confirmExit: () async => false,
            ),
          ),
        );
        expect(
          HardwareKeyboard.instance.lockModesEnabled.contains(
            KeyboardLockMode.numLock,
          ),
          isFalse,
        );
        final model = tester
            .widget<ContentArea>(find.byType(ContentArea))
            .viewModel;
        final title = find.descendant(
          of: find.byType(ContentArea),
          matching: find.byType(TextField),
        );
        await tester.tap(title);
        model.titleController.text = 'Title line';
        model.titleController.selection = const TextSelection.collapsed(
          offset: 4,
        );
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.numpad7);
        expect(model.titleController.selection.extentOffset, 0);
        await tester.sendKeyEvent(LogicalKeyboardKey.numpad1);
        expect(model.titleController.selection.extentOffset, 10);
        model.quillController.document.insert(0, 'first line\nsecond line');
        model.quillController.updateSelection(
          const TextSelection.collapsed(offset: 15),
          ChangeSource.local,
        );
        model.focusNode.requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.numpad7);
        expect(model.quillController.selection.extentOffset, 11);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.numpad1);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        expect(
          model.quillController.selection,
          const TextSelection(baseOffset: 11, extentOffset: 22),
        );
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.numpad7);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        expect(model.quillController.selection.extentOffset, 0);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.numpad1);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        expect(
          model.quillController.selection,
          const TextSelection(baseOffset: 0, extentOffset: 22),
        );

        await tester.sendKeyEvent(LogicalKeyboardKey.numLock);
        expect(
          HardwareKeyboard.instance.lockModesEnabled,
          contains(KeyboardLockMode.numLock),
        );
        for (final key in [
          LogicalKeyboardKey.numpad7,
          LogicalKeyboardKey.numpad1,
        ]) {
          final event = KeyDownEvent(
            logicalKey: key,
            physicalKey: key == LogicalKeyboardKey.numpad7
                ? PhysicalKeyboardKey.numpad7
                : PhysicalKeyboardKey.numpad1,
            timeStamp: Duration.zero,
          );
          expect(
            windowsKeypadNavigationShortcuts.keys.any(
              (activator) =>
                  activator.accepts(event, HardwareKeyboard.instance),
            ),
            isFalse,
            reason:
                'Num Lock on must retain numeric input, not move the caret.',
          );
        }
        await tester.sendKeyEvent(LogicalKeyboardKey.numLock);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        h.disposeEditor();
        await tester.pump(const Duration(seconds: 3));
        await tester.runAsync(h.dispose);
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'title navigation through the actual app and dashboard shortcut tree',
    (tester) async {
      final h = await EditorHarness.create();
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      try {
        await tester.pumpWidget(
          MyApp(
            settings: h.settings,
            home: DashboardScreen(
              settings: h.settings,
              fileService: h.files,
              startBackgroundServices: false,
              confirmExit: () async => false,
            ),
          ),
        );
        final area = tester.widget<ContentArea>(find.byType(ContentArea));
        final title = find.descendant(
          of: find.byType(ContentArea),
          matching: find.byType(TextField),
        );
        await tester.tap(title);
        area.viewModel.titleController.text = 'Title line';
        area.viewModel.titleController.selection =
            const TextSelection.collapsed(offset: 4);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.home);
        expect(area.viewModel.titleController.selection.extentOffset, 0);
        await tester.sendKeyEvent(LogicalKeyboardKey.end);
        expect(area.viewModel.titleController.selection.extentOffset, 10);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.home);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        expect(
          area.viewModel.titleController.selection,
          const TextSelection(baseOffset: 10, extentOffset: 0),
        );
        expect(tester.takeException(), isNull);
        expect(h.files.writeAttempts, 0);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        h.disposeEditor();
        await tester.pump(const Duration(seconds: 3));
        await tester.runAsync(h.dispose);
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  void scenario(
    String name,
    Future<void> Function(WidgetTester, EditorHarness) run,
  ) {
    testWidgets(name, (tester) async {
      final h = await EditorHarness.create();
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      try {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkTheme,
            localizationsDelegates: const [FlutterQuillLocalizations.delegate],
            supportedLocales: FlutterQuillLocalizations.supportedLocales,
            home: Scaffold(body: ContentArea(viewModel: h.editor)),
          ),
        );
        h.editor.quillController.document.insert(0, 'first line\nsecond line');
        h.editor.quillController.updateSelection(
          const TextSelection.collapsed(offset: 15),
          ChangeSource.local,
        );
        h.editor.focusNode.requestFocus();
        await tester.pump();
        await run(tester, h);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        h.disposeEditor();
        await tester.pump(const Duration(seconds: 3));
        await tester.runAsync(h.dispose);
      }
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
  }

  scenario(
    'Windows Home End and modifiers move and extend the rich-text caret',
    (tester, h) async {
      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      expect(h.editor.quillController.selection.extentOffset, 11);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      expect(
        h.editor.quillController.selection,
        const TextSelection(baseOffset: 11, extentOffset: 22),
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(h.editor.quillController.selection.extentOffset, 0);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(h.editor.quillController.selection.extentOffset, 22);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(
        h.editor.quillController.selection,
        const TextSelection(baseOffset: 22, extentOffset: 0),
      );
      expect(tester.takeException(), isNull);
    },
  );

  scenario(
    'formatting retains selection and returns focus for subsequent typing',
    (tester, h) async {
      const selection = TextSelection(baseOffset: 11, extentOffset: 17);
      h.editor.quillController.updateSelection(selection, ChangeSource.local);
      await tester.pump();
      await tester.tap(find.byTooltip('Bold'));
      await tester.pump();
      expect(h.editor.focusNode.hasFocus, isTrue);
      expect(h.editor.quillController.selection, selection);
      expect(
        h.editor.quillController.getSelectionStyle().attributes,
        contains('bold'),
      );
      await tester.tap(find.byTooltip('Align center'));
      await tester.pump();
      expect(h.editor.focusNode.hasFocus, isTrue);
      expect(h.editor.quillController.selection, selection);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(1400, 900));
      await mouse.moveTo(
        tester.getCenter(find.byKey(const ValueKey('formatting-card'))),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Bold'));
      await tester.pump();
      expect(h.editor.focusNode.hasFocus, isTrue);
      expect(h.editor.quillController.selection, selection);
      await mouse.moveTo(const Offset(1400, 900));
      await tester.pump(const Duration(milliseconds: 185));
      await tester.pumpAndSettle();
      await mouse.removePointer();
      expect(h.editor.focusNode.hasFocus, isTrue);
      expect(h.editor.quillController.selection, selection);
    },
  );

  scenario('selected mode has readable foreground and title stays borderless', (
    tester,
    h,
  ) async {
    final button = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Rich text'),
    );
    final foreground = button.style!.foregroundColor!.resolve({})!;
    final background = Color.alphaBlend(
      button.style!.backgroundColor!.resolve({})!,
      AppTheme.darkTheme.appSurface,
    );
    final luminances = [
      foreground.computeLuminance(),
      background.computeLuminance(),
    ]..sort();
    expect(
      (luminances.last + 0.05) / (luminances.first + 0.05),
      greaterThanOrEqualTo(4.5),
    );
    final title = tester.widget<TextField>(find.byType(TextField));
    expect(title.decoration!.enabledBorder, InputBorder.none);
    expect(title.decoration!.focusedBorder, InputBorder.none);
  });

  scenario('Home and End use visual boundaries inside a wrapped paragraph', (
    tester,
    h,
  ) async {
    h.editor.quillController.document.insert(
      0,
      List.filled(120, 'word ').join(),
    );
    h.editor.quillController.updateSelection(
      const TextSelection.collapsed(offset: 310),
      ChangeSource.local,
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    final start = h.editor.quillController.selection.extentOffset;
    expect(start, greaterThan(0));
    expect(start, lessThan(310));
    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    expect(h.editor.quillController.selection.extentOffset, greaterThan(start));
    expect(h.editor.quillController.selection.extentOffset, lessThan(600));
    expect(tester.takeException(), isNull);
  });
}
