import 'dart:convert';
import 'dart:typed_data';

import 'package:uuid/uuid.dart';
import '../operations/operation_result.dart';
import '../platform/library_documents.dart';
import 'provider_document_io.dart';
import 'provider_deletion_store.dart';
import 'permanent_deletion.dart';
import 'provider_legacy_journal.dart';
import 'commit_record.dart';
import 'provider_legacy_recovery.dart';
import 'owned_write.dart';
import 'file_operation_progress.dart';

enum ProviderCommitBoundary {
  staged,
  backedUp,
  intent,
  guarded,
  retired,
  published,
  receipt,
}

class ProviderMutation {
  const ProviderMutation({
    required this.path,
    required this.source,
    required this.expected,
    required this.envelope,
    this.verifyReadback = true,
    this.expectedSourceHash,
    this.ownedCandidate,
    this.sourceReceipt,
    this.displayName,
  });
  final List<String> path;
  final BoundedByteSource source;
  final ProviderRevision? expected;
  final bool envelope;
  final bool verifyReadback;
  final String? expectedSourceHash;
  final OwnedWriteReceipt? ownedCandidate;
  final OwnedWriteReceipt? sourceReceipt;
  final String? displayName;
}

/// Local/SD publication protocol. Two provider renames are recoverable, never
/// described as atomic. An unknown-version guard blocks desktop 1.4.1 cold-open
/// until all canonical objects form an acknowledged generation or verified prior.
/// This does not coordinate with an already-open, uncooperative external writer.
class ProviderGenerationStore {
  ProviderGenerationStore(this.io, {this.boundary});
  final ProviderDocumentIo io;
  final Future<void> Function(ProviderCommitBoundary, int)? boundary;
  Future<void> _tail = Future.value();
  static const _metadataLimit = 1024 * 1024;
  static const _storage = '.future-notes-storage';
  static final _uuid = RegExp(
    r'^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$',
  );

  Future<T> _serialize<T>(Future<T> Function() action) {
    final operation = _tail.then((_) => action());
    _tail = operation.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return operation;
  }

  Future<OperationResult<String>> commit(
    List<ProviderMutation> mutations, {
    void Function(String, int, int)? onProgress,
    void Function(FileOperationProgress)? onFileProgress,
  }) => _serialize(() => _commit(mutations, onProgress, onFileProgress));

  Future<OperationResult<DeletionReport>> deleteNote(
    List<String> envelope,
    ProviderRevision revision,
  ) => _serialize(() => ProviderDeletionStore(io).delete(envelope, revision));

