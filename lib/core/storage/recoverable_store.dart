import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

import '../operations/operation_result.dart';
import 'commit_record.dart';
import 'native_storage_primitives.dart';
import 'permanent_deletion.dart';
import 'storage_environment.dart';
import 'windows_file_actions.dart';

/// Fault points run after the named operation, before its next acknowledgement.
enum CommitBoundary {
  stageCreated,
  stageWritten,
  stageFlushed,
  stageVerified,
  intentWritten,
  intentFlushed,
  intentVerified,
  baselineCreated,
  baselineWritten,
  baselineVerified,
  baselineProofWritten,
  previousMoved,
  previousVerified,
  published,
  publishedVerified,
  receiptWritten,
  receiptFlushed,
  receiptVerified,
  recoveryCandidateRetained,
  recoveryRestored,
  recoveryReceiptWritten,
  deletionIntentVerified,
  deletionFileRemoved,
  deletionReceiptWritten,
}

typedef CommitFaultHook =
    Future<void> Function(CommitBoundary point, String id);
typedef CommitByteProgress = void Function(String phase, int bytes, int total);

/// Reopenable, file-backed input. Its length is checked before and after copying.
class CommitFileSource {
  const CommitFileSource(this.path, this.length);
  final String path;
  final int length;
}

class RecoveryReport {
  RecoveryReport({
    required this.libraryReadOnly,
    required Set<String> blockedTargets,
    required this.restoredTransactions,
    this.pendingDeletions = const [],
    Set<String> restoredTargets = const {},
  }) : blockedTargets = Set.unmodifiable(blockedTargets),
       restoredTargets = Set.unmodifiable(restoredTargets);
  final bool libraryReadOnly;
  final Set<String> blockedTargets;
  final int restoredTransactions;
  final List<DeletionIntent> pendingDeletions;
  final Set<String> restoredTargets;
}

/// Captured-root replacement backend. Own and dispatch it in one storage
/// isolate. It performs no discovery and cannot open an unconfigured environment.
/// Flush/rename does not establish complete power-loss atomicity.
class RecoverableStore {
  RecoverableStore._(
    this.root,
    this.environment,
    this._files,
    this._primitives,
    this._lease,
    this._fault,
    this._identity,
  );

  final String root;
  final StorageEnvironment environment;
  final StorageFileActions _files;
  final NativeStoragePrimitives _primitives;
  final WriterLease _lease;
  final CommitFaultHook? _fault;
  final String Function() _identity;
  final _blocked = <String>{};
  final _deletedTransactions = <String>{};
  final _pendingDeletions = <String, DeletionIntent>{};
  final _restoredTargets = <String>{};
  late final _deletion = PermanentDeletion(
    root: root,
    environment: environment,
    onBoundary: (phase, id) => _point(switch (phase) {
      'intent' => CommitBoundary.deletionIntentVerified,
      'removed' => CommitBoundary.deletionFileRemoved,
      _ => CommitBoundary.deletionReceiptWritten,
    }, id),
  );
  bool _libraryReadOnly = false;
  bool _closing = false;
  Future<void> _tail = Future.value();
  Future<void>? _closeFuture;
  int _restored = 0;

  RecoveryReport get recovery => RecoveryReport(
    libraryReadOnly: _libraryReadOnly,
    blockedTargets: _blocked,
    restoredTransactions: _restored,
    pendingDeletions: List.unmodifiable(_pendingDeletions.values),
    restoredTargets: _restoredTargets,
  );

