import 'dart:convert';
import 'dart:typed_data' as data;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_application_1/core/operations/operation_result.dart';
import 'package:flutter_application_1/core/storage/note_reference.dart';
import 'package:flutter_application_1/features/dashboard/models/draft_session.dart';
import 'package:flutter_application_1/features/dashboard/models/note_list_ui_state.dart';

import '../support/editor_harness.dart';

void main() {
  Future<EditorHarness> harness() async {
    final result = await EditorHarness.create();
    addTearDown(result.dispose);
    return result;
  }

  testWidgets(
    'sidebar state follows unlock, navigation and relock without writes',
    (tester) async {
      final h = await harness();
      h.seed('protected', h.note('protected', 'Protected body', locked: true));
      h.seed('plain', h.note('plain', 'Plain body'));
      NoteLockState? state() =>
          h.editor.noteListStateNotifier.value.selectedLockState;
      await h.editor.loadNote('protected');
      expect(state(), NoteLockState.locked);
      expect(await h.editor.unlockNote('wrong-synthetic-password'), isFalse);
      expect(state(), NoteLockState.locked);
      expect(await h.editor.unlockNote('synthetic-password'), isTrue);
      expect(state(), NoteLockState.unlocked);
      await h.editor.loadNote('plain');
      expect(state(), NoteLockState.unprotected);
      await h.editor.loadNote('protected');
      expect(state(), NoteLockState.unlocked);
      expect((await h.editor.manualLock()).isSuccess, isTrue);
      expect(state(), NoteLockState.locked);
      expect(h.files.writeAttempts, 0);
    },
  );

  testWidgets(
    'locked manual Save and autosave perform zero writes/encryption',
    (tester) async {
      final h = await harness();
      h.seed('note_locked', h.note('locked', 'Protected body', locked: true));
      expect((await h.editor.loadNote('note_locked')).isSuccess, isTrue);
      for (final automatic in [false, true]) {
        final result = await h.editor.saveNote(isAutoSave: automatic);
        expect(result.outcome, OperationOutcome.rejectedInput);
      }
      h.editor.onTextChanged();
      await tester.pump(const Duration(seconds: 3));
      expect(h.files.writeAttempts, 0);
      expect(h.encryption.encryptCalls, 0);
      expect(h.editor.isLocked, isTrue);
    },
  );

  testWidgets('failed unlock never installs an error body or write authority', (
    tester,
  ) async {
    final h = await harness();
    h.seed('note_locked', h.note('locked', 'Protected body', locked: true));
    await h.editor.loadNote('note_locked');
    final document = h.editor.quillController.document;
    expect(await h.editor.unlockNote('wrong-synthetic-password'), isFalse);
    expect(identical(h.editor.quillController.document, document), isTrue);
    expect(
      h.editor.quillController.document.toPlainText(),
      isNot(contains('Error')),
    );
    expect((await h.editor.saveNote()).isSuccess, isFalse);
    expect(h.files.writeAttempts, 0);
    expect(await h.editor.unlockNote('synthetic-password'), isTrue);
    h.seed('note_other', h.note('other', 'Other body'));
    await h.editor.loadNote('note_other');
    h.seed('note_locked', {
      ...h.note('locked', 'Protected body', locked: true),
      'content': h.encryption.wrapUser(
        'Changed protection',
        'different-synthetic-password',
      ),
    });
    await h.editor.loadNote('note_locked');
    expect(h.editor.isLocked, isTrue);
    expect(h.editor.isPasswordSet, isFalse);
    expect(
      h.editor.quillController.document.toPlainText(),
      isNot(contains('Incorrect')),
    );
    await h.editor.saveNote();
    expect(h.files.writeAttempts, 0);
  });

  testWidgets(
    'missing/corrupt/unsupported loads retain prior session and target',
    (tester) async {
      final h = await harness();
      h.seed('note_previous', h.note('previous', 'Previous body'));
      await h.editor.loadNote('note_previous');
      final document = h.editor.quillController.document;
      final generation = h.editor.draftSession.generation;
      final bad = {
        'bad-envelope.enc': 'app:broken',
        'bad-json.enc': '{"content":',
        'bad-attachments.enc': jsonEncode({
          ...h.note('bad', 'body'),
          'attachments': {},
        }),
        'bad-body.enc': jsonEncode(h.note('bad', '[{"insert":')),
      };
      for (final entry in bad.entries) h.files.seed(entry.key, entry.value);
      for (final name in ['missing.enc', ...bad.keys]) {
        expect((await h.editor.loadNote(name)).isSuccess, isFalse);
        expect(h.editor.currentFileName, 'note_previous');
        expect(h.editor.draftSession.generation, generation);
        expect(identical(h.editor.quillController.document, document), isTrue);
        await h.editor.saveNote();
        expect(h.files.writeAttempts, 0);
      }
      expect(h.files.writeAttempts, 0);
      h.editor.titleController.text = 'My retained title';
      expect((await h.editor.saveNote()).isSuccess, isTrue);
      expect(h.files.writes.single.fileName, 'note_previous');
      final empty = await harness();
      empty.files.seed('bad-empty.enc', 'app:broken');
      await empty.editor.loadNote('bad-empty.enc');
      expect((await empty.editor.saveNote()).isSuccess, isFalse);
      expect(empty.files.writeAttempts, 0);
    },
  );

  testWidgets(
    'latest load owns selection even when an older read finishes later',
    (tester) async {
      final h = await harness();
      h.seed('note_old', h.note('old', 'Old body'));
      h.seed('note_new', h.note('new', 'New body'));
      final pause = PausePoint();
      h.files.readPauses['note_old'] = pause;
      final old = h.editor.loadNote('note_old');
      await pause.started.future;
      await h.editor.loadNote('note_new');
      pause.resume();
      expect((await old).outcome, OperationOutcome.cancelled);
      expect(h.editor.currentFileName, 'note_new');
      expect(
        h.editor.quillController.document.toPlainText(),
        contains('New body'),
      );
    },
  );

  testWidgets('typing while another note loads keeps the existing draft', (
    tester,
  ) async {
    final h = await harness();
    h.seed('note_previous', h.note('previous', 'Previous body'));
    h.seed('note_next', h.note('next', 'Next body'));
    await h.editor.loadNote('note_previous');
    final pause = PausePoint();
    h.files.readPauses['note_next'] = pause;
    final loading = h.editor.loadNote('note_next');
    await pause.started.future;
    h.editor.quillController.document.insert(0, 'Latest edit ');
    await tester.pump();
    pause.resume();
    expect((await loading).outcome, OperationOutcome.cancelled);
    expect(h.editor.currentFileName, 'note_previous');
    expect(h.editor.hasUnsavedChanges, isTrue);
    h.disposeEditor();
    await tester.pump(const Duration(seconds: 3));
    expect(h.files.writeAttempts, 0);
  });

  testWidgets('an old unlock cannot publish into a newly selected note', (
    tester,
  ) async {
    final h = await harness();
    h.seed('note_locked', h.note('locked', 'Protected body', locked: true));
    h.seed('note_new', h.note('new', 'New body'));
    await h.editor.loadNote('note_locked');
    final pause = PausePoint();
    h.encryption.nextDecryption = pause;
    final unlocking = h.editor.unlockNote('synthetic-password');
    await pause.started.future;
    await h.editor.loadNote('note_new');
    pause.resume();
    expect(await unlocking, isFalse);
    expect(h.editor.currentFileName, 'note_new');
    expect(h.editor.isPasswordSet, isFalse);
  });

  testWidgets('verification and repeated unlock preserve an editable draft', (
    tester,
  ) async {
    final h = await harness();
    h.seed('note_locked', h.note('locked', 'Protected body', locked: true));
    await h.editor.loadNote('note_locked');
    final lockedDocument = h.editor.quillController.document;
    expect(await h.editor.verifyStoredPassword('synthetic-password'), isTrue);
    expect(h.editor.isLocked, isTrue);
    expect(
      identical(h.editor.quillController.document, lockedDocument),
      isTrue,
    );
    expect(await h.editor.unlockNote('synthetic-password'), isTrue);
    h.editor.quillController.document.insert(0, 'Unsaved addition ');
    await tester.pump();
    final editableDocument = h.editor.quillController.document;
    expect(await h.editor.verifyStoredPassword('synthetic-password'), isTrue);
    expect(await h.editor.unlockNote('synthetic-password'), isTrue);
    expect(
      identical(h.editor.quillController.document, editableDocument),
      isTrue,
    );
    expect(h.editor.hasUnsavedChanges, isTrue);
    expect(h.files.writeAttempts, 0);
    h.disposeEditor();
    await tester.pump(const Duration(seconds: 3));
    expect(h.files.writeAttempts, 0);
  });

  testWidgets(
    'new drafts require first explicit Save even after setting password',
    (tester) async {
      final h = await harness();
      h.editor.titleController.text = 'Short title';
      h.editor.quillController.document.insert(0, 'New body');
      h.editor.setPassword('synthetic-password');
      await tester.pump(const Duration(seconds: 3));
      expect((await h.editor.saveNote(isAutoSave: true)).isSuccess, isFalse);
      expect(h.files.writeAttempts, 0);
      expect((await h.editor.saveNote()).isSuccess, isTrue);
      expect(h.editor.draftSession.isPersisted, isTrue);
      expect(h.editor.hasUnsavedChanges, isFalse);
      final note = await h.decoded(h.editor.currentFileName!);
      expect(note['title'], 'Short title');
      expect(note['timestamp'], 1700000000000);
    },
  );

  testWidgets('immediate Save includes edits before Quill stream delivery', (
    tester,
  ) async {
    final h = await harness();
    h.seed('note_immediate', h.note('immediate', 'Original body'));
    await h.editor.loadNote('note_immediate');
    h.editor.quillController.document.insert(0, 'Immediate edit ');
    await h.editor.saveNote();
    final saved = await h.decoded('note_immediate');
    expect(saved['content'], contains('Immediate edit'));
    expect(h.editor.hasUnsavedChanges, isFalse);
  });

  testWidgets(
    'title-only Save preserves raw body, metadata, timestamp and legacy shape',
    (tester) async {
      final h = await harness();
      const body = '  Synthetic indentation\n\nTrailing whitespace  \n\n';
      final metadata = {
        ...h.note('persistent-id', body, attachments: ['legacy-attachment']),
        'futureNoteField': {
          'retain': [1, true, 'synthetic'],
        },
      };
      h.seed(
        'note_prefixed.enc',
        metadata,
        encrypted: false,
        format: NoteStorageFormat.legacyFile,
      );
      await h.editor.loadNote('note_prefixed.enc');
      expect(
        h.editor.quillController.document.toPlainText(),
        startsWith('  Synthetic'),
      );
      h.editor.titleController.text = 'My short title';
      await h.editor.saveNote();
      final saved = await h.decoded('note_prefixed.enc');
      expect(saved, {...metadata, 'title': 'My short title'});
      expect(h.files.writes.single.format, NoteStorageFormat.legacyFile);
      expect(
        h.files.contents[h.files.writes.single.contentPath],
        startsWith('{'),
      );
    },
  );

  testWidgets(
    'manual/autosave use equivalent rich/title/final-attachment metadata',
    (tester) async {
      final manual = await harness();
      final automatic = await harness();
      for (final h in [manual, automatic]) {
        h.seed(
          'note_equivalent',
          h.note(
            'equivalent',
            'Original',
            attachments: [
              {
                'id': 'remove',
                'fileName': 'synthetic.bin',
                'size': 1,
                'futureField': true,
              },
              {
                'id': 'retain',
                'fileName': 'keep.bin',
                'size': 0,
                'futureField': {'keep': true},
              },
            ],
          ),
        );
        await h.editor.loadNote('note_equivalent');
        h.editor.titleController.text = 'Explicit equivalent title';
        h.editor.quillController.document.insert(0, 'Equivalent edit ');
        h.editor.removeAttachment('remove');
      }
      await manual.editor.saveNote();
      await tester.pump(const Duration(seconds: 2));
      expect(automatic.files.writes.length, 1);
      expect(
        await automatic.decoded('note_equivalent'),
        await manual.decoded('note_equivalent'),
      );
      expect(
        (await manual.decoded(
          'note_equivalent',
        ))['attachments'].single['futureField'],
        {'keep': true},
      );
    },
  );

  testWidgets(
    'HTML changes autosave while selection-only changes schedule no writes',
    (tester) async {
      final h = await harness();
      h.seed('note_html', h.note('html', '<p>Synthetic HTML</p>'));
      await h.editor.loadNote('note_html');
      await tester.runAsync(h.editor.toggleEditorMode);
      await h.editor.saveNote();
      final before = h.files.writes.length;
      h.editor.htmlController.selection = const TextSelection.collapsed(
        offset: 0,
      );
      await tester.pump(const Duration(seconds: 3));
      expect(h.files.writes.length, before);
      h.editor.htmlController.text = '<p>Latest HTML edit</p>\n';
      await tester.pump(const Duration(seconds: 2));
      expect(
        (await h.decoded('note_html'))['content'],
        '<p>Latest HTML edit</p>\n',
      );
    },
  );

  testWidgets(
    'document observation survives load, unlock, reset and conversion',
    (tester) async {
      final h = await harness();
      h.seed('note_rich', h.note('rich', 'Rich body'));
      h.seed('note_locked', h.note('locked', 'Protected body', locked: true));
      await h.editor.loadNote('note_rich');
      h.editor.quillController.document.insert(0, 'First edit ');
      await tester.pump();
      expect(h.editor.draftSession.dirtyFields, contains(DraftField.body));
      await h.editor.loadNote('note_locked');
      await h.editor.unlockNote('synthetic-password');
      h.editor.quillController.document.insert(0, 'Unlocked edit ');
      await tester.pump();
      expect(h.editor.hasUnsavedChanges, isTrue);
      await h.editor.reset(discardChanges: true);
      h.editor.quillController.document.insert(0, 'Reset edit ');
      await tester.pump();
      expect(h.editor.hasUnsavedChanges, isTrue);
      await h.editor.reset(discardChanges: true);
      await h.editor.loadNote('note_rich');
      await tester.runAsync(h.editor.toggleEditorMode);
      await tester.runAsync(h.editor.toggleEditorMode);
      await h.editor.saveNote();
      h.editor.quillController.document.insert(0, 'Converted edit ');
      await tester.pump();
      expect(h.editor.hasUnsavedChanges, isTrue);
    },
  );

  testWidgets(
    'save snapshots exclude edits made during encryption and retain their dirty revision',
    (tester) async {
      final h = await harness();
      h.seed('note_snapshot', h.note('snapshot', 'Original'));
      await h.editor.loadNote('note_snapshot');
      h.editor.titleController.text = 'Captured title';
      final pause = PausePoint();
      h.encryption.nextAppEncryption = pause;
      final saving = h.editor.saveNote();
      await pause.started.future;
      h.editor.titleController.text = 'Later title';
      h.editor.quillController.document.insert(0, 'Later body ');
      await tester.pump();
      pause.resume();
      expect((await saving).isSuccess, isTrue);
      expect((await h.decoded('note_snapshot'))['title'], 'Captured title');
      expect(h.editor.titleController.text, 'Later title');
      expect(h.editor.hasUnsavedChanges, isTrue);
      await h.editor.saveNote();
      expect(
        (await h.decoded('note_snapshot'))['content'],
        contains('Later body'),
      );
      expect(h.editor.hasUnsavedChanges, isFalse);
    },
  );

  testWidgets('changing mutable root cannot redirect an already opened save', (
    tester,
  ) async {
    final h = await harness();
    final originalRoot = h.files.libraryRoot;
    h.seed('note_bound', h.note('bound', 'Original library body'));
    await h.editor.loadNote('note_bound');
    h.files.libraryRoot = p.join(h.run.path, 'second-library');
    h.seed('note_bound', h.note('bound', 'Other library body'));
    h.editor.titleController.text = 'Changed title in original library';
    await h.editor.saveNote();
    expect(h.files.writes.single.binding.root, originalRoot);
    expect((await h.decoded('note_bound'))['content'], 'Other library body');
    expect(
      (await h.decoded('note_bound', root: originalRoot))['title'],
      'Changed title in original library',
    );
  });

  testWidgets(
    'background failure pauses retry until another edit or explicit Save',
    (tester) async {
      final h = await harness();
      h.seed('note_failure', h.note('failure', 'Original'));
      await h.editor.loadNote('note_failure');
      h.files.failWrites = true;
      h.editor.titleController.text = 'Unsaved title';
      await tester.pump(const Duration(seconds: 2));
      expect(h.files.writeAttempts, 1);
      expect(h.editor.hasUnsavedChanges, isTrue);
      expect(
        h.editor.saveStateNotifier.value.failure,
        OperationOutcome.ioFailure,
      );
      await tester.pump(const Duration(seconds: 20));
      expect(h.files.writeAttempts, 1);
      h.editor.titleController.text = 'Another edit';
      await tester.pump(const Duration(seconds: 2));
      expect(h.files.writeAttempts, 2);
      h.files.failWrites = false;
      await h.editor.saveNote();
      expect(h.files.writeAttempts, 3);
      expect(h.editor.hasUnsavedChanges, isFalse);
    },
  );

  testWidgets(
    'a discarded session cancels an old save before file publication',
    (tester) async {
      final h = await harness();
      h.seed('note_cancel', h.note('cancel', 'Original'));
      await h.editor.loadNote('note_cancel');
      h.editor.titleController.text = 'Captured edit';
      final pause = PausePoint();
      h.encryption.nextAppEncryption = pause;
      final saving = h.editor.saveNote();
      await pause.started.future;
      await h.editor.reset(discardChanges: true);
      pause.resume();
      expect((await saving).outcome, OperationOutcome.cancelled);
      expect(h.files.writeAttempts, 0);
      expect(h.editor.currentFileName, isNull);
    },
  );

  testWidgets(
    'navigation flushes existing edits and remains blocked on failure',
    (tester) async {
      final h = await harness();
      h.seed('note_current', h.note('current', 'Original'));
      h.seed('note_next', h.note('next', 'Next'));
      await h.editor.loadNote('note_current');
      h.editor.quillController.document.insert(0, 'Must preserve ');
      h.files.failWrites = true;
      expect(
        (await h.editor.loadNote('note_next')).outcome,
        OperationOutcome.ioFailure,
      );
      expect(h.editor.currentFileName, 'note_current');
      expect(h.editor.hasUnsavedChanges, isTrue);
      h.files.failWrites = false;
      expect((await h.editor.loadNote('note_next')).isSuccess, isTrue);
      expect(
        (await h.decoded('note_current'))['content'],
        contains('Must preserve'),
      );
      expect(h.editor.currentFileName, 'note_next');
    },
  );

  testWidgets(
    'never-saved draft transitions and first attachment require a decision',
    (tester) async {
      final h = await harness();
      h.seed('note_next', h.note('next', 'Next'));
      h.editor.titleController.text = 'New explicit title';
      expect(
        (await h.editor.loadNote('note_next')).outcome,
        OperationOutcome.rejectedInput,
      );
      expect((await h.editor.reset()).isSuccess, isFalse);
      await h.editor
          .pickAttachment(); // Must return before any picker/native I/O.
      expect(h.editor.currentFileName, isNull);
      expect(h.editor.hasUnsavedChanges, isTrue);
      expect(h.files.writeAttempts, 0);
    },
  );

  testWidgets('dispose rejects delayed load publication', (tester) async {
    final h = await harness();
    h.seed('note_late', h.note('late', 'Late body'));
    final pause = PausePoint();
    h.files.readPauses['note_late'] = pause;
    final loading = h.editor.loadNote('note_late');
    await pause.started.future;
    h.disposeEditor();
    pause.resume();
    expect((await loading).outcome, OperationOutcome.cancelled);
    expect(h.files.writeAttempts, 0);
  });

  testWidgets('concurrent first saves retain one persistent note identity', (
    tester,
  ) async {
    final h = await harness();
    h.editor.titleController.text = 'First revision';
    final pause = PausePoint();
    h.encryption.nextAppEncryption = pause;
    final first = h.editor.saveNote();
    await pause.started.future;
    h.editor.titleController.text = 'Second revision';
    final second = h.editor.saveNote();
    pause.resume();
    expect((await first).isSuccess, isTrue);
    expect((await second).isSuccess, isTrue);
    expect(h.files.writes.map((r) => r.contentPath).toSet().length, 1);
    expect(
      (await h.decoded(h.editor.currentFileName!))['title'],
      'Second revision',
    );
    expect(h.editor.hasUnsavedChanges, isFalse);
  });

  testWidgets('manual lock flushes the latest body and then rejects writes', (
    tester,
  ) async {
    final h = await harness();
    h.seed('note_lock', h.note('lock', 'Original', locked: true));
    await h.editor.loadNote('note_lock');
    await h.editor.unlockNote('synthetic-password');
    h.editor.quillController.document.insert(0, 'Must survive lock ');
    expect((await h.editor.manualLock()).isSuccess, isTrue);
    expect(h.editor.isLockedNotifier.value, isTrue);
    final metadata = await h.decoded('note_lock');
    expect(
      await h.encryption.decrypt(
        metadata['content'] as String,
        password: 'synthetic-password',
      ),
      contains('Must survive lock'),
    );
    final before = h.files.writeAttempts;
    await h.editor.saveNote();
    await tester.pump(const Duration(seconds: 3));
    expect(h.files.writeAttempts, before);
    await h.editor.reset(discardChanges: true);
    expect(h.editor.isLocked, isFalse);
    expect(h.editor.isLockedNotifier.value, isFalse);
    expect(h.editor.attachmentsNotifier.value, isEmpty);
  });

  testWidgets(
    'failure-prefix body unlocks, verifies and reopens without replacement',
    (tester) async {
      final h = await harness();
      const body = 'Error decrypting: intentional synthetic plaintext';
      h.seed('note_prefix', h.note('prefix', body, locked: true));
      await h.editor.loadNote('note_prefix');
      expect(await h.editor.verifyStoredPassword('synthetic-password'), isTrue);
      expect(h.editor.isLocked, isTrue);
      expect(await h.editor.unlockNote('synthetic-password'), isTrue);
      expect(h.editor.quillController.document.toPlainText(), contains(body));
      h.seed('note_other', h.note('other', 'Other synthetic content'));
      await h.editor.loadNote('note_other');
      await h.editor.loadNote('note_prefix');
      expect(h.editor.isLocked, isFalse);
      expect(h.editor.quillController.document.toPlainText(), contains(body));
      expect(h.files.writeAttempts, 0);
    },
  );

  testWidgets(
    'empty protected body is valid and failed credentials perform zero writes',
    (tester) async {
      final h = await harness();
      h.seed('note_empty', h.note('empty', '', locked: true));
      await h.editor.loadNote('note_empty');
      expect(await h.editor.unlockNote('wrong-synthetic-password'), isFalse);
      expect((await h.editor.saveNote()).isSuccess, isFalse);
      expect(await h.editor.unlockNote('synthetic-password'), isTrue);
      expect(h.editor.quillController.document.toPlainText(), '\n');
      expect(h.editor.hasUnsavedChanges, isFalse);
      expect(h.files.writeAttempts, 0);
    },
  );

  testWidgets(
    'preview failures are not cached while valid empty payloads are cached',
    (tester) async {
      final h = await harness();
      h.seed('note_attach', h.note('attach', 'Synthetic body'));
      h.files.attachmentContents['attach/a'] = data.Uint8List(0);
      await h.editor.loadNote('note_attach');
      h.encryption.failBinaryDecryption = true;
      expect(await h.editor.readAttachment('a'), isNull);
      expect(await h.editor.readAttachment('a'), isNull);
      expect(h.encryption.binaryDecryptCalls, 2);
      h.encryption.failBinaryDecryption = false;
      expect(await h.editor.readAttachment('a'), isEmpty);
      expect(await h.editor.readAttachment('a'), isEmpty);
      expect(h.encryption.binaryDecryptCalls, 3);
      expect(h.files.writeAttempts, 0);
    },
  );
}
