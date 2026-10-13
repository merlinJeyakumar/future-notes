import 'dart:ui' show AppExitResponse;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/core/operations/operation_result.dart';
import 'package:flutter_application_1/features/dashboard/models/draft_transition.dart';

import '../support/editor_harness.dart';

typedef HarnessFactory = Future<EditorHarness> Function(DraftDecisionHandler);

void main() {
  void draftTest(
    String name,
    Future<void> Function(WidgetTester, HarnessFactory) body,
  ) {
    testWidgets(name, (tester) async {
      final owned = <EditorHarness>[];
      Future<EditorHarness> create(DraftDecisionHandler decisions) async {
        final h = await EditorHarness.create(onDraftDecision: decisions);
        owned.add(h);
        addTearDown(h.dispose);
        return h;
      }

      try {
        await body(tester, create);
      } finally {
        for (final h in owned) h.disposeEditor();
        await tester.pump(const Duration(seconds: 3));
      }
    });
  }

  draftTest('new draft Cancel retains content and performs no writes', (
    tester,
    create,
  ) async {
    final h = await create((r) async {
      expect(r.kind, DraftDecisionKind.firstSave);
      return DraftDecision.cancel;
    });
    h.editor.titleController.text = 'Keep draft';
    h.seed('note_next', h.note('next', 'Next'));
    expect(
      (await h.editor.loadNote('note_next')).outcome,
      OperationOutcome.cancelled,
    );
    expect(h.editor.titleController.text, 'Keep draft');
    expect(h.editor.currentFileName, isNull);
    expect(h.files.writeAttempts, 0);
  });

  draftTest('new draft Save persists before publishing the destination', (
    tester,
    create,
  ) async {
    final h = await create((r) async => DraftDecision.save);
    h.editor.quillController.document.insert(0, 'Keep first save');
    h.seed('note_next', h.note('next', 'Next'));
    expect((await h.editor.loadNote('note_next')).isSuccess, isTrue);
    expect(h.editor.currentFileName, 'note_next');
    expect(h.files.writes, hasLength(1));
    expect(
      (await h.decoded(h.files.writes.single.fileName))['content'],
      contains('Keep first save'),
    );
  });

  draftTest('Discard remains provisional until a destination validates', (
    tester,
    create,
  ) async {
    final h = await create((r) async => DraftDecision.discard);
    h.editor.titleController.text = 'Retain if destination fails';
    expect((await h.editor.loadNote('missing.enc')).isSuccess, isFalse);
    expect(h.editor.titleController.text, 'Retain if destination fails');
    expect(h.editor.hasUnsavedChanges, isTrue);
    h.seed('note_next', h.note('next', 'Next'));
    expect((await h.editor.loadNote('note_next')).isSuccess, isTrue);
    expect(h.files.writeAttempts, 0);
  });

  draftTest('failed existing Save offers Retry and flushes before navigation', (
    tester,
    create,
  ) async {
    late EditorHarness h;
    h = await create((r) async {
      expect(r.kind, DraftDecisionKind.saveFailure);
      h.files.failWrites = false;
      return DraftDecision.retry;
    });
    h.seed('note_current', h.note('current', 'Original'));
    h.seed('note_next', h.note('next', 'Next'));
    await h.editor.loadNote('note_current');
    h.editor.titleController.text = 'Latest saved title';
    h.files.failWrites = true;
    expect((await h.editor.loadNote('note_next')).isSuccess, isTrue);
    expect(h.files.writeAttempts, 2);
    expect((await h.decoded('note_current'))['title'], 'Latest saved title');
  });

  draftTest('failed first Save Retry does not ask first-Save consent again', (
    tester,
    create,
  ) async {
    final kinds = <DraftDecisionKind>[];
    late EditorHarness h;
    h = await create((r) async {
      kinds.add(r.kind);
      if (r.kind == DraftDecisionKind.saveFailure) {
        h.files.failWrites = false;
        return DraftDecision.retry;
      }
      return DraftDecision.save;
    });
    h.editor.titleController.text = 'First save';
    h.files.failWrites = true;
    expect((await h.editor.reset()).isSuccess, isTrue);
    expect(kinds, [DraftDecisionKind.firstSave, DraftDecisionKind.saveFailure]);
    expect(h.files.writeAttempts, 2);
    expect(h.files.writes, hasLength(1));
  });

  draftTest('Discard after save failure does not overwrite stored content', (
    tester,
    create,
  ) async {
    final h = await create((r) async => DraftDecision.discard);
    h.seed('note_current', h.note('current', 'Original'));
    h.seed('note_next', h.note('next', 'Next'));
    await h.editor.loadNote('note_current');
    h.editor.titleController.text = 'Discard this title';
    h.files.failWrites = true;
    expect((await h.editor.loadNote('note_next')).isSuccess, isTrue);
    expect(
      (await h.decoded('note_current'))['title'],
      'Synthetic title current',
    );
    await tester.pump(const Duration(seconds: 3));
    expect(h.files.writeAttempts, 1);
    expect(h.files.writes, isEmpty);
  });

  draftTest('edits during a decision invalidate Discard permission', (
    tester,
    create,
  ) async {
    final pause = PausePoint();
    final h = await create((r) async {
      await pause.wait();
      return DraftDecision.discard;
    });
    h.editor.titleController.text = 'Reviewed revision';
    h.seed('note_next', h.note('next', 'Next'));
    final loading = h.editor.loadNote('note_next');
    await pause.started.future;
    h.editor.titleController.text = 'Later revision';
    pause.resume();
    expect((await loading).outcome, OperationOutcome.conflict);
    expect(h.editor.titleController.text, 'Later revision');
    expect(h.files.writeAttempts, 0);
  });

  draftTest('late decision cannot replace a different session', (
    tester,
    create,
  ) async {
    final pause = PausePoint();
    final h = await create((r) async {
      await pause.wait();
      return DraftDecision.save;
    });
    h.editor.titleController.text = 'Previous draft';
    final replacing = h.editor.reset();
    await pause.started.future;
    await h.editor.reset(discardChanges: true);
    h.editor.titleController.text = 'New owner';
    pause.resume();
    expect((await replacing).isSuccess, isFalse);
    expect(h.editor.titleController.text, 'New owner');
    expect(h.files.writeAttempts, 0);
  });

  draftTest('lock failure Cancel retains editor and credentials', (
    tester,
    create,
  ) async {
    final h = await create((r) async => DraftDecision.cancel);
    h.seed('note_locked', h.note('locked', 'Original', locked: true));
    await h.editor.loadNote('note_locked');
    await h.editor.unlockNote('synthetic-password');
    h.editor.quillController.document.insert(0, 'Keep edit ');
    h.files.failWrites = true;
    expect((await h.editor.manualLock()).outcome, OperationOutcome.cancelled);
    expect(h.editor.isLocked, isFalse);
    expect(h.editor.isPasswordSet, isTrue);
    expect(h.editor.hasUnsavedChanges, isTrue);
  });

  draftTest('first attachment Cancel never opens picker; Save persists first', (
    tester,
    create,
  ) async {
    var choice = DraftDecision.cancel;
    final h = await create((r) async {
      expect(r.kind, DraftDecisionKind.firstAttachment);
      return choice;
    });
    h.editor.titleController.text = 'Before attachment';
    await h.editor.pickAttachment();
    expect(h.files.pickerCalls, 0);
    expect(h.files.writeAttempts, 0);
    choice = DraftDecision.save;
    await h.editor.pickAttachment();
    expect(h.editor.draftSession.isPersisted, isTrue);
    expect(h.files.writeAttempts, 1);
    expect(h.files.pickerCalls, 1);
  });

  draftTest('locking a new protected draft requires explicit first Save', (
    tester,
    create,
  ) async {
    final h = await create((r) async {
      expect(r.kind, DraftDecisionKind.firstSave);
      expect(r.transition, DraftTransition.lock);
      return DraftDecision.save;
    });
    h.editor.titleController.text = 'New protected note';
    h.editor.setPassword('synthetic-password');
    expect((await h.editor.manualLock()).isSuccess, isTrue);
    expect(h.files.writeAttempts, 1);
    expect(h.editor.isLocked, isTrue);
    expect((await h.editor.saveNote()).isSuccess, isFalse);
    expect(h.files.writeAttempts, 1);
  });

  draftTest('Flutter exit-request protocol cancels or saves a new draft', (
    tester,
    create,
  ) async {
    var choice = DraftDecision.cancel;
    final h = await create((r) async {
      expect(r.transition, DraftTransition.exit);
      return choice;
    });
    h.editor.titleController.text = 'Exit draft';
    final listener = AppLifecycleListener(
      onExitRequested: () async => (await h.editor.prepareToExit()).isSuccess
          ? AppExitResponse.exit
          : AppExitResponse.cancel,
    );
    addTearDown(listener.dispose);
    expect(await tester.binding.handleRequestAppExit(), AppExitResponse.cancel);
    expect(h.editor.hasUnsavedChanges, isTrue);
    expect(h.files.writeAttempts, 0);
    choice = DraftDecision.save;
    expect(await tester.binding.handleRequestAppExit(), AppExitResponse.exit);
    expect(h.files.writeAttempts, 1);
    expect(h.editor.hasUnsavedChanges, isFalse);
  });

  draftTest('exit Discard leaves storage untouched and cancels autosave', (
    tester,
    create,
  ) async {
    final h = await create((r) async => DraftDecision.discard);
    h.editor.titleController.text = 'Discard at exit';
    expect((await h.editor.prepareToExit()).isSuccess, isTrue);
    await tester.pump(const Duration(seconds: 3));
    expect(h.files.writeAttempts, 0);
  });
}