  static Future<OperationResult<RecoverableStore>> open({
    required String root,
    required StorageEnvironment environment,
    StorageFileActions? fileActions,
    CommitFaultHook? faultHook,
    String Function()? transactionIdentity,
  }) async {
    // Refuse before any I/O; root admission never follows mutable settings.
    if (!environment.hasOwnedStorage ||
        !Platform.isWindows ||
        !p.isAbsolute(root) ||
        p.split(root).contains('..') ||
        !environment.permitsOwnerRoot(root)) {
      return const OperationResult.failure(
        OperationOutcome.rejectedInput,
        'Recoverable storage requires an explicitly admitted Windows location.',
      );
    }
    WriterLease? lease;
    try {
      await environment.verifyConfiguredPaths();
      await environment.verifyLocation(root);
      final primitives = NativeStoragePrimitives(environment);
      final acquired = await primitives.acquireLease(
        p.join(root, '.future-notes-writer.lock'),
      );
      if (!acquired.isSuccess) {
        return OperationResult.failure(acquired.outcome, acquired.message);
      }
      lease = acquired.value!;
      final store = RecoverableStore._(
        p.normalize(root),
        environment,
        fileActions ?? WindowsFileActions(root: root, environment: environment),
        primitives,
        lease,
        faultHook,
        transactionIdentity ?? _newIdentity,
      );
      await store._recover();
      return OperationResult.success(store);
    } catch (_) {
      if (lease != null) {
        try {
          await lease.close();
        } catch (_) {
          /* Ownership remains reserved. */
        }
      }
      return const OperationResult.failure(
        OperationOutcome.recoveryRequired,
        'Storage ownership or startup recovery failed.',
      );
    }
  }

  Future<OperationResult<StorageRevision>> commit({
    required String target,
    required StorageRevision expected,
    required CommitFileSource source,
    bool Function()? isCancelled,
    CommitByteProgress? onProgress,
  }) {
    final completed = Completer<OperationResult<StorageRevision>>();
    if (_closing) {
      return Future.value(
        const OperationResult.failure(
          OperationOutcome.rejectedInput,
          'Storage owner is closing.',
        ),
      );
    }
    _tail = _tail.then((_) async {
      completed.complete(
        await _commit(target, expected, source, isCancelled, onProgress),
      );
    });
    return completed.future;
  }

  Future<void> close() {
    _closing = true;
    return _closeFuture ??= _close();
  }

  Future<OperationResult<DeletionReport>> delete({
    required String target,
    required StorageRevision expected,
    String? attachmentDirectory,
  }) {
    if (_closing) {
      return Future.value(
        const OperationResult.failure(
          OperationOutcome.rejectedInput,
          'Storage owner is closing.',
        ),
      );
    }
    final completed = Completer<OperationResult<DeletionReport>>();
    _tail = _tail.then((_) async {
      try {
        if (_libraryReadOnly) {
          completed.complete(
            const OperationResult.failure(
              OperationOutcome.recoveryRequired,
              'Library recovery is incomplete.',
            ),
          );
          return;
        }
        DeletionIntent? intent;
        for (final existing in await _deletion.load()) {
          if (_key(existing.target) == _key(target)) {
            intent = existing;
            break;
          }
        }
        if (intent == null) {
          if (_blocked.contains(_key(target))) {
            completed.complete(
              const OperationResult.failure(
                OperationOutcome.recoveryRequired,
                'Recover this note before deleting it.',
              ),
            );
            return;
          }
          intent = await _deletion.prepare(
            id: _checkedIdentity(),
            target: target,
            expected: expected,
            attachmentDirectory: attachmentDirectory,
          );
        }
        _admitDeletion(intent);
        final result = await _deletion.apply(intent);
        if (result.isSuccess) {
          _pendingDeletions.remove(intent.id);
        } else {
          _pendingDeletions[intent.id] = intent;
        }
        completed.complete(result);
      } on DeletionConflict {
        completed.complete(
          const OperationResult.failure(
            OperationOutcome.conflict,
            'The reviewed note changed before deletion.',
          ),
        );
      } catch (_) {
        await _loadDeletions();
        completed.complete(
          const OperationResult.failure(
            OperationOutcome.recoveryRequired,
            'Deletion could not finish. Retained journals require cleanup.',
          ),
        );
      }
    });
    return completed.future;
  }

  void _admitDeletion(DeletionIntent intent) {
    _blocked.addAll(intent.objects.map(_key));
    _deletedTransactions.addAll(
      intent.transactions.map((r) => r.transactionId),
    );
  }

