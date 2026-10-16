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

  testWidgets('app tooltip retains Material semantics and calibrated motion', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AppTooltip(
            message: 'Synthetic filename',
            child: Text('Hover file'),
          ),
        ),
      ),
    );
    expect(find.byTooltip('Synthetic filename'), findsOneWidget);
    final raw = tester.widget<RawTooltip>(find.byType(RawTooltip));
    expect(raw.semanticsTooltip, 'Synthetic filename');
    expect(raw.animationStyle.duration, AppMotion.quickIn);
    expect(raw.animationStyle.reverseDuration, AppMotion.quickOut);
  });
}
