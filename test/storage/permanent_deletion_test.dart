import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_application_1/core/operations/operation_result.dart';
import 'package:flutter_application_1/core/storage/native_storage_primitives.dart';
import 'package:flutter_application_1/core/storage/recoverable_store.dart';
import 'package:flutter_application_1/core/storage/storage_environment.dart';
import 'package:flutter_application_1/core/storage/commit_record.dart';
import '../support/validation_directory.dart';

void main() {
  late Directory run;
  late String root;
  late StorageEnvironment environment;
  late NativeStoragePrimitives primitives;
  RecoverableStore? store;
  setUp(() async {
    run = await createValidationRun();
    root = p.join(run.path, 'library');
    await Directory(root).create();
    environment = StorageEnvironment.validation(
      validationRoot: run.path,
      dataRoot: root,
      settingsFile: p.join(run.path, 'configuration', 'settings.json'),
    );
    primitives = NativeStoragePrimitives(environment);
  });
  tearDown(() async {
    await store?.close();
    store = null;
    await deleteValidationRun(run);
  });
  Future<void> open({CommitFaultHook? fault}) async {
    final result = await RecoverableStore.open(
      root: root,
      environment: environment,
      faultHook: fault,
    );
    expect(result.isSuccess, isTrue);
    store = result.value!;
  }

  Future<StorageRevision> seed(String target, String value) async {
    final file = File(p.join(root, target));
    await file.parent.create(recursive: true);
    await file.writeAsString(value, flush: true);
    return primitives.captureRevision(file.path);
  }

  Future<CommitFileSource> candidate(String value) async {
    final file = File(p.join(run.path, 'candidate'));
    await file.writeAsString(value, flush: true);
    return CommitFileSource(file.path, await file.length());
  }

  test(
    'permanent Delete removes note, attachments and all managed recovery',
    () async {
      const target = 'note_synthetic/note_content_synthetic.enc';
      final original = await seed(target, 'old synthetic');
      await seed('note_synthetic/attachments/old.med', 'old attachment');
      await seed('unrelated.enc', 'keep unrelated');
      await open();
      final committed = await store!.commit(
        target: target,
        expected: original,
        source: await candidate('new synthetic'),
      );
      expect(committed.isSuccess, isTrue);
      final deleted = await store!.delete(
        target: target,
        expected: committed.value!,
        attachmentDirectory: 'note_synthetic/attachments',
      );
      expect(deleted.isSuccess, isTrue);
      expect(await File(p.join(root, target)).exists(), isFalse);
      expect(
        await File(p.join(root, 'note_synthetic/attachments/old.med')).exists(),
        isFalse,
      );
      expect(
        await File(p.join(root, 'unrelated.enc')).readAsString(),
        'keep unrelated',
      );
      final recovery = Directory(
        p.join(root, '.future-notes-storage/recovery'),
      );
      expect(
        await recovery.list(recursive: true).where((e) => e is File).toList(),
        isEmpty,
      );
      await store!.close();
      await open();
      expect(store!.recovery.libraryReadOnly, isFalse);
      expect(await File(p.join(root, target)).exists(), isFalse);
      final staleSave = await store!.commit(
        target: target,
        expected: const StorageRevision.missing(),
        source: await candidate('must not resurrect'),
      );
      expect(staleSave.outcome, OperationOutcome.recoveryRequired);
    },
    skip: !Platform.isWindows,
  );

  test(
    'changed reviewed note rejects Delete without removing anything',
    () async {
      final expected = await seed('note.enc', 'reviewed');
      await open();
      await seed('note.enc', 'external edit');
      final result = await store!.delete(
        target: 'note.enc',
        expected: expected,
      );
      expect(result.outcome, OperationOutcome.conflict);
      expect(
        await File(p.join(root, 'note.enc')).readAsString(),
        'external edit',
      );
    },
    skip: !Platform.isWindows,
  );

  test(
    'Delete journals retained preparation sources and preserves another identity',
    () async {
      const target = 'note.enc';
      final expected = await seed(target, 'synthetic');
      final sources =
          '.future-notes-storage/sources/${CommitRecord.objectIdentity(target)}/attachment-operation-synthetic';
      await seed('$sources/old.med', 'retained encrypted preparation');
      await seed('$sources/note.json', 'synthetic export metadata');
      await seed(
        '.future-notes-storage/sources/${CommitRecord.objectIdentity('other.enc')}/attachment-operation-synthetic/other.med',
        'unrelated',
      );
      await open();
      final result = await store!.delete(target: target, expected: expected);
      expect(result.isSuccess, isTrue);
      expect(await File(p.join(root, sources, 'old.med')).exists(), isFalse);
      expect(await File(p.join(root, sources, 'note.json')).exists(), isFalse);
      expect(
        await File(
          p.join(
            root,
            '.future-notes-storage/sources/${CommitRecord.objectIdentity('other.enc')}/attachment-operation-synthetic/other.med',
          ),
        ).exists(),
        isTrue,
      );
    },
    skip: !Platform.isWindows,
  );

  test(
    'Delete removes attachment recovery even when the active attachment is missing',
    () async {
      const note = 'note_synthetic/note_content_synthetic.enc';
      const attachment = 'note_synthetic/attachments/missing.med';
      final noteRevision = await seed(note, 'synthetic note');
      final oldAttachment = await seed(attachment, 'old synthetic payload');
      await open();
      final saved = await store!.commit(
        target: attachment,
        expected: oldAttachment,
        source: await candidate('new synthetic payload'),
      );
      expect(saved.isSuccess, isTrue);
      await File(p.join(root, attachment)).delete();
      final deleted = await store!.delete(
        target: note,
        expected: noteRevision,
        attachmentDirectory: 'note_synthetic/attachments',
      );
      expect(deleted.isSuccess, isTrue, reason: deleted.message);
      final metadata = Directory(
        p.join(
          root,
          '.future-notes-storage/recovery',
          CommitRecord.objectIdentity(attachment),
        ),
      );
      expect(await metadata.list().toList(), isEmpty);
      await store!.close();
      await open();
      expect(await File(p.join(root, attachment)).exists(), isFalse);
      expect(store!.recovery.blockedTargets, contains(attachment));
    },
    skip: !Platform.isWindows,
  );

  for (final boundary in [
    CommitBoundary.deletionIntentVerified,
    CommitBoundary.deletionFileRemoved,
    CommitBoundary.deletionReceiptWritten,
  ]) {
    test(
      'interruption at ${boundary.name} never resurrects and can retry',
      () async {
        final expected = await seed('note.enc', 'original');
        var injected = false;
        await open(
          fault: (point, _) async {
            if (point == boundary && !injected) {
              injected = true;
              throw StateError('synthetic interruption');
            }
          },
        );
        final changed = await store!.commit(
          target: 'note.enc',
          expected: expected,
          source: await candidate('changed'),
        );
        expect(changed.isSuccess, isTrue);
        final result = await store!.delete(
          target: 'note.enc',
          expected: changed.value!,
        );
        expect(result.outcome, OperationOutcome.recoveryRequired);
        await store!.close();
        await open();
        expect(store!.recovery.libraryReadOnly, isFalse);
        expect(
          store!.recovery.pendingDeletions,
          hasLength(boundary == CommitBoundary.deletionReceiptWritten ? 0 : 1),
        );
        if (boundary != CommitBoundary.deletionIntentVerified) {
          expect(await File(p.join(root, 'note.enc')).exists(), isFalse);
        }
        final retried = await store!.delete(
          target: 'note.enc',
          expected: changed.value!,
        );
        expect(retried.isSuccess, isTrue);
        expect(store!.recovery.pendingDeletions, isEmpty);
        expect(await File(p.join(root, 'note.enc')).exists(), isFalse);
      },
      skip: !Platform.isWindows,
    );
  }
  test(
    'partial failure reports progress and preserves external replacements',
    () async {
      final expected = await seed('note.enc', 'original');
      await seed('note_synthetic/attachments/a.med', 'original attachment');
      var replaced = false;
      await open(
        fault: (point, _) async {
          if (point == CommitBoundary.deletionFileRemoved && !replaced) {
            replaced = true;
            await seed(
              'note_synthetic/attachments/a.med',
              'externally replaced attachment',
            );
          }
        },
      );
      final result = await store!.delete(
        target: 'note.enc',
        expected: expected,
        attachmentDirectory: 'note_synthetic/attachments',
      );
      expect(result.outcome, OperationOutcome.recoveryRequired);
      expect(result.value!.removed, contains('note.enc'));
      expect(
        result.value!.pending,
        contains('note_synthetic/attachments/a.med'),
      );
      expect(
        await File(
          p.join(root, 'note_synthetic/attachments/a.med'),
        ).readAsString(),
        'externally replaced attachment',
      );
      await store!.close();
      await open();
      expect(await File(p.join(root, 'note.enc')).exists(), isFalse);
    },
    skip: !Platform.isWindows,
  );
  test(
    'invalid attachment tree refuses preparation without deletion',
    () async {
      final expected = await seed('note.enc', 'original');
      await open();
      final result = await store!.delete(
        target: 'note.enc',
        expected: expected,
        attachmentDirectory: 'unrelated',
      );
      expect(result.isSuccess, isFalse);
      expect(await File(p.join(root, 'note.enc')).exists(), isTrue);
    },
    skip: !Platform.isWindows,
  );
}
