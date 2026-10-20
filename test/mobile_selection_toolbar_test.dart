import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/features/dashboard/mobile/content_area.dart';
import 'package:flutter_application_1/features/dashboard/mobile/selection_toolbar.dart';
import 'package:flutter_application_1/main.dart';

import 'support/editor_harness.dart';

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final position in ['first', 'middle', 'bottom', 'multiline']) {
      testWidgets('selection menu stays in editor: $platform / $position', (
        tester,
      ) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(320, 760);
        tester.view.viewInsets = const FakeViewPadding(bottom: 280);
        addTearDown(tester.view.reset);
        final viewport = GlobalKey();
        final changes = ValueNotifier<int>(0);
        final top = position == 'first' || position == 'multiline'
            ? 205.0
            : 420.0;
        final bottom = position == 'multiline' ? 700.0 : top + 18;
        final anchors = TextSelectionToolbarAnchors(
          primaryAnchor: Offset(90, top),
          secondaryAnchor: Offset(130, bottom),
        );
        var copied = false;
        var selected = false;
        late final OverlayEntry entry;
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(platform: platform),
            home: Scaffold(
              body: Stack(
                children: [
                  const Positioned(
                    top: 140,
                    height: 50,
                    left: 16,
                    right: 16,
                    child: ColoredBox(color: Colors.blue),
                  ),
                  Positioned.fill(top: 200, child: SizedBox(key: viewport)),
                ],
              ),
            ),
          ),
        );
        final context = viewport.currentContext!;
        entry = OverlayEntry(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(position == 'bottom' ? 2 : 1),
            ),
            child: MobileSelectionToolbar(
              viewportKey: viewport,
              layoutChanges: changes,
              anchors: anchors,
              buttonItems: [
                ContextMenuButtonItem(
                  type: ContextMenuButtonType.cut,
                  onPressed: () {},
                ),
                ContextMenuButtonItem(
                  type: ContextMenuButtonType.copy,
                  onPressed: () => copied = true,
                ),
                ContextMenuButtonItem(
                  type: ContextMenuButtonType.paste,
                  onPressed: () {},
                ),
                ContextMenuButtonItem(
                  type: ContextMenuButtonType.selectAll,
                  onPressed: () => selected = true,
                ),
              ],
            ),
          ),
        );
        Overlay.of(context, rootOverlay: true).insert(entry);
        await tester.pumpAndSettle();
        final menu = find.byKey(const ValueKey('mobile-selection-menu'));
        var rect = tester.getRect(menu);
        expect(rect.top, greaterThanOrEqualTo(208));
        expect(rect.bottom, lessThanOrEqualTo(472));
        expect(rect.left, greaterThanOrEqualTo(8));
        expect(rect.right, lessThanOrEqualTo(312));
        if (position == 'first') expect(rect.top, greaterThan(bottom + 22));
        if (position == 'middle') expect(rect.bottom, lessThan(top));
        await tester.tap(find.text('Copy').hitTestable());
        expect(copied, isTrue);
        final scroll = find.descendant(
          of: menu,
          matching: find.byType(Scrollable),
        );
        final selectAll = find.textContaining(
          RegExp('Select all', caseSensitive: false),
        );
        await tester.scrollUntilVisible(selectAll, 100, scrollable: scroll);
        await tester.tap(selectAll.hitTestable());
        expect(selected, isTrue);
        // Changing the real IME inset reflows the open menu as well.
        tester.view.viewInsets = const FakeViewPadding(bottom: 340);
        changes.value++;
        await tester.pumpAndSettle();
        rect = tester.getRect(menu);
        expect(rect.top, greaterThanOrEqualTo(208));
        expect(rect.bottom, lessThanOrEqualTo(412));
        expect(tester.takeException(), isNull);
        entry.remove();
        entry.dispose();
        await tester.pumpWidget(const SizedBox.shrink());
        changes.dispose();
      });
    }
  }

  testWidgets(
    'real mobile selection uses bounded menu and existing Copy action',
    (tester) async {
      String? copiedText;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copiedText = (call.arguments as Map)['text'] as String?;
          }
          if (call.method == 'Clipboard.hasStrings') return {'value': true};
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final h = await EditorHarness.create();
      h.seed('demo', h.note('demo', 'Synthetic selected text'));
      await h.editor.loadNote('demo');
      try {
        await tester.pumpWidget(
          MyApp(
            settings: h.settings,
            home: Scaffold(body: MobileContentArea(viewModel: h.editor)),
          ),
        );
        h.editor.focusNode.requestFocus();
        h.editor.quillController.updateSelection(
          const TextSelection(baseOffset: 10, extentOffset: 18),
          ChangeSource.local,
        );
        await tester.pumpAndSettle();
        final editor = tester.widget<QuillEditor>(find.byType(QuillEditor));
        editor.config.editorKey!.currentState!.showToolbar();
        await tester.pumpAndSettle();
        final menu = find.byKey(const ValueKey('mobile-selection-menu'));
        final format = find.byKey(const ValueKey('formatting-card'));
        expect(tester.getRect(menu).overlaps(tester.getRect(format)), isFalse);
        await tester.tap(find.text('Copy').hitTestable());
        await tester.pumpAndSettle();
        expect(copiedText, 'selected');
        expect(
          h.editor.quillController.document.toPlainText(),
          'Synthetic selected text\n',
        );
        expect(
          find.byKey(const ValueKey('mobile-selection-menu')),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(h.dispose);
      }
    },
  );
}
