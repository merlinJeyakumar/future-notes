import 'dart:convert';
import 'dart:typed_data';
import 'package:uuid/uuid.dart';
import '../platform/library_documents.dart';
import 'commit_record.dart';
import 'native_storage_primitives.dart';
import 'provider_document_io.dart';
import 'provider_legacy_journal.dart';

/// Recover an interrupted Windows generation through bounded provider access.
/// Its v1 intent is retained unchanged. A v2 guard prevents an older reader from
/// observing the provider's non-atomic rename interval. Ambiguity never selects
/// a winner; verified previous and interrupted ciphertext remain recoverable.
class ProviderLegacyRecovery {
  ProviderLegacyRecovery(this.io);
  final ProviderDocumentIo io;
  static const storage = '.future-notes-storage';
  static final uuid = RegExp(
    r'^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$',
  );
  ProviderRevision? revision(StorageRevision r) =>
      r.exists ? ProviderRevision(r.length!, r.sha256Hex!) : null;
  Future<bool> matches(
    LibraryDocument? doc,
    ProviderRevision? expected,
  ) async => expected == null
      ? doc == null
      : doc != null &&
            !doc.isDirectory &&
            expected.matches(await io.revision(doc));

  Future<void> restore(CommitRecord record) async {
    await _validateGraph(record);
    final id = const Uuid().v4();
    final journal = await io.directory([storage, 'provider-legacy', id]);
    final intent = await _metadata(journal, 'intent.json', {
      'version': 2,
      'kind': 'legacy',
      'id': id,
      'record': record.encode(),
    });
    final guards = await io.directory([storage, 'transactions']);
    final guard = await _metadata(guards, '$id.json', {
      'version': 2,
      'kind': 'legacy',
      'id': id,
      'intent': intent.$2.toJson(),
    });
    await resume(guard.$1, await _read(guard.$1), guard.$2);
  }

  Future<void> _validateGraph(CommitRecord record) async {
    final reader = ProviderLegacyJournal(io);
    final original = await io.resolve(record.recordPath.split('/'));
    if (original == null || await reader.text(original) != record.encode())
      throw const FormatException('Legacy intent changed.');
    final current = await io.resolve(record.target.split('/'));
    final prior = await io.resolve(record.previousPath.split('/'));
    final staged = await io.resolve(record.stagePath.split('/'));
    final expected = revision(record.expected);
    final next = revision(record.staged);
    if (prior != null && !await matches(prior, expected))
      throw const FormatException('Legacy predecessor changed.');
    if (staged != null && !await matches(staged, next))
      throw const FormatException('Legacy candidate changed.');
    final oldCurrent = await matches(current, expected);
    if (current != null && !oldCurrent && !await matches(current, next))
      throw const FormatException('Ambiguous legacy canonical content.');
    if (expected != null && !oldCurrent && prior == null)
      throw const FormatException('Legacy predecessor is unavailable.');
  }

  Future<void> resume(
    LibraryDocument guard,
    Map<String, Object?> data,
    ProviderRevision guardRevision,
  ) async {
    final id = data['id'] as String;
    if (data['version'] != 2 ||
        data['kind'] != 'legacy' ||
        !uuid.hasMatch(id) ||
        guard.name != '$id.json')
      throw const FormatException('Invalid legacy recovery guard.');
    final journal = (await io.resolve([storage, 'provider-legacy', id]))!;
    final intent = (await io.child(journal, 'intent.json'))!;
    if (!ProviderRevision.fromJson(
      Map<String, Object?>.from(data['intent'] as Map),
    ).matches(await io.revision(intent)))
      throw const FormatException('Legacy recovery authorization changed.');
    final value = await _read(intent);
    if (value['version'] != 2 || value['kind'] != 'legacy' || value['id'] != id)
      throw const FormatException('Invalid legacy recovery identity.');
    final record = ProviderLegacyJournal.decode(value['record'] as String);
    final reader = ProviderLegacyJournal(io);
    final original = (await io.resolve(record.recordPath.split('/')))!;
    if (await reader.text(original) != record.encode())
      throw const FormatException('Legacy intent changed during recovery.');
    if (await reader.acknowledged(original)) {
      await reader.verifyBaselines([record]);
      await _removeGuard(guard, guardRevision);
      return;
    }
    await _validateGraph(record);
    final target = record.target.split('/');
    final parent = await io.directory(target.sublist(0, target.length - 1));
    final expected = revision(record.expected);
    var current = await io.child(parent, target.last);
    if (!await matches(current, expected)) {
      LibraryDocument? restore;
      if (expected != null) {
        final previous = (await io.resolve(record.previousPath.split('/')))!;
        await _baseline(record, previous);
        final name = '.future-notes-$id-0.restore';
        restore = await io.child(parent, name);
        if (restore == null) {
          restore = await io.documents.create(io.library, parent, name);
          if (!expected.matches(
            await io.write(
              restore,
              ProviderByteSource(io, previous, expected.length),
            ),
          ))
            throw const FormatException('Legacy restore readback failed.');
        } else if (!await matches(restore, expected)) {
          throw const FormatException('Ambiguous legacy restore candidate.');
        }
      }
      // The captured candidate may already have been retained by an interrupted
      // earlier recovery. Never replace a second observed canonical revision.
      current = await io.child(parent, target.last);
      if (current != null) {
        if (!await matches(current, revision(record.staged)))
          throw const FormatException(
            'Legacy target changed before restoration.',
          );
        final retainedName = '.future-notes-$id-0.recovered';
        if (await io.child(parent, retainedName) != null)
          throw const FormatException('Interrupted version is ambiguous.');
        await _rename(parent, current, retainedName);
      }
      if (restore != null) await _rename(parent, restore, target.last);
    } else if (expected != null) {
      await _baseline(record, current!);
    }
    final restored = await io.child(parent, target.last);
    if (!await matches(restored, expected))
      throw const FormatException('Legacy restoration was not acknowledged.');
    final published = expected == null
        ? const StorageRevision.missing()
        : StorageRevision.present(expected.length, expected.hash, 0);
    await _metadata(
      await io.directory([storage, 'transactions']),
      '${record.transactionId}.resolution',
      Map<String, Object?>.from(
        jsonDecode(
              CommitReceipt(
                record,
                CommitDisposition.restored,
                published,
              ).encode(),
            )
            as Map,
      ),
    );
    if (!await reader.acknowledged(original))
      throw const FormatException('Legacy resolution verification failed.');
    await _metadata(journal, 'completed.json', {
      'version': 2,
      'kind': 'legacy',
      'id': id,
    });
    await _removeGuard(guard, guardRevision);
  }