  Future<void> _loadDeletions() async {
    try {
      for (final intent in await _deletion.load()) {
        _admitDeletion(intent);
        if (!await _deletion.isComplete(intent)) {
          _pendingDeletions[intent.id] = intent;
        } else {
          _pendingDeletions.remove(intent.id);
        }
      }
    } catch (_) {
      _libraryReadOnly = true;
    }
  }

  Future<void> _close() async {
    await _tail;
    await _lease.close();
  }

  Future<OperationResult<StorageRevision>> _commit(
    String target,
    StorageRevision expected,
    CommitFileSource source,
    bool Function()? cancelled,
    CommitByteProgress? onProgress,
  ) async {
    final progressClock = Stopwatch()..start();
    var lastProgress = -100;
    String? lastPhase;
    void progress(String phase, int bytes, int total) {
      if (phase != lastPhase ||
          bytes == total ||
          progressClock.elapsedMilliseconds - lastProgress >= 100) {
        lastPhase = phase;
        lastProgress = progressClock.elapsedMilliseconds;
        try {
          onProgress?.call(phase, bytes, total);
        } catch (_) {
          /* Observation cannot interrupt a journal. */
        }
      }
    }

    var journalStarted = false;
    try {
      if (_closing || _libraryReadOnly || _blocked.contains(_key(target))) {
        return const OperationResult.failure(
          OperationOutcome.recoveryRequired,
          'Storage target is not writable.',
        );
      }
      final id = _identity();
      // Validate caller identities/paths/revisions before source or target I/O.
      final validation = CommitRecord(
        transactionId: id,
        target: target,
        expected: expected,
        staged: const StorageRevision.present(
          0,
          '0000000000000000000000000000000000000000000000000000000000000000',
          0,
        ),
      );
      if (source.length < 0) {
        throw const FormatException('Invalid source length.');
      }
      final destination = await _location(target);
      final current = await _primitives.captureRevision(destination);
      if (!current.matches(expected)) {
        return const OperationResult.failure(
          OperationOutcome.conflict,
          'Storage target changed before commit.',
        );
      }
      if (cancelled?.call() == true) {
        throw const _Cancelled();
      }
      final before = await _captureProgress(
        source.path,
        progress,
        'Checking prepared file',
      );
      if (!before.exists ||
          before.length != source.length ||
          p.equals(source.path, destination)) {
        throw const FormatException('Invalid or changed source.');
      }
      final stagedPath = await _location(validation.stagePath);
      await _copy(
        source.path,
        stagedPath,
        before,
        id,
        created: CommitBoundary.stageCreated,
        written: CommitBoundary.stageWritten,
        flushed: CommitBoundary.stageFlushed,
        cancelled: cancelled,
        onProgress: progress,
      );
      final staged = await _captureProgress(
        stagedPath,
        progress,
        'Confirming staged file',
      );
      if (!_sameContent(staged, before)) {
        throw const _Changed();
      }
      final record = CommitRecord(
        transactionId: id,
        target: target,
        expected: expected,
        staged: staged,
      );
      await _point(CommitBoundary.stageVerified, id);
      if (cancelled?.call() == true) {
        throw const _Cancelled();
      }
      if (!(await _primitives.captureRevision(destination)).matches(expected)) {
        return const OperationResult.failure(
          OperationOutcome.conflict,
          'Storage target changed during preparation.',
        );
      }
      // From here, cancellation cannot interrupt the commit. A partial intent
      // is retained and makes startup fail closed rather than guessing a target.
      journalStarted = true;
      await _writeSmall(
        await _location(record.recordPath),
        record.encode(),
        id,
        written: CommitBoundary.intentWritten,
        flushed: CommitBoundary.intentFlushed,
      );
      if (CommitRecord.decode(
            await _readSmall(await _location(record.recordPath)),
          ).encode() !=
          record.encode()) {
        throw const _Changed();
      }
      await _point(CommitBoundary.intentVerified, id);
      if (expected.exists) {
        await _ensureBaseline(record, destination);
      }
      if (!(await _primitives.captureRevision(destination)).matches(expected)) {
        throw const _Changed();
      }
      if (expected.exists) {
        final previous = await _location(record.previousPath);
        await _move(destination, previous);
        await _point(CommitBoundary.previousMoved, id);
        if (!(await _primitives.captureRevision(previous)).matches(expected)) {
          throw const _Changed();
        }
        await _point(CommitBoundary.previousVerified, id);
      }
      await _parent(destination);
      await _move(stagedPath, destination);
      await _point(CommitBoundary.published, id);
      final published = await _captureProgress(
        destination,
        progress,
        'Verifying published file',
      );
      if (!published.matches(staged)) {
        throw const _Changed();
      }
      await _point(CommitBoundary.publishedVerified, id);
      await _writeSmall(
        await _location(record.receiptPath),
        CommitReceipt(record, CommitDisposition.completed, published).encode(),
        id,
        written: CommitBoundary.receiptWritten,
        flushed: CommitBoundary.receiptFlushed,
      );
      CommitReceipt.decode(
        await _readSmall(await _location(record.receiptPath)),
        record,
      );
      // Detect an observed replacement even after writing the receipt.
      if (!(await _captureProgress(
        destination,
        progress,
        'Confirming commit',
      )).matches(published)) {
        throw const _Changed();
      }
      await _point(CommitBoundary.receiptVerified, id);
      return OperationResult.success(published);
    } on _Cancelled {
      return const OperationResult.failure(
        OperationOutcome.cancelled,
        'Preparation cancelled.',
      );
    } catch (error) {
      if (journalStarted) {
        _blocked.add(_key(target));
        return const OperationResult.failure(
          OperationOutcome.recoveryRequired,
          'Replacement is incomplete; retained versions require recovery.',
        );
      }
      return OperationResult.failure(
        error is FormatException || error is ArgumentError
            ? OperationOutcome.rejectedInput
            : OperationOutcome.ioFailure,
        'Replacement preparation failed; the active object was retained.',
      );
    }
  }

