import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:path/path.dart' as p;

import '../operations/operation_result.dart';
import 'commit_record.dart';
import 'native_storage_primitives.dart';
import 'permanent_deletion.dart';
import 'recoverable_store.dart';
import 'storage_environment.dart';
export 'permanent_deletion.dart' show DeletionReport;

class StorageWorkerStart {
  const StorageWorkerStart(this.replies, this.environment, this.generation);
  final SendPort replies;
  final StorageEnvironment environment;
  final String generation;
}

typedef StorageWorkerLauncher =
    Future<Isolate> Function(
      StorageWorkerStart start,
      SendPort exitPort,
      SendPort errorPort,
    );

/// An immutable capability for one captured root in one live worker generation.
class StorageOwnerRoot {
  const StorageOwnerRoot(this.identity, this.root, this.generation);
  final int identity;
  final String root;
  final String generation;
}

abstract interface class LibraryStorageOwner {
  Future<OperationResult<void>> admitSelectedLibrary(String root);
}

/// Injectable storage owner interface; no controllers or attachment bytes cross
/// its boundary. Application adoption is a separate validation gate.
abstract class StorageOwner {
  Future<OperationResult<StorageOwnerRoot>> openRoot(String root);
  Future<OperationResult<StorageRevision>> revision(
    StorageOwnerRoot owner,
    String target,
  );
  Future<OperationResult<StorageRevision>> commit(
    StorageOwnerRoot owner, {
    required String target,
    required StorageRevision expected,
    required CommitFileSource source,
  });
  RecoveryReport? recoveryFor(StorageOwnerRoot owner);
  Future<OperationResult<DeletionReport>> delete(
    StorageOwnerRoot owner, {
    required String target,
    required StorageRevision expected,
    String? attachmentDirectory,
  }) => Future.value(
    const OperationResult.failure(
      OperationOutcome.rejectedInput,
      'Deletion is unsupported by this owner.',
    ),
  );
  Future<OperationResult<void>> releaseRoot(StorageOwnerRoot owner);
  Future<OperationResult<void>> close();
}

class StorageOwnerWorker implements StorageOwner, LibraryStorageOwner {
  StorageOwnerWorker._(this._environment, this._generation) {
    _replies.listen(_receive);
  }
  final StorageEnvironment _environment;
  final String _generation;
  final _replies = ReceivePort();
  final _ready = Completer<OperationResult<StorageOwnerWorker>>();
  final _pending = <int, Completer<OperationResult<Object?>>>{};
  final _roots = <int, StorageOwnerRoot>{};
  final _reports = <int, RecoveryReport>{};
  SendPort? _commands;
  bool _ended = false;
  bool _closing = false;
  int _request = 0;
  int? _ownerIsolateIdentity;
  int? get ownerIsolateIdentity => _ownerIsolateIdentity;
  Future<OperationResult<void>>? _closeFuture;

  static Future<OperationResult<StorageOwnerWorker>> start({
    required StorageEnvironment environment,
    StorageWorkerLauncher? launcher,
    Duration startupTimeout = const Duration(seconds: 10),
  }) async {
    if (!environment.hasOwnedStorage ||
        !Platform.isWindows ||
        startupTimeout <= Duration.zero) {
      return const OperationResult.failure(
        OperationOutcome.rejectedInput,
        'Storage worker requires explicitly bound Windows storage.',
      );
    }
    final random = Random.secure();
    final generation = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final worker = StorageOwnerWorker._(environment, generation);
    Isolate? isolate;
    try {
      final launching =
          (launcher ?? _launch)(
            StorageWorkerStart(
              worker._replies.sendPort,
              worker._environment,
              generation,
            ),
            worker._replies.sendPort,
            worker._replies.sendPort,
          ).then((created) {
            isolate = created;
            if (worker._ended) {
              created.kill(priority: Isolate.immediate);
            }
            return created;
          });
      final ready = await (() async {
        await launching;
        return await worker._ready.future;
      })().timeout(startupTimeout);
      if (!ready.isSuccess || !worker.isReady) {
        isolate?.kill(priority: Isolate.immediate);
        worker._fail(OperationOutcome.ioFailure);
        return const OperationResult.failure(
          OperationOutcome.ioFailure,
          'Storage worker did not remain ready.',
        );
      }
      return ready;
    } catch (_) {
      // No root/job can be submitted before the handshake. Startup cleanup may
      // therefore stop this owned isolate without interrupting a transaction.
      isolate?.kill(priority: Isolate.immediate);
      worker._fail(OperationOutcome.ioFailure);
      return const OperationResult.failure(
        OperationOutcome.ioFailure,
        'Storage worker startup failed or timed out.',
      );
    }
  }

