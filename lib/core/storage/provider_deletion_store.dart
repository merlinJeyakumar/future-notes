import 'dart:convert';
import 'dart:typed_data';
import 'package:uuid/uuid.dart';
import '../operations/operation_result.dart';
import '../platform/library_documents.dart';
import 'permanent_deletion.dart';
import 'provider_document_io.dart';
import 'provider_legacy_journal.dart';
import 'commit_record.dart';

/// Reviewed permanent deletion. The durable inventory authorizes only exact
/// encrypted revisions. An interrupted cleanup keeps a desktop pending guard
/// and resumes idempotently; changed or unknown material is never removed.
class ProviderDeletionStore {
  ProviderDeletionStore(this.io);
  final ProviderDocumentIo io;
  static const storage = '.future-notes-storage';
  static const maxMetadata = 1024 * 1024;
  static final uuid = RegExp(
    r'^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$',
  );

  Future<bool> blocks(List<String> path) async {
    final directory = await io.resolve([storage, 'provider-deletions']);
    if (directory == null) return false;
    for (final entry in await io.documents.children(io.library, directory)) {
      if (!entry.isDirectory || !uuid.hasMatch(entry.name))
        throw const FormatException('Unknown deletion journal.');
      final intent = await io.child(entry, 'intent.json');
      if (intent == null)
        continue; // Incomplete staging did not authorize deletion.
      if (await io.child(entry, 'completed.json') == null) continue;
      final value = await read(intent);
      final target = (value['target'] as List).cast<String>();
      if (value['version'] != 2 || value['kind'] != 'delete')
        throw const FormatException('Unknown deletion version.');
      if (_under(path, target) || _under(target, path)) return true;
    }
    return false;
  }

  Future<OperationResult<DeletionReport>> delete(
    List<String> envelope,
    ProviderRevision expected,
  ) async {
    var guarded = false;
    try {
      final canonical = await io.resolve(envelope);
      if (canonical == null ||
          !expected.matches(await io.revision(canonical))) {
        return const OperationResult.failure(
          OperationOutcome.conflict,
          'The note changed after Delete was reviewed. Nothing was removed.',
        );
      }
      final transactions = await io.directory([storage, 'transactions']);
      final target = envelope.length == 1
          ? envelope
          : envelope.sublist(0, envelope.length - 1);
      final legacy = <CommitRecord>[];
      final reader = ProviderLegacyJournal(io);
      for (final doc in await io.documents.children(io.library, transactions)) {
        if (!doc.name.endsWith('.json')) continue;
        if (!await reader.acknowledged(doc))
          return const OperationResult.failure(
            OperationOutcome.recoveryRequired,
            'Recover pending transactions before deleting.',
          );
        final record = ProviderLegacyJournal.decode(await reader.text(doc));
        if (_under(record.target.split('/'), target)) legacy.add(record);
      }
      final files = <Map<String, Object?>>[];
      final directories = <List<String>>[];
      Future<void> inventory(
        List<String> path, {
        bool journal = false,
        bool legacyObjects = false,
      }) async {
        if (files.length + directories.length > 10000 || path.length > 16)
          throw const FormatException('Deletion inventory exceeds its limit.');
        final doc = await io.resolve(path);
        if (doc == null) return;
        if (doc.isDirectory) {
          directories.add(path);
          for (final child in await io.documents.children(io.library, doc)) {
            final managed = legacyObjects
                ? _legacyOwns([...path, child.name], legacy)
                : journal
                ? RegExp(
                    r'^(intent\.json|committed\.json|rolled-back\.json|prior-[0-9]+)$',
                  ).hasMatch(child.name)
                : child.name == 'attachments' ||
                      child.name == envelope.last ||
                      (path.last == 'attachments' &&
                          !child.isDirectory &&
                          child.name.endsWith('.med')) ||
                      RegExp(
                        r'^\.future-notes-[a-f0-9-]+-[0-9]+\.(pending|previous|restore|recovered)$',
                      ).hasMatch(child.name);
            if (!managed)
              throw const FormatException(
                'Unknown material inside the managed note folder.',
              );
            await inventory(
              [...path, child.name],
              journal: journal,
              legacyObjects: legacyObjects,
            );
          }
        } else {
          files.add({
            'path': path,
            'revision': (await io.revision(doc)).toJson(),
          });
        }
      }

      await inventory(target);
      final historical = <String>{};
      for (final record in legacy) {
        historical.addAll([
          record.recordPath,
          record.receiptPath,
          '$storage/transactions/${record.transactionId}.resolution',
          record.stagePath,
          '$storage/recovery/${record.objectId}',
          '$storage/sources/${record.objectId}',
        ]);
      }
      for (final path in historical) {
        await inventory(path.split('/'), legacyObjects: true);
      }
      // Include every acknowledged predecessor copy belonging exclusively to
      // this captured storage folder, rather than deriving paths from note IDs.
      final generations = await io.resolve([storage, 'provider-v2']);
      if (generations != null) {
        for (final generation in await io.documents.children(
          io.library,
          generations,
        )) {
          if (!generation.isDirectory || !uuid.hasMatch(generation.name))
            throw const FormatException('Unknown generation journal.');
          final intent = await io.child(generation, 'intent.json');
          if (intent == null) continue;
          final value = await read(intent);
          final paths = (value['objects'] as List)
              .map((o) => ((o as Map)['path'] as List).cast<String>())
              .toList();
          if (paths.any((p) => _under(p, target))) {
            if (!paths.every((p) => _under(p, target)))
              throw const FormatException('Shared recovery generation.');
            await inventory([
              storage,
              'provider-v2',
              generation.name,
            ], journal: true);
          }
        }
      }
      final id = const Uuid().v4();
      final journal = await io.directory([storage, 'provider-deletions', id]);
      final value = <String, Object?>{
        'version': 2,
        'kind': 'delete',
        'id': id,
        'target': target,
        'files': files,
        'directories': directories,
        'legacyRecords': legacy.map((r) => r.encode()).toList(),
      };
      final intent = await metadata(journal, 'intent.json', value);
      final guard = await metadata(transactions, '$id.json', {
        'version': 2,
        'kind': 'delete',
        'id': id,
        'intent': intent.$2.toJson(),
      });
      guarded = true;
      return await resume(guard.$1, await read(guard.$1), guard.$2);
    } catch (_) {
      return OperationResult.failure(
        guarded
            ? OperationOutcome.recoveryRequired
            : OperationOutcome.ioFailure,
        guarded
            ? 'Permanent deletion is pending. Its exact cleanup inventory was retained for recovery.'
            : 'Deletion preparation failed. No removal was authorized.',
      );
    }
  }

