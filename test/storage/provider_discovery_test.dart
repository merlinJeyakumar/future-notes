import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/core/platform/library_documents.dart';
import 'package:flutter_application_1/core/platform/mobile_library_documents.dart';
import 'package:flutter_application_1/features/dashboard/services/background_service.dart';
import 'package:flutter_application_1/features/dashboard/services/encryption_service.dart';
import 'package:flutter_application_1/features/dashboard/services/note_import_service.dart';
import 'package:flutter_application_1/features/dashboard/services/provider_discovery.dart';
import 'package:flutter_application_1/features/dashboard/services/provider_note_files.dart';

import '../support/memory_library_documents.dart';

const _location = LibraryLocation(
  kind: LibraryLocationKind.androidTree,
  token: 'content://synthetic/tree',
);

class _Documents extends MobileLibraryDocuments {
  _Documents() : super(kind: LibraryLocationKind.androidTree);
  final memory = MemoryLibraryDocuments();
  final oversized = <String>{};
  final blocked = <String>{};
  String blockedCode = 'document_io';
  String? folderFailure;
  bool failAfterListing = false;
  Completer<void>? pause;
  @override
  Future<LibraryDocument> root(LibraryLocation library) async {
    if (folderFailure != null) {
      throw LibraryAccessException(folderFailure!, 'Synthetic folder failure');
    }
    return memory.root(library);
  }

  @override
  Future<List<LibraryDocument>> children(
    LibraryLocation library,
    LibraryDocument parent,
  ) async {
    final entries = await memory.children(library, parent);
    if (parent.token == 'root' && failAfterListing) {
      folderFailure = 'document_io';
    }
    return [
      for (final doc in entries)
        LibraryDocument(
          token: doc.token,
          name: doc.name,
          isDirectory: doc.isDirectory,
          length: oversized.contains(doc.name)
              ? 3 * 1024 * 1024 * 1024
              : doc.length,
          modifiedMillis: doc.modifiedMillis,
        ),
    ];
  }

  @override
  Future<Uint8List> read(
    LibraryLocation library,
    LibraryDocument document, {
    required int offset,
    required int length,
  }) async {
    await pause?.future;
    if (blocked.contains(document.name)) {
      throw LibraryAccessException(blockedCode, 'Synthetic file failure');
    }
    return memory.read(library, document, offset: offset, length: length);
  }

  Future<LibraryDocument> seed(
    String name,
    List<int> bytes, {
    LibraryDocument? parent,
    bool directory = false,
  }) async {
    final doc = await memory.create(
      _location,
      parent ?? await memory.root(_location),
      name,
      directory: directory,
    );
    if (!directory) memory.corrupt(doc, bytes);
    return doc;
  }
}

String _note(String id) => jsonEncode({
  'id': id,
  'title': 'Synthetic $id',
  'content': 'Synthetic body',
  'isLocked': false,
  'timestamp': 1700000000000,
  'attachments': [],
});

