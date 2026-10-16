import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../operations/operation_result.dart';
import 'note_reference.dart';
import 'commit_record.dart';
import 'native_storage_primitives.dart';
import 'streaming_file_cipher.dart';
import 'recoverable_store.dart';
import 'storage_environment.dart';
import 'storage_owner_worker.dart';
import 'attachment_transform_worker.dart';

/// Injected library owner. Exact references carry both their
/// observed revision and worker capability; no mutable settings are consulted.
class OwnedNotePersistence {
  OwnedNotePersistence({required this.environment, required this.owner}) {
    if (!environment.hasOwnedStorage || !Platform.isWindows) {
      throw ArgumentError(
        'Owned notes require explicitly bound Windows storage.',
      );
    }
  }

  final StorageEnvironment environment;
  final StorageOwner owner;
  final _roots = <String, Future<StorageOwnerRoot>>{};
  final _jobs = <Future<void>>{};
  final _sources = <Directory>{};
  final _attachmentReader = AttachmentTransformWorker();
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
    if (environment.isRecoverable && !environment.permitsOwnerRoot(root)) {
      if (owner is! LibraryStorageOwner) {
        throw const NotePersistenceFailure(OperationOutcome.rejectedInput);
      }
      final admitted = await (owner as LibraryStorageOwner)
          .admitSelectedLibrary(root);
      if (!admitted.isSuccess) throw NotePersistenceFailure(admitted.outcome);
      await environment.admitSelectedLibrary(root);
    }
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

  Future<List<NoteReference>> pendingDeletions(StorageBinding binding) =>
      _run(() async {
        final root = await _root(binding.root);
        return (owner.recoveryFor(root)?.pendingDeletions ?? []).map((intent) {
          final parts = p.posix.split(intent.target);
          final folder = parts.length > 1 ? parts.first : null;
          final attachmentTargets = intent.objects.where(
            (object) =>
                object != intent.target &&
                p.posix.basename(p.posix.dirname(object)) == 'attachments',
          );
          return NoteReference(
            binding: binding,
            fileName: folder ?? intent.target,
            format: folder == null
                ? NoteStorageFormat.legacyFile
                : NoteStorageFormat.folder,
            contentPath: binding.child(intent.target),
            attachmentLocation: binding.child(
              attachmentTargets.isEmpty
                  ? '${folder ?? 'note_pending'}/attachments'
                  : p.posix.dirname(attachmentTargets.first),
            ),
            storageRevision: intent.files[intent.target],
            storageOwner: root,
          );
        }).toList();
      });

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

