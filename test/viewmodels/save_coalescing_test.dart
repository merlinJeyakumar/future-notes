import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/core/operations/operation_result.dart';

import '../support/editor_harness.dart';

void main() {
  void saveTest(
    String name,
    Future<void> Function(WidgetTester tester, EditorHarness h) body,
  ) {
    testWidgets(name, (tester) async {
      final h = await EditorHarness.create();
      addTearDown(h.dispose);
      try {
        await body(tester, h);
      } finally {
        h.disposeEditor();
        await tester.pump(const Duration(seconds: 3));
      }
    });
  }

  Future<void> open(EditorHarness h) async {
    h.seed('note_current', h.note('current', '  Original body  '));
    expect((await h.editor.loadNote('note_current')).isSuccess, isTrue);
  }

  saveTest('first explicit Saves coalesce before work begins', (
    tester,
    h,
  ) async {
    h.editor.titleController.text = 'First requested title';
    final first = h.editor.saveNote();
    h.editor.titleController.text = 'Latest explicit title';
    final latest = h.editor.saveNote();
    expect((await first).isSuccess, isTrue);
    expect((await latest).isSuccess, isTrue);
    expect(h.files.writeAttempts, 1);
    expect(
      (await h.decoded(h.editor.currentFileName!))['title'],
      'Latest explicit title',
    );
    expect(h.editor.hasUnsavedChanges, isFalse);
  });

  saveTest('an active Save plus many pending edits publishes two revisions', (
    tester,
    h,
  ) async {
    await open(h);
    final pause = PausePoint();
    h.encryption.nextAppEncryption = pause;
    h.editor.titleController.text = 'Active immutable revision';
    final active = h.editor.saveNote();
    await pause.started.future;
    final waiting = <Future<OperationResult<void>>>[];
    for (var index = 0; index < 32; index++) {
      h.editor.titleController.text = 'Pending revision $index';
      waiting.add(h.editor.saveNote());
    }
    expect(h.files.writeAttempts, 0);
    pause.resume();
    expect((await active).isSuccess, isTrue);
    expect((await Future.wait(waiting)).every((r) => r.isSuccess), isTrue);
    expect(h.files.writeAttempts, 2);
    expect(h.encryption.encryptCalls, 2);
    expect((await h.decoded('note_current'))['title'], 'Pending revision 31');
  });

  saveTest('already acknowledged duplicate requests do not rewrite storage', (
    tester,
    h,
  ) async {
    await open(h);
    final pause = PausePoint();
    h.encryption.nextAppEncryption = pause;
    h.editor.titleController.text = 'One revision';
    final first = h.editor.saveNote();
    await pause.started.future;
    final second = h.editor.saveNote();
    final third = h.editor.saveNote(isAutoSave: true);
    pause.resume();
    expect((await first).isSuccess, isTrue);
    expect((await second).isSuccess, isTrue);
    expect((await third).isSuccess, isTrue);
    expect(h.files.writeAttempts, 1);
    expect(h.encryption.encryptCalls, 1);
  });

  saveTest('mixed pending manual and automatic requests retain manual status', (
    tester,
    h,
  ) async {
    await open(h);
    final activePause = PausePoint();
    h.encryption.nextAppEncryption = activePause;
    h.editor.titleController.text = 'Active';
    final active = h.editor.saveNote();
    await activePause.started.future;
    h.editor.titleController.text = 'Automatic';
    final automatic = h.editor.saveNote(isAutoSave: true);
    h.editor.titleController.text = 'Manual';
    final manual = h.editor.saveNote();
    h.editor.titleController.text = 'Latest automatic';
    final latest = h.editor.saveNote(isAutoSave: true);
    final pendingPause = PausePoint();
    h.encryption.nextAppEncryption = pendingPause;
    activePause.resume();
    await pendingPause.started.future;
    expect(h.editor.isBusy, isTrue);
    expect(h.editor.isAutoSavingNotifier.value, isFalse);
    pendingPause.resume();
    for (final result in await Future.wait([
      active,
      automatic,
      manual,
      latest,
    ])) {
      expect(result.isSuccess, isTrue);
    }
    expect(h.files.writeAttempts, 2);
    expect((await h.decoded('note_current'))['title'], 'Latest automatic');
  });

  saveTest(
    'typing after the latest capture stays dirty and keeps its document',
    (tester, h) async {
      await open(h);
      final document = h.editor.quillController.document;
      final firstPause = PausePoint();
      h.encryption.nextAppEncryption = firstPause;
      h.editor.titleController.text = 'Active';
      final first = h.editor.saveNote();
      await firstPause.started.future;
      h.editor.titleController.text = 'Queued';
      final queued = h.editor.saveNote();
      h.editor.titleController.text = 'Latest captured';
      final latest = h.editor.saveNote();
      final secondPause = PausePoint();
      h.encryption.nextAppEncryption = secondPause;
      firstPause.resume();
      await secondPause.started.future;
      document.insert(0, 'Typed during final Save ');
      await tester.pump();
      secondPause.resume();
      expect((await first).isSuccess, isTrue);
      expect((await queued).isSuccess, isTrue);
      expect((await latest).isSuccess, isTrue);
      expect(identical(document, h.editor.quillController.document), isTrue);
      expect(h.editor.hasUnsavedChanges, isTrue);
      expect((await h.decoded('note_current'))['content'], '  Original body  ');
      expect((await h.editor.saveNote()).isSuccess, isTrue);
      expect(
        (await h.decoded('note_current'))['content'],
        contains('Typed during final Save'),
      );
      expect(h.editor.hasUnsavedChanges, isFalse);
    },
  );

  saveTest('coalesced failure settles callers and retains the latest draft', (
    tester,
    h,
  ) async {
    await open(h);
    h.files.failWrites = true;
    h.editor.titleController.text = 'First failing revision';
    final first = h.editor.saveNote();
    h.editor.titleController.text = 'Retained latest revision';
    final second = h.editor.saveNote();
    for (final result in await Future.wait([first, second])) {
      expect(result.outcome, OperationOutcome.ioFailure);
    }
    expect(h.files.writeAttempts, 1);
    expect(h.editor.titleController.text, 'Retained latest revision');
    expect(h.editor.hasUnsavedChanges, isTrue);
    await tester.pump(const Duration(seconds: 20));
    expect(h.files.writeAttempts, 1);
    h.files.failWrites = false;
    expect((await h.editor.saveNote()).isSuccess, isTrue);
    expect(h.files.writeAttempts, 2);
    expect(h.editor.hasUnsavedChanges, isFalse);
  });

  saveTest('disposal settles pending callers without waiting for active work', (
    tester,
    h,
  ) async {
    await open(h);
    final pause = PausePoint();
    h.encryption.nextAppEncryption = pause;
    h.editor.titleController.text = 'Active';
    final active = h.editor.saveNote();
    await pause.started.future;
    h.editor.titleController.text = 'Pending';
    final pending = h.editor.saveNote();
    h.editor.titleController.text = 'Latest pending';
    final latest = h.editor.saveNote();
    h.disposeEditor();
    expect((await pending).outcome, OperationOutcome.cancelled);
    expect((await latest).outcome, OperationOutcome.cancelled);
    expect(h.files.writeAttempts, 0);
    pause.resume();
    expect((await active).outcome, OperationOutcome.cancelled);
    expect(h.files.writeAttempts, 0);
  });

  saveTest('a new session never merges with discarded pending snapshots', (
    tester,
    h,
  ) async {
    await open(h);
    final pause = PausePoint();
    h.encryption.nextAppEncryption = pause;
    h.editor.titleController.text = 'Discarded active';
    final active = h.editor.saveNote();
    await pause.started.future;
    h.editor.titleController.text = 'Discarded pending';
    final oldPending = h.editor.saveNote();
    expect((await h.editor.reset(discardChanges: true)).isSuccess, isTrue);
    h.editor.titleController.text = 'Different draft';
    final newSave = h.editor.saveNote();
    expect((await oldPending).outcome, OperationOutcome.cancelled);
    pause.resume();
    expect((await active).outcome, OperationOutcome.cancelled);
    expect((await newSave).isSuccess, isTrue);
    expect(h.files.writeAttempts, 1);
    expect(h.files.writes.single.fileName, isNot('note_current'));
    expect(
      (await h.decoded('note_current'))['title'],
      'Synthetic title current',
    );
    expect(
      (await h.decoded(h.editor.currentFileName!))['title'],
      'Different draft',
    );
  });

  saveTest('a credential generation never merges with older queued Saves', (
    tester,
    h,
  ) async {
    await open(h);
    final pause = PausePoint();
    h.encryption.nextAppEncryption = pause;
    h.editor.titleController.text = 'Active prior credentials';
    final active = h.editor.saveNote();
    await pause.started.future;
    h.editor.titleController.text = 'Pending prior credentials';
    final oldPending = h.editor.saveNote();
    h.editor.setPassword('synthetic-password');
    h.editor.titleController.text = 'Current credentials';
    final current = h.editor.saveNote();
    expect((await oldPending).outcome, OperationOutcome.cancelled);
    pause.resume();
    expect((await active).outcome, OperationOutcome.cancelled);
    expect((await current).isSuccess, isTrue);
    expect(h.files.writeAttempts, 1);
    final stored = await h.decoded('note_current');
    expect(stored['isLocked'], isTrue);
    expect(
      await h.encryption.decrypt(
        stored['content'] as String,
        password: 'synthetic-password',
      ),
      contains('Original body'),
    );
  });

  saveTest(
    'a pending first explicit Save does not admit automatic first Save',
    (tester, h) async {
      h.editor.titleController.text = 'Explicit new draft';
      final manual = h.editor.saveNote();
      final automatic = await h.editor.saveNote(isAutoSave: true);
      expect(automatic.outcome, OperationOutcome.rejectedInput);
      expect((await manual).isSuccess, isTrue);
      expect(h.files.writeAttempts, 1);
    },
  );

  saveTest('exit waits for the latest coalesced revision', (tester, h) async {
    await open(h);
    final pause = PausePoint();
    h.encryption.nextAppEncryption = pause;
    h.editor.titleController.text = 'Active';
    final active = h.editor.saveNote();
    await pause.started.future;
    h.editor.titleController.text = 'Intermediate';
    final intermediate = h.editor.saveNote();
    h.editor.titleController.text = 'Latest before exit';
    final latest = h.editor.saveNote();
    var exited = false;
    final exiting = h.editor.prepareToExit().then((result) {
      exited = true;
      return result;
    });
    await tester.pump();
    expect(exited, isFalse);
    pause.resume();
    for (final result in await Future.wait([
      active,
      intermediate,
      latest,
      exiting,
    ])) {
      expect(result.isSuccess, isTrue);
    }
    expect(h.files.writeAttempts, 2);
    expect((await h.decoded('note_current'))['title'], 'Latest before exit');
  });

  saveTest(
    'coalescing preserves latest HTML and finalized attachment metadata',
    (tester, h) async {
      h.seed(
        'note_current',
        h.note(
          'current',
          '<p>Original</p>',
          attachments: [
            {'id': 'remove', 'fileName': 'remove.bin', 'size': 0},
            {
              'id': 'keep',
              'fileName': 'keep.bin',
              'size': 0,
              'unknown': {'retained': true},
            },
          ],
        ),
      );
      expect((await h.editor.loadNote('note_current')).isSuccess, isTrue);
      await tester.runAsync(h.editor.toggleEditorMode);
      h.editor.htmlController.text = '<p>Intermediate</p>';
      final first = h.editor.saveNote();
      h.editor.htmlController.text = '  <p>Latest body</p>\n';
      h.editor.titleController.text = 'Latest title';
      h.editor.removeAttachment('remove');
      final last = h.editor.saveNote();
      expect((await first).isSuccess, isTrue);
      expect((await last).isSuccess, isTrue);
      expect(h.files.writeAttempts, 1);
      final stored = await h.decoded('note_current');
      expect(stored['content'], '  <p>Latest body</p>\n');
      expect(stored['title'], 'Latest title');
      expect((stored['attachments'] as List).single['id'], 'keep');
      expect((stored['attachments'] as List).single['unknown'], {
        'retained': true,
      });
      expect(stored['timestamp'], 1700000000000);
    },
  );
}
