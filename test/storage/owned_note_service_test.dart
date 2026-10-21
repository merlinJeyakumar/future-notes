import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:path/path.dart' as p;
import 'package:flutter_application_1/core/operations/operation_result.dart';
import 'package:flutter_application_1/core/storage/native_storage_primitives.dart';
import 'package:flutter_application_1/core/storage/note_reference.dart';
import 'package:flutter_application_1/core/storage/owned_note_persistence.dart';
import 'package:flutter_application_1/core/storage/owned_settings_persistence.dart';
import 'package:flutter_application_1/core/storage/recoverable_store.dart';
import 'package:flutter_application_1/core/storage/storage_environment.dart';
import 'package:flutter_application_1/core/storage/storage_owner_worker.dart';
import 'package:flutter_application_1/features/dashboard/services/file_service.dart';
import 'package:flutter_application_1/features/dashboard/services/settings_service.dart';
import 'package:flutter_application_1/features/dashboard/viewmodels/content_viewmodel.dart';

import '../support/editor_harness.dart' show PausePoint, SyntheticCipher;
import '../support/validation_directory.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory run;
  late StorageEnvironment environment;
  late StorageOwnerWorker worker;
  late NoteTestOwner owner;
  late SettingsService settings;
  late FileService files;
  late List<ContentViewModel> editors;
  late List<File> cleanupObstructions;
  late List<StorageOwnerWorker> probeWorkers;

  setUp(() async {
    run = await createValidationRun();
    environment = StorageEnvironment.validation(
      validationRoot: run.path,
      dataRoot: p.join(run.path, 'library'),
      settingsFile: p.join(run.path, 'configuration', 'settings.json'),
    );
    final started = await StorageOwnerWorker.start(environment: environment);
    expect(started.isSuccess, isTrue);
    worker = started.value!;
    owner = NoteTestOwner(worker);
    settings = SettingsService.withStorage(
      storage: environment,
      storageOwner: worker,
      documentsDirectoryResolver: () async =>
          throw StateError('Production resolution forbidden'),
    );
    await settings.init();
    files = FileService(settings: settings, storageOwner: owner);
    editors = [];
    cleanupObstructions = [];
    probeWorkers = [];
  });

  tearDown(() async {
    owner.failRelease = null;
    owner.beforeRelease = null;
    owner.beforeSourceCommit = null;
    for (final obstruction in cleanupObstructions) {
      await environment.verifyLocation(obstruction.path);
      if (await obstruction.exists()) {
        await obstruction.delete();
      }
    }
    for (final editor in editors) {
      editor.dispose();
      await editor.closeLibraryResources();
    }
    await files.closePersistence();
    await settings.closePersistence();
    settings.themeModeNotifier.dispose();
    expect((await worker.close()).isSuccess, isTrue);
    for (final probe in probeWorkers) {
      expect((await probe.close()).isSuccess, isTrue);
    }
    await deleteValidationRun(run);
  });

  Future<StorageOwnerWorker> independentOwner() async {
    final started = await StorageOwnerWorker.start(environment: environment);
    expect(started.isSuccess, isTrue, reason: started.message);
    probeWorkers.add(started.value!);
    return started.value!;
  }

  Future<File> fixture(String relative, String content, {String? root}) async {
    final file = File(p.join(root ?? environment.dataRoot!, relative));
    await file.parent.create(recursive: true);
    await file.writeAsString(content, flush: true);
    return file;
  }

  Future<File> obstructCleanup(CommitFileSource source) async {
    final sidecar = File(p.join(p.dirname(source.path), 'synthetic-sidecar'));
    await environment.verifyLocation(sidecar.path);
    cleanupObstructions.add(sidecar);
    await sidecar.writeAsString('Synthetic cleanup obstruction', flush: true);
    return sidecar;
  }

  Map<String, dynamic> note({bool locked = false}) => {
    'id': 'persistent-id',
    'title': 'Original',
    'content': '  Synthetic body  ',
    'isLocked': locked,
    'timestamp': 1700000000000,
    'attachments': [],
    'extension': {'retained': true},
  };

  TypeMatcher<NotePersistenceFailure> failure(OperationOutcome outcome) =>
      isA<NotePersistenceFailure>().having(
        (error) => error.outcome,
        'outcome',
        outcome,
      );

  ContentViewModel editor({SyntheticCipher? cipher}) {
    final vm = ContentViewModel(
      fileService: files,
      encryptionService: cipher ?? SyntheticCipher(),
      settings: settings,
      startBackgroundServices: false,
    );
    editors.add(vm);
    return vm;
  }

  test(
    'production owner injection is refused before directory resolution',
    () async {
      var calls = 0;
      final production = SettingsService.withStorage(
        storage: const StorageEnvironment.production(),
        documentsDirectoryResolver: () async {
          calls++;
          throw StateError('Must not resolve');
        },
      );
      expect(
        () => FileService(settings: production, storageOwner: owner),
        throwsArgumentError,
      );
      expect(calls, 0);
      expect(owner.opens, 0);
      production.themeModeNotifier.dispose();
    },
  );

  test(
    'folder and legacy references retain exact paths and advance acknowledged revisions',
    () async {
      await fixture('note_folder/note_content_folder.enc', 'synthetic folder');
      await fixture('note_legacy.enc', 'synthetic legacy');
      for (final name in ['note_folder', 'note_legacy.enc']) {
        final original = (await files.resolveNote(
          name,
        ))!.withModelId('persistent-id');
        expect(original.storageRevision!.exists, isTrue);
        expect(await files.readResolved(original), contains('synthetic'));
        final saved = await files.writeResolved(original, 'replacement $name');
        expect(saved.contentPath, original.contentPath);
        expect(saved.modelId, 'persistent-id');
        expect(
          saved.storageOwner!.generation,
          original.storageOwner!.generation,
        );
        expect(
          saved.storageRevision!.matches(original.storageRevision!),
          isFalse,
        );
        expect(await files.readResolved(saved), 'replacement $name');
        await expectLater(
          files.writeResolved(original, 'stale'),
          throwsA(failure(OperationOutcome.conflict)),
        );
        final again = await files.writeResolved(saved, 'second $name');
        expect(await files.readResolved(again), 'second $name');
      }
      expect(files.noteCleanupPending, isFalse);
    },
  );

  test(
    'new references refuse existing identities and first publication uses a missing revision',
    () async {
      final fresh = await files.newNoteReference('fresh');
      expect(owner.lastRevisionTarget, 'note_fresh/note_content_fresh.enc');
      expect(fresh.storageRevision!.exists, isFalse);
      expect(await files.readResolved(fresh), isNull);
      final saved = await files.writeResolved(
        fresh,
        'synthetic first generation',
      );
      expect(saved.storageRevision!.exists, isTrue);
      expect(await files.readResolved(saved), 'synthetic first generation');
      await expectLater(
        files.newNoteReference('fresh'),
        throwsA(failure(OperationOutcome.conflict)),
      );
    },
  );

  test(
    'same-size external edits cannot be overwritten after opening',
    () async {
      final target = await fixture('legacy.enc', 'AAAA');
      final reference = (await files.resolveNote('legacy.enc'))!;
      final modified = (await target.stat()).modified;
      await target.writeAsString('BBBB', flush: true);
      await target.setLastModified(modified);
      await expectLater(
        files.readResolved(reference),
        throwsA(failure(OperationOutcome.conflict)),
      );
      await expectLater(
        files.writeResolved(reference, 'CCCC'),
        throwsA(failure(OperationOutcome.conflict)),
      );
      expect(await target.readAsString(), 'BBBB');
    },
  );

  test(
    'change during a checked read is rejected without granting a new revision',
    () async {
      final target = await fixture('legacy.enc', 'AAAA');
      final reference = (await files.resolveNote('legacy.enc'))!;
      owner.onRevision = (count) async {
        if (count == 3) {
          await target.writeAsString('BBBB', flush: true);
        }
      };
      await expectLater(
        files.readResolved(reference),
        throwsA(failure(OperationOutcome.conflict)),
      );
      expect(reference.storageRevision!.length, 4);
    },
  );

  test(
    'captured writes remain in the original library after settings publication',
    () async {
      final first = await fixture('legacy.enc', 'first library');
      final reference = (await files.resolveNote('legacy.enc'))!;
      final secondRoot = p.join(run.path, 'second-library');
      final second = await fixture(
        'legacy.enc',
        'second library',
        root: secondRoot,
      );
      await settings.setCustomDataPath(secondRoot);
      expect(await files.readFile('legacy.enc'), 'second library');
      final saved = await files.writeResolved(reference, 'updated original');
      expect(await files.readResolved(saved), 'updated original');
      expect(await first.readAsString(), 'updated original');
      expect(await second.readAsString(), 'second library');
    },
  );

  test(
    'plain or foreign owner references cannot bypass captured authority',
    () async {
      final reference = await files.newNoteReference('fresh');
      final forged = NoteReference(
        binding: reference.binding,
        fileName: reference.fileName,
        format: reference.format,
        contentPath: reference.contentPath,
        attachmentLocation: reference.attachmentLocation,
        storageRevision: reference.storageRevision,
        storageOwner: StorageOwnerRoot(
          reference.storageOwner!.identity,
          reference.binding.root,
          'foreign',
        ),
      );
      await expectLater(
        files.writeResolved(forged, 'synthetic'),
        throwsA(failure(OperationOutcome.rejectedInput)),
      );
      final plain = NoteReference(
        binding: reference.binding,
        fileName: reference.fileName,
        format: reference.format,
        contentPath: reference.contentPath,
        attachmentLocation: reference.attachmentLocation,
      );
      await expectLater(
        files.writeResolved(plain, 'synthetic'),
        throwsA(failure(OperationOutcome.rejectedInput)),
      );
      expect(await File(reference.contentPath).exists(), isFalse);
    },
  );

  test('unintegrated legacy mutators refuse direct fallback writes', () async {
    await expectLater(
      files.saveFile('synthetic', 'legacy.enc'),
      throwsUnsupportedError,
    );
    await expectLater(
      files.saveNoteContent('fresh', 'synthetic'),
      throwsUnsupportedError,
    );
    await expectLater(
      files.saveAttachment(Uint8List(0), 'fresh'),
      throwsUnsupportedError,
    );
    await expectLater(files.deleteFile('legacy.enc'), throwsUnsupportedError);
    await expectLater(
      files.importFile(PlatformFile(name: 'synthetic.enc', size: 0)),
      throwsUnsupportedError,
    );
    expect(await Directory(environment.dataRoot!).exists(), isFalse);
    expect(owner.commits, 0);
  });

  test(
    'startup recovery finishes before discovery or editor reading',
    () async {
      final target = await fixture('legacy.enc', 'original');
      final expected = await NativeStoragePrimitives(
        environment,
      ).captureRevision(target.path);
      final backend = await RecoverableStore.open(
        root: environment.dataRoot!,
        environment: environment,
        faultHook: (point, id) async {
          if (point == CommitBoundary.published) {
            throw StateError('interrupted');
          }
        },
      );
      final source = await fixture(
        'replacement.synthetic',
        'replacement',
        root: run.path,
      );
      final interrupted = await backend.value!.commit(
        target: 'legacy.enc',
        expected: expected,
        source: CommitFileSource(source.path, await source.length()),
      );
      expect(interrupted.outcome, OperationOutcome.recoveryRequired);
      await backend.value!.close();
      expect(await files.getRecentFiles(), ['legacy.enc']);
      expect(await files.readFile('legacy.enc'), 'original');
      expect(await target.readAsString(), 'original');
    },
  );

  test(
    'ambiguous recovery retains bytes and never grants a writable reference',
    () async {
      final target = await fixture('legacy.enc', 'original');
      await fixture(
        '.future-notes-storage/transactions/${'a' * 32}.json',
        '{broken',
      );
      await expectLater(
        files.resolveNote('legacy.enc'),
        throwsA(failure(OperationOutcome.recoveryRequired)),
      );
      expect(await target.readAsString(), 'original');
      expect(owner.commits, 0);
    },
  );

  test(
    'closing waits for accepted commits and rejects later library work',
    () async {
      final reference = await files.newNoteReference('fresh');
      final pause = PausePoint();
      owner.commitPause = pause;
      final saving = files.writeResolved(reference, 'accepted generation');
      await pause.started.future;
      final closing = files.closePersistence();
      await expectLater(
        files.newNoteReference('later'),
        throwsA(failure(OperationOutcome.rejectedInput)),
      );
      pause.resume();
      final saved = await saving;
      await closing;
      expect(
        await File(saved.contentPath).readAsString(),
        'accepted generation',
      );
      expect(worker.isReady, isTrue);
      final reacquired = await worker.openRoot(reference.binding.root);
      expect(reacquired.isSuccess, isTrue);
      expect((await worker.releaseRoot(reacquired.value!)).isSuccess, isTrue);
      await settings.setCompressionLevel(CompressionLevel.none);
      expect(settings.compressionLevel, CompressionLevel.none);
    },
  );

  test(
    'lease contention rejects preparation and explicit retry can acquire after release',
    () async {
      final probe = await independentOwner();
      final external = await probe.openRoot(environment.dataRoot!);
      expect(external.isSuccess, isTrue);
      await expectLater(
        files.newNoteReference('fresh'),
        throwsA(failure(OperationOutcome.conflict)),
      );
      expect((await probe.releaseRoot(external.value!)).isSuccess, isTrue);
      expect(
        (await files.newNoteReference('fresh')).storageRevision!.exists,
        isFalse,
      );
    },
  );

  test(
    'editor title saves retain raw body metadata and update the storage revision',
    () async {
      final metadata = note();
      final target = await fixture('legacy.enc', jsonEncode(metadata));
      final vm = editor();
      expect((await vm.loadNote('legacy.enc')).isSuccess, isTrue);
      vm.titleController.text = 'X';
      expect((await vm.saveNote()).isSuccess, isTrue);
      vm.titleController.text = 'Y';
      expect((await vm.saveNote()).isSuccess, isTrue);
      final saved = jsonDecode(await target.readAsString());
      expect(saved['content'], metadata['content']);
      expect(saved['id'], metadata['id']);
      expect(saved['timestamp'], metadata['timestamp']);
      expect(saved['extension'], metadata['extension']);
      expect(saved['title'], 'Y');
      expect(vm.hasUnsavedChanges, isFalse);
    },
  );

  test(
    'new editor requires first manual Save then autosave advances its revision',
    () async {
      final cipher = SyntheticCipher();
      final vm = editor(cipher: cipher);
      vm.titleController.text = 'First draft';
      vm.quillController.document.insert(0, 'New synthetic body');
      expect(
        (await vm.saveNote(isAutoSave: true)).outcome,
        OperationOutcome.rejectedInput,
      );
      expect(owner.commits, 0);
      expect((await vm.saveNote()).isSuccess, isTrue);
      final firstName = vm.currentFileName!;
      vm.titleController.text = 'Second title';
      expect((await vm.saveNote(isAutoSave: true)).isSuccess, isTrue);
      expect(vm.currentFileName, firstName);
      final saved = jsonDecode(
        await cipher.decryptApp((await files.readFile(firstName))!),
      );
      expect(saved['title'], 'Second title');
      expect(saved['content'], contains('New synthetic body'));
      expect(owner.commits, 2);
      expect(vm.hasUnsavedChanges, isFalse);
    },
  );

  test(
    'queued editor saves rebase onto their own earlier acknowledgement',
    () async {
      final cipher = SyntheticCipher();
      final target = await fixture(
        'current.enc',
        cipher.wrapApp(jsonEncode(note())),
      );
      final vm = editor(cipher: cipher);
      expect((await vm.loadNote('current.enc')).isSuccess, isTrue);
      final pause = PausePoint();
      cipher.nextAppEncryption = pause;
      vm.titleController.text = 'First';
      final first = vm.saveNote();
      await pause.started.future;
      vm.titleController.text = 'Second';
      final second = vm.saveNote();
      pause.resume();
      expect((await first).isSuccess, isTrue);
      expect((await second).isSuccess, isTrue);
      final saved = jsonDecode(
        await cipher.decryptApp(await target.readAsString()),
      );
      expect(saved['title'], 'Second');
      expect(vm.hasUnsavedChanges, isFalse);
    },
  );

  test(
    'typing during note commit remains dirty and saves with the next generation',
    () async {
      final target = await fixture('legacy.enc', jsonEncode(note()));
      final vm = editor();
      await vm.loadNote('legacy.enc');
      final document = vm.quillController.document;
      final pause = PausePoint();
      owner.commitPause = pause;
      vm.titleController.text = 'Changed';
      final first = vm.saveNote();
      await pause.started.future;
      document.insert(0, 'Typed ');
      final second = vm.saveNote();
      pause.resume();
      expect((await first).isSuccess, isTrue);
      expect((await second).isSuccess, isTrue);
      expect(identical(vm.quillController.document, document), isTrue);
      expect(vm.quillController.document.toPlainText(), startsWith('Typed '));
      expect(
        jsonDecode(await target.readAsString())['content'],
        contains('Typed '),
      );
      expect(vm.hasUnsavedChanges, isFalse);
    },
  );

  test(
    'editor conflict retains dirty content and reports the typed outcome',
    () async {
      final target = await fixture('legacy.enc', jsonEncode(note()));
      final vm = editor();
      await vm.loadNote('legacy.enc');
      vm.titleController.text = 'My draft';
      final external = jsonEncode({...note(), 'title': 'External'});
      await target.writeAsString(external, flush: true);
      expect((await vm.saveNote()).outcome, OperationOutcome.conflict);
      expect(vm.titleController.text, 'My draft');
      expect(vm.hasUnsavedChanges, isTrue);
      expect(await target.readAsString(), external);
    },
  );

  test(
    'locked editor and failed prospective loads perform no commits',
    () async {
      await fixture('locked.enc', jsonEncode(note(locked: true)));
      await fixture('broken.enc', '{broken');
      final vm = editor();
      expect((await vm.loadNote('locked.enc')).isSuccess, isTrue);
      expect((await vm.saveNote()).outcome, OperationOutcome.rejectedInput);
      expect((await vm.loadNote('broken.enc')).isSuccess, isFalse);
      expect(vm.currentFileName, 'locked.enc');
      expect((await vm.saveNote()).outcome, OperationOutcome.rejectedInput);
      expect(owner.commits, 0);
    },
  );
  test(
    'coalesced Saves advance their own acknowledged native revision',
    () async {
      final content = await fixture('legacy.enc', jsonEncode(note()));
      final vm = editor();
      expect((await vm.loadNote('legacy.enc')).isSuccess, isTrue);
      final pause = PausePoint();
      owner.commitPause = pause;
      vm.titleController.text = 'Active';
      final active = vm.saveNote();
      await pause.started.future;
      final waiting = <Future<OperationResult<void>>>[];
      for (var index = 0; index < 20; index++) {
        vm.titleController.text = 'Native revision $index';
        waiting.add(vm.saveNote());
      }
      pause.resume();
      expect((await active).isSuccess, isTrue);
      expect(
        (await Future.wait(waiting)).every((result) => result.isSuccess),
        isTrue,
      );
      expect(owner.commits, 2);
      expect(
        jsonDecode(await content.readAsString())['title'],
        'Native revision 19',
      );
      expect(vm.hasUnsavedChanges, isFalse);
      final resolved = await files.resolveNote('legacy.enc');
      expect(
        (await files.readResolved(resolved!)),
        await content.readAsString(),
      );
    },
  );

  test(
    'coalesced native conflict retains every requested latest edit',
    () async {
      final content = await fixture('legacy.enc', jsonEncode(note()));
      final vm = editor();
      expect((await vm.loadNote('legacy.enc')).isSuccess, isTrue);
      final pause = PausePoint();
      owner.commitPause = pause;
      vm.titleController.text = 'Active';
      final active = vm.saveNote();
      await pause.started.future;
      vm.titleController.text = 'Intermediate';
      final intermediate = vm.saveNote();
      vm.titleController.text = 'Retained latest';
      final latest = vm.saveNote();
      final external = jsonEncode({...note(), 'title': 'External version'});
      await content.writeAsString(external, flush: true);
      pause.resume();
      for (final result in await Future.wait([active, intermediate, latest])) {
        expect(result.outcome, OperationOutcome.conflict);
      }
      // The second coalesced snapshot is rejected by its revision precheck,
      // before calling the writer. The first active request reached it.
      expect(owner.commits, 1);
      expect(await content.readAsString(), external);
      expect(vm.titleController.text, 'Retained latest');
      expect(vm.hasUnsavedChanges, isTrue);
    },
  );
  test(
    'acknowledged note survives source cleanup failure and explicit close retry',
    () async {
      final reference = await files.newNoteReference('cleanup');
      late File sidecar;
      owner.beforeSourceCommit = (source) async {
        sidecar = await obstructCleanup(source);
      };
      final saved = await files.writeResolved(reference, 'Acknowledged note');
      expect(await File(saved.contentPath).readAsString(), 'Acknowledged note');
      expect(files.noteCleanupPending, isTrue);
      final journal = Directory(
        p.join(reference.binding.root, '.future-notes-storage'),
      );
      final retained = (await journal.list(recursive: true).toList())
          .map((entry) => p.relative(entry.path, from: journal.path))
          .where((relative) => p.split(relative).first != 'sources')
          .toSet();
      await expectLater(
        files.closePersistence(),
        throwsA(failure(OperationOutcome.recoveryRequired)),
      );
      expect(files.noteCleanupPending, isTrue);
      expect(await sidecar.exists(), isTrue);
      await expectLater(
        files.newNoteReference('later'),
        throwsA(failure(OperationOutcome.rejectedInput)),
      );
      final reacquired = await worker.openRoot(reference.binding.root);
      expect(reacquired.isSuccess, isTrue);
      expect((await worker.releaseRoot(reacquired.value!)).isSuccess, isTrue);
      await sidecar.delete();
      await files.closePersistence();
      expect(files.noteCleanupPending, isFalse);
      expect(await File(saved.contentPath).readAsString(), 'Acknowledged note');
      expect(
        (await journal.list(recursive: true).toList())
            .map((entry) => p.relative(entry.path, from: journal.path))
            .where((relative) => p.split(relative).first != 'sources')
            .toSet(),
        retained,
      );
      await settings.setCompressionLevel(CompressionLevel.none);
      expect(settings.compressionLevel, CompressionLevel.none);
    },
  );

  test(
    'failed note commit is not disguised by temporary source cleanup failure',
    () async {
      final content = await fixture('legacy.enc', 'Synthetic previous version');
      final reference = await files.resolveNote('legacy.enc');
      late File sidecar;
      owner.beforeSourceCommit = (source) async {
        sidecar = await obstructCleanup(source);
        await content.writeAsString('Synthetic external version', flush: true);
      };
      await expectLater(
        files.writeResolved(reference!, 'Candidate'),
        throwsA(failure(OperationOutcome.conflict)),
      );
      expect(files.noteCleanupPending, isTrue);
      expect(await content.readAsString(), 'Synthetic external version');
      await expectLater(
        files.closePersistence(),
        throwsA(failure(OperationOutcome.recoveryRequired)),
      );
      await sidecar.delete();
      await files.closePersistence();
      expect(files.noteCleanupPending, isFalse);
      expect(await content.readAsString(), 'Synthetic external version');
    },
  );

  test(
    'thrown note release error permits other root cleanup and a sanitized retry',
    () async {
      final probe = await independentOwner();
      final first = await files.newNoteReference('first');
      final secondRoot = p.join(run.path, 'other-library');
      await settings.setCustomDataPath(secondRoot);
      final second = await files.newNoteReference('second');
      var throwOnce = true;
      owner.beforeRelease = (root) async {
        if (p.equals(root.root, first.binding.root) && throwOnce) {
          throwOnce = false;
          throw StateError('synthetic-sensitive-native-detail');
        }
      };
      await expectLater(
        files.closePersistence(),
        throwsA(
          failure(OperationOutcome.recoveryRequired).having(
            (error) => error.toString(),
            'sanitized error',
            isNot(contains('synthetic-sensitive-native-detail')),
          ),
        ),
      );
      expect(
        (await probe.openRoot(first.binding.root)).outcome,
        OperationOutcome.conflict,
      );
      final secondOwner = await probe.openRoot(second.binding.root);
      expect(secondOwner.isSuccess, isTrue);
      expect((await probe.releaseRoot(secondOwner.value!)).isSuccess, isTrue);
      await files.closePersistence();
      final firstOwner = await probe.openRoot(first.binding.root);
      expect(firstOwner.isSuccess, isTrue);
      expect((await probe.releaseRoot(firstOwner.value!)).isSuccess, isTrue);
      expect(worker.isReady, isTrue);
    },
  );

  test(
    'typed note release failure retains ownership until explicit retry',
    () async {
      final probe = await independentOwner();
      final reference = await files.newNoteReference('release');
      owner.failRelease = OperationOutcome.ioFailure;
      await expectLater(
        files.closePersistence(),
        throwsA(failure(OperationOutcome.recoveryRequired)),
      );
      expect(
        (await probe.openRoot(reference.binding.root)).outcome,
        OperationOutcome.conflict,
      );
      await expectLater(
        files.newNoteReference('later'),
        throwsA(failure(OperationOutcome.rejectedInput)),
      );
      owner.failRelease = null;
      await files.closePersistence();
      final reacquired = await probe.openRoot(reference.binding.root);
      expect(reacquired.isSuccess, isTrue);
      expect((await probe.releaseRoot(reacquired.value!)).isSuccess, isTrue);
    },
  );
  test(
    'library switch joins native watching, settings acknowledgement and old lease release',
    () async {
      final original = await fixture('existing.enc', jsonEncode(note()));
      final bytes = await original.readAsBytes();
      final vm = editor();
      expect((await vm.loadNote('existing.enc')).isSuccess, isTrue);
      final oldReference = await files.resolveNote('existing.enc');
      final next = p.join(run.path, 'other-library');
      expect((await vm.switchLibrary(next)).isSuccess, isTrue);
      expect(await settings.getUserDataPath(), next);
      expect(
        (jsonDecode(await File(environment.settingsFile!).readAsString())
            as Map)['customDataPath'],
        next,
      );
      expect(await original.readAsBytes(), bytes);
      final reacquired = await worker.openRoot(environment.dataRoot!);
      expect(reacquired.isSuccess, isTrue);
      expect((await worker.releaseRoot(reacquired.value!)).isSuccess, isTrue);
      await expectLater(
        files.writeResolved(oldReference!, 'stale'),
        throwsA(failure(OperationOutcome.rejectedInput)),
      );
      expect((await files.newNoteReference('next')).binding.root, next);
    },
  );

  test(
    'candidate settings conflict retains the old note and releases the candidate lease',
    () async {
      await settings.setThemeMode(ThemeMode.light);
      await fixture('existing.enc', jsonEncode(note()));
      final vm = editor();
      await vm.loadNote('existing.enc');
      final document = vm.quillController.document;
      final settingsFile = File(environment.settingsFile!);
      await settingsFile.writeAsString(
        '{"themeMode":2,"external":true}',
        flush: true,
      );
      final next = p.join(run.path, 'conflicting-library');
      expect((await vm.switchLibrary(next)).outcome, OperationOutcome.conflict);
      expect(await settings.getUserDataPath(), environment.dataRoot);
      expect(identical(vm.quillController.document, document), isTrue);
      expect(
        await settingsFile.readAsString(),
        '{"themeMode":2,"external":true}',
      );
      final acquired = await worker.openRoot(next);
      expect(acquired.isSuccess, isTrue);
      expect((await worker.releaseRoot(acquired.value!)).isSuccess, isTrue);
    },
  );

  test(
    'root release failure retains ownership for explicit retry and reopening',
    () async {
      final probe = await independentOwner();
      final binding = await files.prepareLibrary(environment.dataRoot!);
      owner.failRelease = OperationOutcome.ioFailure;
      await expectLater(
        files.releaseLibrary(binding),
        throwsA(failure(OperationOutcome.ioFailure)),
      );
      expect(
        (await probe.openRoot(binding.root)).outcome,
        OperationOutcome.conflict,
      );
      owner.failRelease = null;
      await files.releaseLibrary(binding);
      final reacquired = await probe.openRoot(binding.root);
      expect(reacquired.isSuccess, isTrue);
      expect((await probe.releaseRoot(reacquired.value!)).isSuccess, isTrue);
      final reference = await files.newNoteReference('reopened');
      expect(reference.binding.root, binding.root);
      expect(reference.storageOwner, isNotNull);
    },
  );

  test(
    'settings candidate guard rejects before any new settings file is written',
    () async {
      final next = p.join(run.path, 'rejected-library');
      await expectLater(
        settings.commitLibraryPath(
          next,
          expectedRoot: environment.dataRoot!,
          canCommit: () => false,
        ),
        throwsA(
          isA<SettingsPersistenceFailure>().having(
            (error) => error.outcome,
            'outcome',
            OperationOutcome.conflict,
          ),
        ),
      );
      expect(await File(environment.settingsFile!).exists(), isFalse);
      expect(await settings.getUserDataPath(), environment.dataRoot);
    },
  );
}

