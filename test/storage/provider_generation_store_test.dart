import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_application_1/core/operations/operation_result.dart';
import 'package:flutter_application_1/core/platform/library_documents.dart';
import 'package:flutter_application_1/core/storage/provider_document_io.dart';
import 'package:flutter_application_1/core/storage/provider_generation_store.dart';
import 'package:flutter_test/flutter_test.dart';
import '../support/memory_library_documents.dart';

const location = LibraryLocation(
  kind: LibraryLocationKind.androidTree,
  token: 'content://synthetic/tree/one',
);
const envelope = ['note_opaque', 'note_content_opaque.enc'];
const attachment = ['note_opaque', 'attachments', 'stable-storage-id.med'];

void main() {
  Future<(MemoryLibraryDocuments, ProviderDocumentIo, List<ProviderMutation>)>
  fixture() async {
    final backend = MemoryLibraryDocuments();
    final io = ProviderDocumentIo(backend, location);
    for (final path in [envelope, attachment]) {
      final parent = await io.directory(path.sublist(0, path.length - 1));
      final doc = await backend.create(location, parent, path.last);
      await io.write(doc, _Source('old-${path.last}'));
    }
    final changes = <ProviderMutation>[];
    for (final path in [envelope, attachment]) {
      changes.add(
        ProviderMutation(
          path: path,
          source: _Source('new-${path.last}'),
          expected: await io.revision((await io.resolve(path))!),
          envelope: path == envelope,
        ),
      );
    }
    return (backend, io, changes);
  }

  Future<String> content(ProviderDocumentIo io, List<String> path) async {
    final doc = (await io.resolve(path))!;
    return utf8.decode(
      await ProviderByteSource(
        io,
        doc,
        doc.length!,
      ).open().expand((e) => e).toList(),
    );
  }

  test(
    'attachment-first publication verifies canonical data and removes guard last',
    () async {
      final (backend, io, changes) = await fixture();
      final result = await ProviderGenerationStore(io).commit(changes);
      expect(result.isSuccess, isTrue);
      expect(await content(io, attachment), 'new-${attachment.last}');
      expect(await content(io, envelope), 'new-${envelope.last}');
      expect(
        backend.renames.indexOf(attachment.last),
        lessThan(backend.renames.indexOf(envelope.last)),
      );
      final guards = (await io.resolve([
        '.future-notes-storage',
        'transactions',
      ]))!;
      expect(await backend.children(location, guards), isEmpty);
      expect(
        backend.nodes.length,
        greaterThan(7),
        reason: 'Previous encrypted objects stay recoverable',
      );
    },
  );

  for (final boundary in ProviderCommitBoundary.values) {
    test(
      'interruption at ${boundary.name} recovers one complete generation',
      () async {
        final (_, io, changes) = await fixture();
        final store = ProviderGenerationStore(
          io,
          boundary: (phase, index) async {
            if (phase == boundary) {
              throw StateError('Synthetic process interruption');
            }
          },
        );
        expect((await store.commit(changes)).isSuccess, isFalse);
        expect((await ProviderGenerationStore(io).recover()).isSuccess, isTrue);
        final body = await content(io, envelope);
        final payload = await content(io, attachment);
        expect(body.startsWith('new-'), payload.startsWith('new-'));
        expect(
          (await ProviderGenerationStore(io).recover()).isSuccess,
          isTrue,
          reason: 'Recovery is idempotent',
        );
      },
    );
  }

  test(
    'fully published generation interrupted at receipt is acknowledged on restart',
    () async {
      final (_, io, changes) = await fixture();
      await ProviderGenerationStore(
        io,
        boundary: (phase, index) async {
          if (phase == ProviderCommitBoundary.receipt) {
            throw StateError('Synthetic death');
          }
        },
      ).commit(changes);
      expect((await ProviderGenerationStore(io).recover()).isSuccess, isTrue);
      expect(await content(io, envelope), 'new-${envelope.last}');
    },
  );

  for (final fault in ['short_write', 'full_disk', 'permission_revoked']) {
    test(
      '$fault preserves canonical predecessor and never acknowledges',
      () async {
        final (backend, io, changes) = await fixture();
        backend.fault = fault;
        expect(
          (await ProviderGenerationStore(io).commit(changes)).isSuccess,
          isFalse,
        );
        backend.fault = null;
        expect(await content(io, envelope), 'old-${envelope.last}');
        expect(await content(io, attachment), 'old-${attachment.last}');
      },
    );
  }

  test(
    'revision race preserves external data and keeps pending guard',
    () async {
      final (backend, io, changes) = await fixture();
      final result = await ProviderGenerationStore(
        io,
        boundary: (phase, _) async {
          if (phase == ProviderCommitBoundary.guarded) {
            backend.corrupt(
              (await io.resolve(envelope))!,
              utf8.encode('external-writer'),
            );
          }
        },
      ).commit(changes);
      expect(result.outcome, OperationOutcome.conflict);
      expect(
        (await ProviderGenerationStore(io).recover()).outcome,
        OperationOutcome.recoveryRequired,
      );
      expect(await content(io, envelope), 'external-writer');
    },
  );

  test(
    'duplicate names and damaged backup block recovery without choosing one',
    () async {
      final (backend, io, changes) = await fixture();
      await ProviderGenerationStore(
        io,
        boundary: (phase, _) async {
          if (phase == ProviderCommitBoundary.guarded) {
            throw StateError('Synthetic death');
          }
        },
      ).commit(changes);
      backend.duplicateName((await io.resolve(envelope))!);
      expect(
        (await ProviderGenerationStore(io).recover()).outcome,
        OperationOutcome.recoveryRequired,
      );
      expect(backend.nodes.values.length, greaterThan(1));
    },
  );

  test(
    'unknown desktop transaction is retained and blocks provider writes',
    () async {
      final (backend, io, changes) = await fixture();
      final folder = await io.directory([
        '.future-notes-storage',
        'transactions',
      ]);
      final unknown = await backend.create(location, folder, 'unknown.json');
      await io.write(unknown, _Source('{"version":99}'));
      expect(
        (await ProviderGenerationStore(io).recover()).outcome,
        OperationOutcome.recoveryRequired,
      );
      expect(
        (await ProviderGenerationStore(io).commit(changes)).outcome,
        OperationOutcome.recoveryRequired,
      );
      expect(await content(io, envelope), 'old-${envelope.last}');
    },
  );

  test('source bytes are copied and hashed in bounded windows', () async {
    final backend = MemoryLibraryDocuments();
    final io = ProviderDocumentIo(backend, location);
    final doc = await backend.create(
      location,
      await backend.root(location),
      'synthetic',
    );
    final text = 'x' * (LibraryDocuments.chunkBytes * 2 + 17);
    final result = await io.write(doc, _Source(text));
    expect(result.hash, sha256.convert(utf8.encode(text)).toString());
    expect(backend.largestWrite, LibraryDocuments.chunkBytes);
  });
}

class _Source implements BoundedByteSource {
  _Source(String text) : bytes = utf8.encode(text);
  final List<int> bytes;
  @override
  int get length => bytes.length;
  @override
  Stream<List<int>> open() => Stream.value(bytes);
}
