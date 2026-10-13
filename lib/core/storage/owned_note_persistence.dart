import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../operations/operation_result.dart';
import 'note_reference.dart';
import 'recoverable_store.dart';
import 'storage_environment.dart';
import 'storage_owner_worker.dart';

/// Injected validation-only library owner. Exact references carry both their
/// observed revision and worker capability; no mutable settings are consulted.
class OwnedNotePersistence {
  OwnedNotePersistence({required this.environment, required this.owner}) {
    if (!environment.isValidation || !Platform.isWindows) {
      throw ArgumentError('Owned notes require disposable Windows storage.');
    }
  }

  final StorageEnvironment environment;
  final StorageOwner owner;
  final _roots = <String, Future<StorageOwnerRoot>>{};
  final _jobs = <Future<void>>{};
  final _sources = <Directory>{};
  final _releasingRoots = <String>{};
  bool _closing = false;
  Future<void>? _closeFuture;
  bool get cleanupPending => _sources.isNotEmpty;

  Future<T> _run<T>(Future<T> Function() action) {
    if (_closing) {
      return Future.error(
        const NotePersistenceFailure(OperationOutcome.rejectedInput),
      );
    }
    final operation = (() async {
      try {
        return await action();
      } on NotePersistenceFailure {
        rethrow;
      } on ArgumentError {
        throw const NotePersistenceFailure(OperationOutcome.rejectedInput);
      } catch (_) {
        throw const NotePersistenceFailure(OperationOutcome.ioFailure);
      }
    })();
    final settled = operation.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {},
    );
    _jobs.add(settled);
    settled.then((_) => _jobs.remove(settled));
    return operation;
  }

  Future<StorageOwnerRoot> _root(String location) {
    if (_releasingRoots.contains(location)) {
      throw const NotePersistenceFailure(OperationOutcome.rejectedInput);
    }
    final existing = _roots[location];
    if (existing != null) {
      return existing;
    }
    late final Future<StorageOwnerRoot> opening;
    opening =
        (() async {
          await environment.verifyLocation(
            environment.validateLibraryPath(location),
          );
          final opened = await owner.openRoot(location);
          if (!opened.isSuccess) {
            throw NotePersistenceFailure(opened.outcome);
          }
          return opened.value!;
        })().then(
          (value) => value,
          onError: (Object error, StackTrace stackTrace) {
            if (identical(_roots[location], opening)) {
              _roots.remove(location);
            }
            Error.throwWithStackTrace(error, stackTrace);
          },
        );
    _roots[location] = opening;
    return opening;
  }

  Future<void> prepareLibrary(String root) => _run(() async {
    await _root(root);
  });

  Future<void> releaseLibrary(String location) {
    if (_closing || !_releasingRoots.add(location)) {
      return Future.error(
        const NotePersistenceFailure(OperationOutcome.rejectedInput),
      );
    }
    final accepted = _jobs.toList();
    return _run(() async {
      try {
        await Future.wait(accepted);
        final opening = _roots[location];
        if (opening == null) return;
        final root = await opening;
        final result = await owner.releaseRoot(root);
        if (!result.isSuccess) throw NotePersistenceFailure(result.outcome);
        _roots.remove(location);
      } on NotePersistenceFailure {
        rethrow;
      } catch (_) {
        throw const NotePersistenceFailure(OperationOutcome.recoveryRequired);
      } finally {
        _releasingRoots.remove(location);
      }
    });
  }

  String _target(NoteReference reference) {
    final path = reference.contentPath;
    if (!p.isAbsolute(path) || !p.isWithin(reference.binding.root, path)) {
      throw const NotePersistenceFailure(OperationOutcome.rejectedInput);
    }
    return p.posix.joinAll(
      p.split(p.relative(path, from: reference.binding.root)),
    );
  }

  void _requireWritable(StorageOwnerRoot root, String target) {
    final report = owner.recoveryFor(root);
    if (report == null ||
        report.libraryReadOnly ||
        report.blockedTargets.any((blocked) => p.equals(blocked, target))) {
      throw const NotePersistenceFailure(OperationOutcome.recoveryRequired);
    }
  }

  Future<StorageOwnerRoot> _capturedOwner(NoteReference reference) async {
    final root = await _root(reference.binding.root);
    final captured = reference.storageOwner;
    if (captured == null ||
        reference.storageRevision == null ||
        captured.identity != root.identity ||
        captured.generation != root.generation ||
        !p.equals(captured.root, root.root)) {
      throw const NotePersistenceFailure(OperationOutcome.rejectedInput);
    }
    _requireWritable(root, _target(reference));
    return root;
  }

  Future<NoteReference> capture(
    NoteReference reference, {
    bool newObject = false,
  }) => _run(() async {
    final root = await _root(reference.binding.root);
    final target = _target(reference);
    _requireWritable(root, target);
    final observed = await owner.revision(root, target);
    if (!observed.isSuccess) {
      throw NotePersistenceFailure(observed.outcome);
    }
    if (newObject == observed.value!.exists) {
      throw const NotePersistenceFailure(OperationOutcome.conflict);
    }
    return reference.withStorageRevision(observed.value!, root);
  });

  Future<String?> read(NoteReference reference) => _run(() async {
    final root = await _capturedOwner(reference);
    final target = _target(reference);
    final before = await owner.revision(root, target);
    if (!before.isSuccess) {
      throw NotePersistenceFailure(before.outcome);
    }
    if (!reference.storageRevision!.matches(before.value!)) {
      throw const NotePersistenceFailure(OperationOutcome.conflict);
    }
    if (!before.value!.exists) {
      return null;
    }
    await environment.verifyLocation(reference.contentPath);
    final content = await File(reference.contentPath).readAsString();
    final after = await owner.revision(root, target);
    if (!after.isSuccess) {
      throw NotePersistenceFailure(after.outcome);
    }
    if (!before.value!.matches(after.value!)) {
      throw const NotePersistenceFailure(OperationOutcome.conflict);
    }
    return content;
  });

  Future<NoteReference> commit(NoteReference reference, String content) =>
      _run(() async {
        final root = await _capturedOwner(reference);
        Directory? operation;
        try {
          await environment.verifyLocation(
            environment.validationRoot!,
            allowRunRoot: true,
          );
          operation = await Directory(
            environment.validationRoot!,
          ).createTemp('note-operation-');
          _sources.add(operation);
          final file = File(p.join(operation.path, 'candidate.enc'));
          await environment.verifyLocation(file.path);
          await file.create(exclusive: true);
          final bytes = utf8.encode(content);
          await file.writeAsBytes(bytes, flush: true);
          final result = await owner.commit(
            root,
            target: _target(reference),
            expected: reference.storageRevision!,
            source: CommitFileSource(file.path, bytes.length),
          );
          if (!result.isSuccess) {
            throw NotePersistenceFailure(result.outcome);
          }
          return reference.withStorageRevision(result.value!, root);
        } finally {
          if (operation != null) {
            await _cleanup(operation);
          }
        }
      });

  Future<void> _cleanup(Directory operation) async {
    try {
      final source = File(p.join(operation.path, 'candidate.enc'));
      await environment.verifyLocation(source.path);
      if (await source.exists()) {
        await source.delete();
      }
      await operation.delete();
      _sources.remove(operation);
    } catch (_) {
      // A commit receipt remains authoritative if source cleanup fails. Retain
      // local ownership, expose cleanupPending and retry cleanup on close.
    }
  }

  Future<void> close() => _closeFuture ??= _close();

  Future<void> _close() async {
    _closing = true;
    await Future.wait(_jobs.toList());
    var failed = false;
    for (final location in _roots.keys.toList()) {
      StorageOwnerRoot root;
      try {
        root = await _roots[location]!;
      } catch (_) {
        _roots.remove(location);
        continue;
      }
      try {
        final released = await owner.releaseRoot(root);
        if (released.isSuccess) {
          _roots.remove(location);
        } else {
          failed = true;
        }
      } catch (_) {
        // Retain this root for explicit retry, but finish releasing independent
        // roots and local sources. Never expose a raw transport/native error.
        failed = true;
      }
    }
    for (final source in _sources.toList()) {
      await _cleanup(source);
    }
    if (failed || cleanupPending) {
      _closeFuture = null;
      throw const NotePersistenceFailure(OperationOutcome.recoveryRequired);
    }
  }
}

class NotePersistenceFailure implements Exception {
  const NotePersistenceFailure(this.outcome);
  final OperationOutcome outcome;

  @override
  String toString() => 'Note persistence failed (${outcome.name}).';
}