Future<Object> _scan(ProviderDiscovery discovery) async {
  final result = Completer<Object>();
  final snapshots = discovery.discoveriesStream.listen((value) {
    if (!result.isCompleted) result.complete(value);
  });
  final failures = discovery.failuresStream.listen((value) {
    if (!result.isCompleted) result.complete(value);
  });
  try {
    discovery.loadRecentFiles('synthetic-library');
    return await result.future.timeout(const Duration(seconds: 10));
  } finally {
    await snapshots.cancel();
    await failures.cancel();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Documents documents;
  late ProviderDiscovery discovery;
  late ProviderNoteFiles files;
  final diagnostics = <MethodCall>[];
  setUp(() {
    documents = _Documents();
    files = ProviderNoteFiles(
      documents: documents,
      location: _location,
      libraryId: '11111111-1111-4111-8111-111111111111',
      privateRoot: Directory.systemTemp.path,
    );
    discovery = ProviderDiscovery(files);
    diagnostics.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('future_notes/diagnostics'),
          (call) async {
            diagnostics.add(call);
            return null;
          },
        );
  });
  tearDown(() {
    discovery.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('future_notes/diagnostics'),
          null,
        );
  });

  test(
    'unchanged provider hints reuse rows without reading note bytes; explicit refresh bypasses cache',
    () async {
      await documents.seed('one.enc', utf8.encode(_note('one')));
      final first = await _scan(discovery) as DiscoverySnapshot;
      documents.memory.readBytesByName.clear();
      final second = await _scan(discovery) as DiscoverySnapshot;
      expect(second.files.single, same(first.files.single));
      expect(documents.memory.readBytesByName, isEmpty);
      discovery.invalidateMetadataCache();
      await _scan(discovery);
      expect(documents.memory.readBytesByName['one.enc'], greaterThan(0));
    },
  );

  test(
    'changed envelope identity or size updates inventory and never reads attachments',
    () async {
      final old = await documents.seed('one.enc', utf8.encode(_note('one')));
      await documents.seed('demo.med', [0, 1, 2]);
      await _scan(discovery);
      documents.memory.readBytesByName.clear();
      documents.memory.corrupt(old, utf8.encode(_note('replacement-longer')));
      final result = await _scan(discovery) as DiscoverySnapshot;
      expect(result.files.single.noteId, 'replacement-longer');
      expect(documents.memory.readBytesByName['one.enc'], greaterThan(0));
      // Unrelated files may receive only the existing bounded recognition probe.
      expect(
        documents.memory.readBytesByName['demo.med'] ?? 0,
        lessThanOrEqualTo(256),
      );
      documents.folderFailure = 'permission_revoked';
      expect(await _scan(discovery), isA<DiscoveryFailureEvent>());
    },
  );

  test(
    'mixed folder preserves canonical and arbitrary legacy names without payload scans',
    () async {
      final folder = await documents.seed(
        'note_canonical',
        [],
        directory: true,
      );
      await documents.seed(
        'note_content_canonical.enc',
        utf8.encode(_note('canonical')),
        parent: folder,
      );
      await documents.seed(
        'arbitrary legacy name',
        utf8.encode('  \n${_note('legacy')}'),
      );
      final encrypted = await EncryptionService(
        useNative: false,
      ).encryptApp(_note('encrypted'));
      await documents.seed('renamed without extension', utf8.encode(encrypted));
      await documents.seed('large-backup.fnote', [78, 79, 84, 69, 1, 0]);
      documents.oversized.add('large-backup.fnote');
      await documents.seed('movie.mp4', [0, 0, 0, 18, 102, 116, 121, 112]);
      await documents.seed('archive.zip', [80, 75, 3, 4, 0]);
      await documents.seed('empty unrelated file', []);
      await documents.seed('settings.json', utf8.encode('{}'));
      final before = documents.memory.nodes.keys.toSet();
      final result = await _scan(discovery) as DiscoverySnapshot;
      expect(
        result.files.map((e) => e.noteId),
        containsAll(['canonical', 'legacy', 'encrypted']),
      );
      expect(result.files, hasLength(3));
      expect(documents.memory.readBytesByName['large-backup.fnote'], isNull);
      expect(documents.memory.readBytesByName['movie.mp4'], 8);
      expect(documents.memory.readBytesByName['archive.zip'], 5);
      expect(documents.memory.readBytesByName['settings.json'], isNull);
      expect(documents.memory.nodes.keys.toSet(), before);
    },
  );

  test(
    'damaged, oversized and unreadable notes do not hide valid notes; diagnostics are safe',
    () async {
      await documents.seed('valid.enc', utf8.encode(_note('valid')));
      await documents.seed('damaged.enc', [0, 0, 0]);
      await documents.seed('oversized.enc', []);
      documents.oversized.add('oversized.enc');
      await documents.seed('unreadable.enc', utf8.encode(_note('blocked')));
      documents.blocked.add('unreadable.enc');
      final result = await _scan(discovery) as DiscoverySnapshot;
      expect(result.files.single.noteId, 'valid');
      expect(documents.memory.readBytesByName['oversized.enc'], isNull);
      expect(diagnostics, hasLength(3));
      for (final event in diagnostics) {
        expect(event.arguments['event'], 'DISCOVERY_FAILED');
        expect(
          (event.arguments['metrics'] as Map).values,
          everyElement(isA<num>()),
        );
        expect(event.arguments.toString(), isNot(contains('.enc')));
        expect(event.arguments.toString(), isNot(contains('content://')));
      }
    },
  );

  test(
    'UID import lookup ignores legacy attachment-only folders without note metadata',
    () async {
      final attachmentFolder = await documents.seed(
        'note_legacy',
        [],
        directory: true,
      );
      await documents.seed('payload.med', [1, 2, 3], parent: attachmentFolder);
      await documents.seed('legacy.enc', utf8.encode(_note('legacy')));
      final before = documents.memory.nodes.keys.toSet();
      final found = await NoteImportService(
        files,
        EncryptionService(useNative: false),
      ).find('legacy', files.binding);
      expect(found!.reference.fileName, 'legacy.enc');
      expect(documents.memory.nodes.keys.toSet(), before);
      expect(documents.memory.readBytesByName['payload.med'], isNull);
    },
  );

  test(
    'UID import lookup still rejects a present malformed canonical note',
    () async {
      final folder = await documents.seed('note_existing', [], directory: true);
      await documents.seed('note_content_existing.enc', [
        0,
        1,
        2,
      ], parent: folder);
      final before = documents.memory.nodes.keys.toSet();
      await expectLater(
        NoteImportService(
          files,
          EncryptionService(useNative: false),
        ).find('existing', files.binding),
        throwsFormatException,
      );
      expect(documents.memory.nodes.keys.toSet(), before);
    },
  );

  test(
    'UID import lookup reaches existing notes beside a huge exported backup',
    () async {
      await documents.seed('large-backup.fnote', [78, 79, 84, 69, 1, 0]);
      documents.oversized.add('large-backup.fnote');
      final folder = await documents.seed('note_existing', [], directory: true);
      await documents.seed(
        'note_content_existing.enc',
        utf8.encode(_note('existing')),
        parent: folder,
      );
      final found = await NoteImportService(
        files,
        EncryptionService(useNative: false),
      ).find('existing', files.binding);
      expect(found!.decoded.note.id, 'existing');
      expect(documents.memory.readBytesByName['large-backup.fnote'], isNull);
    },
  );

  test(
    'individual permission denial is silent when the library remains accessible',
    () async {
      await documents.seed('valid.enc', utf8.encode(_note('valid')));
      await documents.seed('unreadable.enc', utf8.encode(_note('blocked')));
      documents.blocked.add('unreadable.enc');
      documents.blockedCode = 'permission_revoked';
      final result = await _scan(discovery) as DiscoverySnapshot;
      expect(result.files.single.noteId, 'valid');
      expect(diagnostics.single.arguments['metrics']['reason'], 2);
    },
  );

  test(
    'folder grant failure emits a failure, never an empty successful snapshot',
    () async {
      documents.folderFailure = 'permission_revoked';
      final result = await _scan(discovery) as DiscoveryFailureEvent;
      expect(result.result.message, contains('Folder permission'));
      expect(diagnostics.single.arguments['metrics']['stage'], 1);
    },
  );

  test(
    'folder outage during a scan does not acknowledge a partial inventory',
    () async {
      await documents.seed('unreadable.enc', utf8.encode(_note('blocked')));
      documents.blocked.add('unreadable.enc');
      documents.failAfterListing = true;
      expect(await _scan(discovery), isA<DiscoveryFailureEvent>());
    },
  );

  test(
    'invalidated scan cannot publish after a delayed read completes',
    () async {
      await documents.seed('valid.enc', utf8.encode(_note('valid')));
      documents.pause = Completer<void>();
      final events = <Object>[];
      final subscription = discovery.discoveriesStream.listen(events.add);
      discovery.loadRecentFiles('synthetic-library');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      discovery.invalidateRequests();
      documents.pause!.complete();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(events, isEmpty);
      await subscription.cancel();
    },
  );
}
