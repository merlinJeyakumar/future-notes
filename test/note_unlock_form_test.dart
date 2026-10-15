import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/features/dashboard/widgets/note_unlock_form.dart';

Widget host(
  FocusNode focus,
  Future<bool> Function(String) unlock, {
  Key? key,
}) => MaterialApp(
  home: Scaffold(
    body: NoteUnlockForm(key: key, focusNode: focus, onUnlock: unlock),
  ),
);

void main() {
  testWidgets('autofocus accepts typing and Enter without a dialog', (
    tester,
  ) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    String? received;
    await tester.pumpWidget(
      host(focus, (password) async {
        received = password;
        return true;
      }),
    );
    await tester.pumpAndSettle();
    expect(focus.hasFocus, isTrue);
    expect(find.byType(Dialog), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    tester.testTextInput.enterText('synthetic-password');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(received, 'synthetic-password');
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
  });

  testWidgets(
    'verification suppresses duplicates and failed unlock refocuses',
    (tester) async {
      final focus = FocusNode();
      addTearDown(focus.dispose);
      final result = Completer<bool>();
      var calls = 0;
      await tester.pumpWidget(
        host(focus, (_) {
          calls++;
          return result.future;
        }),
      );
      await tester.pumpAndSettle();
      tester.testTextInput.enterText('synthetic-wrong');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(tester.widget<TextField>(find.byType(TextField)).readOnly, isTrue);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      expect(calls, 1);
      result.complete(false);
      await tester.pumpAndSettle();
      expect(find.textContaining('Could not unlock.'), findsOneWidget);
      expect(focus.hasFocus, isTrue);
      tester.testTextInput.enterText('synthetic-retry');
      await tester.pump();
      expect(find.textContaining('Could not unlock.'), findsNothing);
    },
  );

  testWidgets('note switch clears password and ignores an old completion', (
    tester,
  ) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    final oldUnlock = Completer<bool>();
    await tester.pumpWidget(
      host(focus, (_) => oldUnlock.future, key: const ValueKey(1)),
    );
    await tester.pumpAndSettle();
    tester.testTextInput.enterText('synthetic-first');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.pumpWidget(
      host(focus, (_) async => true, key: const ValueKey(2)),
    );
    await tester.pumpAndSettle();
    oldUnlock.complete(false);
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
    expect(find.textContaining('Could not unlock.'), findsNothing);
    expect(focus.hasFocus, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('small editor and large text scroll without overflow', (
    tester,
  ) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    tester.view.physicalSize = const Size(240, 200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
            body: NoteUnlockForm(
              focusNode: focus,
              onUnlock: (_) async => false,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Unlock'));
    expect(tester.takeException(), isNull);
  });
}
