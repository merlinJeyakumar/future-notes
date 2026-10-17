import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/features/dashboard/mobile/expanding_formatting_bar.dart';
import 'package:flutter_application_1/features/dashboard/widgets/mention_popup_layout.dart';

void main() {
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
        scrollable: find.byType(Scrollable).first,
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
