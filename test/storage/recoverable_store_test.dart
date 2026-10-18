import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_application_1/core/operations/operation_result.dart';
import 'package:flutter_application_1/core/storage/commit_record.dart';
import 'package:flutter_application_1/core/storage/native_storage_primitives.dart';
import 'package:flutter_application_1/core/storage/recoverable_store.dart';
import 'package:flutter_application_1/core/storage/storage_environment.dart';
import 'package:flutter_application_1/core/storage/windows_file_actions.dart';

import '../support/validation_directory.dart';
import 'package:flutter_application_1/core/storage/owned_stream_writer.dart';

void main() {
  late Directory run;
  late String root;
  late StorageEnvironment environment;
  late NativeStoragePrimitives primitives;
  late List<RecoverableStore> owners;
  var identity = 0;
  setUp(() async {
    run = await Directory.systemTemp.createTemp('future-notes-validation-');
    root = p.join(run.path, 'library');
    await Directory(root).create();
    environment = StorageEnvironment.validation(
      validationRoot: run.path,
      dataRoot: root,
      settingsFile: p.join(run.path, 'configuration', 'settings.json'),
    );
    primitives = NativeStoragePrimitives(environment);
    owners = [];
    identity = 0;
  });
  tearDown(() async {
    for (final store in owners) {
      await store.close();
    }
    await deleteValidationRun(run);
  });

  Future<RecoverableStore> open({
    CommitFaultHook? fault,
    String? storageRoot,
    String Function()? identities,
  }) async {
    final result = await RecoverableStore.open(
      root: storageRoot ?? root,
      environment: environment,
      faultHook: fault,
      transactionIdentity:
          identities ?? () => (++identity).toRadixString(16).padLeft(32, '0'),
    );
    expect(result.isSuccess, isTrue, reason: result.message);
    owners.add(result.value!);
    return result.value!;
  }

  Future<CommitFileSource> source(String text, {String name = 'input'}) async {
    final file = File(p.join(run.path, 'sources', '$name.synthetic'));
    await file.parent.create(recursive: true);
    await file.writeAsString(text, flush: true);
    return CommitFileSource(file.path, await file.length());
  }

  Future<File> active([String text = 'Synthetic original']) async {
    final file = File(p.join(root, 'note.enc'));
    await file.writeAsString(text, flush: true);
    return file;
  }

  Future<List<CommitRecord>> records() async {
    final folder = Directory(
      p.join(root, '.future-notes-storage', 'transactions'),
    );
    if (!await folder.exists()) return [];
    final entries = await folder
        .list()
        .where((f) => f is File && f.path.endsWith('.json'))
        .toList();
    entries.sort((a, b) => a.path.compareTo(b.path));
    return Future.wait(
      entries.map(
        (f) async => CommitRecord.decode(await File(f.path).readAsString()),
      ),
    );
  }

  for (final boundary in CommitBoundary.values.where(
    (b) => b.index <= CommitBoundary.receiptVerified.index,
  )) {
    test(
      'owned candidate interrupted at ${boundary.name} preserves a complete generation',
      () async {
        final sources = await Directory(
          p.join(root, '.future-notes-storage', 'sources', 'synthetic'),
        ).create(recursive: true);
        final writer = await OwnedStreamWriter.open(
          p.join(sources.path, 'new.med'),
        );
        await writer.add(List.filled(4096, 42));
        final proof = await writer.close();
        final canonical = File(p.join(root, 'attachments', 'new.med'));
        await canonical.parent.create(recursive: true);
        await canonical.writeAsBytes(List.filled(4096, 17), flush: true);
        final expected = await primitives.captureRevision(canonical.path);
        final store = await open(
          fault: (phase, id) async {
            if (phase == boundary) throw StateError('Synthetic interruption');
          },
        );
        final result = await store.commit(
          target: 'attachments/new.med',
          expected: expected,
          source: CommitFileSource(proof.path, proof.length, receipt: proof),
        );
        expect(result.isSuccess, isFalse);
        await store.close();
        owners.remove(store);
        final reopened = await open();
        expect(reopened.recovery.libraryReadOnly, isFalse);
        final bytes = await canonical.readAsBytes();
        expect(bytes.toSet(), anyOf({17}, {42}));
        expect(bytes.length, 4096);
        await reopened.close();
        owners.remove(reopened);
      },
    );
  }
  test('owned adoption skips copy and payload readback stages', () async {
    final dir = await Directory(
      p.join(root, '.future-notes-storage', 'sources', 'synthetic'),
    ).create(recursive: true);
    final writer = await OwnedStreamWriter.open(p.join(dir.path, 'new.med'));
    await writer.add(List.filled(4096, 42));
    final proof = await writer.close();
    final phases = <String>[];
    final store = await open();
    final result = await store.commit(
      target: 'attachments/new.med',
      expected: const StorageRevision.missing(),
      source: CommitFileSource(proof.path, proof.length, receipt: proof),
      onProgress: (phase, _, _) => phases.add(phase),
    );
    expect(result.isSuccess, isTrue, reason: result.message);
    expect(await File(proof.path).exists(), isFalse);
    expect(
      phases.any(
        (p) =>
            p.contains('Checking prepared') ||
            p.contains('Verifying published') ||
            p.contains('Confirming staged'),
      ),
      isFalse,
    );
    expect(
      await File(p.join(root, 'attachments', 'new.med')).readAsBytes(),
      List.filled(4096, 42),
    );
  });
  test(
    'production and escaped roots are rejected without creating storage',
    () async {
      final candidate = p.join(run.path, 'must-not-create');
      final result = await RecoverableStore.open(
        root: candidate,
        environment: const StorageEnvironment.production(),
      );
      expect(result.outcome, OperationOutcome.rejectedInput);
      expect(await Directory(candidate).exists(), isFalse);
      expect(
        (await RecoverableStore.open(
          root: p.dirname(run.path),
          environment: environment,
        )).outcome,
        OperationOutcome.rejectedInput,
      );
    },
  );

  test(
    'successful replacement retains exact first baseline and every prior version',
    () async {
      final file = await active();
      final expected = await primitives.captureRevision(file.path);
      final store = await open();
      final first = await store.commit(
        target: 'note.enc',
        expected: expected,
        source: await source('Synthetic second'),
      );
      expect(first.isSuccess, isTrue);
      final second = await store.commit(
        target: 'note.enc',
        expected: first.value!,
        source: await source('Synthetic third', name: 'second'),
      );
      expect(second.isSuccess, isTrue);
      final journal = await records();
      expect(journal.length, 2);
      expect(await file.readAsString(), 'Synthetic third');
      expect(
        await File(
          journal.first.resolve(root, journal.first.baselinePath),
        ).readAsString(),
        'Synthetic original',
      );
      expect(
        await File(
          journal.first.resolve(root, journal.first.previousPath),
        ).readAsString(),
        'Synthetic original',
      );
      expect(
        await File(
          journal.last.resolve(root, journal.last.previousPath),
        ).readAsString(),
        'Synthetic second',
      );
      for (final record in journal) {
        final receipt = CommitReceipt.decode(
          await File(record.resolve(root, record.receiptPath)).readAsString(),
          record,
        );
        expect(receipt.disposition, CommitDisposition.completed);
      }
      await store.close();
      final reopened = await open();
      expect(reopened.recovery.libraryReadOnly, isFalse);
      expect(reopened.recovery.blockedTargets, isEmpty);
      expect(await file.readAsString(), 'Synthetic third');
    },
    skip: !Platform.isWindows,
  );

  test(
    'new and empty objects have acknowledged receipts without fabricated prior versions',
    () async {
      final store = await open();
      final result = await store.commit(
        target: 'new/note.enc',
        expected: const StorageRevision.missing(),
        source: await source(''),
      );
      expect(result.isSuccess, isTrue);
      expect(result.value!.length, 0);
      final record = (await records()).single;
      expect(
        await File(record.resolve(root, record.previousPath)).exists(),
        isFalse,
      );
      expect(
        await File(record.resolve(root, record.baselinePath)).exists(),
        isFalse,
      );
      await store.close();
      expect((await open()).recovery.blockedTargets, isEmpty);
      expect(await File(p.join(root, 'new', 'note.enc')).length(), 0);
    },
    skip: !Platform.isWindows,
  );

  test(
    'same-size external edits reject commit without a transaction or overwrite',
    () async {
      final file = await active('old');
      final expected = await primitives.captureRevision(file.path);
      await file.writeAsString('new', flush: true);
      await file.setLastModified(
        DateTime.fromMicrosecondsSinceEpoch(expected.modifiedMicros!),
      );
      final store = await open();
      expect(
        (await store.commit(
          target: 'note.enc',
          expected: expected,
          source: await source('Synthetic candidate'),
        )).outcome,
        OperationOutcome.conflict,
      );
      expect(await file.readAsString(), 'new');
      expect(await records(), isEmpty);
    },
    skip: !Platform.isWindows,
  );

  test(
    'source length and traversal errors perform no target writes',
    () async {
      final file = await active();
      final expected = await primitives.captureRevision(file.path);
      final input = await source('Synthetic candidate');
      final store = await open();
      expect(
        (await store.commit(
          target: 'note.enc',
          expected: expected,
          source: CommitFileSource(input.path, input.length + 1),
        )).outcome,
        OperationOutcome.rejectedInput,
      );
      expect(
        (await store.commit(
          target: '../outside.enc',
          expected: expected,
          source: input,
        )).outcome,
        OperationOutcome.rejectedInput,
      );
      expect(await records(), isEmpty);
      expect(await file.readAsString(), 'Synthetic original');
    },
    skip: !Platform.isWindows,
  );

  test(
    'source mutation during bounded copying fails before journaling',
    () async {
      final file = await active();
      final expected = await primitives.captureRevision(file.path);
      final input = await source('Synthetic candidate');
      final store = await open(
        fault: (point, id) async {
          if (point == CommitBoundary.stageWritten) {
            await File(
              input.path,
            ).writeAsString('Synthetic changed source', flush: true);
          }
        },
      );
      expect(
        (await store.commit(
          target: 'note.enc',
          expected: expected,
          source: input,
        )).outcome,
        OperationOutcome.ioFailure,
      );
      expect(await records(), isEmpty);
      expect(await file.readAsString(), 'Synthetic original');
    },
    skip: !Platform.isWindows,
  );

  test(
    'preparation cancellation retains active bytes and never writes an intent',
    () async {
      final file = await active();
      final expected = await primitives.captureRevision(file.path);
      var cancel = false;
      final store = await open(
        fault: (point, id) async {
          if (point == CommitBoundary.stageVerified) {
            cancel = true;
          }
        },
      );
      expect(
        (await store.commit(
          target: 'note.enc',
          expected: expected,
          source: await source('Synthetic candidate'),
          isCancelled: () => cancel,
        )).outcome,
        OperationOutcome.cancelled,
      );
      expect(await records(), isEmpty);
      expect(await file.readAsString(), 'Synthetic original');
    },
    skip: !Platform.isWindows,
  );

  test(
    'cancellation after the intent does not interrupt publication',
    () async {
      final file = await active();
      final expected = await primitives.captureRevision(file.path);
      var cancel = false;
      final store = await open(
        fault: (point, id) async {
          if (point == CommitBoundary.intentVerified) {
            cancel = true;
          }
        },
      );
      expect(
        (await store.commit(
          target: 'note.enc',
          expected: expected,
          source: await source('Synthetic candidate'),
          isCancelled: () => cancel,
        )).isSuccess,
        isTrue,
      );
      expect(await file.readAsString(), 'Synthetic candidate');
    },
    skip: !Platform.isWindows,
  );

  test(
    'one queue serializes commits and rejects a later stale revision',
    () async {
      final file = await active();
      final expected = await primitives.captureRevision(file.path);
      final prepared = Completer<void>();
      final release = Completer<void>();
      var preparations = 0;
      final store = await open(
        fault: (point, id) async {
          if (point == CommitBoundary.stageVerified && ++preparations == 1) {
            prepared.complete();
            await release.future;
          }
        },
      );
      final firstSource = await source('Synthetic first');
      final secondSource = await source('Synthetic second', name: 'second');
      final first = store.commit(
        target: 'note.enc',
        expected: expected,
        source: firstSource,
      );
      await prepared.future;
      final second = store.commit(
        target: 'note.enc',
        expected: expected,
        source: secondSource,
      );
      expect(preparations, 1);
      release.complete();
      expect((await first).isSuccess, isTrue);
      expect((await second).outcome, OperationOutcome.conflict);
      expect(preparations, 1);
      expect(await file.readAsString(), 'Synthetic first');
      expect((await records()).length, 1);
    },
    skip: !Platform.isWindows,
  );

  for (final failure in [(1, false), (2, false), (1, true)]) {
    test(
      'native move ${failure.$1} failure, after move ${failure.$2}, recovers the original',
      () async {
        final file = await active();
        final expected = await primitives.captureRevision(file.path);
        final result = await RecoverableStore.open(
          root: root,
          environment: environment,
          fileActions: _FailMove(
            WindowsFileActions(root: root, environment: environment),
            failure.$1,
            failure.$2,
          ),
        );
        expect(result.isSuccess, isTrue);
        final store = result.value!;
        owners.add(store);
        expect(
          (await store.commit(
            target: 'note.enc',
            expected: expected,
            source: await source('Synthetic candidate'),
          )).outcome,
          OperationOutcome.recoveryRequired,
        );
        await store.close();
        final recovered = await open();
        expect(recovered.recovery.blockedTargets, isEmpty);
        expect(await file.readAsString(), 'Synthetic original');
        expect(
          (await primitives.captureRevision(file.path)).matches(expected),
          isTrue,
        );
      },
      skip: !Platform.isWindows,
    );
  }

  test(
    'leases exclude a second owner while settings and library remain independent',
    () async {
      final store = await open();
      expect(
        (await RecoverableStore.open(
          root: root,
          environment: environment,
        )).outcome,
        OperationOutcome.conflict,
      );
      final settings = await open(
        storageRoot: p.dirname(environment.settingsFile!),
      );
      expect(
        (await settings.commit(
          target: 'settings.json',
          expected: const StorageRevision.missing(),
          source: await source('{"synthetic":true}'),
        )).isSuccess,
        isTrue,
      );
      await store.close();
      expect((await open()).recovery.libraryReadOnly, isFalse);
      expect(
        (await store.commit(
          target: 'late.enc',
          expected: const StorageRevision.missing(),
          source: await source('late'),
        )).outcome,
        OperationOutcome.rejectedInput,
      );
    },
    skip: !Platform.isWindows,
  );

  const commitPoints = [
    CommitBoundary.stageCreated,
    CommitBoundary.stageWritten,
    CommitBoundary.stageFlushed,
    CommitBoundary.stageVerified,
    CommitBoundary.intentWritten,
    CommitBoundary.intentFlushed,
    CommitBoundary.intentVerified,
    CommitBoundary.baselineCreated,
    CommitBoundary.baselineWritten,
    CommitBoundary.baselineVerified,
    CommitBoundary.baselineProofWritten,
    CommitBoundary.previousMoved,
    CommitBoundary.previousVerified,
    CommitBoundary.published,
    CommitBoundary.publishedVerified,
    CommitBoundary.receiptWritten,
    CommitBoundary.receiptFlushed,
    CommitBoundary.receiptVerified,
  ];
  for (final stop in commitPoints) {
    test(
      'interruption at ${stop.name} retains versions and truthful acknowledgement',
      () async {
        final file = await active();
        final expected = await primitives.captureRevision(file.path);
        final store = await open(
          fault: (point, id) async {
            if (point == stop) {
              throw StateError('Synthetic interruption');
            }
          },
        );
        final result = await store.commit(
          target: 'note.enc',
          expected: expected,
          source: await source('Synthetic candidate'),
        );
        expect(result.isSuccess, isFalse);
        final beforeIntent = stop.index < CommitBoundary.intentWritten.index;
        expect(
          result.outcome,
          beforeIntent
              ? OperationOutcome.ioFailure
              : OperationOutcome.recoveryRequired,
        );
        if (!beforeIntent) {
          expect(store.recovery.blockedTargets, contains('note.enc'));
        }
        await store.close();
        final recovered = await open();
        final receiptExists = stop.index >= CommitBoundary.receiptWritten.index;
        expect(
          await file.readAsString(),
          receiptExists ? 'Synthetic candidate' : 'Synthetic original',
        );
        if (stop == CommitBoundary.baselineCreated) {
          expect(recovered.recovery.blockedTargets, contains('note.enc'));
        } else {
          expect(recovered.recovery.blockedTargets, isEmpty);
        }
        expect(recovered.recovery.libraryReadOnly, isFalse);
        final journal = await records();
        if (!beforeIntent) {
          expect(journal.length, 1);
        }
        if (stop.index > CommitBoundary.baselineCreated.index) {
          expect(
            await File(
              journal.single.resolve(root, journal.single.baselinePath),
            ).readAsString(),
            'Synthetic original',
          );
        }
      },
      skip: !Platform.isWindows,
    );
  }

  test(
    'interrupted new-note publication restores absence and retains candidate bytes',
    () async {
      final store = await open(
        fault: (point, id) async {
          if (point == CommitBoundary.published) {
            throw StateError('Synthetic interruption');
          }
        },
      );
      expect(
        (await store.commit(
          target: 'new.enc',
          expected: const StorageRevision.missing(),
          source: await source('Synthetic candidate'),
        )).outcome,
        OperationOutcome.recoveryRequired,
      );
      await store.close();
      final recovered = await open();
      expect(recovered.recovery.restoredTransactions, 1);
      expect(await File(p.join(root, 'new.enc')).exists(), isFalse);
      final retained =
          await Directory(p.join(root, '.future-notes-storage', 'recovery'))
              .list(recursive: true)
              .where((e) => e is File && e.path.endsWith('.interrupted'))
              .toList();
      expect(retained.length, 1);
      expect(
        await File(retained.single.path).readAsString(),
        'Synthetic candidate',
      );
    },
    skip: !Platform.isWindows,
  );

  for (final stop in [
    CommitBoundary.recoveryCandidateRetained,
    CommitBoundary.recoveryRestored,
    CommitBoundary.recoveryReceiptWritten,
  ]) {
    test(
      'recovery resumes after ${stop.name} without overwriting retained objects',
      () async {
        final file = await active();
        final expected = await primitives.captureRevision(file.path);
        final store = await open(
          fault: (point, id) async {
            if (point == CommitBoundary.published) {
              throw StateError('Synthetic interruption');
            }
          },
        );
        await store.commit(
          target: 'note.enc',
          expected: expected,
          source: await source('Synthetic candidate'),
        );
        await store.close();
        final interruptedRecovery = await open(
          fault: (point, id) async {
            if (point == stop) {
              throw StateError('Synthetic recovery interruption');
            }
          },
        );
        expect(
          interruptedRecovery.recovery.blockedTargets,
          contains('note.enc'),
        );
        await interruptedRecovery.close();
        final recovered = await open();
        expect(recovered.recovery.blockedTargets, isEmpty);
        expect(await file.readAsString(), 'Synthetic original');
        expect(
          (await primitives.captureRevision(file.path)).matches(expected),
          isTrue,
        );
        final journal = (await records()).single;
        expect(
          await File(
            journal.resolve(root, journal.previousPath),
          ).readAsString(),
          'Synthetic original',
        );
      },
      skip: !Platform.isWindows,
    );
  }

  test(
    'a destination appearing after the prior move is preserved and blocked',
    () async {
      final file = await active();
      final expected = await primitives.captureRevision(file.path);
      final store = await open(
        fault: (point, id) async {
          if (point == CommitBoundary.previousMoved) {
            await file.writeAsString('Synthetic external object', flush: true);
          }
        },
      );
      expect(
        (await store.commit(
          target: 'note.enc',
          expected: expected,
          source: await source('Synthetic candidate'),
        )).outcome,
        OperationOutcome.recoveryRequired,
      );
      await store.close();
      final recovered = await open();
      expect(recovered.recovery.blockedTargets, contains('note.enc'));
      expect(await file.readAsString(), 'Synthetic external object');
      final record = (await records()).single;
      expect(
        await File(record.resolve(root, record.previousPath)).readAsString(),
        'Synthetic original',
      );
      expect(
        await File(record.resolve(root, record.stagePath)).readAsString(),
        'Synthetic candidate',
      );
    },
    skip: !Platform.isWindows,
  );

  test(
    'unexpected external changes after interrupted publication are never restored over',
    () async {
      final file = await active();
      final expected = await primitives.captureRevision(file.path);
      final store = await open(
        fault: (point, id) async {
          if (point == CommitBoundary.published) {
            throw StateError('Synthetic interruption');
          }
        },
      );
      await store.commit(
        target: 'note.enc',
        expected: expected,
        source: await source('Synthetic candidate'),
      );
      await store.close();
      await file.writeAsString('Synthetic external revision', flush: true);
      final recovered = await open();
      expect(recovered.recovery.blockedTargets, contains('note.enc'));
      expect(await file.readAsString(), 'Synthetic external revision');
      expect(
        (await recovered.commit(
          target: 'note.enc',
          expected: await primitives.captureRevision(file.path),
          source: await source('later', name: 'later'),
        )).outcome,
        OperationOutcome.recoveryRequired,
      );
      expect(
        (await recovered.commit(
          target: 'unaffected.enc',
          expected: const StorageRevision.missing(),
          source: await source(
            'Synthetic independent note',
            name: 'independent',
          ),
        )).isSuccess,
        isTrue,
      );
    },
    skip: !Platform.isWindows,
  );

  test(
    'historical completed receipts never resurrect a missing active object',
    () async {
      final file = await active();
      final expected = await primitives.captureRevision(file.path);
      final store = await open();
      expect(
        (await store.commit(
          target: 'note.enc',
          expected: expected,
          source: await source('Synthetic candidate'),
        )).isSuccess,
        isTrue,
      );
      await store.close();
      await file.delete();
      final reopened = await open();
      expect(reopened.recovery.blockedTargets, isEmpty);
      expect(await file.exists(), isFalse);
    },
    skip: !Platform.isWindows,
  );

  for (final damage in ['baseline', 'receipt']) {
    test(
      'damaged $damage blocks its known target and retains active bytes',
      () async {
        final file = await active();
        final expected = await primitives.captureRevision(file.path);
        final store = await open();
        expect(
          (await store.commit(
            target: 'note.enc',
            expected: expected,
            source: await source('Synthetic candidate'),
          )).isSuccess,
          isTrue,
        );
        await store.close();
        final record = (await records()).single;
        final damagedPath = damage == 'baseline'
            ? record.baselinePath
            : record.receiptPath;
        await File(
          record.resolve(root, damagedPath),
        ).writeAsString('{', flush: true);
        final reopened = await open();
        expect(reopened.recovery.blockedTargets, contains('note.enc'));
        expect(await file.readAsString(), 'Synthetic candidate');
      },
      skip: !Platform.isWindows,
    );
  }

  for (final corrupt in ['partial', 'oversized', 'orphan']) {
    test(
      '$corrupt transaction metadata makes the library read-only without guessing',
      () async {
        final file = await active();
        final transactions = Directory(
          p.join(root, '.future-notes-storage', 'transactions'),
        );
        await transactions.create(recursive: true);
        final metadata = File(
          p.join(
            transactions.path,
            '${'a' * 32}.${corrupt == 'orphan' ? 'receipt' : 'json'}',
          ),
        );
        await metadata.writeAsString(
          corrupt == 'oversized'
              ? 'x' * (CommitRecord.maxRecordBytes + 1)
              : '{',
          flush: true,
        );
        final store = await open();
        expect(store.recovery.libraryReadOnly, isTrue);
        expect(await file.readAsString(), 'Synthetic original');
        expect(await metadata.exists(), isTrue);
        expect(
          (await store.commit(
            target: 'new.enc',
            expected: const StorageRevision.missing(),
            source: await source('Synthetic candidate'),
          )).outcome,
          OperationOutcome.recoveryRequired,
        );
      },
      skip: !Platform.isWindows,
    );
  }

  test(
    'multiple unfinished generations of one target are retained without ordered guesses',
    () async {
      final file = await active();
      final expected = await primitives.captureRevision(file.path);
      final store = await open(
        fault: (point, id) async {
          if (point == CommitBoundary.intentVerified) {
            throw StateError('Synthetic interruption');
          }
        },
      );
      await store.commit(
        target: 'note.enc',
        expected: expected,
        source: await source('Synthetic candidate'),
      );
      await store.close();
      final record = (await records()).single;
      final duplicate = CommitRecord(
        transactionId: 'b' * 32,
        target: record.target,
        expected: record.expected,
        staged: record.staged,
      );
      await File(
        duplicate.resolve(root, duplicate.recordPath),
      ).writeAsString(duplicate.encode(), flush: true);
      final reopened = await open();
      expect(reopened.recovery.blockedTargets, contains('note.enc'));
      expect(reopened.recovery.restoredTransactions, 0);
      expect(await file.readAsString(), 'Synthetic original');
      expect((await records()).length, 2);
    },
    skip: !Platform.isWindows,
  );

  test(
    'transaction identity collision never replaces retained metadata or active objects',
    () async {
      final file = await active();
      final expected = await primitives.captureRevision(file.path);
      final store = await open(identities: () => 'a' * 32);
      final first = await store.commit(
        target: 'note.enc',
        expected: expected,
        source: await source('Synthetic first'),
      );
      expect(first.isSuccess, isTrue);
      final record = (await records()).single;
      final encoded = record.encode();
      expect(
        (await store.commit(
          target: 'other.enc',
          expected: const StorageRevision.missing(),
          source: await source('Synthetic second', name: 'second'),
        )).isSuccess,
        isFalse,
      );
      expect(
        await File(record.resolve(root, record.recordPath)).readAsString(),
        encoded,
      );
      expect(await file.readAsString(), 'Synthetic first');
      expect(await File(p.join(root, 'other.enc')).exists(), isFalse);
    },
    skip: !Platform.isWindows,
  );

  test(
    'file-backed input spans multiple windows and round trips by bounded hashes',
    () async {
      final input = File(p.join(run.path, 'large.synthetic'));
      final handle = await input.open(mode: FileMode.writeOnly);
      try {
        final window = List<int>.generate(
          NativeStoragePrimitives.ioWindow,
          (i) => i % 251,
        );
        for (var i = 0; i < 3; i++) {
          await handle.writeFrom(window);
        }
        await handle.writeFrom([0, 127, 255]);
        await handle.flush();
      } finally {
        await handle.close();
      }
      final inputRevision = await primitives.captureRevision(input.path);
      final store = await open();
      final result = await store.commit(
        target: 'large.enc',
        expected: const StorageRevision.missing(),
        source: CommitFileSource(input.path, inputRevision.length!),
      );
      expect(result.isSuccess, isTrue);
      expect(result.value!.sha256Hex, inputRevision.sha256Hex);
      expect(result.value!.length, inputRevision.length);
    },
    skip: !Platform.isWindows,
  );
}

class _FailMove implements StorageFileActions {
  _FailMove(this.delegate, this.failCall, this.afterMove);
  final StorageFileActions delegate;
  final int failCall;
  final bool afterMove;
  int calls = 0;
  @override
  Future<OperationResult<void>> moveWithoutReplace(
    String source,
    String destination,
  ) async {
    if (++calls != failCall) {
      return delegate.moveWithoutReplace(source, destination);
    }
    if (afterMove) {
      final moved = await delegate.moveWithoutReplace(source, destination);
      if (!moved.isSuccess) {
        return moved;
      }
    }
    return OperationResult.failure(
      afterMove
          ? OperationOutcome.recoveryRequired
          : OperationOutcome.ioFailure,
      'Synthetic native failure.',
    );
  }
}
