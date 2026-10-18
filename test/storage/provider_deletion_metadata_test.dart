import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/core/platform/library_documents.dart';
import 'package:flutter_application_1/core/storage/provider_document_io.dart';
import 'package:flutter_application_1/core/storage/provider_generation_store.dart';
import '../support/memory_library_documents.dart';

class _Payload implements BoundedByteSource {
  _Payload(String text) : bytes = utf8.encode(text);
  final List<int> bytes;
  @override
  int get length => bytes.length;
  @override
  Stream<List<int>> open() => Stream.value(bytes);
}

void main() {
  test(
    'completed provider generation deletes using fresh journal metadata',
    () async {
      final backend = MemoryLibraryDocuments();
      const library = LibraryLocation(
        kind: LibraryLocationKind.androidTree,
        token: 'content://synthetic/deletion',
      );
      final io = ProviderDocumentIo(backend, library);
      final store = ProviderGenerationStore(io);
      const note = ['note_synthetic', 'note_content_synthetic.enc'];
      const attachment = ['note_synthetic', 'attachments', 'synthetic.med'];
      final unrelated = await backend.create(
        library,
        await backend.root(library),
        'unrelated.enc',
      );
      await io.write(unrelated, _Payload('preserve'));
      final committed = await store.commit([
        ProviderMutation(
          path: attachment,
          source: _Payload('encrypted payload'),
          expected: null,
          envelope: false,
        ),
        ProviderMutation(
          path: note,
          source: _Payload('encrypted note'),
          expected: null,
          envelope: true,
        ),
      ]);
      expect(committed.isSuccess, isTrue);
      final deleted = await store.deleteNote(
        note,
        await io.revision((await io.resolve(note))!),
      );
      expect(deleted.isSuccess, isTrue, reason: deleted.message);
      expect(await io.resolve(['note_synthetic']), isNull);
      expect(await io.resolve(['unrelated.enc']), isNotNull);
      expect((await store.recover()).isSuccess, isTrue);
      final transactions = (await io.resolve([
        '.future-notes-storage',
        'transactions',
      ]))!;
      expect(await backend.children(library, transactions), isEmpty);
    },
  );
}
