import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/core/operations/operation_result.dart';
import 'package:flutter_application_1/features/dashboard/views/dashboard_screen.dart';
import 'package:flutter_application_1/features/dashboard/widgets/content_area.dart';
import 'package:flutter_application_1/main.dart';

import 'support/editor_harness.dart';

class _Fixture {
  _Fixture(this.harness);

  final EditorHarness harness;
  Completer<OperationResult<void>> cleanup = Completer();
  int closeCalls = 0;

  Future<OperationResult<void>> close() {
    closeCalls++;
    return cleanup.future;
  }
}

void main() {
  void scenario(
    String name,
    Future<void> Function(WidgetTester, _Fixture) body,
  ) {
    testWidgets(name, (tester) async {
      final harness = await EditorHarness.create();
      final fixture = _Fixture(harness);
      addTearDown(harness.dispose);
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      try {
        await tester.pumpWidget(
          MyApp(
            settings: harness.settings,
            home: DashboardScreen(
              settings: harness.settings,
              fileService: harness.files,
              startBackgroundServices: false,
              onClose: fixture.close,
            ),
          ),
        );
        await body(tester, fixture);
      } finally {
        if (!fixture.cleanup.isCompleted) {
          fixture.cleanup.complete(const OperationResult.success());
        }
        await tester.pump();
        await tester.pumpWidget(const SizedBox.shrink());
        harness.disposeEditor();
        await tester.pump(const Duration(seconds: 3));
      }
    });
  }

  List<EditableTextState> editors(WidgetTester tester) =>
      tester.stateList<EditableTextState>(find.byType(EditableText)).toList();

  void expectRetained(WidgetTester tester, List<EditableTextState> before) {
    expect(before.length, greaterThanOrEqualTo(2));
    expect(editors(tester), orderedEquals(before));
    expect(before.every((state) => state.mounted), isTrue);
    expect(find.byType(ContentArea), findsOneWidget);
    expect(find.text('Storage closed. Closing window…'), findsNothing);
  }

  scenario('real exit aggregation retains text listeners through cleanup', (
    tester,
    fixture,
  ) async {
    final before = editors(tester);
    final exit = tester.binding.handleRequestAppExit();
    await tester.pump();
    expect(fixture.closeCalls, 1);
    expectRetained(tester, before);
    final gate = tester.widget<AbsorbPointer>(
      find
          .descendant(
            of: find.byType(DashboardScreen),
            matching: find.byType(AbsorbPointer),
          )
          .first,
    );
    expect(gate.absorbing, isTrue);
    final focusGate = tester.widget<ExcludeFocus>(
      find
          .descendant(
            of: find.byType(DashboardScreen),
            matching: find.byType(ExcludeFocus),
          )
          .first,
    );
    expect(focusGate.excluding, isTrue);
    expect(
      before.every((state) => !state.widget.focusNode.canRequestFocus),
      isTrue,
    );
    expect(fixture.harness.files.writeAttempts, 0);
    fixture.cleanup.complete(const OperationResult.success());
    await tester.pump();
    expect(await exit, AppExitResponse.exit);
    expectRetained(tester, before);
    expect(tester.takeException(), isNull);
  });

  scenario('slow cleanup keeps the original exit request and editor alive', (
    tester,
    fixture,
  ) async {
    final before = editors(tester);
    AppExitResponse? response;
    final exit = tester.binding.handleRequestAppExit().then((value) {
      response = value;
      return value;
    });
    await tester.pump();
    await tester.pump(const Duration(seconds: 11));
    expect(response, isNull);
    expect(fixture.closeCalls, 1);
    expectRetained(tester, before);
    fixture.cleanup.complete(const OperationResult.success());
    await tester.pump();
    expect(await exit, AppExitResponse.exit);
    expect(tester.takeException(), isNull);
  });

  scenario('concurrent exit requests share one cleanup attempt', (
    tester,
    fixture,
  ) async {
    final before = editors(tester);
    final first = tester.binding.handleRequestAppExit();
    await tester.pump();
    final second = tester.binding.handleRequestAppExit();
    await tester.pump();
    expect(fixture.closeCalls, 1);
    expectRetained(tester, before);
    fixture.cleanup.complete(const OperationResult.success());
    await tester.pump();
    expect(await first, AppExitResponse.exit);
    expect(await second, AppExitResponse.exit);
    expect(tester.takeException(), isNull);
  });

  scenario('another observer can still cancel the combined exit response', (
    tester,
    fixture,
  ) async {
    final other = AppLifecycleListener(
      onExitRequested: () async => AppExitResponse.cancel,
    );
    addTearDown(other.dispose);
    final before = editors(tester);
    final exit = tester.binding.handleRequestAppExit();
    await tester.pump();
    fixture.cleanup.complete(const OperationResult.success());
    await tester.pump();
    expect(await exit, AppExitResponse.cancel);
    expect(fixture.closeCalls, 1);
    expectRetained(tester, before);
    expect(tester.takeException(), isNull);
  });

  scenario('cleanup failure cancels exit and a deliberate retry can finish', (
    tester,
    fixture,
  ) async {
    final before = editors(tester);
    final first = tester.binding.handleRequestAppExit();
    await tester.pump();
    fixture.cleanup.complete(
      const OperationResult.failure(
        OperationOutcome.recoveryRequired,
        'Synthetic cleanup failure',
      ),
    );
    await tester.pump();
    expect(await first, AppExitResponse.cancel);
    expectRetained(tester, before);
    expect(
      find.text(
        'Storage cleanup is incomplete. Close the window again to retry.',
      ),
      findsOneWidget,
    );
    fixture.cleanup = Completer();
    final retry = tester.binding.handleRequestAppExit();
    await tester.pump();
    expect(fixture.closeCalls, 2);
    fixture.cleanup.complete(const OperationResult.success());
    await tester.pump();
    expect(await retry, AppExitResponse.exit);
    expect(fixture.harness.files.writeAttempts, 0);
    expect(tester.takeException(), isNull);
  });

  scenario('cancelled unsaved draft keeps editing enabled and storage open', (
    tester,
    fixture,
  ) async {
    final area = tester.widget<ContentArea>(find.byType(ContentArea));
    area.viewModel.titleController.text = 'Synthetic unsaved title';
    final exit = tester.binding.handleRequestAppExit();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Save this new note?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(await exit, AppExitResponse.cancel);
    expect(fixture.closeCalls, 0);
    expect(area.viewModel.titleController.text, 'Synthetic unsaved title');
    expect(fixture.harness.files.writeAttempts, 0);
    final gate = tester.widget<AbsorbPointer>(
      find
          .descendant(
            of: find.byType(DashboardScreen),
            matching: find.byType(AbsorbPointer),
          )
          .first,
    );
    expect(gate.absorbing, isFalse);
    expect(tester.takeException(), isNull);
  });

  scenario('New Note makes the unsaved draft state explicit and focuses it', (
    tester,
    fixture,
  ) async {
    expect(find.text('Not saved'), findsOneWidget);
    await tester.tap(find.widgetWithText(ElevatedButton, 'New Note'));
    await tester.pump();
    expect(
      find.text(
        'New draft ready. Edit it, then select Save to create the note.',
      ),
      findsOneWidget,
    );
    final area = tester.widget<ContentArea>(find.byType(ContentArea));
    expect(area.viewModel.currentFileName, isNull);
    expect(area.viewModel.focusNode.hasFocus, isTrue);
    expect(fixture.harness.files.writeAttempts, 0);
  });

  scenario('first explicit Save publishes the note date', (
    tester,
    fixture,
  ) async {
    final area = tester.widget<ContentArea>(find.byType(ContentArea));
    area.viewModel.titleController.text = 'Synthetic dated note';
    final saved = await tester.runAsync(area.viewModel.saveNote);
    expect(saved?.isSuccess, isTrue);
    await tester.pump();
    expect(area.viewModel.currentFileName, isNotNull);
    expect(area.viewModel.currentNoteDate, isNotNull);
    expect(find.text('Not saved'), findsNothing);
    expect(find.textContaining('Note date '), findsWidgets);
    expect(fixture.harness.files.writeAttempts, 1);
  });
}
