import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../operations/operation_result.dart';
import 'commit_record.dart';
import 'native_storage_primitives.dart';
import 'storage_environment.dart';

class DeletionReport {
  DeletionReport(this.removed, this.pending);
  final List<String> removed;
  final List<String> pending;
}

/// Immutable deletion authorization. Retain its intent after completion so old
/// save work cannot recreate the reviewed identity. No payloads or credentials.
class DeletionIntent {
  DeletionIntent(
    this.id,
    this.target,
    this.objects,
    this.files,
    this.transactions, {
    this.desktopCompatibility = false,
  }) {
    CommitRecord(
      transactionId: id,
      target: target,
      expected: const StorageRevision.missing(),
      staged: const StorageRevision.present(
        0,
        '0000000000000000000000000000000000000000000000000000000000000000',
        0,
      ),
    );
    if (files.length > 10000 ||
        objects.length > 10000 ||
        transactions.length > 10000 ||
        !objects.contains(target) ||
        !files.containsKey(target)) {
      throw const FormatException('Invalid deletion inventory.');
    }
    for (final object in objects) {
      if (object != target) {
        final parts = object.split('/');
        final noteParts = target.split('/');
        if (parts.length != 3 ||
            !parts.first.startsWith('note_') ||
            parts[1] != 'attachments' ||
            !RegExp(r'^[A-Za-z0-9_-]+\.med$').hasMatch(parts.last) ||
            (noteParts.length > 1 && !p.equals(parts.first, noteParts.first))) {
          throw const FormatException('Unrelated managed attachment.');
        }
      }
      CommitRecord(
        transactionId: id,
        target: object,
        expected: const StorageRevision.missing(),
        staged: const StorageRevision.present(
          0,
          '0000000000000000000000000000000000000000000000000000000000000000',
          0,
        ),
      );
    }
    final admitted = <String>{...objects};
    for (final record in transactions) {
      if (!objects.any((object) => p.equals(object, record.target))) {
        throw const FormatException('Unrelated deletion transaction.');
      }
      admitted.addAll([
        record.recordPath,
        record.receiptPath,
        record.stagePath,
        record.previousPath,
        record.baselinePath,
        '${record.baselinePath}.receipt',
        '.future-notes-storage/transactions/${record.transactionId}.resolution',
      ]);
    }
    for (final entry in files.entries) {
      final relative = entry.key;
      if (relative.contains('\\') ||
          relative.contains(':') ||
          relative
              .split('/')
              .any((part) => part.isEmpty || part == '..' || part == '.') ||
          relative.startsWith('/') ||
          utf8.encode(relative).length > 4096) {
        throw const FormatException('Invalid deletion path.');
      }
      final recoveryVersion = transactions.any(
        (r) =>
            relative.startsWith(
              '.future-notes-storage/recovery/${r.objectId}/',
            ) &&
            RegExp(
              r'^[a-f0-9]{32}-[a-f0-9]{32}\.interrupted$',
            ).hasMatch(p.posix.basename(relative)),
      );
      final sourceParts = relative.split('/');
      final ownedSource =
          sourceParts.length == 5 &&
          sourceParts[0] == '.future-notes-storage' &&
          sourceParts[1] == 'sources' &&
          objects.any(
            (object) =>
                sourceParts[2] == CommitRecord.objectIdentity(object) ||
                (desktopCompatibility &&
                    sourceParts[2] ==
                        CommitRecord.windowsObjectIdentity(object)),
          ) &&
          RegExp(
            r'^(note|attachment)-operation-[A-Za-z0-9]+$',
          ).hasMatch(sourceParts[3]) &&
          RegExp(r'^[A-Za-z0-9_.-]+$').hasMatch(sourceParts[4]);
      if (!admitted.contains(relative) && !recoveryVersion && !ownedSource) {
        throw const FormatException('Unrelated deletion object.');
      }
      final revision = entry.value;
      if (!revision.exists ||
          revision.length == null ||
          revision.length! < 0 ||
          revision.modifiedMicros == null ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(revision.sha256Hex!)) {
        throw const FormatException('Invalid deletion revision.');
      }
    }
  }
  final String id;
  final String target;
  final Set<String> objects;
  final Map<String, StorageRevision> files;
  final List<CommitRecord> transactions;
  final bool desktopCompatibility;
  String get path => '.future-notes-storage/deletions/$id.json';
  String get hash => sha256.convert(utf8.encode(encode())).toString();
  String encode() => jsonEncode({
    'version': 1,
    'id': id,
    'target': target,
    'objects': objects.toList(),
    'transactions': transactions.map((r) => r.encode()).toList(),
    'files': files.map(
      (path, r) => MapEntry(path, {
        'length': r.length,
        'sha256': r.sha256Hex,
        'modifiedMicros': r.modifiedMicros,
      }),
    ),
  });
  static DeletionIntent decode(String text) {
    final json = jsonDecode(text);
    if (json is! Map<String, dynamic> || json['version'] != 1) {
      throw const FormatException('Unsupported deletion journal.');
    }
    final objects = List<String>.from(json['objects'] as List);
    if (objects.toSet().length != objects.length) {
      throw const FormatException('Duplicate deletion objects.');
    }
    final intent = DeletionIntent(
      json['id'] as String,
      json['target'] as String,
      objects.toSet(),
      (json['files'] as Map<String, dynamic>).map(
        (path, value) => MapEntry(
          path,
          StorageRevision.present(
            value['length'] as int,
            value['sha256'] as String,
            value['modifiedMicros'] as int,
          ),
        ),
      ),
      (json['transactions'] as List)
          .map((text) => CommitRecord.decodeDesktopCompatible(text as String))
          .toList(),
      desktopCompatibility: Platform.isMacOS || Platform.isLinux,
    );
    if (intent.encode() != text) {
      throw const FormatException('Noncanonical deletion journal.');
    }
    return intent;
  }
}

