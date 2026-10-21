import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_application_1/core/storage/storage_environment.dart';
import 'package:flutter_application_1/features/dashboard/services/file_service.dart';
import 'package:flutter_application_1/features/dashboard/services/settings_service.dart';

import '../support/validation_directory.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory run;
  late String library;
  late String settingsFile;
  late SettingsService settings;
  late int documentsRequests;

  setUp(() async {
    run = await createValidationRun();
    library = p.join(run.path, 'library');
    settingsFile = p.join(run.path, 'configuration', 'settings.json');
    documentsRequests = 0;
    settings = SettingsService.withStorage(
      storage: StorageEnvironment.validation(
        validationRoot: run.path,
        dataRoot: library,
        settingsFile: settingsFile,
      ),
      documentsDirectoryResolver: () async {
        documentsRequests++;
        throw StateError(
          'Production directory resolution is forbidden in this test.',
        );
      },
    );
  });

  tearDown(() async {
    settings.themeModeNotifier.dispose();
    await deleteValidationRun(run);
  });

  test('initialization and saves never resolve production Documents', () async {
    await settings.init();
    await settings.init();
    expect(await settings.getUserDataPath(), library);
    expect(await settings.getSettingsFilePath(), settingsFile);
    expect(await File(settingsFile).exists(), isFalse);

    await settings.setThemeMode(ThemeMode.light);
    await settings.setCompressionLevel(CompressionLevel.none);

    final saved = jsonDecode(await File(settingsFile).readAsString());
    expect(saved['themeMode'], ThemeMode.light.index);
    expect(saved['compressionLevel'], CompressionLevel.none.index);
    expect(await Directory(library).exists(), isFalse);
    expect(documentsRequests, 0);
  });

  test(
    'copied settings cannot override the explicit validation library',
    () async {
      final file = File(settingsFile);
      await file.parent.create(recursive: true);
      await file.writeAsString(
        jsonEncode({
          'customDataPath': p.join(run.parent.path, 'outside'),
          'themeMode': ThemeMode.light.index,
          'compressionLevel': CompressionLevel.none.index,
        }),
      );

      await settings.init();
      expect(await settings.getUserDataPath(), library);
      expect(settings.customDataPath, isNull);
      expect(settings.themeMode, ThemeMode.light);
      expect(documentsRequests, 0);
    },
  );

  test('refuses configuration changes after initialization starts', () async {
    final initialization = settings.init();
    expect(
      () => settings.configureStorage(const StorageEnvironment.production()),
      throwsStateError,
    );
    await initialization;
    expect(documentsRequests, 0);
  });

  test('library changes cannot leave the disposable run', () async {
    await settings.init();
    await expectLater(
      settings.setCustomDataPath(p.join(run.parent.path, 'outside')),
      throwsArgumentError,
    );
    expect(await settings.getUserDataPath(), library);
    expect(await File(settingsFile).exists(), isFalse);

    final secondLibrary = p.join(run.path, 'second-library');
    await settings.setCustomDataPath(secondLibrary);
    expect(await settings.getUserDataPath(), secondLibrary);
    expect(await settings.getSettingsFilePath(), settingsFile);
    await settings.setCustomDataPath(null);
    expect(await settings.getUserDataPath(), library);
    expect(documentsRequests, 0);
  });

  test(
    'injected file service writes and reads only its isolated library',
    () async {
      await settings.init();
      final files = FileService(settings: settings);
      await files.saveNoteContent(
        'synthetic-id',
        'synthetic ciphertext fixture',
      );
      final contentPath = await settings.getNoteFilePath('synthetic-id');
      expect(p.isWithin(library, contentPath), isTrue);
      expect(
        await files.readFile('note_synthetic-id'),
        'synthetic ciphertext fixture',
      );

      await files.saveFile('synthetic legacy fixture', 'legacy.enc');
      expect(await files.readFile('legacy.enc'), 'synthetic legacy fixture');
      expect(await File(settingsFile).exists(), isFalse);
      expect(documentsRequests, 0);
    },
  );

  test(
    'file-service destination traversal is rejected before writing',
    () async {
      await settings.init();
      final files = FileService(settings: settings);
      await expectLater(
        files.saveFile('synthetic only', '../escape.enc'),
        throwsArgumentError,
      );
      await expectLater(
        settings.getAttachmentFilePath('id', '../../escape'),
        throwsArgumentError,
      );
      expect(await File(p.join(run.path, 'escape.enc')).exists(), isFalse);
      expect(documentsRequests, 0);
    },
  );

  test(
    'production path shapes remain compatible with an injected Documents root',
    () async {
      final production = SettingsService.withStorage(
        storage: const StorageEnvironment.production(),
        documentsDirectoryResolver: () async =>
            Directory(p.join(run.path, 'docs')),
      );
      addTearDown(production.themeModeNotifier.dispose);
      final productionLibrary = p.join(run.path, 'docs', 'UserData');
      expect(
        p.normalize(await production.getUserDataPath()),
        productionLibrary,
      );
      expect(
        await production.getSettingsFilePath(),
        p.join(productionLibrary, 'settings.json'),
      );
      expect(
        await production.getAttachmentFilePath('id', 'attachment'),
        p.join(productionLibrary, 'note_id', 'attachments', 'attachment.med'),
      );
    },
  );
}
