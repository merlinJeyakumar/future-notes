import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/core/operations/operation_result.dart';
import 'package:flutter_application_1/features/dashboard/widgets/desktop_window_frame.dart';
import 'support/fake_window_actions.dart';

void main() {
  Widget frame(FakeWindowActions actions) => MaterialApp(
    builder: (_, child) => DesktopWindowFrame(actions: actions, child: child!),
    home: Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) =>
                const AlertDialog(content: Text('Synthetic dialog')),
          ),
          child: const Text('Show dialog'),
        ),
      ),
    ),
  );

  testWidgets(
    'caption controls stay above dialogs and reflect maximize state',
    (tester) async {
      final actions = FakeWindowActions();
      await tester.pumpWidget(frame(actions));
      await tester.pumpAndSettle();
      expect(actions.calls, ['frame:true']);
      expect(
        tester.getSize(find.byKey(const ValueKey('window-caption'))).height,
        36,
      );
      await tester.tap(find.byTooltip('Maximize'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Restore'), findsOneWidget);
      await tester.tap(find.byTooltip('Restore'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Show dialog'));
      await tester.pumpAndSettle();
      expect(find.text('Synthetic dialog'), findsOneWidget);
      await tester.tap(find.byTooltip('Minimize'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(actions.calls, [
        'frame:true',
        'maximize',
        'maximize',
        'minimize',
        'close',
      ]);
      await tester.pumpWidget(const SizedBox.shrink());
      await actions.dispose();
    },
  );

  testWidgets(
    'failed frame setup leaves native fallback and editor available',
    (tester) async {
      final actions = FakeWindowActions()..failConfigure = true;
      await tester.pumpWidget(frame(actions));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('window-caption')), findsNothing);
      expect(find.text('Show dialog'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await actions.dispose();
    },
  );

  testWidgets(
    'pending command cannot repeat; failure is visible and controls recover',
    (tester) async {
      final gate = Completer<OperationResult<void>>();
      final actions = FakeWindowActions()..onMinimize = () => gate.future;
      await tester.pumpWidget(frame(actions));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Minimize'));
      await tester.pump();
      await tester.tap(find.byTooltip('Minimize'));
      await tester.pump();
      expect(actions.calls.where((call) => call == 'minimize'), hasLength(1));
      gate.complete(
        const OperationResult.failure(
          OperationOutcome.ioFailure,
          'Synthetic minimize failure',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Synthetic minimize failure'), findsOneWidget);
      await tester.tap(find.byTooltip('Maximize'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Restore'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await actions.dispose();
    },
  );
}