class PermanentDeletion {
  PermanentDeletion({
    required this.root,
    required this.environment,
    this.onBoundary,
  });
  final String root;
  final StorageEnvironment environment;
  final Future<void> Function(String phase, String id)? onBoundary;
  static const maxJournalBytes = 32 * 1024 * 1024;
  late final _primitives = NativeStoragePrimitives(environment);

  Future<String> _location(String relative) async {
    final target = p.normalize(p.join(root, relative));
    if (!p.isWithin(root, target)) {
      throw const FormatException('Deletion escapes root.');
    }
    await environment.verifyLocation(target);
    return target;
  }

  Future<String> _read(String location) async {
    final file = File(location);
    if (await file.length() > maxJournalBytes) {
      throw const FormatException('Deletion journal exceeds limit.');
    }
    final input = await file.open();
    try {
      final bytes = await input.read(maxJournalBytes + 1);
      if (bytes.length > maxJournalBytes) {
        throw const FormatException('Deletion journal exceeds limit.');
      }
      return utf8.decode(bytes);
    } finally {
      await input.close();
    }
  }

  Future<void> _write(String relative, String value) async {
    final bytes = utf8.encode(value);
    if (bytes.length > maxJournalBytes) {
      throw const FormatException('Deletion journal exceeds limit.');
    }
    final file = File(await _location(relative));
    final primitives = NativeStoragePrimitives(environment);
    await primitives.prepareParent(file.path);
    await file.create(exclusive: true);
    await file.writeAsBytes(bytes, flush: true);
    await primitives.persistParent(file.path);
    if (await _read(file.path) != value) {
      throw const FormatException('Deletion journal verification failed.');
    }
  }