  Future<void> _recover() async {
    await _loadDeletions();
    if (_libraryReadOnly) return;
    final directory = await _location('.future-notes-storage/transactions');
    final pending = <CommitRecord>[];
    final records = <CommitRecord>[];
    final receiptOwners = <String>{};
    var count = 0;
    try {
      await for (final entry in Directory(directory).list(followLinks: false)) {
        if (++count > 30000) {
          _libraryReadOnly = true;
          return;
        }
        final name = p.basename(entry.path);
        if (_deletedTransactions.contains(name.split('.').first)) continue;
        if (!RegExp(
              r'^[a-f0-9]{32}\.(json|receipt|resolution)$',
            ).hasMatch(name) ||
            entry is! File) {
          _libraryReadOnly = true;
          continue;
        }
        if (!name.endsWith('.json')) {
          receiptOwners.add(name.split('.').first);
          continue;
        }
        try {
          final record = CommitRecord.decode(await _readSmall(entry.path));
          if (name != '${record.transactionId}.json') {
            throw const FormatException();
          }
          records.add(record);
          final resolution = await _optionalReceipt(
            _resolution(record),
            record,
          );
          final receipt = await _optionalReceipt(record.receiptPath, record);
          if (resolution != null) {
            if (resolution.disposition != CommitDisposition.restored ||
                receipt?.disposition == CommitDisposition.completed) {
              _blocked.add(_key(record.target));
            }
          } else if (receipt == null) {
            pending.add(record);
          }
        } catch (_) {
          // A damaged intent cannot safely identify its affected target.
          _libraryReadOnly = true;
        }
      }
    } on FileSystemException catch (error) {
      final code = error.osError?.errorCode;
      if (count == 0 && (code == 2 || (Platform.isWindows && code == 3))) {
        return;
      }
      _libraryReadOnly = true;
      return;
    }
    final recordedIds = records.map((r) => r.transactionId).toSet();
    if (receiptOwners.any((id) => !recordedIds.contains(id))) {
      _libraryReadOnly = true;
    }
    if (_libraryReadOnly) {
      return;
    }
    final counts = <String, int>{};
    for (final record in pending) {
      final key = _key(record.target);
      counts[key] = (counts[key] ?? 0) + 1;
    }
    for (final record in pending) {
      if (counts[_key(record.target)] != 1) {
        _blocked.add(_key(record.target));
        continue;
      }
      try {
        await _restore(record);
      } catch (_) {
        _blocked.add(_key(record.target));
      }
    }
    // Verify retained baselines independently of the current target: completed
    // receipts are historical and must not resurrect later deleted/changed files.
    final checkedBaselines = <String>{};
    for (final record in records) {
      if (!record.expected.exists || _blocked.contains(_key(record.target))) {
        continue;
      }
      if (!checkedBaselines.add(record.objectId)) {
        continue;
      }
      try {
        await _verifyBaseline(record);
      } catch (_) {
        _blocked.add(_key(record.target));
      }
    }
  }

