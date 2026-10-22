import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_application_1/core/operations/operation_result.dart';
import 'package:flutter_application_1/core/storage/native_storage_primitives.dart';
import 'package:flutter_application_1/core/storage/recoverable_store.dart';
import 'package:flutter_application_1/core/storage/storage_environment.dart';
import 'package:flutter_application_1/core/storage/storage_owner_worker.dart';

import '../support/validation_directory.dart';

void main() {
  late Directory run;
  late String root;
  late StorageEnvironment environment;
  late List<StorageOwnerWorker> workers;
  setUp(() async {
    run = await createValidationRun();
    root = p.join(run.path, 'library');
    environment = StorageEnvironment.validation(
      validationRoot: run.path,
      dataRoot: root,
      settingsFile: p.join(run.path, 'configuration', 'settings.json'),
    );
    workers = [];
  });
  tearDown(() async {
    for (final worker in workers) {
      await worker.close();
    }
    await deleteValidationRun(run);
  });

  Future<StorageOwnerWorker> start() async {
    final result = await StorageOwnerWorker.start(environment: environment);
    expect(result.isSuccess, isTrue, reason: result.message);
    workers.add(result.value!);
    return result.value!;
  }

  Future<StorageOwnerRoot> bind(
    StorageOwnerWorker worker, [
    String? location,
  ]) async {
    final opened = await worker.openRoot(location ?? root);
    expect(opened.isSuccess, isTrue, reason: opened.message);
    return opened.value!;
  }

  Future<CommitFileSource> source(
    String content, {
    String name = 'input',
  }) async {
    final file = File(p.join(run.path, '$name.synthetic'));
    await file.writeAsString(content, flush: true);
    return CommitFileSource(file.path, await file.length());
  }

  test('production worker is rejected before launcher invocation', () async {
    var launches = 0;
    final result = await StorageOwnerWorker.start(
      environment: const StorageEnvironment.production(),
      launcher: (start, exits, errors) async {
        launches++;
        throw StateError('Launcher must not run');
      },
    );
    expect(result.outcome, OperationOutcome.rejectedInput);
    expect(launches, 0);
    expect(await Directory(root).exists(), isFalse);
  });

  test(
    'readiness waits for a real worker and creates no storage before opening a root',
    () async {
      final worker = await start();
      expect(worker.isReady, isTrue);
      expect(worker.ownerIsolateIdentity, isNotNull);
      expect(worker.ownerIsolateIdentity, isNot(Isolate.current.hashCode));
      expect(await Directory(root).exists(), isFalse);
      final owner = await bind(worker);
      expect(worker.recoveryFor(owner)!.libraryReadOnly, isFalse);
      expect(
        await File(p.join(root, '.future-notes-writer.lock')).exists(),
        isTrue,
      );
    },
    skip: !Platform.isWindows,
  );

  test(
    'launcher failure returns a sanitized startup result',
    () async {
      final result = await StorageOwnerWorker.start(
        environment: environment,
        launcher: (start, exits, errors) async {
          throw StateError('Synthetic private launch details');
        },
      );
      expect(result.outcome, OperationOutcome.ioFailure);
      expect(result.message, isNot(contains('Synthetic private')));
      expect(await Directory(root).exists(), isFalse);
    },
    skip: !Platform.isWindows,
  );

  test(
    'missing handshake times out and stops only the uninitialized owned isolate',
    () async {
      final result = await StorageOwnerWorker.start(
        environment: environment,
        startupTimeout: const Duration(milliseconds: 200),
        launcher: (start, exits, errors) => Isolate.spawn(
          _silentWorker,
          start,
          onExit: exits,
          onError: errors,
          errorsAreFatal: true,
        ),
      );
      expect(result.outcome, OperationOutcome.ioFailure);
      expect(await Directory(root).exists(), isFalse);
    },
    skip: !Platform.isWindows,
  );

  test(
    'launch-phase timeout includes a late-created isolate in startup cleanup',
    () async {
      final created = Completer<Isolate>();
      final launch = Completer<Isolate>();
      final result = await StorageOwnerWorker.start(
        environment: environment,
        startupTimeout: const Duration(milliseconds: 100),
        launcher: (start, exits, errors) {
          Isolate.spawn(
            _silentWorker,
            start,
            onExit: exits,
            onError: errors,
            errorsAreFatal: true,
          ).then(created.complete);
          return launch.future;
        },
      );
      expect(result.outcome, OperationOutcome.ioFailure);
      launch.complete(await created.future);
      await Future<void>.delayed(Duration.zero);
      expect(await Directory(root).exists(), isFalse);
    },
    skip: !Platform.isWindows,
  );

  test(
    'exit and native worker error before readiness produce typed failures',
    () async {
      for (final entry in [_exitWorker, _errorWorker]) {
        final result = await StorageOwnerWorker.start(
          environment: environment,
          launcher: (start, exits, errors) => Isolate.spawn(
            entry,
            start,
            onExit: exits,
            onError: errors,
            errorsAreFatal: true,
          ),
        );
        expect(result.outcome, OperationOutcome.ioFailure);
        expect(result.message, isNot(contains('Synthetic private')));
      }
      expect(await Directory(root).exists(), isFalse);
    },
    skip: !Platform.isWindows,
  );

  test(
    'worker commits file-backed generations and returns verified revisions',
    () async {
      final worker = await start();
      final owner = await bind(worker);
      final missing = await worker.revision(owner, 'note.enc');
      expect(missing.isSuccess, isTrue);
      expect(missing.value!.exists, isFalse);
      final first = await worker.commit(
        owner,
        target: 'note.enc',
        expected: missing.value!,
        source: await source('Synthetic first'),
      );
      expect(first.isSuccess, isTrue);
      final second = await worker.commit(
        owner,
        target: 'note.enc',
        expected: first.value!,
        source: await source('Synthetic second', name: 'second'),
      );
      expect(second.isSuccess, isTrue);
      expect(
        (await worker.revision(
          owner,
          'note.enc',
        )).value!.matches(second.value!),
        isTrue,
      );
      expect(
        await File(p.join(root, 'note.enc')).readAsString(),
        'Synthetic second',
      );
      expect(worker.recoveryFor(owner)!.blockedTargets, isEmpty);
    },
    skip: !Platform.isWindows,
  );

  test(
    'request backpressure rejects overload and drains accepted descriptors',
    () async {
      final worker = await start();
      final owner = await bind(worker);
      final accepted = List.generate(
        128,
        (_) => worker.revision(owner, 'missing.enc'),
      );
      expect(
        (await worker.revision(owner, 'overflow.enc')).outcome,
        OperationOutcome.conflict,
      );
      for (final result in await Future.wait(accepted)) {
        expect(result.isSuccess, isTrue);
        expect(result.value!.exists, isFalse);
      }
      expect(
        (await worker.revision(owner, 'after-drain.enc')).isSuccess,
        isTrue,
      );
    },
    skip: !Platform.isWindows,
  );

  test(
    'unexpected idle-owner exit invalidates readiness with a typed shutdown outcome',
    () async {
      late Isolate owned;
      final exitWatch = ReceivePort();
      final exited = Completer<void>();
      addTearDown(exitWatch.close);
      final started = await StorageOwnerWorker.start(
        environment: environment,
        launcher: (start, exits, errors) async {
          exitWatch.listen((message) {
            exits.send(message);
            if (!exited.isCompleted) {
              exited.complete();
            }
            exitWatch.close();
          });
          owned = await Isolate.spawn(
            StorageOwnerWorker.workerEntry,
            start,
            onExit: exitWatch.sendPort,
            onError: errors,
            errorsAreFatal: true,
          );
          return owned;
        },
      );
      expect(started.isSuccess, isTrue);
      final worker = started.value!;
      workers.add(worker);
      expect(worker.isReady, isTrue);
      // This test owner has no roots, leases or accepted file operations.
      owned.kill(priority: Isolate.immediate);
      await exited.future;
      expect((await worker.close()).outcome, OperationOutcome.recoveryRequired);
      expect(worker.isReady, isFalse);
      expect(await Directory(root).exists(), isFalse);
    },
    skip: !Platform.isWindows,
  );

  test(
    'root generations reject foreign, released and forged capabilities',
    () async {
      final first = await start();
      final owner = await bind(first);
      final second = await start();
      expect(
        (await second.revision(owner, 'note.enc')).outcome,
        OperationOutcome.rejectedInput,
      );
      final forged = StorageOwnerRoot(
        owner.identity,
        p.join(run.path, 'other'),
        owner.generation,
      );
      expect(
        (await first.revision(forged, 'note.enc')).outcome,
        OperationOutcome.rejectedInput,
      );
      expect((await first.releaseRoot(owner)).isSuccess, isTrue);
      final reopened = await bind(first);
      expect(reopened.identity, isNot(owner.identity));
      expect(
        (await first.revision(owner, 'note.enc')).outcome,
        OperationOutcome.rejectedInput,
      );
      expect(first.recoveryFor(owner), isNull);
    },
    skip: !Platform.isWindows,
  );

  test(
    'independent native workers cannot acquire the same library lease',
    () async {
      final first = await start();
      final owner = await bind(first);
      final second = await start();
      expect((await second.openRoot(root)).outcome, OperationOutcome.conflict);
      expect((await first.releaseRoot(owner)).isSuccess, isTrue);
      final reacquired = await bind(second);
      expect(second.recoveryFor(reacquired)!.libraryReadOnly, isFalse);
    },
    skip: !Platform.isWindows,
  );

  test(
    'candidate root failure retains the old library and independent settings owner',
    () async {
      final worker = await start();
      final library = await bind(worker);
      final settings = await bind(worker, p.dirname(environment.settingsFile!));
      expect(
        (await worker.openRoot(p.dirname(run.path))).outcome,
        OperationOutcome.rejectedInput,
      );
      expect(
        (await worker.commit(
          settings,
          target: 'settings.json',
          expected: const StorageRevision.missing(),
          source: await source('{"synthetic":true}'),
        )).isSuccess,
        isTrue,
      );
      expect(
        (await worker.commit(
          library,
          target: 'note.enc',
          expected: const StorageRevision.missing(),
          source: await source('Synthetic note', name: 'note'),
        )).isSuccess,
        isTrue,
      );
      expect(await File(environment.settingsFile!).exists(), isTrue);
      expect(await File(p.join(root, 'note.enc')).exists(), isTrue);
    },
    skip: !Platform.isWindows,
  );

  test(
    'queued revisions run after commit and stale competing writes cannot mix roots',
    () async {
      final worker = await start();
      final owner = await bind(worker);
      final input = await source('Synthetic first');
      final competing = await source('Synthetic stale', name: 'second');
      final first = worker.commit(
        owner,
        target: 'note.enc',
        expected: const StorageRevision.missing(),
        source: input,
      );
      final revision = worker.revision(owner, 'note.enc');
      final second = worker.commit(
        owner,
        target: 'note.enc',
        expected: const StorageRevision.missing(),
        source: competing,
      );
      final committed = await first;
      expect(committed.isSuccess, isTrue);
      expect((await revision).value!.matches(committed.value!), isTrue);
      expect((await second).outcome, OperationOutcome.conflict);
      expect(
        await File(p.join(root, 'note.enc')).readAsString(),
        'Synthetic first',
      );
    },
    skip: !Platform.isWindows,
  );

  test(
    'recovery finishes inside the owner before a root becomes writable',
    () async {
      await Directory(root).create();
      final file = File(p.join(root, 'note.enc'));
      await file.writeAsString('Synthetic original', flush: true);
      final expected = await NativeStoragePrimitives(
        environment,
      ).captureRevision(file.path);
      final opened = await RecoverableStore.open(
        root: root,
        environment: environment,
        faultHook: (point, id) async {
          if (point == CommitBoundary.published) {
            throw StateError('Synthetic interruption');
          }
        },
      );
      final store = opened.value!;
      try {
        expect(
          (await store.commit(
            target: 'note.enc',
            expected: expected,
            source: await source('Synthetic candidate'),
          )).outcome,
          OperationOutcome.recoveryRequired,
        );
      } finally {
        await store.close();
      }
      final worker = await start();
      final owner = await bind(worker);
      expect(worker.recoveryFor(owner)!.restoredTransactions, 1);
      expect(await file.readAsString(), 'Synthetic original');
      expect(
        (await worker.revision(owner, 'note.enc')).value!.matches(expected),
        isTrue,
      );
    },
    skip: !Platform.isWindows,
  );

  test(
    'ambiguous recovery state crosses the worker boundary without granting writes',
    () async {
      final transactions = Directory(
        p.join(root, '.future-notes-storage', 'transactions'),
      );
      await transactions.create(recursive: true);
      await File(
        p.join(transactions.path, '${'a' * 32}.json'),
      ).writeAsString('{', flush: true);
      final worker = await start();
      final owner = await bind(worker);
      expect(worker.recoveryFor(owner)!.libraryReadOnly, isTrue);
      expect(
        (await worker.commit(
          owner,
          target: 'note.enc',
          expected: const StorageRevision.missing(),
          source: await source('Synthetic candidate'),
        )).outcome,
        OperationOutcome.recoveryRequired,
      );
      expect(await File(p.join(root, 'note.enc')).exists(), isFalse);
      expect(worker.recoveryFor(owner)!.libraryReadOnly, isTrue);
    },
    skip: !Platform.isWindows,
  );

  test(
    'shutdown waits for accepted work and releases all leases before acknowledgement',
    () async {
      final worker = await start();
      final owner = await bind(worker);
      final writing = worker.commit(
        owner,
        target: 'note.enc',
        expected: const StorageRevision.missing(),
        source: await source('Synthetic candidate'),
      );
      final closing = worker.close();
      expect(
        (await worker.revision(owner, 'note.enc')).outcome,
        OperationOutcome.rejectedInput,
      );
      expect((await writing).isSuccess, isTrue);
      expect((await closing).isSuccess, isTrue);
      expect((await worker.close()).isSuccess, isTrue);
      expect(worker.isReady, isFalse);
      expect(worker.recoveryFor(owner), isNull);
      final next = await start();
      expect((await next.openRoot(root)).isSuccess, isTrue);
    },
    skip: !Platform.isWindows,
  );
}

void _silentWorker(StorageWorkerStart start) {
  ReceivePort().listen((_) {});
}

void _exitWorker(StorageWorkerStart start) {
  Isolate.exit();
}

void _errorWorker(StorageWorkerStart start) {
  throw StateError('Synthetic private worker error');
}