  static Future<Isolate> _launch(
    StorageWorkerStart start,
    SendPort exits,
    SendPort errors,
  ) => Isolate.spawn(
    workerEntry,
    start,
    onExit: exits,
    onError: errors,
    errorsAreFatal: true,
    debugName: 'future-notes-storage-owner',
  );

  bool get isReady => !_ended && _commands != null && !_closing;

  void _receive(dynamic message) {
    if (_ended) {
      return;
    }
    if (message is _Hello && message.generation == _generation) {
      if (_commands != null) {
        _fail(OperationOutcome.recoveryRequired);
        return;
      }
      _commands = message.commands;
      _ownerIsolateIdentity = message.isolateIdentity;
      _ready.complete(OperationResult.success(this));
      return;
    }
    if (message is _Reply && message.generation == _generation) {
      final waiter = _pending.remove(message.identity);
      if (waiter == null) {
        return;
      }
      if (message.rootIdentity != null && message.recovery != null) {
        _reports[message.rootIdentity!] = message.recovery!;
      }
      waiter.complete(message.result);
      return;
    }
    // Exit and error events are intentionally sanitized. Their raw messages
    // may contain paths; never forward or log them as user-visible diagnostics.
    _fail(
      _commands == null
          ? OperationOutcome.ioFailure
          : OperationOutcome.recoveryRequired,
    );
  }

  void _fail(OperationOutcome outcome) {
    if (_ended) {
      return;
    }
    // If the actor is still alive, request orderly cleanup after accepted work.
    // An exited actor's port discards this message. Never kill an active writer.
    _commands?.send(
      _Request(
        ++_request,
        _generation,
        _Kind.shutdown,
        null,
        null,
        null,
        null,
        null,
        null,
      ),
    );
    _ended = true;
    final result = OperationResult<Object?>.failure(
      outcome,
      'Storage worker is unavailable; acknowledgement is unknown.',
    );
    if (!_ready.isCompleted) {
      _ready.complete(
        OperationResult.failure(
          outcome,
          'Storage worker did not become ready.',
        ),
      );
    }
    for (final waiter in _pending.values) {
      waiter.complete(result);
    }
    _pending.clear();
    _roots.clear();
    _reports.clear();
    _replies.close();
  }

  Future<OperationResult<Object?>> _ask(
    _Kind kind, {
    StorageOwnerRoot? owner,
    String? root,
    String? target,
    StorageRevision? expected,
    CommitFileSource? source,
    String? attachmentDirectory,
  }) {
    if (_ended ||
        _commands == null ||
        (_closing && kind != _Kind.shutdown) ||
        (owner != null && !_owns(owner))) {
      return Future.value(
        const OperationResult.failure(
          OperationOutcome.rejectedInput,
          'Storage request has no live owner.',
        ),
      );
    }
    if (_pending.length >= 128) {
      return Future.value(
        const OperationResult.failure(
          OperationOutcome.conflict,
          'Storage request queue is full.',
        ),
      );
    }
    final id = ++_request;
    final waiter = Completer<OperationResult<Object?>>();
    _pending[id] = waiter;
    _commands!.send(
      _Request(
        id,
        _generation,
        kind,
        owner?.identity,
        root,
        target,
        expected,
        source,
        attachmentDirectory,
      ),
    );
    return waiter.future;
  }

  bool _owns(StorageOwnerRoot owner) =>
      owner.generation == _generation &&
      _roots[owner.identity]?.root == owner.root;

  @override
  Future<OperationResult<StorageOwnerRoot>> openRoot(String root) async {
    final result = await _ask(_Kind.open, root: root);
    if (!result.isSuccess) {
      return OperationResult.failure(result.outcome, result.message);
    }
    final value = result.value;
    if (value is! StorageOwnerRoot || value.generation != _generation) {
      _fail(OperationOutcome.recoveryRequired);
      return const OperationResult.failure(
        OperationOutcome.recoveryRequired,
        'Invalid storage ownership response.',
      );
    }
    _roots[value.identity] = value;
    return OperationResult.success(value);
  }