  Future<OperationResult<String>> _commit(
    List<ProviderMutation> mutations,
    void Function(String, int, int)? onProgress,
    void Function(FileOperationProgress)? onFileProgress,
  ) async {
    var guarded = false;
    final id = const Uuid().v4();
    try {
      if (mutations.isEmpty ||
          mutations.length > 10000 ||
          mutations.where((e) => e.envelope).length != 1) {
        throw const FormatException('One final envelope is required.');
      }
      final names = <String>{};
      for (final mutation in mutations) {
        _validateTarget(mutation.path);
        if (await ProviderDeletionStore(io).blocks(mutation.path)) {
          return const OperationResult.failure(
            OperationOutcome.conflict,
            'This storage identity was permanently deleted. Create a new note instead.',
          );
        }
        if (!names.add(jsonEncode(mutation.path))) {
          throw const FormatException('Duplicate generation target.');
        }
      }
      if (await _guardsExist()) {
        return const OperationResult.failure(
          OperationOutcome.recoveryRequired,
          'Recover pending library transactions before saving.',
        );
      }
      final journal = await io.directory([_storage, 'provider-v2', id]);
      final ordered = [
        ...mutations.where((e) => !e.envelope),
        ...mutations.where((e) => e.envelope),
      ];
      final records = <_Record>[];
      final payloads = ordered.where((e) => !e.envelope).toList();
      final overallTotal = payloads.fold<int>(0, (n, e) => n + e.source.length);
      var completedBytes = 0;
      final candidates = <int, LibraryDocument>{};
      for (var i = 0; i < ordered.length; i++) {
        final item = ordered[i];
        var savedBytes = 0;
        void report(String stage, int bytes, int total) {
          if (bytes > savedBytes)
            savedBytes = bytes.clamp(0, item.source.length);
          onFileProgress?.call(
            FileOperationProgress(
              stage: item.envelope ? 'Finishing import' : stage,
              fileName:
                  item.displayName ??
                  (item.envelope ? 'Note details' : item.path.last),
              fileIndex: item.envelope ? payloads.length : i + 1,
              fileCount: payloads.length,
              bytes: item.envelope ? 0 : bytes,
              total: item.envelope ? 0 : total,
              overallBytes: completedBytes + (item.envelope ? 0 : savedBytes),
              overallTotal: overallTotal,
            ),
          );
          onProgress?.call(stage, bytes, total);
        }

        report(
          item.envelope ? 'Finishing import' : 'Saving encrypted files',
          0,
          item.source.length,
        );
        final parent = await io.directory(
          item.path.sublist(0, item.path.length - 1),
        );
        final current = await io.child(parent, item.path.last);
        if (!await _matches(current, item.expected)) {
          return const OperationResult.failure(
            OperationOutcome.conflict,
            'The library changed before staging.',
          );
        }
        final candidateName = '.future-notes-$id-$i.pending';
        final retiredName = '.future-notes-$id-$i.previous';
        final proof = item.ownedCandidate;
        final transferred = item.sourceReceipt;
        if (!item.verifyReadback &&
            proof == null &&
            (transferred == null ||
                transferred.length != item.source.length ||
                transferred.sha256Hex != item.expectedSourceHash ||
                !await transferred.isCurrent())) {
          throw const FormatException(
            'Unchecked transfer requires a current owned write receipt.',
          );
        }
        late final LibraryDocument candidate;
        late final ProviderRevision next;
        if (proof != null) {
          final sink = proof.target.sink;
          if (sink == null ||
              sink.library.token != io.library.token ||
              sink.parent.token != parent.token ||
              proof.length != item.source.length ||
              !await proof.isCurrent())
            throw const FormatException('Invalid owned provider candidate.');
          final currentCandidate = await io.child(parent, sink.document.name);
          if (currentCandidate?.token != sink.document.token)
            throw const FormatException('Provider candidate identity changed.');
          candidate = await _rename(parent, currentCandidate!, candidateName);
          next = ProviderRevision(proof.length, proof.sha256Hex);
          if (item.verifyReadback &&
              !next.matches(await io.revision(candidate))) {
            throw const FormatException('Owned provider readback failed.');
          }
        } else {
          candidate = await io.documents.create(
            io.library,
            parent,
            candidateName,
          );
          next = await io.write(
            candidate,
            item.source,
            onProgress: report,
            verifyReadback: item.verifyReadback,
            expectedHash: item.expectedSourceHash,
          );
        }
        candidates[i] = await io.documents.stat(io.library, candidate);
        await boundary?.call(ProviderCommitBoundary.staged, i);
        if (current != null) {
          final prior = await io.documents.create(
            io.library,
            journal,
            'prior-$i',
          );
          final copied = await io.write(
            prior,
            ProviderByteSource(io, current, item.expected!.length),
            verifyReadback: item.verifyReadback,
            expectedHash: item.expected!.hash,
            onProgress: (phase, bytes, total) => onProgress?.call(
              'Retaining previous encrypted version',
              bytes,
              total,
            ),
          );
          if (!item.expected!.matches(copied) ||
              !await _matches(
                await io.child(parent, item.path.last),
                item.expected,
              )) {
            return const OperationResult.failure(
              OperationOutcome.conflict,
              'The predecessor changed while creating its recovery copy.',
            );
          }
        }
        records.add(
          _Record(
            item.path,
            item.expected,
            next,
            candidateName,
            retiredName,
            i,
          ),
        );
        await boundary?.call(ProviderCommitBoundary.backedUp, i);
        if (!item.envelope) {
          report(
            'Saving encrypted files',
            item.source.length,
            item.source.length,
          );
          completedBytes += item.source.length;
        }
      }
      final intent = await _metadata(journal, 'intent.json', {
        'version': 2,
        'id': id,
        'objects': records.map((e) => e.toJson()).toList(),
      });
      await boundary?.call(ProviderCommitBoundary.intent, -1);
      final transactions = await io.directory([_storage, 'transactions']);
      final guard = await _metadata(transactions, '$id.json', {
        'version': 2,
        'id': id,
        'intent': intent.$2.toJson(),
      });
      guarded = true;
      await boundary?.call(ProviderCommitBoundary.guarded, -1);
      // Recheck the entire predecessor graph after the durable guard and before
      // any canonical mutation. Retain every recovery object on any ambiguity.
      for (final record in records) {
        if (!await _matches(await io.resolve(record.path), record.before)) {
          return const OperationResult.failure(
            OperationOutcome.conflict,
            'The library changed before publication; recovery material was retained.',
          );
        }
      }
      for (final record in records) {
        final parent = (await io.resolve(record.parent))!;
        final current = await io.child(parent, record.path.last);
        if (current != null) await _rename(parent, current, record.retired);
        await boundary?.call(ProviderCommitBoundary.retired, record.index);
        final candidate = await io.child(parent, record.candidate);
        final fast = !ordered[record.index].verifyReadback;
        final captured = candidates[record.index]!;
        if (candidate == null ||
            (fast
                ? candidate.token != captured.token ||
                      candidate.length != record.after.length ||
                      candidate.modifiedMillis != captured.modifiedMillis
                : !await _matches(candidate, record.after))) {
          throw const FormatException('Staged candidate changed.');
        }
        final renamed = await _rename(parent, candidate, record.path.last);
        final published = await io.child(parent, record.path.last);
        if (fast
            ? published == null ||
                  published.token != renamed.token ||
                  published.length != record.after.length
            : !await _matches(published, record.after)) {
          throw const FormatException('Published readback failed.');
        }
        await boundary?.call(ProviderCommitBoundary.published, record.index);
      }
      await _metadata(journal, 'committed.json', {
        'version': 2,
        'id': id,
        'state': 'committed',
      });
      await boundary?.call(ProviderCommitBoundary.receipt, -1);
      await _removeGuard(guard.$1, guard.$2);
      return OperationResult.success(id);
    } catch (_) {
      return OperationResult.failure(
        guarded
            ? OperationOutcome.recoveryRequired
            : OperationOutcome.ioFailure,
        guarded
            ? 'Publication was interrupted. Recovery objects were retained.'
            : 'Staging failed. Existing canonical notes were preserved.',
      );
    }
  }

