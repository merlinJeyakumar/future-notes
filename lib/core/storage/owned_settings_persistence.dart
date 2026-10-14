import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../operations/operation_result.dart';
import 'native_storage_primitives.dart';
import 'recoverable_store.dart';
import 'storage_environment.dart';
import 'storage_owner_worker.dart';

/// Captured settings binding. The caller serializes settings mutations
/// and owns this root; the injected worker may also own an independent library.
class OwnedSettingsPersistence {
  OwnedSettingsPersistence({required this.environment, required this.owner}) {
    if (!environment.hasOwnedStorage || !Platform.isWindows) {
      throw ArgumentError(
        'Owned settings require explicitly bound Windows storage.',
      );
    }
  }

  static const maximumBytes = 64 * 1024;
  final StorageEnvironment environment;
  final StorageOwner owner;
  StorageOwnerRoot? _root;
  StorageRevision? _revision;
  bool _closed = false;
  final _temporarySources = <Directory>{};
  bool get cleanupPending => _temporarySources.isNotEmpty;
  bool get settingsRestored =>
      _root != null &&
      (owner.recoveryFor(_root!)?.restoredTargets.contains(_target) ?? false);

  String get _target => p.basename(environment.settingsFile!);

  void _requireWritable() {
    final root = _root;
    final report = root == null ? null : owner.recoveryFor(root);
    if (_closed ||
        root == null ||
        report == null ||
        report.libraryReadOnly ||
        report.blockedTargets.any((target) => p.equals(target, _target))) {
      throw const SettingsPersistenceFailure(OperationOutcome.recoveryRequired);
    }
  }

  Future<Map<String, dynamic>> read() async {
    if (_closed || _root != null) {
      throw const SettingsPersistenceFailure(OperationOutcome.rejectedInput);
    }
    await environment.verifyConfiguredPaths();
    final opened = await owner.openRoot(p.dirname(environment.settingsFile!));
    if (!opened.isSuccess) {
      throw SettingsPersistenceFailure(opened.outcome);
    }
    _root = opened.value!;
    _requireWritable();
    final before = await owner.revision(_root!, _target);
    if (!before.isSuccess) {
      throw SettingsPersistenceFailure(before.outcome);
    }
    final revision = before.value!;
    Map<String, dynamic> metadata = {};
    if (revision.exists) {
      if (revision.length! > maximumBytes) {
        throw const SettingsPersistenceFailure(OperationOutcome.rejectedInput);
      }
      await environment.verifyLocation(environment.settingsFile!);
      final input = await File(environment.settingsFile!).open();
      try {
        final bytes = <int>[];
        while (true) {
          final chunk = await input.read(8192);
          if (chunk.isEmpty) {
            break;
          }
          if (bytes.length + chunk.length > maximumBytes) {
            throw const SettingsPersistenceFailure(
              OperationOutcome.rejectedInput,
            );
          }
          bytes.addAll(chunk);
        }
        if (bytes.length != revision.length) {
          throw const SettingsPersistenceFailure(OperationOutcome.conflict);
        }
        dynamic decoded;
        try {
          decoded = jsonDecode(utf8.decode(bytes));
        } on FormatException {
          throw const SettingsPersistenceFailure(
            OperationOutcome.rejectedInput,
          );
        }
        if (decoded is! Map<String, dynamic>) {
          throw const SettingsPersistenceFailure(
            OperationOutcome.rejectedInput,
          );
        }
        metadata = decoded;
      } finally {
        await input.close();
      }
    }
    final after = await owner.revision(_root!, _target);
    if (!after.isSuccess) {
      throw SettingsPersistenceFailure(after.outcome);
    }
    if (!revision.matches(after.value!)) {
      throw const SettingsPersistenceFailure(OperationOutcome.conflict);
    }
    _revision = revision;
    return metadata;
  }

  Future<void> write(Map<String, dynamic> metadata) async {
    _requireWritable();
    if (_revision == null) {
      throw const SettingsPersistenceFailure(OperationOutcome.rejectedInput);
    }
    final bytes = utf8.encode(jsonEncode(metadata));
    if (bytes.length > maximumBytes) {
      throw const SettingsPersistenceFailure(OperationOutcome.rejectedInput);
    }
    Directory? operation;
    try {
      await environment.verifyLocation(
        environment.operationRoot,
        allowRunRoot: true,
      );
      final sources = Directory(environment.operationRoot);
      await sources.create(recursive: true);
      await environment.verifyLocation(sources.path, allowRunRoot: true);
      operation = await sources.createTemp('settings-operation-');
      _temporarySources.add(operation);
      final file = File(p.join(operation.path, 'candidate.json'));
      await environment.verifyLocation(file.path);
      await file.create(exclusive: true);
      await file.writeAsBytes(bytes, flush: true);
      final committed = await owner.commit(
        _root!,
        target: _target,
        expected: _revision!,
        source: CommitFileSource(file.path, bytes.length),
      );
      if (!committed.isSuccess) {
        throw SettingsPersistenceFailure(committed.outcome);
      }
      _revision = committed.value!;
    } finally {
      if (operation != null) {
        await _cleanSource(operation);
      }
    }
  }

  Future<void> close() async {
    _closed = true;
    for (final operation in _temporarySources.toList()) {
      await _cleanSource(operation);
    }
    final root = _root;
    if (root != null) {
      try {
        final released = await owner.releaseRoot(root);
        if (!released.isSuccess) {
          throw SettingsPersistenceFailure(released.outcome);
        }
        _root = null;
      } on SettingsPersistenceFailure {
        rethrow;
      } catch (_) {
        // Keep ownership for a retry without publishing a sensitive raw error.
        throw const SettingsPersistenceFailure(
          OperationOutcome.recoveryRequired,
        );
      }
    }
    if (cleanupPending) {
      throw const SettingsPersistenceFailure(OperationOutcome.ioFailure);
    }
  }

  Future<void> _cleanSource(Directory operation) async {
    try {
      // Only this operation's local source is temporary. Journal, baseline and
      // staged/recovery objects remain owned by the backend. Cleanup failure
      // must not disguise a successfully acknowledged settings commit.
      final candidate = File(p.join(operation.path, 'candidate.json'));
      await environment.verifyLocation(candidate.path);
      if (await candidate.exists()) {
        await candidate.delete();
      }
      await operation.delete();
      _temporarySources.remove(operation);
    } catch (_) {
      // Retain operation ownership for an explicit cleanup retry on close.
    }
  }
}

/// Sanitized error with a typed outcome; contains no path or raw native error.
class SettingsPersistenceFailure implements Exception {
  const SettingsPersistenceFailure(this.outcome);
  final OperationOutcome outcome;

  @override
  String toString() => 'Settings persistence failed (${outcome.name}).';
}
