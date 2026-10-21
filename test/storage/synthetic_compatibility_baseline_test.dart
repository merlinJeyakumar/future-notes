import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_application_1/core/storage/storage_environment.dart';
import 'package:flutter_application_1/features/dashboard/models/note_model.dart';
import 'package:flutter_application_1/features/dashboard/services/encryption_service.dart';
import 'package:flutter_application_1/features/dashboard/services/file_service.dart';
import 'package:flutter_application_1/features/dashboard/services/pack_service.dart';
import 'package:flutter_application_1/features/dashboard/services/settings_service.dart';

import '../support/synthetic_note_fixtures.dart';
import '../support/validation_directory.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final encryption = EncryptionService();
  late SyntheticNoteFixtures fixtures;
  late Directory run;
  late SettingsService settings;
  late FileService files;

  setUpAll(() async {
    fixtures = await SyntheticNoteFixtures.create(encryption);
  });

  setUp(() async {
    run = await createValidationRun();
    settings = SettingsService.withStorage(
      storage: StorageEnvironment.validation(
        validationRoot: run.path,
        dataRoot: p.join(run.path, 'library'),
        settingsFile: p.join(run.path, 'configuration', 'settings.json'),
      ),
      documentsDirectoryResolver: () async {
        throw StateError(
          'A synthetic fixture must not resolve production storage.',
        );
      },
    );
    await settings.init();
    files = FileService(settings: settings);
  });

  tearDown(() async {
    settings.themeModeNotifier.dispose();
    await deleteValidationRun(run);
  });

  test(
    'existing folder envelope is readable without modifying its bytes',
    () async {
      await files.saveNoteContent(
        SyntheticNoteFixtures.noteId,
        fixtures.currentEnvelope,
      );
      final stored = await files.readFile(
        'note_${SyntheticNoteFixtures.noteId}',
      );
      expect(stored, fixtures.currentEnvelope);
      final decoded = jsonDecode(await encryption.decryptApp(stored!));
      expect(decoded, fixtures.rawNote);
      expect(
        await files.readFile('note_${SyntheticNoteFixtures.noteId}'),
        fixtures.currentEnvelope,
      );
    },
  );

  test(
    'plaintext legacy, HTML and legacy attachment declarations stay unchanged',
    () async {
      final envelopes = {
        'legacy.enc': fixtures.legacyJson,
        'html.enc': fixtures.htmlLegacyJson,
        'legacy-attachments.enc': fixtures.legacyAttachmentJson,
      };
      for (final entry in envelopes.entries) {
        await files.saveFile(entry.value, entry.key);
        expect(await files.readFile(entry.key), entry.value);
      }
    },
  );

  test(
    'password fixture retains its body and original encrypted envelope',
    () async {
      await files.saveNoteContent(
        SyntheticNoteFixtures.noteId,
        fixtures.protectedEnvelope,
      );
      final envelope = await files.readFile(
        'note_${SyntheticNoteFixtures.noteId}',
      );
      final note = NoteModel.fromJson(
        jsonDecode(await encryption.decryptApp(envelope!))
            as Map<String, dynamic>,
      );
      expect(note.isLocked, isTrue);
      expect(
        await encryption.decrypt(note.content, password: fixtures.password),
        fixtures.rawNote['content'],
      );
      expect(
        await files.readFile('note_${SyntheticNoteFixtures.noteId}'),
        fixtures.protectedEnvelope,
      );
    },
  );

  test(
    'encrypted attachment fixtures round trip through isolated object storage',
    () async {
      final original =
          fixtures.encryptedAttachments[SyntheticNoteFixtures.attachmentId]!;
      final id = await files.saveAttachment(
        original,
        SyntheticNoteFixtures.noteId,
      );
      final stored = await files.readAttachment(
        SyntheticNoteFixtures.noteId,
        id,
      );
      expect(stored, original);
      expect(
        await encryption.decryptBinary(stored!),
        Uint8List.fromList([0, 1, 127, 128, 255]),
      );
    },
  );

  test(
    'existing binary and ZIP packages preserve all ciphertext fixture objects',
    () async {
      final packs = PackService(encryption);
      final binary = await packs.createPack(
        fixtures.note,
        fixtures.encryptedAttachments,
        password: fixtures.password,
      );
      final zip = await packs.createZipPack(
        fixtures.note,
        fixtures.encryptedAttachments,
        password: fixtures.password,
      );
      final results = [
        await packs.extractPack(binary, password: fixtures.password),
        await packs.extractZipPack(zip, password: fixtures.password),
      ];
      for (final result in results) {
        expect(result, isNotNull);
        expect(result!.note.id, SyntheticNoteFixtures.noteId);
        expect(result.note.content, fixtures.rawNote['content']);
        expect(
          result.attachments.keys.toSet(),
          fixtures.encryptedAttachments.keys.toSet(),
        );
        for (final entry in fixtures.encryptedAttachments.entries) {
          expect(result.attachments[entry.key], entry.value);
        }
      }
    },
  );
}