  Future<CommitReceipt?> _optionalReceipt(
    String relative,
    CommitRecord record,
  ) async {
    final location = await _location(relative);
    try {
      return CommitReceipt.decode(await _readSmall(location), record);
    } on FileSystemException catch (error) {
      final code = error.osError?.errorCode;
      if (code == 2 || (Platform.isWindows && code == 3)) {
        return null;
      }
      _blocked.add(_key(record.target));
      return null;
    } catch (_) {
      // Invalid receipt is ambiguous: retain it and block its known target.
      _blocked.add(_key(record.target));
      return null;
    }
  }

  Future<void> _restore(CommitRecord record) async {
    if (_blocked.contains(_key(record.target))) {
      return;
    }
    final target = await _location(record.target);
    final current = await _primitives.captureRevision(target);
    final previous = await _location(record.previousPath);
    final prior = await _primitives.captureRevision(previous);
    if (prior.exists && !prior.matches(record.expected)) {
      throw const _Changed();
    }
    final stage = await _primitives.captureRevision(
      await _location(record.stagePath),
    );
    if (stage.exists && !stage.matches(record.staged)) {
      throw const _Changed();
    }
    if (current.matches(record.expected)) {
      if (record.expected.exists) {
        await _ensureBaseline(record, target);
      }
    } else {
      if (current.exists && !current.matches(record.staged)) {
        throw const _Changed();
      }
      if (record.expected.exists && !prior.exists) {
        throw const _Changed();
      }
      if (record.expected.exists) {
        await _ensureBaseline(record, previous);
      }
      if (current.exists) {
        final retained =
            '.future-notes-storage/recovery/${record.objectId}/${record.transactionId}-${_checkedIdentity()}.interrupted';
        await _move(target, await _location(retained));
        await _point(
          CommitBoundary.recoveryCandidateRetained,
          record.transactionId,
        );
      }
      if (record.expected.exists) {
        final restore =
            '.future-notes-storage/staging/${record.transactionId}-${_checkedIdentity()}.restore';
        final restoredStage = await _location(restore);
        await _copy(previous, restoredStage, prior, record.transactionId);
        // Preserve the captured filesystem revision so recovery can resume if
        // interrupted after restoration but before its resolution receipt.
        await File(restoredStage).setLastModified(
          DateTime.fromMicrosecondsSinceEpoch(record.expected.modifiedMicros!),
        );
        if (!(await _primitives.captureRevision(
          restoredStage,
        )).matches(record.expected)) {
          throw const _Changed();
        }
        await _move(restoredStage, target);
        await _point(CommitBoundary.recoveryRestored, record.transactionId);
      }
    }
    final restored = await _primitives.captureRevision(target);
    if (!_sameContent(restored, record.expected)) {
      throw const _Changed();
    }
    await _writeSmall(
      await _location(_resolution(record)),
      CommitReceipt(record, CommitDisposition.restored, restored).encode(),
      record.transactionId,
    );
    CommitReceipt.decode(
      await _readSmall(await _location(_resolution(record))),
      record,
    );
    await _point(CommitBoundary.recoveryReceiptWritten, record.transactionId);
    _restored++;
    _restoredTargets.add(_key(record.target));
  }