  @override
  Future<OperationResult<void>> admitSelectedLibrary(String root) async {
    final result = await _ask(_Kind.admit, root: root);
    return result.isSuccess
        ? const OperationResult.success()
        : OperationResult.failure(result.outcome, result.message);
  }

  @override
  RecoveryReport? recoveryFor(StorageOwnerRoot owner) =>
      _owns(owner) ? _reports[owner.identity] : null;

  @override
  Future<OperationResult<StorageRevision>> revision(
    StorageOwnerRoot owner,
    String target,
  ) async =>
      _revisionResult(await _ask(_Kind.revision, owner: owner, target: target));

  @override
  Future<OperationResult<StorageRevision>> commit(
    StorageOwnerRoot owner, {
    required String target,
    required StorageRevision expected,
    required CommitFileSource source,
  }) async => _revisionResult(
    await _ask(
      _Kind.commit,
      owner: owner,
      target: target,
      expected: expected,
      source: source,
    ),
  );

  OperationResult<StorageRevision> _revisionResult(
    OperationResult<Object?> result,
  ) {
    if (!result.isSuccess) {
      return OperationResult.failure(result.outcome, result.message);
    }
    if (result.value is StorageRevision) {
      return OperationResult.success(result.value as StorageRevision);
    }
    _fail(OperationOutcome.recoveryRequired);
    return const OperationResult.failure(
      OperationOutcome.recoveryRequired,
      'Invalid storage revision response.',
    );
  }

  @override
  Future<OperationResult<DeletionReport>> delete(
    StorageOwnerRoot owner, {
    required String target,
    required StorageRevision expected,
    String? attachmentDirectory,
  }) async {
    final result = await _ask(
      _Kind.delete,
      owner: owner,
      target: target,
      expected: expected,
      attachmentDirectory: attachmentDirectory,
    );
    if (result.value is DeletionReport) {
      return result.isSuccess
          ? OperationResult.success(result.value as DeletionReport)
          : OperationResult.partial(
              result.outcome,
              result.message,
              result.value as DeletionReport,
            );
    }
    return OperationResult.failure(result.outcome, result.message);
  }

  @override
  Future<OperationResult<void>> releaseRoot(StorageOwnerRoot owner) async {
    final result = await _ask(_Kind.release, owner: owner);
    if (!result.isSuccess) {
      return OperationResult.failure(result.outcome, result.message);
    }
    _roots.remove(owner.identity);
    _reports.remove(owner.identity);
    return const OperationResult.success();
  }

  @override
  Future<OperationResult<void>> close() => _closeFuture ??= _close();

  Future<OperationResult<void>> _close() async {
    if (_ended) {
      return const OperationResult.failure(
        OperationOutcome.recoveryRequired,
        'Storage worker has already exited.',
      );
    }
    _closing = true;
    final result = await _ask(_Kind.shutdown);
    if (!result.isSuccess) {
      _closing = false;
      _closeFuture = null;
      return OperationResult.failure(result.outcome, result.message);
    }
    _ended = true;
    _roots.clear();
    _reports.clear();
    _replies.close();
    return const OperationResult.success();
  }