  /// Complete an entirely published generation, otherwise restore the complete
  /// verified predecessor graph. Unknown content is never overwritten/deleted.
  Future<OperationResult<void>> recover() => _serialize(_recover);
  Future<OperationResult<void>> _recover() async {
    try {
      final transactions = await io.resolve([_storage, 'transactions']);
      if (transactions == null) return const OperationResult.success();
      // Finish explicit deletions before reading historical v1 records: an
      // interrupted purge may already have removed some of those records.
      for (final candidate in await io.documents.children(
        io.library,
        transactions,
      )) {
        if (!candidate.name.endsWith('.json') ||
            !_uuid.hasMatch(
              candidate.name.substring(0, candidate.name.length - 5),
            ))
          continue;
        final data = await _readMetadata(candidate);
        if (data['kind'] == 'delete') {
          final deleted = await ProviderDeletionStore(
            io,
          ).resume(candidate, data, await io.revision(candidate));
          if (!deleted.isSuccess)
            return OperationResult.failure(deleted.outcome, deleted.message);
        } else if (data['kind'] == 'legacy') {
          await ProviderLegacyRecovery(
            io,
          ).resume(candidate, data, await io.revision(candidate));
        }
      }
      final pending = <CommitRecord>[];
      final legacyReader = ProviderLegacyJournal(io);
      for (final document in await io.documents.children(
        io.library,
        transactions,
      )) {
        if (RegExp(r'^[a-f0-9]{32}\.json$').hasMatch(document.name) &&
            !await legacyReader.acknowledged(document))
          pending.add(
            ProviderLegacyJournal.decode(await legacyReader.text(document)),
          );
      }
      final pendingTargets = <String>{};
      for (final record in pending) {
        if (!pendingTargets.add(record.target.toLowerCase()))
          throw const FormatException(
            'Multiple interrupted generations for one object are ambiguous.',
          );
      }
      for (final record in pending) {
        await ProviderLegacyRecovery(io).restore(record);
      }
      final legacy = <CommitRecord>[];
      for (final guard in await io.documents.children(
        io.library,
        transactions,
      )) {
        if (!guard.name.endsWith('.json')) continue;
        final guardRevision = await io.revision(guard);
        final guardData = await _readMetadata(guard);
        if (guardData['version'] == 1) {
          final reader = ProviderLegacyJournal(io);
          if (!await reader.acknowledged(guard))
            throw const FormatException(
              'An interrupted desktop transaction could not be resolved safely.',
            );
          final record = ProviderLegacyJournal.decode(await reader.text(guard));
          legacy.add(record);
          continue;
        }
        if (guardData['kind'] == 'delete') {
          final deleted = await ProviderDeletionStore(
            io,
          ).resume(guard, guardData, guardRevision);
          if (!deleted.isSuccess)
            return OperationResult.failure(deleted.outcome, deleted.message);
          continue;
        }
        final id = guardData['id'] as String;
        if (guardData['version'] != 2 ||
            !_uuid.hasMatch(id) ||
            guard.name != '$id.json') {
          throw const FormatException('Unknown transaction guard.');
        }
        final journal = await io.resolve([_storage, 'provider-v2', id]);
        if (journal == null) {
          throw const FormatException('Missing provider journal.');
        }
        final intent = await io.child(journal, 'intent.json');
        final expectedIntent = ProviderRevision.fromJson(
          Map<String, Object?>.from(guardData['intent'] as Map),
        );
        if (intent == null ||
            !expectedIntent.matches(await io.revision(intent))) {
          throw const FormatException('Invalid provider journal.');
        }
        final data = await _readMetadata(intent);
        if (data['version'] != 2 || data['id'] != id) {
          throw const FormatException('Invalid transaction identity.');
        }
        final objects = data['objects'] as List;
        if (objects.isEmpty || objects.length > 10000) {
          throw const FormatException('Invalid generation.');
        }
        final records = [
          for (var i = 0; i < objects.length; i++)
            _Record.fromJson(
              Map<String, Object?>.from(objects[i] as Map),
              id,
              i,
            ),
        ];
        final targets = records.map((e) => jsonEncode(e.path)).toSet();
        if (targets.length != records.length) {
          throw const FormatException('Duplicate transaction target.');
        }
        var allPublished = true;
        // Validate the complete graph before beginning rollback.
        for (final record in records) {
          final current = await io.resolve(record.path);
          final isNew = await _matches(current, record.after);
          allPublished &= isNew;
          final isPrior = await _matches(current, record.before);
          if (!isNew && !isPrior && current != null) {
            throw const FormatException('Ambiguous canonical content.');
          }
          if (record.before != null) {
            final prior = await io.child(journal, 'prior-${record.index}');
            if (!await _matches(prior, record.before)) {
              throw const FormatException('Unverified predecessor backup.');
            }
          }
        }
        if (!allPublished) {
          for (final record in records.reversed) {
            final parent = (await io.resolve(record.parent))!;
            final current = await io.child(parent, record.path.last);
            if (await _matches(current, record.before)) continue;
            LibraryDocument? restore;
            if (record.before != null) {
              final name = '.future-notes-$id-${record.index}.restore';
              restore = await io.child(parent, name);
              if (restore == null) {
                restore = await io.documents.create(io.library, parent, name);
                final prior = (await io.child(
                  journal,
                  'prior-${record.index}',
                ))!;
                final revision = await io.write(
                  restore,
                  ProviderByteSource(io, prior, record.before!.length),
                );
                if (!record.before!.matches(revision)) {
                  throw const FormatException('Restore readback failed.');
                }
              } else if (!await _matches(restore, record.before)) {
                throw const FormatException('Ambiguous restore candidate.');
              }
            }
            if (current != null) {
              await _rename(
                parent,
                current,
                '.future-notes-$id-${record.index}.recovered',
              );
            }
            if (restore != null) {
              await _rename(parent, restore, record.path.last);
            }
            if (!await _matches(
              await io.child(parent, record.path.last),
              record.before,
            )) {
              throw const FormatException('Predecessor restoration failed.');
            }
          }
          await _receipt(journal, 'rolled-back.json', id, 'rolledBack');
        } else {
          await _receipt(journal, 'committed.json', id, 'committed');
        }
        await _removeGuard(guard, guardRevision);
      }
      await ProviderLegacyJournal(io).verifyBaselines(legacy);
      return const OperationResult.success();
    } catch (_) {
      return const OperationResult.failure(
        OperationOutcome.recoveryRequired,
        'The library has an ambiguous or unsupported transaction. All recoverable objects were retained.',
      );
    }
  }

