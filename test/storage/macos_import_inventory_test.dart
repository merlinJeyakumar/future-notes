import 'dart:convert';
import 'dart:io';

import 'package:flutter_application_1/core/storage/owned_app_services.dart';
import 'package:flutter_application_1/core/storage/storage_environment.dart';
import 'package:flutter_application_1/features/dashboard/models/note_import.dart';
import 'package:flutter_application_1/features/dashboard/services/encryption_service.dart';
import 'package:flutter_application_1/features/dashboard/services/macos_file_service.dart';
import 'package:flutter_application_1/features/dashboard/services/pack_service.dart';
import 'package:flutter_application_1/features/dashboard/services/streaming_pack_service.dart';
import 'package:flutter_application_1/features/dashboard/viewmodels/content_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../support/validation_directory.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory run;
  late OwnedAppServices app;
  late ContentViewModel editor;
  late EncryptionService cipher;

  setUp(() async {
    run = await createValidationRun('future-notes-validation-mac-import-');
    app = OwnedAppServices(
      environment: StorageEnvironment.validation(
        validationRoot: run.path,
        dataRoot: p.join(run.path, 'library'),
        settingsFile: p.join(run.path, 'configuration', 'settings.json'),
      ),
      createFiles: (settings, owner) =>
          MacosFileService(settings: settings, storageOwner: owner),
    );
    expect((await app.initialize()).isSuccess, isTrue);
    cipher = EncryptionService();
    editor = ContentViewModel(
      fileService: app.files,
      settings: app.settings,
      encryptionService: cipher,
      startBackgroundServices: false,
    );
  });

  tearDown(() async {
    editor.dispose();
    await editor.closeLibraryResources();
    expect((await app.close()).isSuccess, isTrue);
    await deleteValidationRun(run);
  });

  for (final finderFiles in <List<String>>[
    [],
    ['.DS_Store'],
    ['._demo.fnote', '._note_fixture'],
  ]) {
    test('UID choices ignore Finder bookkeeping $finderFiles', () async {
      final metadata = <String, dynamic>{
        'id': 'synthetic-mac-import-id',
        'title': 'Synthetic import',
        'content': jsonEncode([
          {'insert': 'Synthetic body\n'},
        ]),
        'timestamp': 1700000000000,
        'isLocked': false,
        'attachments': [],
      };
      final reference = await app.files.newNoteReference('fixture');
      final original = File(reference.contentPath);
      await original.parent.create(recursive: true);
      final encoded = await cipher.encryptApp(jsonEncode(metadata));
      await original.writeAsString(encoded, flush: true);
      await File(p.join(reference.binding.root, '.legacy.enc')).writeAsString(
        await cipher.encryptApp(jsonEncode({...metadata, 'id': 'other-id'})),
        flush: true,
      );
      final finderBytes = [0, 0, 0, 1, 0xff, 0xfe, 0x80];
      for (final name in finderFiles) {
        await File(
          p.join(reference.binding.root, name),
        ).writeAsBytes(finderBytes, flush: true);
      }
      final source = p.join(run.path, 'demo.fnote');
      final staging = await Directory(p.join(run.path, 'packing')).create();
      await StreamingPackService().exportPackage(
        metadata: metadata,
        attachments: const {},
        format: ExportFormat.binary,
        destination: source,
        operationDirectory: staging.path,
      );
      var choices = 0;
      final result = await editor.importNoteFile(
        source,
        resolveConflict: (conflict) async {
          choices++;
          expect(conflict.reference.fileName, reference.fileName);
          return NoteImportDecision.ignore;
        },
      );
      expect(result.isSuccess, isTrue, reason: result.message);
      expect(choices, 1);
      expect(result.value!.disposition, NoteImportDisposition.ignored);
      expect(await app.files.getRecentFiles(), contains('.legacy.enc'));
      expect(await original.readAsString(), encoded);
      for (final name in finderFiles) {
        expect(
          await File(p.join(reference.binding.root, name)).readAsBytes(),
          finderBytes,
        );
      }
    });
  }

  test('canonical unreadable note remains an import failure', () async {
    await File(
      p.join(app.environment.dataRoot!, 'unreadable.enc'),
    ).writeAsBytes([0xff, 0xfe, 0x80], flush: true);
    final source = p.join(run.path, 'demo.fnote');
    final staging = await Directory(p.join(run.path, 'packing')).create();
    await StreamingPackService().exportPackage(
      metadata: {
        'id': 'synthetic-mac-import-id',
        'title': 'Synthetic import',
        'content': jsonEncode([
          {'insert': 'Synthetic body\n'},
        ]),
        'timestamp': 1700000000000,
        'isLocked': false,
        'attachments': [],
      },
      attachments: const {},
      format: ExportFormat.binary,
      destination: source,
      operationDirectory: staging.path,
    );
    var choices = 0;
    final result = await editor.importNoteFile(
      source,
      resolveConflict: (_) async {
        choices++;
        return NoteImportDecision.ignore;
      },
    );
    expect(result.isSuccess, isFalse);
    expect(choices, 0);
    expect(
      await File(
        p.join(app.environment.dataRoot!, 'unreadable.enc'),
      ).readAsBytes(),
      [0xff, 0xfe, 0x80],
    );
  });
}