  Future<List<DeletionIntent>> load() async {
    final directory = Directory(
      await _location('.future-notes-storage/deletions'),
    );
    if (!await directory.exists()) return [];
    final result = <DeletionIntent>[];
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File ||
          !RegExp(
            r'^[a-f0-9]{32}\.json(\.receipt)?$',
          ).hasMatch(p.basename(entity.path))) {
        throw const FormatException('Invalid deletion directory object.');
      }
      if (entity.path.endsWith('.receipt')) continue;
      final intent = DeletionIntent.decode(await _read(entity.path));
      if (p.basename(entity.path) != '${intent.id}.json') {
        throw const FormatException('Invalid deletion identity.');
      }
      result.add(intent);
      if (result.length > 10000) {
        throw const FormatException('Too many deletion journals.');
      }
    }
    return result;
  }

  Future<bool> isComplete(DeletionIntent intent) async {
    final receipt = File(await _location('${intent.path}.receipt'));
    if (!await receipt.exists()) return false;
    if (await _read(receipt.path) !=
        jsonEncode({'version': 1, 'intentHash': intent.hash})) {
      throw const FormatException('Invalid deletion receipt.');
    }
    for (final path in intent.files.keys) {
      if (await FileSystemEntity.type(
            await _location(path),
            followLinks: false,
          ) !=
          FileSystemEntityType.notFound) {
        return false;
      }
    }
    return true;
  }

  Future<DeletionIntent> prepare({
    required String id,
    required String target,
    required StorageRevision expected,
    String? attachmentDirectory,
  }) async {
    final active = await _location(target);
    if (!expected.exists ||
        !(await _primitives.captureRevision(active)).matches(expected)) {
      throw const DeletionConflict();
    }
    final objects = <String>{target};
    if (attachmentDirectory != null) {
      final parts = p.posix.split(attachmentDirectory);
      if (parts.length != 2 ||
          !parts.first.startsWith('note_') ||
          parts.last != 'attachments') {
        throw const FormatException('Invalid managed attachment directory.');
      }
      final folder = Directory(await _location(attachmentDirectory));
      if (await folder.exists()) {
        await for (final entity in folder.list(followLinks: false)) {
          if (entity is! File || !entity.path.endsWith('.med')) {
            throw const FormatException('Unrecognized managed attachment.');
          }
          objects.add(
            p.posix.join(attachmentDirectory, p.basename(entity.path)),
          );
          if (objects.length > 10000) {
            throw const FormatException('Too many managed objects.');
          }
        }
      }
    }
    final paths = <String>{...objects};
    for (final object in objects) {
      final sourceRoot =
          '.future-notes-storage/sources/${CommitRecord.objectIdentity(object)}';
      final sources = Directory(await _location(sourceRoot));
      if (!await sources.exists()) continue;
      await for (final operation in sources.list(followLinks: false)) {
        if (operation is! Directory ||
            !RegExp(
              r'^(note|attachment)-operation-[A-Za-z0-9]+$',
            ).hasMatch(p.basename(operation.path))) {
          throw const FormatException('Unrecognized operation source.');
        }
        await for (final file in operation.list(followLinks: false)) {
          if (file is! File ||
              !RegExp(r'^[A-Za-z0-9_.-]+$').hasMatch(p.basename(file.path))) {
            throw const FormatException('Unrecognized source payload.');
          }
          paths.add(
            p.posix.join(
              sourceRoot,
              p.basename(operation.path),
              p.basename(file.path),
            ),
          );
        }
      }
    }
    final records = <CommitRecord>[];
    final metadata = <String>[];
    final journals = Directory(
      await _location('.future-notes-storage/transactions'),
    );
    if (await journals.exists()) {
      await for (final entity in journals.list(followLinks: false)) {
        if (entity is! File || !entity.path.endsWith('.json')) continue;
        final record = CommitRecord.decodeDesktopCompatible(
          await _read(entity.path),
        );
        if (!objects.any((object) => p.equals(object, record.target))) {
          final managedAttachment =
              attachmentDirectory != null &&
              p.equals(p.posix.dirname(record.target), attachmentDirectory) &&
              RegExp(
                r'^[A-Za-z0-9_-]+\.med$',
              ).hasMatch(p.posix.basename(record.target));
          if (!managedAttachment) continue;
          // Missing active objects can still have retained recovery versions.
          objects.add(record.target);
          paths.add(record.target);
        }
        records.add(record);
        paths.addAll([
          record.previousPath,
          record.stagePath,
          record.baselinePath,
          '${record.baselinePath}.receipt',
        ]);
        metadata.addAll([
          record.receiptPath,
          '.future-notes-storage/transactions/${record.transactionId}.resolution',
          record.recordPath,
        ]);
        final folder = Directory(
          p.dirname(await _location(record.previousPath)),
        );
        if (await folder.exists()) {
          await for (final version in folder.list(followLinks: false)) {
            if (version is! File) {
              throw const FormatException('Invalid recovery object.');
            }
            paths.add(
              p.posix.join(
                '.future-notes-storage/recovery',
                record.objectId,
                p.basename(version.path),
              ),
            );
          }
        }
      }
    }
    paths.addAll(metadata);
    final files = <String, StorageRevision>{};
    for (final path in paths) {
      final revision = await _primitives.captureRevision(await _location(path));
      if (revision.exists) files[path] = revision;
    }
    if (!(await _primitives.captureRevision(active)).matches(expected)) {
      throw const DeletionConflict();
    }
    final intent = DeletionIntent(id, target, objects, files, records);
    await _write(intent.path, intent.encode());
    await onBoundary?.call('intent', id);
    return intent;
  }

  Future<OperationResult<DeletionReport>> apply(DeletionIntent intent) async {
    final removed = <String>[];
    final pending = <String>[];
    var failed = false;
    for (final entry in intent.files.entries) {
      if (failed) {
        pending.add(entry.key);
        continue;
      }
      try {
        final location = await _location(entry.key);
        final actual = await _primitives.captureRevision(location);
        if (actual.exists) {
          if (!actual.matches(entry.value)) throw const DeletionConflict();
          await File(location).delete();
          await onBoundary?.call('removed', intent.id);
          if ((await _primitives.captureRevision(location)).exists) {
            throw const DeletionConflict();
          }
        }
        removed.add(entry.key);
      } catch (_) {
        failed = true;
        pending.add(entry.key);
      }
    }
    if (pending.isEmpty) {
      try {
        final expected = jsonEncode({'version': 1, 'intentHash': intent.hash});
        final receipt = await _location('${intent.path}.receipt');
        if (!await File(receipt).exists()) {
          await _write('${intent.path}.receipt', expected);
        }
        if (await _read(receipt) != expected) {
          throw const FormatException('Invalid deletion receipt.');
        }
        await onBoundary?.call('receipt', intent.id);
        return OperationResult.success(DeletionReport(removed, pending));
      } catch (_) {
        pending.add('${intent.path}.receipt');
      }
    }
    return OperationResult.partial(
      OperationOutcome.recoveryRequired,
      'Permanent deletion is incomplete. Retry remaining cleanup.',
      DeletionReport(removed, pending),
    );
  }
}

class DeletionConflict implements Exception {
  const DeletionConflict();
}