  Future<bool> _guardsExist() async {
    final directory = await io.resolve([_storage, 'transactions']);
    if (directory == null) return false;
    for (final document in await io.documents.children(io.library, directory)) {
      if (document.name.endsWith('.json') &&
          !await ProviderLegacyJournal(io).acknowledged(document))
        return true;
    }
    return false;
  }

  Future<bool> _matches(
    LibraryDocument? document,
    ProviderRevision? expected,
  ) async => expected == null
      ? document == null
      : document != null && expected.matches(await io.revision(document));

  Future<LibraryDocument> _rename(
    LibraryDocument parent,
    LibraryDocument document,
    String name,
  ) async {
    if (await io.child(parent, name) != null) {
      throw const FormatException('Rename target is occupied.');
    }
    final renamed = await io.documents.rename(io.library, document, name);
    final found = await io.child(parent, name);
    if (renamed.name != name || found == null || found.token != renamed.token) {
      throw const FormatException(
        'Provider rename did not preserve exact identity.',
      );
    }
    return found;
  }

  Future<(LibraryDocument, ProviderRevision)> _metadata(
    LibraryDocument parent,
    String name,
    Map<String, Object?> value,
  ) async {
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(value)));
    if (bytes.length > _metadataLimit) {
      throw const FormatException('Journal exceeds supported size.');
    }
    final document = await io.documents.create(io.library, parent, name);
    final revision = await io.write(document, _Bytes(bytes));
    return (document, revision);
  }

  Future<Map<String, Object?>> _readMetadata(LibraryDocument document) async {
    if (document.length == null || document.length! > _metadataLimit) {
      throw const FormatException('Invalid journal size.');
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in ProviderByteSource(
      io,
      document,
      document.length!,
    ).open()) {
      bytes.add(chunk);
    }
    return Map<String, Object?>.from(
      jsonDecode(utf8.decode(bytes.takeBytes())) as Map,
    );
  }

  Future<void> _receipt(
    LibraryDocument journal,
    String name,
    String id,
    String state,
  ) async {
    final existing = await io.child(journal, name);
    if (existing == null) {
      await _metadata(journal, name, {'version': 2, 'id': id, 'state': state});
    } else {
      final data = await _readMetadata(existing);
      if (data['version'] != 2 || data['id'] != id || data['state'] != state) {
        throw const FormatException('Invalid completion receipt.');
      }
    }
  }

  Future<void> _removeGuard(
    LibraryDocument guard,
    ProviderRevision revision,
  ) async {
    final fresh = await io.documents.stat(io.library, guard);
    if (!revision.matches(await io.revision(fresh))) {
      throw const FormatException('Transaction guard changed.');
    }
    await io.documents.delete(io.library, guard);
  }

  static void _validateTarget(List<String> path) {
    if (path.isEmpty ||
        path.length > 16 ||
        path.first.startsWith('.future-notes-')) {
      throw const FormatException('Invalid canonical target.');
    }
    for (final part in path) {
      validateDocumentName(part);
    }
  }
}