  Future<void> _ensureBaseline(CommitRecord record, String prior) async {
    final baseline = await _location(record.baselinePath);
    final proof = await _location(_baselineProof(record));
    final exists = (await _primitives.captureRevision(baseline)).exists;
    if ((await _primitives.captureRevision(proof)).exists) {
      await _verifyBaseline(record);
      return;
    }
    if (!exists) {
      await _copy(
        prior,
        baseline,
        record.expected,
        record.transactionId,
        created: CommitBoundary.baselineCreated,
        written: CommitBoundary.baselineWritten,
      );
    }
    if (!_sameContent(
      await _primitives.captureRevision(baseline),
      record.expected,
    )) {
      throw const _Changed();
    }
    await _point(CommitBoundary.baselineVerified, record.transactionId);
    final encoded = jsonEncode({
      'transactionId': record.transactionId,
      'recordHash': record.recordHash,
    });
    await _writeSmall(proof, encoded, record.transactionId);
    await _point(CommitBoundary.baselineProofWritten, record.transactionId);
    await _verifyBaseline(record);
  }

  Future<void> _verifyBaseline(CommitRecord record) async {
    final encoded = await _readSmall(await _location(_baselineProof(record)));
    final proof = jsonDecode(encoded);
    if (proof is! Map<String, dynamic> ||
        proof['transactionId'] is! String ||
        proof['recordHash'] is! String ||
        !RegExp(r'^[a-f0-9]{32}$').hasMatch(proof['transactionId'] as String) ||
        jsonEncode({
              'transactionId': proof['transactionId'],
              'recordHash': proof['recordHash'],
            }) !=
            encoded) {
      throw const FormatException('Invalid baseline receipt.');
    }
    final original = CommitRecord.decode(
      await _readSmall(
        await _location(
          '.future-notes-storage/transactions/${proof['transactionId']}.json',
        ),
      ),
    );
    if (original.recordHash != proof['recordHash'] ||
        original.objectId != record.objectId ||
        !original.expected.exists ||
        !_sameContent(
          await _primitives.captureRevision(
            await _location(record.baselinePath),
          ),
          original.expected,
        )) {
      throw const _Changed();
    }
  }

  Future<void> _copy(
    String source,
    String destination,
    StorageRevision required,
    String id, {
    CommitBoundary? created,
    CommitBoundary? written,
    CommitBoundary? flushed,
    bool Function()? cancelled,
    CommitByteProgress? onProgress,
  }) async {
    if (!required.exists) {
      throw const _Changed();
    }
    await _parent(destination);
    await environment.verifyLocation(source);
    final before = await _captureProgress(
      source,
      onProgress,
      'Verifying prepared source',
    );
    if (!_sameContent(before, required)) {
      throw const _Changed();
    }
    await File(destination).create(exclusive: true);
    if (created != null) {
      await _point(created, id);
    }
    RandomAccessFile? input;
    RandomAccessFile? output;
    try {
      input = await File(source).open();
      output = await File(destination).open(mode: FileMode.writeOnly);
      var copied = 0;
      while (true) {
        if (cancelled?.call() == true) {
          throw const _Cancelled();
        }
        final bytes = await input.read(NativeStoragePrimitives.ioWindow);
        if (bytes.isEmpty) {
          break;
        }
        copied += bytes.length;
        if (copied > required.length!) {
          throw const _Changed();
        }
        await output.writeFrom(bytes);
        onProgress?.call('Writing staged file', copied, required.length!);
      }
      if (copied != required.length) {
        throw const _Changed();
      }
      if (written != null) {
        await _point(written, id);
      }
      await output.flush();
      if (flushed != null) {
        await _point(flushed, id);
      }
    } finally {
      try {
        if (input != null) {
          await input.close();
        }
      } finally {
        if (output != null) {
          await output.close();
        }
      }
    }
    if (!(await _captureProgress(
          source,
          onProgress,
          'Rechecking prepared source',
        )).matches(before) ||
        !_sameContent(
          await _captureProgress(
            destination,
            onProgress,
            'Verifying staged file',
          ),
          required,
        )) {
      throw const _Changed();
    }
  }