  Future<OperationResult<DeletionReport>> resume(
    LibraryDocument guard,
    Map<String, Object?> data,
    ProviderRevision guardRevision,
  ) async {
    final removed = <String>[];
    final pending = <String>[];
    try {
      final id = data['id'] as String;
      if (data['version'] != 2 ||
          data['kind'] != 'delete' ||
          !uuid.hasMatch(id) ||
          guard.name != '$id.json')
        throw const FormatException('Invalid deletion guard.');
      final journal = (await io.resolve([storage, 'provider-deletions', id]))!;
      final intent = (await io.child(journal, 'intent.json'))!;
      if (!ProviderRevision.fromJson(
        Map<String, Object?>.from(data['intent'] as Map),
      ).matches(await io.revision(intent)))
        throw const FormatException('Deletion authorization changed.');
      final value = await read(intent);
      if (value['version'] != 2 ||
          value['id'] != id ||
          value['kind'] != 'delete')
        throw const FormatException('Invalid deletion identity.');
      final target = (value['target'] as List).cast<String>();
      final legacy = ((value['legacyRecords'] ?? const []) as List)
          .cast<String>()
          .map(ProviderLegacyJournal.decode)
          .toList();
      if (legacy.any((r) => !_under(r.target.split('/'), target)))
        throw const FormatException('Unrelated legacy deletion record.');
      if (target.length != 1 ||
          target.first.startsWith('.') ||
          !target.first.startsWith('note_'))
        throw const FormatException('Invalid deletion target.');
      validateDocumentName(target.single);
      final files = (value['files'] as List).cast<Map>();
      final directories = (value['directories'] as List)
          .map((p) => (p as List).cast<String>())
          .toList();
      if (files.length + directories.length > 10000)
        throw const FormatException('Invalid deletion inventory.');
      void validate(List<String> path) {
        if (path.isEmpty ||
            path.length > 16 ||
            (!_under(path, target) &&
                !_legacyOwns(path, legacy) &&
                !(path.length >= 3 &&
                    path[0] == storage &&
                    path[1] == 'provider-v2' &&
                    uuid.hasMatch(path[2]))))
          throw const FormatException('Unrelated deletion object.');
        for (final part in path) {
          validateDocumentName(part);
        }
      }

      // Verify the full remaining graph before resuming any irreversible step.
      for (final file in files) {
        final path = (file['path'] as List).cast<String>();
        validate(path);
        final current = await io.resolve(path);
        if (current != null &&
            (current.isDirectory ||
                !ProviderRevision.fromJson(
                  Map<String, Object?>.from(file['revision'] as Map),
                ).matches(await io.revision(current))))
          throw const FormatException('Deletion revision changed.');
        pending.add(path.join('/'));
      }
      for (final path in directories) {
        validate(path);
      }
      for (final file in files) {
        final path = (file['path'] as List).cast<String>();
        final current = await io.resolve(path);
        if (current != null) {
          if (!ProviderRevision.fromJson(
            Map<String, Object?>.from(file['revision'] as Map),
          ).matches(await io.revision(current)))
            throw const FormatException('Deletion revision changed.');
          await io.documents.delete(io.library, current);
          if (await io.resolve(path) != null)
            throw const FormatException('Removal not acknowledged.');
        }
        removed.add(path.join('/'));
        pending.remove(path.join('/'));
      }
      directories.sort((a, b) => b.length.compareTo(a.length));
      for (final path in directories) {
        final current = await io.resolve(path);
        if (current == null) continue;
        if (!current.isDirectory ||
            (await io.documents.children(io.library, current)).isNotEmpty)
          throw const FormatException(
            'Unexpected directory material retained.',
          );
        await io.documents.delete(io.library, current);
      }
      if (await io.child(journal, 'completed.json') == null)
        await metadata(journal, 'completed.json', {'version': 2, 'id': id});
      if (!guardRevision.matches(
        await io.revision(await io.documents.stat(io.library, guard)),
      ))
        throw const FormatException('Deletion guard changed.');
      await io.documents.delete(io.library, guard);
      return OperationResult.success(DeletionReport(removed, const []));
    } catch (_) {
      return OperationResult.partial(
        OperationOutcome.recoveryRequired,
        'Permanent deletion is incomplete. Changed material and the cleanup journal were retained.',
        DeletionReport(removed, pending),
      );
    }
  }