  /// Public only to support an injected native launcher. No Flutter bindings.
  static void workerEntry(StorageWorkerStart start) async {
    final commands = ReceivePort();
    final stores = <int, RecoverableStore>{};
    var nextRoot = 0;
    try {
      if (!start.environment.hasOwnedStorage || !Platform.isWindows) {
        throw StateError('Unsupported storage owner.');
      }
      await start.environment.verifyConfiguredPaths();
      start.replies.send(
        _Hello(commands.sendPort, start.generation, Isolate.current.hashCode),
      );
      await for (final message in commands) {
        if (message is! _Request || message.generation != start.generation) {
          continue;
        }
        OperationResult<Object?> result;
        int? rootIdentity = message.rootIdentity;
        RecoveryReport? report;
        var shutdown = false;
        try {
          if (message.kind == _Kind.admit) {
            await start.environment.admitSelectedLibrary(message.root!);
            result = const OperationResult.success();
          } else if (message.kind == _Kind.open) {
            if (!start.environment.permitsOwnerRoot(message.root!)) {
              throw const FormatException('Unadmitted storage root.');
            }
            // Settings and notes can share UserData. Each binding gets its own
            // capability, while aliases retain one queue, recovery and lease.
            RecoverableStore? shared;
            for (final store in stores.values) {
              if (p.equals(store.root, p.normalize(message.root!))) {
                shared = store;
                break;
              }
            }
            final OperationResult<RecoverableStore> opened = shared == null
                ? await RecoverableStore.open(
                    root: message.root!,
                    environment: start.environment,
                  )
                : OperationResult.success(shared);
            if (opened.isSuccess) {
              final id = ++nextRoot;
              stores[id] = opened.value!;
              rootIdentity = id;
              report = opened.value!.recovery;
              result = OperationResult.success(
                StorageOwnerRoot(id, opened.value!.root, start.generation),
              );
            } else {
              result = OperationResult.failure(opened.outcome, opened.message);
            }
          } else if (message.kind == _Kind.shutdown) {
            for (final store in stores.values.toSet()) {
              await store.close();
              stores.removeWhere((_, value) => identical(value, store));
            }
            result = const OperationResult.success();
            shutdown = true;
          } else {
            final store = stores[message.rootIdentity];
            if (store == null) {
              throw const FormatException('Unknown storage owner.');
            }
            if (message.kind == _Kind.release) {
              final aliases = stores.values
                  .where((value) => identical(value, store))
                  .length;
              if (aliases == 1) {
                await store.close();
              }
              stores.remove(message.rootIdentity);
              result = const OperationResult.success();
            } else if (message.kind == _Kind.commit) {
              result = await store.commit(
                target: message.target!,
                expected: message.expected!,
                source: message.source!,
              );
              report = store.recovery;
            } else if (message.kind == _Kind.delete) {
              result = await store.delete(
                target: message.target!,
                expected: message.expected!,
                attachmentDirectory: message.attachmentDirectory,
              );
              report = store.recovery;
            } else {
              final valid = CommitRecord(
                transactionId: '0' * 32,
                target: message.target!,
                expected: const StorageRevision.missing(),
                staged: StorageRevision.present(0, '0' * 64, 0),
              );
              final revision = await NativeStoragePrimitives(
                start.environment,
              ).captureRevision(valid.resolve(store.root, valid.target));
              result = OperationResult.success(revision);
              report = store.recovery;
            }
          }
        } catch (error) {
          result = OperationResult.failure(
            error is FormatException || error is ArgumentError
                ? OperationOutcome.rejectedInput
                : OperationOutcome.recoveryRequired,
            'Storage owner operation failed.',
          );
        }
        final reply = _Reply(
          message.identity,
          start.generation,
          result,
          rootIdentity,
          report,
        );
        if (shutdown) {
          commands.close();
          Isolate.exit(start.replies, reply);
        }
        start.replies.send(reply);
      }
    } catch (_) {
      start.replies.send(false);
    } finally {
      for (final store in stores.values.toSet()) {
        try {
          await store.close();
        } catch (_) {
          /* Preserve uncertain ownership. */
        }
      }
      commands.close();
    }
  }
}

enum _Kind { admit, open, revision, commit, delete, release, shutdown }

class _Hello {
  const _Hello(this.commands, this.generation, this.isolateIdentity);
  final SendPort commands;
  final String generation;
  final int isolateIdentity;
}

class _Request {
  const _Request(
    this.identity,
    this.generation,
    this.kind,
    this.rootIdentity,
    this.root,
    this.target,
    this.expected,
    this.source,
    this.attachmentDirectory,
  );
  final int identity;
  final String generation;
  final _Kind kind;
  final int? rootIdentity;
  final String? root;
  final String? target;
  final StorageRevision? expected;
  final CommitFileSource? source;
  final String? attachmentDirectory;
}

class _Reply {
  const _Reply(
    this.identity,
    this.generation,
    this.result,
    this.rootIdentity,
    this.recovery,
  );
  final int identity;
  final String generation;
  final OperationResult<Object?> result;
  final int? rootIdentity;
  final RecoveryReport? recovery;
}