  Future<StorageRevision> _captureProgress(
    String path,
    CommitByteProgress? progress,
    String phase,
  ) async {
    if (progress == null) return _primitives.captureRevision(path);
    var length = 0;
    return _primitives.captureRevision(
      path,
      onStart: (bytes) {
        length = bytes;
        progress(phase, 0, length);
      },
      onChunk: (bytes) async {
        progress(phase, min(bytes, length), length);
      },
    );
  }

  Future<void> _writeSmall(
    String location,
    String value,
    String id, {
    CommitBoundary? written,
    CommitBoundary? flushed,
  }) async {
    final bytes = utf8.encode(value);
    if (bytes.length > CommitRecord.maxRecordBytes) {
      throw const FormatException();
    }
    await _parent(location);
    await File(location).create(exclusive: true);
    final handle = await File(location).open(mode: FileMode.writeOnly);
    try {
      await handle.writeFrom(bytes);
      if (written != null) {
        await _point(written, id);
      }
      await handle.flush();
      if (flushed != null) {
        await _point(flushed, id);
      }
    } finally {
      await handle.close();
    }
    if (await _readSmall(location) != value) {
      throw const _Changed();
    }
  }

  Future<String> _readSmall(String location) async {
    await environment.verifyLocation(location);
    final handle = await File(location).open();
    try {
      final before = await File(location).stat();
      if (before.type != FileSystemEntityType.file ||
          before.size > CommitRecord.maxRecordBytes) {
        throw const FormatException();
      }
      final bytes = <int>[];
      while (true) {
        final chunk = await handle.read(4096);
        if (chunk.isEmpty) {
          break;
        }
        if (bytes.length + chunk.length > CommitRecord.maxRecordBytes) {
          throw const FormatException();
        }
        bytes.addAll(chunk);
      }
      if (bytes.length != before.size) {
        throw const FormatException();
      }
      final text = utf8.decode(bytes);
      await environment.verifyLocation(location);
      final after = await File(location).stat();
      if (after.type != FileSystemEntityType.file ||
          before.size != after.size ||
          before.modified != after.modified ||
          before.changed != after.changed) {
        throw const _Changed();
      }
      return text;
    } finally {
      await handle.close();
    }
  }

  Future<String> _location(String relative) async {
    if (p.isAbsolute(relative) ||
        relative.contains('\\') ||
        relative.contains(':') ||
        relative.split('/').any((s) => s.isEmpty || s == '.' || s == '..')) {
      throw const FormatException();
    }
    final location = p.normalize(p.join(root, relative));
    if (!p.isWithin(root, location)) {
      throw const FormatException();
    }
    await environment.verifyLocation(location);
    return location;
  }

  Future<void> _parent(String location) async {
    await environment.verifyLocation(location);
    await File(location).parent.create(recursive: true);
    await environment.verifyLocation(location);
  }

  Future<void> _move(String source, String destination) async {
    await _parent(destination);
    final result = await _files.moveWithoutReplace(source, destination);
    if (!result.isSuccess) {
      throw const _Changed();
    }
  }

  Future<void> _point(CommitBoundary point, String id) async {
    if (_fault != null) {
      await _fault(point, id);
    }
  }

  String _checkedIdentity() {
    final id = _identity();
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(id)) {
      throw const FormatException();
    }
    return id;
  }

  static String _newIdentity() {
    final random = Random.secure();
    return List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  static String _key(String target) =>
      Platform.isWindows ? target.toLowerCase() : target;
  static bool _sameContent(StorageRevision a, StorageRevision b) =>
      a.exists == b.exists &&
      a.length == b.length &&
      a.sha256Hex == b.sha256Hex;
  static String _baselineProof(CommitRecord r) => '${r.baselinePath}.receipt';
  static String _resolution(CommitRecord r) =>
      '.future-notes-storage/transactions/${r.transactionId}.resolution';
}

class _Changed implements Exception {
  const _Changed();
}

class _Cancelled implements Exception {
  const _Cancelled();
}
