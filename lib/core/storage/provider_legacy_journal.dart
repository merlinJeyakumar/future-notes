import 'dart:convert';
import 'dart:typed_data';
import '../platform/library_documents.dart';
import 'commit_record.dart';
import 'provider_document_io.dart';

/// Completed desktop v1 records are historical. Validate their acknowledgements
/// and retain them; never restore a completed old generation over a newer note.
class ProviderLegacyJournal {
  ProviderLegacyJournal(this.io);
  final ProviderDocumentIo io;
  static CommitRecord decode(String text) =>
      CommitRecord.decode(text, windowsObjectPaths: true);
  Future<String> text(LibraryDocument document) async {
    if (document.length == null ||
        document.length! > CommitRecord.maxRecordBytes)
      throw const FormatException('Invalid legacy journal size.');
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in ProviderByteSource(
      io,
      document,
      document.length!,
    ).open()) {
      bytes.add(chunk);
    }
    return utf8.decode(bytes.takeBytes());
  }

  Future<bool> acknowledged(LibraryDocument document) async {
    if (!RegExp(r'^[a-f0-9]{32}\.json$').hasMatch(document.name)) return false;
    final record = decode(await text(document));
    if (document.name != '${record.transactionId}.json')
      throw const FormatException('Legacy journal identity changed.');
    final receipt = await io.resolve(record.receiptPath.split('/'));
    final resolution = await io.resolve([
      '.future-notes-storage',
      'transactions',
      '${record.transactionId}.resolution',
    ]);
    final accepted = receipt == null
        ? null
        : CommitReceipt.decode(await text(receipt), record);
    final restored = resolution == null
        ? null
        : CommitReceipt.decode(await text(resolution), record);
    if (restored != null &&
        (restored.disposition != CommitDisposition.restored ||
            accepted?.disposition == CommitDisposition.completed))
      throw const FormatException('Conflicting legacy acknowledgements.');
    return accepted != null || restored != null;
  }

  Future<void> verifyBaselines(Iterable<CommitRecord> records) async {
    final checked = <String>{};
    for (final record in records) {
      if (!record.expected.exists || !checked.add(record.objectId)) continue;
      final proofDoc = await io.resolve(
        '${record.baselinePath}.receipt'.split('/'),
      );
      if (proofDoc == null)
        throw const FormatException('Missing legacy baseline proof.');
      final encoded = await text(proofDoc);
      final proof = jsonDecode(encoded) as Map<String, dynamic>;
      final id = proof['transactionId'] as String;
      if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(id) ||
          jsonEncode({
                'transactionId': id,
                'recordHash': proof['recordHash'],
              }) !=
              encoded)
        throw const FormatException('Invalid legacy baseline proof.');
      final originalDoc = await io.resolve([
        '.future-notes-storage',
        'transactions',
        '$id.json',
      ]);
      if (originalDoc == null)
        throw const FormatException('Missing baseline authorization.');
      final original = decode(await text(originalDoc));
      final baseline = await io.resolve(record.baselinePath.split('/'));
      if (original.recordHash != proof['recordHash'] ||
          original.objectId != record.objectId ||
          !original.expected.exists ||
          baseline == null ||
          !ProviderRevision(
            original.expected.length!,
            original.expected.sha256Hex!,
          ).matches(await io.revision(baseline)))
        throw const FormatException('Legacy baseline changed.');
    }
  }
}
