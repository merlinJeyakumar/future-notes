import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_application_1/core/storage/note_reference.dart';
import 'package:flutter_application_1/core/storage/storage_environment.dart';
import 'package:flutter_application_1/features/dashboard/services/file_service.dart';
import 'package:flutter_application_1/features/dashboard/services/settings_service.dart';

import '../support/validation_directory.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory run;
  late SettingsService settings;
  late FileService files;
  late String library;

  setUp(() async {
    run = await Directory.systemTemp.createTemp('future-notes-validation-');
    library = p.join(run.path, 'library');
    settings = SettingsService.withStorage(
      storage: StorageEnvironment.validation(
        validationRoot: run.path,
        dataRoot: library,
        settingsFile: p.join(run.path, 'configuration', 'settings.json'),
      ),
      documentsDirectoryResolver: () async {
        throw StateError('Production storage resolution is forbidden.');
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
    'attachment date uses its captured library without reading payloads',
    () async {
      await files.saveNoteContent('synthetic', 'synthetic');
      final reference = (await files.resolveNote('note_synthetic'))!;
      final object = File(p.join(reference.attachmentLocation, 'media.med'));
      await object.parent.create(recursive: true);
      await object.writeAsBytes([1, 2, 3]);
      await object.setLastModified(DateTime(2026, 10, 15, 14, 30));
      final expected = (await object.stat()).modified;
      final other = p.join(run.path, 'other-library');
      await settings.setCustomDataPath(other);
      expect(await files.attachmentModified(reference, 'media'), expected);
      expect(await files.attachmentModified(reference, 'missing'), isNull);
      expect(await object.readAsBytes(), [1, 2, 3]);
      expect(await Directory(other).exists(), isFalse);
    },
  );

  test(
    'attachment metadata rejects traversal and forged storage locations',
    () async {
      await files.saveNoteContent('synthetic', 'synthetic');
      final reference = (await files.resolveNote('note_synthetic'))!;
      await expectLater(
        files.attachmentModified(reference, '../outside'),
        throwsArgumentError,
      );
      final forged = NoteReference(
        binding: reference.binding,
        fileName: reference.fileName,
        format: reference.format,
        contentPath: reference.contentPath,
        attachmentLocation: p.join(run.path, 'outside'),
      );
      await expectLater(
        files.attachmentModified(forged, 'media'),
        throwsArgumentError,
      );
      expect(await Directory(p.join(run.path, 'outside')).exists(), isFalse);
    },
  );

  test(
    'captured folder write remains in its original library after root changes',
    () async {
      await files.saveNoteContent('synthetic-id', 'original synthetic content');
      final reference = (await files.resolveNote(
        'note_synthetic-id',
      ))!.withModelId('persistent-id');
      expect(reference.format, NoteStorageFormat.folder);
      final other = p.join(run.path, 'other-library');
      await settings.setCustomDataPath(other);
      await files.saveNoteContent('synthetic-id', 'other synthetic content');
      await files.writeResolved(
        reference,
        'updated original synthetic content',
      );
      expect(
        await files.readResolved(reference),
        'updated original synthetic content',
      );
      expect(
        await files.readFile('note_synthetic-id'),
        'other synthetic content',
      );
      expect(reference.modelId, 'persistent-id');
      expect(
        reference.attachmentLocation,
        p.join(library, 'note_synthetic-id', 'attachments'),
      );
    },
  );

  test(
    'prefixed legacy filename is resolved as the exact file rather than a new folder',
    () async {
      await files.saveFile(
        'synthetic legacy envelope',
        'note_synthetic-id.enc',
      );
      final reference = (await files.resolveNote(
        'note_synthetic-id.enc',
      ))!.withModelId('persistent-id');
      expect(reference.format, NoteStorageFormat.legacyFile);
      expect(reference.contentPath, p.join(library, 'note_synthetic-id.enc'));
      await files.writeResolved(reference, 'synthetic replacement');
      expect(await files.readResolved(reference), 'synthetic replacement');
      expect(
        await Directory(p.join(library, 'note_synthetic-id.enc')).exists(),
        isFalse,
      );
      expect(
        reference.attachmentLocation,
        p.join(library, 'note_persistent-id', 'attachments'),
      );
    },
  );

  test(
    'missing objects and escaped identifiers are not resolved or published',
    () async {
      expect(await files.resolveNote('missing.enc'), isNull);
      await expectLater(
        files.resolveNote('../outside.enc'),
        throwsArgumentError,
      );
      await expectLater(
        files.newNoteReference('id/../../outside'),
        throwsArgumentError,
      );
      expect(await Directory(library).exists(), isFalse);
    },
  );

  test('forged captured target is rejected before native writing', () async {
    final binding = StorageBinding(library, 1);
    final forged = NoteReference(
      binding: binding,
      fileName: 'outside.enc',
      format: NoteStorageFormat.legacyFile,
      contentPath: p.join(run.path, 'outside.enc'),
      attachmentLocation: library,
    );
    await expectLater(
      files.writeResolved(forged, 'synthetic'),
      throwsArgumentError,
    );
    expect(await File(p.join(run.path, 'outside.enc')).exists(), isFalse);
  });
}