  String attachmentTarget(NoteReference reference, String id) {
    if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(id) ||
        !p.isWithin(reference.binding.root, reference.attachmentLocation)) {
      throw const NotePersistenceFailure(OperationOutcome.rejectedInput);
    }
    return p.posix.joinAll(
      p.split(
        p.relative(
          p.join(reference.attachmentLocation, '$id.med'),
          from: reference.binding.root,
        ),
      ),
    );
  }

  Future<StreamingFileSource> attachmentSource(
    NoteReference reference,
    String id, {
    FileByteProgress? onProgress,
    FileReadCancellation? cancellation,
    bool verifyContent = true,
  }) => _run(() async {
    await _capturedOwner(reference);
    final target = attachmentTarget(reference, id);
    if (!verifyContent) {
      if (cancellation?.cancelled == true)
        throw const NotePersistenceFailure(OperationOutcome.cancelled);
      final path = reference.binding.child(target);
      final metadata = await NativeStoragePrimitives(
        environment,
      ).inspectMetadata(path);
      if (metadata.length > StreamingFileCipher.maxAttachmentBytes + 32)
        throw const NotePersistenceFailure(OperationOutcome.rejectedInput);
      if (cancellation?.cancelled == true)
        throw const NotePersistenceFailure(OperationOutcome.cancelled);
      return StreamingFileSource(
        path,
        metadata.length,
        modifiedMicros: metadata.modifiedMicros,
      );
    }
    // Fresh attachment objects are immutable. Read verification owns no writer
    // commands and must not wait behind a multi-GiB generation publication.
    // _run retains the root lease until this owned reader has closed its handle.
    final revision = await _attachmentReader
        .inspect(
          FileRevisionRequest(environment, reference.binding.child(target)),
          onProgress: onProgress,
          cancellation: cancellation,
        )
        .result;
    if (!revision.isSuccess) {
      throw NotePersistenceFailure(revision.outcome);
    }
    if (!revision.value!.exists) {
      throw const NotePersistenceFailure(OperationOutcome.ioFailure);
    }
    return StreamingFileSource(
      reference.binding.child(target),
      revision.value!.length!,
      sha256Hex: revision.value!.sha256Hex,
      modifiedMicros: revision.value!.modifiedMicros,
    );
  });

  Future<bool> needsDeletionOwnershipCheck(NoteReference reference) =>
      _run(() async {
        final root = await _root(reference.binding.root);
        final target = _target(reference);
        for (final intent in owner.recoveryFor(root)?.pendingDeletions ?? []) {
          if (intent.target == target)
            return intent.objects.any((object) => object != target);
        }
        return true;
      });

  Future<OperationResult<DeletionReport>> delete(NoteReference reference) =>
      _run(() async {
        final root = await _root(reference.binding.root);
        final capability = reference.storageOwner;
        if (capability == null ||
            capability.identity != root.identity ||
            capability.generation != root.generation ||
            reference.storageRevision == null) {
          throw const NotePersistenceFailure(OperationOutcome.rejectedInput);
        }
        final directory = p.posix.joinAll(
          p.split(
            p.relative(
              reference.attachmentLocation,
              from: reference.binding.root,
            ),
          ),
        );
        return owner.delete(
          root,
          target: _target(reference),
          expected: reference.storageRevision!,
          attachmentDirectory: directory,
        );
      });

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

  Future<NoteReference> commit(
    NoteReference reference,
    String content, {
    List<PreparedAttachmentFile> attachments = const [],
    CommitByteProgress? onProgress,
  }) => _run(() async {
    final root = await _capturedOwner(reference);
    Future<OperationResult<StorageRevision>> publish(
      String target,
      StorageRevision expected,
      CommitFileSource source,
    ) {
      if (onProgress != null && owner is ProgressStorageOwner) {
        return (owner as ProgressStorageOwner).commitWithProgress(
          root,
          target: target,
          expected: expected,
          source: source,
          onProgress: onProgress,
        );
      }
      return owner.commit(
        root,
        target: target,
        expected: expected,
        source: source,
      );
    }

    final current = await owner.revision(root, _target(reference));
    if (!current.isSuccess ||
        !reference.storageRevision!.matches(current.value!)) {
      throw const NotePersistenceFailure(OperationOutcome.conflict);
    }
    final ids = <String>{};
    for (final attachment in attachments) {
      if (!ids.add(attachment.id)) {
        throw const NotePersistenceFailure(OperationOutcome.rejectedInput);
      }
      final result = await publish(
        attachmentTarget(reference, attachment.id),
        const StorageRevision.missing(),
        CommitFileSource(attachment.source.path, attachment.source.length),
      );
      if (!result.isSuccess) throw NotePersistenceFailure(result.outcome);
    }
    Directory? operation;
    try {
      final sources = Directory(
        reference.binding.child(
          '.future-notes-storage/sources/${CommitRecord.objectIdentity(_target(reference))}',
        ),
      );
      await environment.verifyLocation(sources.path);
      await sources.create(recursive: true);
      await environment.verifyLocation(sources.path, allowRunRoot: true);
      operation = await sources.createTemp('note-operation-');
      _sources.add(operation);
      final file = File(p.join(operation.path, 'candidate.enc'));
      await environment.verifyLocation(file.path);
      await file.create(exclusive: true);
      final bytes = utf8.encode(content);
      await file.writeAsBytes(bytes, flush: true);
      final result = await publish(
        _target(reference),
        reference.storageRevision!,
        CommitFileSource(file.path, bytes.length),
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
    await _attachmentReader.close();
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

/// Prepared ciphertext, never plaintext or an in-memory attachment payload.
class PreparedAttachmentFile {
  const PreparedAttachmentFile(this.id, this.source);
  final String id;
  final StreamingFileSource source;
}

class NotePersistenceFailure implements Exception {
  const NotePersistenceFailure(this.outcome);
  final OperationOutcome outcome;

  @override
  String toString() => 'Note persistence failed (${outcome.name}).';
}