  Future<void> _baseline(CommitRecord record, LibraryDocument source) async {
    final proof = await io.resolve('${record.baselinePath}.receipt'.split('/'));
    if (proof != null) {
      await ProviderLegacyJournal(io).verifyBaselines([record]);
      return;
    }
    final path = record.baselinePath.split('/');
    final parent = await io.directory(path.sublist(0, path.length - 1));
    var baseline = await io.child(parent, path.last);
    final expected = revision(record.expected)!;
    if (baseline == null) {
      baseline = await io.documents.create(io.library, parent, path.last);
      if (!expected.matches(
        await io.write(
          baseline,
          ProviderByteSource(io, source, expected.length),
        ),
      ))
        throw const FormatException('Legacy baseline readback failed.');
    } else if (!await matches(baseline, expected)) {
      throw const FormatException('Unverified legacy baseline retained.');
    }
    await _metadata(parent, '${path.last}.receipt', {
      'transactionId': record.transactionId,
      'recordHash': record.recordHash,
    });
    await ProviderLegacyJournal(io).verifyBaselines([record]);
  }

  Future<void> _rename(
    LibraryDocument parent,
    LibraryDocument source,
    String name,
  ) async {
    if (await io.child(parent, name) != null)
      throw const FormatException('Recovery destination is occupied.');
    final renamed = await io.documents.rename(io.library, source, name);
    final acknowledged = await io.child(parent, name);
    if (renamed.name != name || renamed.token != acknowledged?.token)
      throw const FormatException('Recovery rename not acknowledged.');
  }

  Future<void> _removeGuard(
    LibraryDocument doc,
    ProviderRevision revision,
  ) async {
    if (!revision.matches(
      await io.revision(await io.documents.stat(io.library, doc)),
    ))
      throw const FormatException('Recovery guard changed.');
    await io.documents.delete(io.library, doc);
  }

  Future<Map<String, Object?>> _read(LibraryDocument doc) async =>
      Map<String, Object?>.from(
        jsonDecode(await ProviderLegacyJournal(io).text(doc)) as Map,
      );
  Future<(LibraryDocument, ProviderRevision)> _metadata(
    LibraryDocument parent,
    String name,
    Map<String, Object?> value,
  ) async {
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(value)));
    if (bytes.length > 64 * 1024)
      throw const FormatException('Recovery metadata exceeds its limit.');
    final existing = await io.child(parent, name);
    if (existing != null) {
      if (await ProviderLegacyJournal(io).text(existing) != utf8.decode(bytes))
        throw const FormatException('Existing recovery metadata differs.');
      return (existing, await io.revision(existing));
    }
    final doc = await io.documents.create(io.library, parent, name);
    return (doc, await io.write(doc, _Bytes(bytes)));
  }
}

class _Bytes implements BoundedByteSource {
  _Bytes(this.bytes);
  final Uint8List bytes;
  @override
  int get length => bytes.length;
  @override
  Stream<List<int>> open() => Stream.value(bytes);
}
