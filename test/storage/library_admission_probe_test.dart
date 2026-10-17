import 'package:flutter/services.dart';
import 'package:flutter_application_1/core/platform/library_documents.dart';
import 'package:flutter_application_1/core/platform/mobile_library_documents.dart';
import 'package:flutter_application_1/core/storage/library_admission_probe.dart';
import 'package:flutter_test/flutter_test.dart';

const library = LibraryLocation(
  kind: LibraryLocationKind.androidTree,
  token: 'content://synthetic/tree/opaque',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('opaque location round trip; rejects path fragments as names', () {
    expect(LibraryLocation.fromJson(library.toJson()).token, library.token);
    for (final name in ['', '.', '..', '../note', 'a/b', r'a\b', 'a\u0000b']) {
      expect(
        () => validateDocumentName(name),
        throwsA(isA<LibraryAccessException>()),
      );
    }
    validateDocumentName('സംഗീതം report @1.pdf');
  });

  test(
    'probe validates readback, changed rename IDs and cleans owned objects',
    () async {
      final backend = _Documents();
      await LibraryAdmissionProbe(backend).verify(library);
      expect(backend.entries.keys, ['root', 'existing-note']);
      expect(backend.entries['existing-note']!.bytes, [17, 29]);
      expect(backend.largestRead, lessThanOrEqualTo(8192));
      expect(backend.renames, 1);
    },
  );

  for (final fault in [
    'short_write',
    'full_disk',
    'permission_revoked',
    'duplicate_name',
    'rename_missing',
  ]) {
    test(
      'provider fault $fault cannot admit or touch existing notes',
      () async {
        final backend = _Documents(fault: fault);
        await expectLater(
          LibraryAdmissionProbe(backend).verify(library),
          throwsA(isA<LibraryAccessException>()),
        );
        expect(backend.entries['existing-note']!.bytes, [17, 29]);
      },
    );
  }

  test(
    'channel enforces bounded ranges and refuses a different backend',
    () async {
      const channel = MethodChannel('synthetic/documents');
      var calls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls++;
            return Uint8List(1);
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      const backend = MobileLibraryDocuments(
        kind: LibraryLocationKind.androidTree,
        channel: channel,
      );
      const doc = LibraryDocument(
        token: 'opaque',
        name: 'file',
        isDirectory: false,
        length: 1,
        modifiedMillis: null,
      );
      for (final range in [
        (-1, 1),
        (0, 0),
        (0, LibraryDocuments.chunkBytes + 1),
      ]) {
        await expectLater(
          backend.read(library, doc, offset: range.$1, length: range.$2),
          throwsA(isA<LibraryAccessException>()),
        );
      }
      await expectLater(
        backend.read(
          const LibraryLocation(
            kind: LibraryLocationKind.fileSystem,
            token: '/tmp',
          ),
          doc,
          offset: 0,
          length: 1,
        ),
        throwsA(isA<LibraryAccessException>()),
      );
      expect(calls, 0);
      expect(await backend.read(library, doc, offset: 0, length: 1), [0]);
      expect(calls, 1);
    },
  );
}

class _Entry {
  _Entry(this.parent, this.document, [List<int> bytes = const []])
    : bytes = Uint8List.fromList(bytes);
  final String? parent;
  final LibraryDocument document;
  Uint8List bytes;
}

class _Documents implements LibraryDocuments {
  _Documents({this.fault}) {
    entries['root'] = _Entry(null, _doc('root', 'root', true));
    entries['existing-note'] = _Entry(
      'root',
      _doc('existing-note', 'note_existing', false),
      [17, 29],
    );
  }
  final String? fault;
  final entries = <String, _Entry>{};
  int next = 0;
  int largestRead = 0;
  int renames = 0;
  LibraryDocument _doc(String token, String name, bool directory) =>
      LibraryDocument(
        token: token,
        name: name,
        isDirectory: directory,
        length: null,
        modifiedMillis: null,
      );

  @override
  Future<LibraryLocation?> selectLocalFolder() async => library;
  @override
  Future<LibraryDocument> root(LibraryLocation library) async =>
      entries['root']!.document;
  @override
  Future<LibraryDocument> stat(
    LibraryLocation library,
    LibraryDocument document,
  ) async {
    final entry = entries[document.token]!;
    return LibraryDocument(
      token: document.token,
      name: document.name,
      isDirectory: document.isDirectory,
      length: entry.bytes.length,
      modifiedMillis: null,
    );
  }

  @override
  Future<List<LibraryDocument>> children(
    LibraryLocation library,
    LibraryDocument parent,
  ) async => entries.values
      .where((entry) => entry.parent == parent.token)
      .map((entry) => entry.document)
      .toList();
  @override
  Future<LibraryDocument> create(
    LibraryLocation library,
    LibraryDocument parent,
    String name, {
    bool directory = false,
  }) async {
    if ((await children(library, parent)).any((doc) => doc.name == name)) {
      if (fault != 'duplicate_name') {
        throw const LibraryAccessException('name_exists', 'Exists');
      }
    }
    final doc = _doc('id-${next++}', name, directory);
    entries[doc.token] = _Entry(parent.token, doc);
    return doc;
  }

  @override
  Future<void> append(
    LibraryLocation library,
    LibraryDocument document,
    Uint8List bytes, {
    required int offset,
  }) async {
    if (fault == 'full_disk' || fault == 'permission_revoked') {
      throw LibraryAccessException(fault!, 'Synthetic failure');
    }
    final entry = entries[document.token]!;
    if (entry.bytes.length != offset) {
      throw const LibraryAccessException('revision_changed', 'Length changed');
    }
    entry.bytes = Uint8List.fromList([...entry.bytes, ...bytes]);
    if (fault == 'short_write') {
      entry.bytes = entry.bytes.sublist(0, entry.bytes.length - 1);
    }
  }

  @override
  Future<Uint8List> read(
    LibraryLocation library,
    LibraryDocument document, {
    required int offset,
    required int length,
  }) async {
    if (length > largestRead) largestRead = length;
    final bytes = entries[document.token]!.bytes;
    if (offset >= bytes.length) return Uint8List(0);
    return bytes.sublist(offset, (offset + length).clamp(0, bytes.length));
  }

  @override
  Future<void> flush(LibraryLocation library, LibraryDocument document) async {}
  @override
  Future<LibraryDocument> rename(
    LibraryLocation library,
    LibraryDocument document,
    String name,
  ) async {
    renames++;
    if (fault == 'rename_missing') {
      throw const LibraryAccessException('rename_failed', 'Synthetic failure');
    }
    final old = entries.remove(document.token)!;
    final doc = _doc('changed-id-${next++}', name, document.isDirectory);
    entries[doc.token] = _Entry(old.parent, doc, old.bytes);
    return doc;
  }

  @override
  Future<void> delete(LibraryLocation library, LibraryDocument document) async {
    if (document.token == 'root' || document.token == 'existing-note') {
      throw StateError('Touched unowned object');
    }
    entries.remove(document.token);
  }
}
