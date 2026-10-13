import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_application_1/core/operations/operation_result.dart';
import 'package:flutter_application_1/core/storage/owned_app_services.dart';
import 'package:flutter_application_1/core/storage/owned_note_persistence.dart';
import 'package:flutter_application_1/core/storage/storage_environment.dart';
import 'package:flutter_application_1/core/storage/storage_owner_worker.dart';
import 'package:flutter_application_1/core/storage/validation_app_services.dart';
import 'package:flutter_application_1/features/dashboard/viewmodels/content_viewmodel.dart';

import '../support/editor_harness.dart' show SyntheticCipher;
import '../support/validation_directory.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('native storage integration', () {
    late Directory run;
    late String library;
    late File configuration;
    late StorageEnvironment environment;
    OwnedAppServices? services;

    setUp(() async {
      services = null;
      run = await Directory.systemTemp.createTemp('future-notes-validation-');
      library = p.join(run.path, 'UserData');
      configuration = File(p.join(library, 'settings.json'));
      environment = StorageEnvironment.recoverable(
        dataRoot: library,
        settingsFile: configuration.path,
      );
    });

    tearDown(() async {
      final current = services;
      if (current != null) expect((await current.close()).isSuccess, isTrue);
      await deleteValidationRun(run);
    });

    Future<OwnedAppServices> initialize() async {
      final current = OwnedAppServices(environment: environment);
      services = current;
      final result = await current.initialize();
      expect(result.isSuccess, isTrue, reason: result.message);
      return current;
    }

    test('default writer and validation admission remain separate', () {
      expect(StorageEnvironment.fromValues().hasOwnedStorage, isFalse);
      expect(environment.isRecoverable, isTrue);
      expect(environment.isValidation, isFalse);
      expect(
        () => ValidationAppServices(environment: environment),
        throwsArgumentError,
      );
      expect(
        () => StorageEnvironment.fromValues(
          mode: 'true',
          recoverableMode: 'true',
          validationRoot: run.path,
          dataRoot: library,
          settingsFile: configuration.path,
        ),
        throwsArgumentError,
      );
      expect(
        () => StorageEnvironment.fromValues(recoverableMode: 'true'),
        throwsArgumentError,
      );
    });

    test(
      'root capabilities cannot admit siblings or overlapping trees',
      () async {
        expect(environment.permitsOwnerRoot(library), isTrue);
        expect(environment.permitsOwnerRoot(run.path), isFalse);
        expect(
          environment.permitsOwnerRoot(p.join(library, 'note_child')),
          isFalse,
        );
        expect(
          () => environment.validateLibraryPath(run.path),
          throwsArgumentError,
        );
        await expectLater(
          environment.verifyLocation(p.join(run.path, 'outside')),
          throwsArgumentError,
        );
        expect(
          () => StorageEnvironment.recoverable(
            dataRoot: library,
            settingsFile: p.join(library, 'nested', 'settings.json'),
          ),
          throwsArgumentError,
        );
      },
    );

    test(
      'shared UserData supports settings and note acknowledgements',
      () async {
        await configuration.parent.create(recursive: true);
        await configuration.writeAsString(
          jsonEncode({
            'futureSetting': {'keep': true},
            'customDataPath': null,
          }),
        );
        final current = await initialize();
        expect(await current.settings.getUserDataPath(), library);
        expect(
          await current.settings.getSettingsFilePath(),
          configuration.path,
        );
        expect(current.files.supportsLibrarySwitch, isFalse);
        final reference = await current.files.newNoteReference(
          'synthetic-native',
        );
        final saved = await current.files.writeResolved(
          reference,
          'synthetic first revision',
        );
        expect(
          await current.files.readResolved(saved),
          'synthetic first revision',
        );
        await current.settings.setThemeMode(ThemeMode.light);
        final metadata = jsonDecode(await configuration.readAsString()) as Map;
        expect(metadata['futureSetting'], {'keep': true});
        expect(metadata['customDataPath'], isNull);
        expect(metadata['themeMode'], ThemeMode.light.index);
        expect(
          await current.files.readResolved(saved),
          'synthetic first revision',
        );
      },
    );

    test(
      'releasing notes retains the shared settings lease until shutdown',
      () async {
        final current = await initialize();
        await current.files.closePersistence();
        final started = await StorageOwnerWorker.start(
          environment: environment,
        );
        expect(started.isSuccess, isTrue);
        final contender = started.value!;
        try {
          expect(
            (await contender.openRoot(library)).outcome,
            OperationOutcome.conflict,
          );
          await current.settings.setThemeMode(ThemeMode.light);
          expect((await current.close()).isSuccess, isTrue);
          final acquired = await contender.openRoot(library);
          expect(acquired.isSuccess, isTrue);
          expect(
            (await contender.releaseRoot(acquired.value!)).isSuccess,
            isTrue,
          );
        } finally {
          expect((await contender.close()).isSuccess, isTrue);
        }
      },
    );

    test('a recovered settings path mismatch retains existing bytes', () async {
      await configuration.parent.create(recursive: true);
      final source = jsonEncode({
        'customDataPath': p.join(run.path, 'other-library'),
      });
      await configuration.writeAsString(source);
      final note = File(p.join(library, 'note_synthetic-existing'));
      await note.writeAsString('synthetic preserved content');
      final current = OwnedAppServices(environment: environment);
      services = current;
      expect((await current.initialize()).isSuccess, isFalse);
      expect(() => current.files, throwsStateError);
      expect(await configuration.readAsString(), source);
      expect(await note.readAsString(), 'synthetic preserved content');
    });

    test('external note changes reject the captured commit', () async {
      final current = await initialize();
      final reference = await current.files.newNoteReference(
        'synthetic-conflict',
      );
      final saved = await current.files.writeResolved(
        reference,
        'synthetic original',
      );
      await File(
        saved.contentPath,
      ).writeAsString('synthetic external revision', flush: true);
      await expectLater(
        current.files.writeResolved(saved, 'synthetic stale overwrite'),
        throwsA(
          isA<NotePersistenceFailure>().having(
            (error) => error.outcome,
            'outcome',
            OperationOutcome.conflict,
          ),
        ),
      );
      expect(
        await File(saved.contentPath).readAsString(),
        'synthetic external revision',
      );
    });

    test(
      'unfinished entry points reject before draft mutation and I/O',
      () async {
        final current = await initialize();
        final editor = ContentViewModel(
          fileService: current.files,
          encryptionService: SyntheticCipher(),
          settings: current.settings,
          startBackgroundServices: false,
        );
        try {
          editor.titleController.text = 'Synthetic retained draft';
          final revision = editor.draftSession.editRevision;
          editor.setPassword('synthetic-only');
          editor.clearPassword();
          expect(
            await editor.removePassword(password: 'synthetic-only'),
            isFalse,
          );
          expect(
            await editor.changePassword('synthetic-only'),
            contains('unavailable'),
          );
          await editor.pickAttachment();
          await editor.performImport(
            PlatformFile(name: 'synthetic.txt', size: 0),
          );
          await editor.deleteNote('note_synthetic');
          expect(editor.titleController.text, 'Synthetic retained draft');
          expect(editor.draftSession.editRevision, revision);
          expect(editor.isPasswordSet, isFalse);
          expect(
            editor.operationResultNotifier.value!.outcome,
            OperationOutcome.rejectedInput,
          );
          expect(await current.files.getRecentFiles(), isEmpty);
        } finally {
          editor.dispose();
          await editor.closeLibraryResources();
        }
      },
    );
  }, skip: !Platform.isWindows);
}