class _Record {
  const _Record(
    this.path,
    this.before,
    this.after,
    this.candidate,
    this.retired,
    this.index,
  );
  final List<String> path;
  final ProviderRevision? before;
  final ProviderRevision after;
  final String candidate;
  final String retired;
  final int index;
  List<String> get parent => path.sublist(0, path.length - 1);
  Map<String, Object?> toJson() => {
    'path': path,
    'before': before?.toJson(),
    'after': after.toJson(),
    'candidate': candidate,
    'retired': retired,
  };
  factory _Record.fromJson(Map<String, Object?> json, String id, int index) {
    final path = (json['path'] as List).cast<String>();
    ProviderGenerationStore._validateTarget(path);
    final candidate = '.future-notes-$id-$index.pending';
    final retired = '.future-notes-$id-$index.previous';
    if (json['candidate'] != candidate || json['retired'] != retired) {
      throw const FormatException('Invalid transaction object identity.');
    }
    return _Record(
      path,
      json['before'] == null
          ? null
          : ProviderRevision.fromJson(
              Map<String, Object?>.from(json['before'] as Map),
            ),
      ProviderRevision.fromJson(
        Map<String, Object?>.from(json['after'] as Map),
      ),
      candidate,
      retired,
      index,
    );
  }
}

class _Bytes implements BoundedByteSource {
  const _Bytes(this.bytes);
  final Uint8List bytes;
  @override
  int get length => bytes.length;
  @override
  Stream<List<int>> open() => Stream.value(bytes);
}
