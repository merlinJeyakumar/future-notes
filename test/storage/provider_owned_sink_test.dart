import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_application_1/core/platform/library_documents.dart';
import 'package:flutter_application_1/core/storage/owned_write.dart';
import 'package:flutter_application_1/core/storage/provider_document_io.dart';
import 'package:flutter_application_1/core/storage/provider_generation_store.dart';
import 'package:flutter_application_1/core/storage/streaming_file_cipher.dart';
import '../support/memory_library_documents.dart';
import '../support/validation_directory.dart';

class _NoRead implements BoundedByteSource {
  _NoRead(this.length);
  @override
  final int length;
  @override
  Stream<List<int>> open() =>
      throw StateError('Owned candidate must not be copied.');
}

class _Metadata implements BoundedByteSource {
  @override
  int get length => 2;
  @override
  Stream<List<int>> open() => Stream.value([123, 125]);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('future_notes/documents');
  const location = LibraryLocation(
    kind: LibraryLocationKind.androidTree,
    token: 'content://synthetic/owned',
  );
  for (final verify in [false, true]) {
    for (final boundary in <ProviderCommitBoundary?>[
      null,
      ...ProviderCommitBoundary.values,
    ]) {
      test(
        'owned provider sink verify=$verify boundary=$boundary never recopies payload',
        () async {
          final run = await createValidationRun();
          final backend = MemoryLibraryDocuments();
          final io = ProviderDocumentIo(backend, location);
          final parent = await io.directory(['note', 'attachments']);
          final doc = await backend.create(
            location,
            parent,
            '.future-notes-owned-synthetic.pending',
          );
          final file = File(p.join(run.path, 'owned-output'));
          await file.create(exclusive: true);
          final sink = LibraryOutputSinkLease(
            library: location,
            document: doc,
            parent: parent,
            lease: 'synthetic-owned-lease',
            path: file.path,
          );
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(channel, (call) async {
                expect(call.method, 'checkOutputSink');
                expect(call.arguments['lease'], sink.lease);
                return <String, Object?>{
                  'token': doc.token,
                  'name': doc.name,
                  'directory': false,
                  'length': await file.length(),
                  'modified': 1,
                };
              });
          try {
            final source = File(p.join(run.path, 'source'));
            await source.writeAsBytes(
              Uint8List.fromList(List.generate(65539, (i) => i % 251)),
            );
            final transformed = await StreamingFileCipher.transform(
              source: StreamingFileSource(source.path, await source.length()),
              destination: file.path,
              decryptSource: false,
              encryptDestination: true,
              useNative: false,
              verifyOutput: verify,
              ownedTarget: OwnedWriteTarget.forSink(sink),
            );
            final receipt = transformed.receipt!;
            backend.corrupt(doc, await file.readAsBytes());
            backend.readBytesByName.clear();
            var interrupted = false;
            final store = ProviderGenerationStore(
              io,
              boundary: (phase, index) async {
                if (phase == boundary) {
                  interrupted = true;
                  throw StateError('Synthetic interruption');
                }
              },
            );
            final result = await store.commit([
              ProviderMutation(
                path: ['note', 'attachments', 'new.med'],
                source: _NoRead(receipt.length),
                expected: null,
                envelope: false,
                verifyReadback: verify,
                ownedCandidate: receipt,
              ),
              ProviderMutation(
                path: ['note', 'note.enc'],
                source: _Metadata(),
                expected: null,
                envelope: true,
              ),
            ]);
            expect(result.isSuccess, boundary == null, reason: result.message);
            expect(interrupted, boundary != null);
            if (boundary == null) {
              expect(
                backend.readBytesByName.entries
                    .where((e) => e.key.endsWith('-0.pending'))
                    .fold<int>(0, (a, b) => a + b.value),
                verify ? greaterThan(0) : 0,
              );
            } else {
              expect(
                (await ProviderGenerationStore(io).recover()).isSuccess,
                isTrue,
              );
            }
            final published = await io.resolve([
              'note',
              'attachments',
              'new.med',
            ]);
            if (published != null)
              expect((await io.revision(published)).hash, receipt.sha256Hex);
            expect(await source.length(), 65539);
          } finally {
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
                .setMockMethodCallHandler(channel, null);
            await deleteValidationRun(run);
          }
        },
      );
    }
  }
}