class NoteTestOwner implements StorageOwner {
  NoteTestOwner(this.delegate);
  final StorageOwner delegate;
  @override
  Future<OperationResult<DeletionReport>> delete(
    StorageOwnerRoot owner, {
    required String target,
    required StorageRevision expected,
    String? attachmentDirectory,
  }) => delegate.delete(
    owner,
    target: target,
    expected: expected,
    attachmentDirectory: attachmentDirectory,
  );
  int opens = 0;
  int commits = 0;
  int revisions = 0;
  String? lastRevisionTarget;
  PausePoint? commitPause;
  Future<void> Function(int count)? onRevision;
  Future<void> Function(CommitFileSource source)? beforeSourceCommit;
  Future<void> Function(StorageOwnerRoot root)? beforeRelease;
  OperationOutcome? failRelease;

  @override
  Future<OperationResult<StorageOwnerRoot>> openRoot(String root) {
    opens++;
    return delegate.openRoot(root);
  }

  @override
  Future<OperationResult<StorageRevision>> revision(
    StorageOwnerRoot owner,
    String target,
  ) async {
    revisions++;
    lastRevisionTarget = target;
    await onRevision?.call(revisions);
    return delegate.revision(owner, target);
  }

  @override
  Future<OperationResult<StorageRevision>> commit(
    StorageOwnerRoot owner, {
    required String target,
    required StorageRevision expected,
    required CommitFileSource source,
  }) async {
    commits++;
    final pause = commitPause;
    commitPause = null;
    await pause?.wait();
    await beforeSourceCommit?.call(source);
    return delegate.commit(
      owner,
      target: target,
      expected: expected,
      source: source,
    );
  }

  @override
  RecoveryReport? recoveryFor(StorageOwnerRoot owner) =>
      delegate.recoveryFor(owner);
  @override
  Future<OperationResult<void>> releaseRoot(StorageOwnerRoot owner) async {
    await beforeRelease?.call(owner);
    if (failRelease != null) {
      return OperationResult.failure(
        failRelease!,
        'Synthetic release failure.',
      );
    }
    return delegate.releaseRoot(owner);
  }

  @override
  Future<OperationResult<void>> close() => delegate.close();
}
