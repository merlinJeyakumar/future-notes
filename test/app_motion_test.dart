import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/core/theme/app_dialog.dart';
import 'package:flutter_application_1/core/theme/app_motion.dart';
import 'package:flutter_application_1/core/theme/app_tooltip.dart';

void main() {
  testWidgets(
    'reveal reverses in place and excludes closing focus immediately',
    (tester) async {
      var open = true;
      late StateSetter update;
      final focus = FocusNode();
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return Scaffold(
                body: Row(
                  children: [
                    AppReveal(
                      visible: open,
                      axis: Axis.horizontal,
                      duration: AppMotion.dialogIn,
                      reverseDuration: AppMotion.dialogOut,
                      child: SizedBox(
                        width: 280,
                        child: TextField(focusNode: focus),
                      ),
                    ),
                    const Expanded(child: Text('Editor')),
                  ],
                ),
              );
            },
          ),
        ),
      );
      final fieldState = tester.state(find.byType(TextField));
      update(() => open = false);
      await tester.pump();
      expect(focus.canRequestFocus, isFalse);
      await tester.pump(const Duration(milliseconds: 70));
      final width = tester.getSize(find.byType(AppReveal)).width;
      expect(width, greaterThan(0));
      expect(width, lessThan(280));
      update(() => open = true);
      await tester.pump();
      expect(tester.getSize(find.byType(AppReveal)).width, closeTo(width, .01));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(AppReveal)).width, 280);
      expect(tester.state(find.byType(TextField)), same(fieldState));
      expect(focus.canRequestFocus, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      focus.dispose();
    },
  );

  testWidgets('changing reduced motion finishes a running reveal immediately', (
    tester,
  ) async {
    var open = true;
    var reduced = false;
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
              child: Align(
                alignment: Alignment.topLeft,
                child: AppReveal(
                  visible: open,
                  child: const SizedBox(width: 100, height: 160),
                ),
              ),
            );
          },
        ),
      ),
    );
    update(() => open = false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    expect(tester.getSize(find.byType(AppReveal)).height, greaterThan(0));
    update(() => reduced = true);
    await tester.pump();
    expect(tester.getSize(find.byType(AppReveal)).height, 0);
    update(() => open = true);
    await tester.pump();
    expect(tester.getSize(find.byType(AppReveal)).height, 160);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'incoming content has no outgoing copy or restart on ordinary rebuild',
    (tester) async {
      var identity = 'first';
      var locked = false;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return AppEntrance(
                trigger: identity,
                enabled: !locked,
                child: Text(locked ? 'Locked' : identity),
              );
            },
          ),
        ),
      );
      update(() => identity = 'second');
      await tester.pump();
      expect(find.text('first'), findsNothing);
      expect(find.text('second'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 40));
      double offset() => tester
          .widget<Transform>(
            find.descendant(
              of: find.byType(AppEntrance),
              matching: find.byType(Transform),
            ),
          )
          .transform
          .storage[13];
      final before = offset();
      expect(before, greaterThan(0));
      expect(before, lessThan(6));
      update(() {});
      await tester.pump();
      expect(offset(), closeTo(before, .001));
      await tester.pump(const Duration(milliseconds: 40));
      expect(offset(), lessThan(before));
      update(() => locked = true);
      await tester.pump();
      expect(find.text('second'), findsNothing);
      expect(offset(), 0);
    },
  );

  testWidgets(
    'typed dialog animates intermediate frames and preserves barrier/result',
    (tester) async {
      Future<bool?>? result;
      late BuildContext host;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              host = context;
              return const Scaffold();
            },
          ),
        ),
      );
      result = showAppDialog<bool>(
        context: host,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          content: const Text('Synthetic dialog'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Done'),
            ),
          ],
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final route = ModalRoute.of(tester.element(find.byType(AlertDialog)))!;
      expect(route, isA<AppDialogRoute<bool>>());
      expect(route.animation!.value, greaterThan(0));
      expect(route.animation!.value, lessThan(1));
      await tester.tapAt(const Offset(2, 2));
      await tester.pumpAndSettle();
      expect(find.text('Synthetic dialog'), findsOneWidget);
      await tester.tap(find.text('Done'));
      await tester.pump();
      expect(await result, isTrue);
      await tester.pump(const Duration(milliseconds: 70));
      expect(find.text('Synthetic dialog'), findsOneWidget);
      expect(route.animation!.value, greaterThan(0));
      expect(route.animation!.value, lessThan(1));
      await tester.pumpAndSettle();
      expect(find.text('Synthetic dialog'), findsNothing);
    },
  );

  testWidgets(
    'reduced motion is immediate for an open dialog and its dismissal',
    (tester) async {
      final reduced = ValueNotifier(false);
      late BuildContext host;
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => ValueListenableBuilder<bool>(
            valueListenable: reduced,
            builder: (_, value, _) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: value),
              child: child!,
            ),
          ),
          home: Builder(
            builder: (context) {
              host = context;
              return const Scaffold();
            },
          ),
        ),
      );
      showAppDialog<void>(
        context: host,
        builder: (context) =>
            const AlertDialog(content: Text('Reduced dialog')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));
      final route = ModalRoute.of(tester.element(find.byType(AlertDialog)))!;
      reduced.value = true;
      await tester.pump();
      await tester.pump();
      expect(route.animation!.value, 1);
      Navigator.of(host).pop();
      await tester.pump();
      await tester.pump();
      expect(find.text('Reduced dialog'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      reduced.dispose();
    },
  );

  testWidgets(
    'app tooltip keeps semantics, themed placement, hover timing and rebuild state',
    (tester) async {
      const message = 'Synthetic filename';
      const waitDuration = Duration(milliseconds: 200);
      const decoration = BoxDecoration(color: Color(0xff123456));
      final focus = FocusNode();
      addTearDown(focus.dispose);
      late StateSetter rebuild;

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            tooltipTheme: const TooltipThemeData(
              decoration: decoration,
              textStyle: TextStyle(color: Color(0xffabcdef)),
              preferBelow: false,
              verticalOffset: 18,
            ),
          ),
          home: Scaffold(
            body: Center(
              child: StatefulBuilder(
                builder: (context, setState) {
                  rebuild = setState;
                  return AppTooltip(
                    message: message,
                    waitDuration: waitDuration,
                    showDuration: const Duration(milliseconds: 400),
                    child: SizedBox(
                      width: 180,
                      child: TextField(
                        focusNode: focus,
                        decoration: const InputDecoration(
                          labelText: 'Hover file',
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );

      expect(find.byTooltip(message), findsOneWidget);
      final tooltipState = tester.state<TooltipState>(find.byType(AppTooltip));
      final fieldState = tester.state(find.byType(TextField));
      focus.requestFocus();
      await tester.pump();
      expect(focus.hasFocus, isTrue);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(find.byType(AppTooltip)));
      await tester.pump();
      await tester.pump(waitDuration - const Duration(milliseconds: 1));
      expect(find.text(message), findsNothing);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(const Duration(milliseconds: 150));
      expect(find.text(message), findsOneWidget);

      final tooltipText = tester.widget<Text>(find.text(message));
      expect(tooltipText.style?.color, const Color(0xffabcdef));
      final tooltipContainer = find
          .ancestor(of: find.text(message), matching: find.byType(Container))
          .first;
      expect(tester.widget<Container>(tooltipContainer).decoration, decoration);
      final targetCenter = tester.getCenter(find.byType(AppTooltip));
      final tooltipBox = tester.renderObject<RenderBox>(tooltipContainer);
      expect(
        tooltipBox.localToGlobal(tooltipBox.size.center(Offset.zero)).dy,
        lessThan(targetCenter.dy),
      );

      rebuild(() {});
      await tester.pump();
      expect(
        tester.state<TooltipState>(find.byType(AppTooltip)),
        same(tooltipState),
      );
      expect(tester.state(find.byType(TextField)), same(fieldState));
      expect(focus.hasFocus, isTrue);

      await mouse.moveTo(Offset.zero);
      await tester.pump(const Duration(milliseconds: 99));
      expect(find.text(message), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pumpAndSettle();
      expect(find.text(message), findsNothing);
    },
  );

  testWidgets('app tooltip honors configured touch show duration', (
    tester,
  ) async {
    const message = 'Touch tooltip';
    const showDuration = Duration(milliseconds: 300);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: AppTooltip(
              message: message,
              showDuration: showDuration,
              child: Text('Press target'),
            ),
          ),
        ),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(AppTooltip)),
    );
    await tester.pump(kLongPressTimeout);
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.text(message), findsOneWidget);
    await gesture.up();
    await tester.pump(showDuration - const Duration(milliseconds: 1));
    expect(find.text(message), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pumpAndSettle();
    expect(find.text(message), findsNothing);
  });

  testWidgets('app tooltip settles quickly for platform reduced motion', (
    tester,
  ) async {
    const message = 'Reduced tooltip';
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAllTestValues);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: AppTooltip(
              message: message,
              waitDuration: Duration.zero,
              child: SizedBox(width: 100, height: 40),
            ),
          ),
        ),
      ),
    );

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.byType(AppTooltip)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 8));
    expect(find.text(message), findsOneWidget);
    final fade = tester.widget<FadeTransition>(
      find
          .ancestor(
            of: find.text(message),
            matching: find.byType(FadeTransition),
          )
          .first,
    );
    expect(fade.opacity.value, 1);

    await mouse.moveTo(Offset.zero);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 4));
    expect(find.text(message), findsNothing);
  });
}