  Future<Map<String, Object?>> read(LibraryDocument doc) async {
    if (doc.length == null || doc.length! > maxMetadata)
      throw const FormatException('Invalid journal size.');
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in ProviderByteSource(io, doc, doc.length!).open()) {
      bytes.add(chunk);
    }
    return Map<String, Object?>.from(
      jsonDecode(utf8.decode(bytes.takeBytes())) as Map,
    );
  }

  Future<(LibraryDocument, ProviderRevision)> metadata(
    LibraryDocument parent,
    String name,
    Map<String, Object?> data,
  ) async {
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(data)));
    if (bytes.length > maxMetadata)
      throw const FormatException('Deletion journal too large.');
    final doc = await io.documents.create(io.library, parent, name);
    return (doc, await io.write(doc, _Data(bytes)));
  }

  static bool _legacyOwns(List<String> path, List<CommitRecord> records) {
    final encoded = path.join('/');
    for (final r in records) {
      if ([
        r.recordPath,
        r.receiptPath,
        r.stagePath,
        '$storage/transactions/${r.transactionId}.resolution',
      ].contains(encoded))
        return true;
      if (path.length >= 3 && path[0] == storage && path[2] == r.objectId) {
        if (path[1] == 'recovery')
          return path.length == 3 ||
              path.length == 4 &&
                  RegExp(
                    r'^(baseline(\.receipt)?|[a-f0-9]{32}\.previous|[a-f0-9]{32}-[a-f0-9]{32}\.interrupted)$',
                  ).hasMatch(path.last);
        if (path[1] == 'sources')
          return path.length == 3 ||
              path.length >= 4 &&
                  path.length <= 5 &&
                  RegExp(
                    r'^(note|attachment)-operation-[A-Za-z0-9]+$',
                  ).hasMatch(path[3]) &&
                  (path.length == 4 ||
                      RegExp(r'^[A-Za-z0-9_.-]+$').hasMatch(path.last));
      }
    }
    return false;
  }

  static bool _under(List<String> path, List<String> root) =>
      path.length >= root.length &&
      List.generate(root.length, (i) => path[i] == root[i]).every((e) => e);
}

class _Data implements BoundedByteSource {
  _Data(this.bytes);
  final Uint8List bytes;
  @override
  int get length => bytes.length;
  @override
  Stream<List<int>> open() => Stream.value(bytes);
}
