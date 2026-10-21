import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_application_1/core/storage/windows_storage_bootstrap.dart';
import '../support/validation_directory.dart';

void main() {
  late Directory run;
  setUp(() async {
    run = await createValidationRun();
  });
  tearDown(() => deleteValidationRun(run));
  test(
    'normal startup captures existing selected library without rewriting settings',
    () async {
      final docs = Directory(p.join(run.path, 'Documents'));
      final settings = File(p.join(docs.path, 'UserData', 'settings.json'));
      await settings.parent.create(recursive: true);
      final library = p.join(run.path, 'existing-library');
      final text = jsonEncode({
        'customDataPath': library,
        'unknown': {'preserved': true},
      });
      await settings.writeAsString(text);
      final result = await WindowsStorageBootstrap.resolve(
        documentsDirectory: () async => docs,
      );
      expect(result.isRecoverable, isTrue);
      expect(result.isValidation, isFalse);
      expect(result.dataRoot, library);
      expect(result.settingsFile, settings.path);
      expect(await settings.readAsString(), text);
      expect(await Directory(library).exists(), isFalse);
    },
  );
  test(
    'fresh normal startup uses original Documents UserData layout',
    () async {
      final docs = Directory(p.join(run.path, 'Documents'));
      final result = await WindowsStorageBootstrap.resolve(
        documentsDirectory: () async => docs,
      );
      expect(result.dataRoot, p.join(docs.path, 'UserData'));
      expect(await docs.exists(), isFalse);
    },
  );
  test(
    'invalid existing configuration never selects a fallback library',
    () async {
      final docs = Directory(p.join(run.path, 'Documents'));
      final settings = File(p.join(docs.path, 'UserData', 'settings.json'));
      await settings.parent.create(recursive: true);
      await settings.writeAsString('{broken');
      await expectLater(
        WindowsStorageBootstrap.resolve(documentsDirectory: () async => docs),
        throwsFormatException,
      );
      expect(await settings.readAsString(), '{broken');
    },
  );
}
