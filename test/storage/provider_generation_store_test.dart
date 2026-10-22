import 'dart:convert';
import 'dart:io';
import 'package:flutter_application_1/core/storage/owned_stream_writer.dart';
import 'package:flutter_application_1/core/storage/owned_write.dart';
import '../support/validation_directory.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_application_1/core/operations/operation_result.dart';
import 'package:flutter_application_1/core/platform/library_documents.dart';
import 'package:flutter_application_1/core/storage/provider_document_io.dart';
import 'package:flutter_application_1/core/storage/provider_generation_store.dart';
import 'package:flutter_application_1/core/storage/file_operation_progress.dart';
import 'package:flutter_test/flutter_test.dart';
import '../support/memory_library_documents.dart';

const location = LibraryLocation(
  kind: LibraryLocationKind.androidTree,
  token: 'content://synthetic/tree/one',
);
const envelope = ['note_opaque', 'note_content_opaque.enc'];
const attachment = ['note_opaque', 'attachments', 'stable-storage-id.med'];

void main() {
  final runs = <Directory>[];
  tearDown(() async {
    for (final run in runs) await deleteValidationRun(run);
    runs.clear();
  });
  Future<(MemoryLibraryDocuments, ProviderDocumentIo, List<ProviderMutation>)>
  fixture({bool verify = true}) async {
    final backend = MemoryLibraryDocuments();
    final io = ProviderDocumentIo(backend, location);
    for (final path in [envelope, attachment]) {
      final parent = await io.directory(path.sublist(0, path.length - 1));
      final doc = await backend.create(location, parent, path.last);
      await io.write(doc, _Source('old-${path.last}'));
    }
    final changes = <ProviderMutation>[];
    for (final path in [envelope, attachment]) {
      OwnedWriteReceipt? receipt;
      if (!verify) {
        final run = await createValidationRun();
        runs.add(run);
        final output = await OwnedStreamWriter.open('${run.path}/payload');
        await output.add(utf8.encode('new-${path.last}'));
        receipt = await output.close();
      }
      changes.add(
        ProviderMutation(
          path: path,
          source: _Source('new-${path.last}'),
          expected: await io.revision((await io.resolve(path))!),
          envelope: path == envelope,
          verifyReadback: verify,
          sourceReceipt: receipt,
          expectedSourceHash: sha256
              .convert(utf8.encode('new-${path.last}'))
              .toString(),
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
    'publication reports named files and cumulative byte-weighted saving',
    () async {
      final backend = MemoryLibraryDocuments();
      final io = ProviderDocumentIo(backend, location);
      final events = <FileOperationProgress>[];
      final result = await ProviderGenerationStore(io).commit([
        ProviderMutation(
          path: [...attachment.take(2), 'one.med'],
          source: _Source('a' * 23),
          expected: null,
          envelope: false,
          displayName: 'One.txt',
        ),
        ProviderMutation(
          path: [...attachment.take(2), 'two.med'],
          source: _Source('b' * 101),
          expected: null,
          envelope: false,
          displayName: 'Two.mp4',
        ),
        ProviderMutation(
          path: envelope,
          source: _Source('{}'),
          expected: null,
          envelope: true,
        ),
      ], onFileProgress: events.add);
      expect(result.isSuccess, isTrue, reason: result.message);
      final files = events.where((e) => e.total > 0).toList();
      expect(files.map((e) => e.fileName).toSet(), {'One.txt', 'Two.mp4'});
      expect(
        files.every((e) => e.fileCount == 2 && e.overallTotal == 124),
        isTrue,
      );
      final second = files.where((e) => e.fileIndex == 2).toList();
      expect(second.first.bytes, 0);
      expect(second.first.overallBytes, 23);
      expect(second.last.overallBytes, 124);
      for (var i = 1; i < files.length; i++) {
        expect(
          files[i].overallBytes,
          greaterThanOrEqualTo(files[i - 1].overallBytes),
        );
      }
      expect(events.last.stage, 'Finishing import');
      expect(events.last.total, 0);
      expect(events.last.overallBytes, 124);
    },
  );

  for (final verify in [false, true]) {
    test(
      'provider fallback verify=$verify has only necessary transfer reads',
      () async {
        final (backend, io, changes) = await fixture(verify: verify);
        backend.readBytesByName.clear();
        expect(
          (await ProviderGenerationStore(io).commit(changes)).isSuccess,
          isTrue,
        );
        final candidates = backend.readBytesByName.entries.where(
          (e) => e.key.endsWith('.pending'),
        );
        expect(
          candidates.fold<int>(0, (n, e) => n + e.value),
          verify ? greaterThan(0) : 0,
        );
        expect(await content(io, attachment), 'new-${attachment.last}');
      },
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

  for (final verify in [false, true]) {
    for (final boundary in ProviderCommitBoundary.values) {
      test(
        'verify=$verify interruption at ${boundary.name} recovers one complete generation',
        () async {
          final (_, io, changes) = await fixture(verify: verify);
          final store = ProviderGenerationStore(
            io,
            boundary: (phase, index) async {
              if (phase == boundary) {
                throw StateError('Synthetic process interruption');
              }
            },
          );
          expect((await store.commit(changes)).isSuccess, isFalse);
          expect(
            (await ProviderGenerationStore(io).recover()).isSuccess,
            isTrue,
          );
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

  for (final verify in [false, true]) {
    test(
      'predecessor copy readback follows job policy verify=$verify',
      () async {
        final (backend, io, changes) = await fixture(verify: verify);
        final result = await ProviderGenerationStore(io).commit(changes);
        expect(result.isSuccess, isTrue, reason: result.message);
        final priorReadBytes = backend.readBytesByName.entries
            .where((entry) => entry.key.startsWith('prior-'))
            .fold<int>(0, (total, entry) => total + entry.value);
        expect(priorReadBytes, verify ? greaterThan(0) : 0);
        expect(await content(io, envelope), 'new-${envelope.last}');
      },
    );
  }

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
