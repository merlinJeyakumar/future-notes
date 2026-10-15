import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/core/operations/operation_result.dart';
import 'package:flutter_application_1/features/dashboard/models/save_ui_state.dart';
import '../support/editor_harness.dart';

void main() {
  void scenario(
    String name,
    Future<void> Function(WidgetTester, EditorHarness) run,
  ) {
    testWidgets(name, (tester) async {
      final h = await EditorHarness.create();
      try {
        await run(tester, h);
      } finally {
        h.disposeEditor();
        await tester.pump(const Duration(seconds: 3));
        await tester.runAsync(h.dispose);
      }
    });
  }

  scenario(
    'dirty edits publish one semantic Save transition and no dashboard notifications',
    (tester, h) async {
      h.seed('current', h.note('current', 'body'));
      await h.editor.loadNote('current');
      var statusChanges = 0;
      var dashboardChanges = 0;
      h.editor.saveStateNotifier.addListener(() => statusChanges++);
      h.editor.addListener(() => dashboardChanges++);
      for (var i = 0; i < 20; i++) {
        h.editor.titleController.text = 'title $i';
      }
      expect(h.editor.saveStateNotifier.value.phase, SavePhase.dirty);
      expect(statusChanges, 1);
      expect(dashboardChanges, 0);
      expect((await h.editor.saveNote()).isSuccess, isTrue);
      expect(h.editor.saveStateNotifier.value.phase, SavePhase.saved);
    },
  );

  scenario(
    'typing during acknowledged Save stays dirty without a false Saved event',
    (tester, h) async {
      h.seed('current', h.note('current', 'body'));
      await h.editor.loadNote('current');
      final pause = PausePoint();
      h.encryption.nextAppEncryption = pause;
      h.editor.titleController.text = 'captured';
      final saving = h.editor.saveNote();
      await pause.started.future;
      final phases = <SavePhase>[];
      h.editor.saveStateNotifier.addListener(
        () => phases.add(h.editor.saveStateNotifier.value.phase),
      );
      h.editor.titleController.text = 'newer';
      pause.resume();
      expect((await saving).isSuccess, isTrue);
      expect(h.editor.saveStateNotifier.value.phase, SavePhase.dirty);
      expect(phases, isNot(contains(SavePhase.saved)));
      expect((await h.decoded('current'))['title'], 'captured');
    },
  );

  scenario(
    'Save failure survives unrelated results and Retry captures current draft',
    (tester, h) async {
      h.seed('current', h.note('current', 'body'));
      await h.editor.loadNote('current');
      h.editor.titleController.text = 'failed revision';
      h.files.failWrites = true;
      expect((await h.editor.saveNote()).isSuccess, isFalse);
      expect(h.editor.saveStateNotifier.value.phase, SavePhase.failed);
      h.editor.operationResultNotifier.value = const OperationResult.success();
      expect(h.editor.saveStateNotifier.value.phase, SavePhase.failed);
      h.editor.titleController.text = 'latest revision';
      h.files.failWrites = false;
      expect((await h.editor.retrySave()).isSuccess, isTrue);
      expect((await h.decoded('current'))['title'], 'latest revision');
      expect(h.editor.saveStateNotifier.value.phase, SavePhase.saved);
    },
  );

  scenario('listed note identity is checked before same-name fast path', (
    tester,
    h,
  ) async {
    h.seed('current', h.note('current', 'body'));
    await h.editor.loadNote('current');
    final document = h.editor.quillController.document;
    final result = await h.editor.loadNote(
      'current',
      expectedContentPath: 'D:/wrong/current',
    );
    expect(result.outcome, OperationOutcome.cancelled);
    expect(identical(h.editor.quillController.document, document), isTrue);
    expect(h.files.writeAttempts, 0);
  });

  testWidgets(
    'conversion is local, single-flight and discards results after typing',
    (tester) async {
      final output = Completer<String>();
      var calls = 0;
      final h = await EditorHarness.create(
        deltaToHtml: (_) {
          calls++;
          return output.future;
        },
      );
      try {
        h.editor.quillController.document.insert(0, 'body');
        final converting = h.editor.setEditorMode(EditorMode.html);
        await tester.pump();
        expect(h.editor.isConvertingEditor, isTrue);
        expect(h.editor.isBusy, isFalse);
        expect(
          (await h.editor.setEditorMode(EditorMode.html)).outcome,
          OperationOutcome.conflict,
        );
        expect(calls, 1);
        h.editor.quillController.document.insert(0, 'later ');
        await tester.pump();
        output.complete('<p>body</p>');
        expect((await converting).outcome, OperationOutcome.cancelled);
        expect(h.editor.isHtmlMode, isFalse);
        expect(
          h.editor.quillController.document.toPlainText(),
          contains('later body'),
        );
        expect(h.editor.isConvertingEditor, isFalse);
      } finally {
        h.disposeEditor();
        await tester.pump(const Duration(seconds: 3));
        await tester.runAsync(h.dispose);
      }
    },
  );
}
