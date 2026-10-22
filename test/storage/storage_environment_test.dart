import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_application_1/core/storage/storage_environment.dart';

import '../support/validation_directory.dart';

void main() {
  late Directory run;
  late String library;
  late String settings;

  setUp(() async {
    run = await createValidationRun();
    library = p.join(run.path, 'library');
    settings = p.join(run.path, 'configuration', 'settings.json');
  });

  tearDown(() async {
    await deleteValidationRun(run);
  });

  StorageEnvironment environment() => StorageEnvironment.validation(
    validationRoot: run.path,
    dataRoot: library,
    settingsFile: settings,
  );

  test('production remains the default only without validation overrides', () {
    expect(StorageEnvironment.fromValues().isValidation, isFalse);
    expect(StorageEnvironment.fromValues(mode: 'false').isValidation, isFalse);
    expect(
      () => StorageEnvironment.fromValues(dataRoot: library),
      throwsArgumentError,
    );
    expect(
      () =>
          StorageEnvironment.fromValues(mode: 'false', settingsFile: settings),
      throwsArgumentError,
    );
    expect(() => StorageEnvironment.fromValues(mode: '1'), throwsArgumentError);
  });

  test('missing validation input never falls back to production', () {
    for (final inputs in [
      ['', library, settings],
      [run.path, '', settings],
      [run.path, library, ''],
    ]) {
      expect(
        () => StorageEnvironment.fromValues(
          mode: 'true',
          validationRoot: inputs[0],
          dataRoot: inputs[1],
          settingsFile: inputs[2],
        ),
        throwsArgumentError,
      );
    }
  });

  test('rejects relative, unnamed, escaping and overlapping locations', () {
    expect(
      () => StorageEnvironment.validation(
        validationRoot: 'future-notes-validation-relative',
        dataRoot: library,
        settingsFile: settings,
      ),
      throwsArgumentError,
    );
    expect(
      () => StorageEnvironment.validation(
        validationRoot: run.parent.path,
        dataRoot: library,
        settingsFile: settings,
      ),
      throwsArgumentError,
    );
    for (final invalidLibrary in [
      run.path,
      p.join(run.parent.path, 'outside'),
      p.join(run.path, '..', 'outside'),
    ]) {
      expect(
        () => StorageEnvironment.validation(
          validationRoot: run.path,
          dataRoot: invalidLibrary,
          settingsFile: settings,
        ),
        throwsArgumentError,
      );
    }
    expect(
      () => StorageEnvironment.validation(
        validationRoot: run.path,
        dataRoot: library,
        settingsFile: p.join(library, 'settings.json'),
      ),
      throwsArgumentError,
    );
    expect(
      () => StorageEnvironment.validation(
        validationRoot: run.path,
        dataRoot: library,
        settingsFile: p.join(run.parent.path, 'settings.json'),
      ),
      throwsArgumentError,
    );
  });

  test('verification performs no directory or settings creation', () async {
    final storage = environment();
    await storage.verifyConfiguredPaths();
    expect(await Directory(library).exists(), isFalse);
    expect(await File(settings).exists(), isFalse);
  });

  test('rejects escaped library filenames and absolute paths', () {
    final storage = environment();
    for (final invalid in [
      '../outside.enc',
      p.join('note_id', '..', '..', 'outside.enc'),
      p.join(run.path, 'outside.enc'),
    ]) {
      expect(() => storage.libraryChild(library, invalid), throwsArgumentError);
    }
    expect(
      storage.libraryChild(library, 'note_id/note_content_id.enc'),
      p.join(library, 'note_id', 'note_content_id.enc'),
    );
  });

  test('validation cannot select its configuration as a library', () {
    final storage = environment();
    expect(
      () => storage.validateLibraryPath(p.dirname(settings)),
      throwsArgumentError,
    );
    expect(
      () => storage.validateLibraryPath(p.join(run.parent.path, 'outside')),
      throwsArgumentError,
    );
  });

  test('refuses a linked child before accessing its destination', () async {
    final target = Directory(p.join(run.path, 'target'));
    await target.create();
    final alias = Link(p.join(run.path, 'alias'));
    await alias.create(target.path);
    final storage = environment();
    await expectLater(
      storage.verifyLocation(p.join(alias.path, 'unopened.enc')),
      throwsStateError,
    );
    expect(await File(p.join(target.path, 'unopened.enc')).exists(), isFalse);
    await alias.delete();
  });
}
