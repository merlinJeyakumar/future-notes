import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_application_1/core/operations/operation_result.dart';
import 'package:flutter_application_1/core/storage/library_watch.dart';
import 'package:flutter_application_1/core/storage/note_reference.dart';
import 'package:flutter_application_1/core/storage/owned_settings_persistence.dart';
import 'package:flutter_application_1/core/storage/storage_environment.dart';
import 'package:flutter_application_1/features/dashboard/models/draft_transition.dart';
import 'package:flutter_application_1/features/dashboard/models/note_model.dart';
import 'package:flutter_application_1/features/dashboard/services/background_service.dart';
import 'package:flutter_application_1/features/dashboard/services/file_service.dart';
import 'package:flutter_application_1/features/dashboard/services/settings_service.dart';
import 'package:flutter_application_1/features/dashboard/viewmodels/content_viewmodel.dart';

import '../support/editor_harness.dart';
import '../support/validation_directory.dart';

void main() {
  void scenario(
    String name,
    Future<void> Function(WidgetTester, _Fixture) body,
  ) {
    testWidgets(name, (tester) async {
      final f = _Fixture();
      addTearDown(f.close);
      try {
        await tester.pump();
        await body(tester, f);
      } finally {
        f.dispose();
        await _joinLibraryOperation(tester, f.editor.closeLibraryResources());
        await tester.pump(const Duration(seconds: 3));
      }
    });
  }

  scenario(
    'candidate preparation precedes durable settings and old-root release',
    (tester, f) async {
      await f.load();
      f.reader.publish();
      await tester.pump();
      expect(f.editor.recentFiles, hasLength(1));
      final oldBytes = f.files.contents.values.single;
      final result = await _joinLibraryOperation(
        tester,
        f.editor.switchLibrary(f.nextRoot),
      );
      expect(result.isSuccess, isTrue);
      expect(f.events, ['prepare', 'watch', 'commit', 'publish', 'release']);
      expect(f.settings.root, f.nextRoot);
      expect(f.editor.currentFileName, isNull);
      expect(f.files.contents.values.single, oldBytes);
      expect(f.files.writeAttempts, 0);
      expect(f.editor.recentFiles, isEmpty);
      expect(f.files.watches.first.closed, isTrue);
      expect(f.files.watches.last.closed, isFalse);
      expect(f.reader.requests.last, f.nextRoot);
    },
  );
  scenario(
    'existing dirty notes save to their captured library before switching',
    (tester, f) async {
      await f.load();
      f.editor.titleController.text = 'Saved before opening';
      expect(
        (await _joinLibraryOperation(
          tester,
          f.editor.switchLibrary(f.nextRoot),
        )).isSuccess,
        isTrue,
      );
      expect(f.files.writes.single.binding.root, f.originalRoot);
      expect(f.files.contents.values.single, contains('Saved before opening'));
    },
  );
  scenario('a new draft Cancel neither prepares nor writes a candidate', (
    tester,
    f,
  ) async {
    f.editor.titleController.text = 'Unsaved';
    f.decision = DraftDecision.cancel;
    expect(
      (await _joinLibraryOperation(
        tester,
        f.editor.switchLibrary(f.nextRoot),
      )).outcome,
      OperationOutcome.cancelled,
    );
    expect(f.editor.titleController.text, 'Unsaved');
    expect(f.events, isEmpty);
    expect(f.settings.root, f.originalRoot);
    expect(f.files.writeAttempts, 0);
  });
  scenario('new drafts require explicit first Save before publication', (
    tester,
    f,
  ) async {
    f.editor.titleController.text = 'Explicitly saved';
    f.decision = DraftDecision.save;
    expect(
      (await _joinLibraryOperation(
        tester,
        f.editor.switchLibrary(f.nextRoot),
      )).isSuccess,
      isTrue,
    );
    expect(f.files.writes.single.binding.root, f.originalRoot);
  });
  scenario(
    'provisional Discard does not replace a draft when preparation fails',
    (tester, f) async {
      f.editor.titleController.text = 'Keep this draft';
      f.decision = DraftDecision.discard;
      f.files.failPrepare = true;
      expect(
        (await _joinLibraryOperation(
          tester,
          f.editor.switchLibrary(f.nextRoot),
        )).outcome,
        OperationOutcome.ioFailure,
      );
      expect(f.editor.titleController.text, 'Keep this draft');
      expect(f.editor.hasUnsavedChanges, isTrue);
      expect(f.settings.root, f.originalRoot);
      expect(f.files.writeAttempts, 0);
    },
  );
  scenario(
    'settings failure retains editor, inventory and the original watcher',
    (tester, f) async {
      await f.load();
      f.reader.publish();
      await tester.pump();
      final document = f.editor.quillController.document;
      final oldWatch = f.files.watches.single;
      f.settings.failCommit = true;
      final result = await _joinLibraryOperation(
        tester,
        f.editor.switchLibrary(f.nextRoot),
      );
      expect(result.outcome, OperationOutcome.ioFailure);
      expect(f.settings.root, f.originalRoot);
      expect(f.editor.recentFiles.single.title, 'Synthetic listing');
      expect(identical(f.editor.quillController.document, document), isTrue);
      expect(oldWatch.closed, isFalse);
      expect(f.files.watches.last.closed, isTrue);
      expect(f.files.released, [f.nextRoot]);
      expect(f.editor.isLibraryCutover, isFalse);
      expect(f.editor.quillController.readOnly, isFalse);
    },
  );
  scenario('watch preparation failure leaves settings untouched', (
    tester,
    f,
  ) async {
    await f.load();
    f.files.failWatch = true;
    expect(
      (await _joinLibraryOperation(
        tester,
        f.editor.switchLibrary(f.nextRoot),
      )).outcome,
      OperationOutcome.ioFailure,
    );
    expect(f.events, ['prepare', 'watch', 'release']);
    expect(f.settings.root, f.originalRoot);
    expect(f.editor.currentFileName, 'existing.enc');
  });
  scenario(
    'typing during candidate preparation invalidates the transition permit',
    (tester, f) async {
      await f.load();
      final pause = f.files.preparePause = PausePoint();
      final operation = f.editor.switchLibrary(f.nextRoot);
      await tester.pump();
      expect(pause.started.isCompleted, isTrue);
      f.editor.titleController.text = 'Typed during preparation';
      pause.resume();
      final result = await _joinLibraryOperation(tester, operation);
      expect(result.outcome, OperationOutcome.conflict);
      expect(f.settings.root, f.originalRoot);
      expect(f.editor.titleController.text, 'Typed during preparation');
      expect(f.events, isNot(contains('commit')));
    },
  );
  scenario('commit cutover guards Save, navigation, reset and note mutations', (
    tester,
    f,
  ) async {
    await f.load();
    final pause = f.settings.commitPause = PausePoint();
    final operation = f.editor.switchLibrary(f.nextRoot);
    await tester.pump();
    expect(pause.started.isCompleted, isTrue);
    expect(f.editor.isLibraryCutover, isTrue);
    expect(f.editor.quillController.readOnly, isTrue);
    expect((await f.editor.saveNote()).outcome, OperationOutcome.conflict);
    expect(
      (await f.editor.reset(discardChanges: true)).outcome,
      OperationOutcome.conflict,
    );
    expect(
      (await f.editor.loadNote('other.enc')).outcome,
      OperationOutcome.conflict,
    );
    await f.editor.pickAttachment();
    await f.editor.deleteNote('existing.enc');
    f.editor.setPassword('synthetic-password');
    expect(f.files.pickerCalls, 0);
    expect(f.editor.isPasswordSet, isFalse);
    pause.resume();
    expect((await _joinLibraryOperation(tester, operation)).isSuccess, isTrue);
  });
  scenario(
    'a late programmatic edit retains its old reference and writer lease',
    (tester, f) async {
      await f.load();
      final pause = f.settings.commitPause = PausePoint();
      final operation = f.editor.switchLibrary(f.nextRoot);
      await tester.pump();
      f.editor.titleController.text = 'Late retained edit';
      pause.resume();
      expect(
        (await _joinLibraryOperation(tester, operation)).outcome,
        OperationOutcome.conflict,
      );
      expect(f.settings.root, f.nextRoot);
      expect(f.editor.currentFileName, 'existing.enc');
      expect(f.editor.titleController.text, 'Late retained edit');
      expect(f.files.released, isEmpty);
      expect((await f.editor.saveNote()).isSuccess, isTrue);
      expect(f.files.writes.single.binding.root, f.originalRoot);
      await f.editor.reset();
      expect(
        (await _joinLibraryOperation(
          tester,
          f.editor.retryLibraryCleanup(),
        )).isSuccess,
        isTrue,
      );
      expect(f.files.released, [f.originalRoot]);
    },
  );
  scenario('candidate cleanup failure is returned truthfully and retryable', (
    tester,
    f,
  ) async {
    await f.load();
    f.settings.failCommit = true;
    f.files.failRelease = true;
    expect(
      (await _joinLibraryOperation(
        tester,
        f.editor.switchLibrary(f.nextRoot),
      )).outcome,
      OperationOutcome.recoveryRequired,
    );
    expect(f.settings.root, f.originalRoot);
    f.files.failRelease = false;
    expect(
      (await _joinLibraryOperation(
        tester,
        f.editor.retryLibraryCleanup(),
      )).isSuccess,
      isTrue,
    );
    expect(f.files.released, [f.nextRoot]);
  });
  scenario('post-commit release failure reports the new library accurately', (
    tester,
    f,
  ) async {
    await f.load();
    f.files.failRelease = true;
    final result = await _joinLibraryOperation(
      tester,
      f.editor.switchLibrary(f.nextRoot),
    );
    expect(result.outcome, OperationOutcome.recoveryRequired);
    expect(result.message, contains('new library opened'));
    expect(f.settings.root, f.nextRoot);
    expect(f.editor.currentFileName, isNull);
    f.files.failRelease = false;
    expect(
      (await _joinLibraryOperation(
        tester,
        f.editor.retryLibraryCleanup(),
      )).isSuccess,
      isTrue,
    );
  });
  scenario('retired watcher events cannot refresh the new library', (
    tester,
    f,
  ) async {
    final old = f.files.watches.single;
    await _joinLibraryOperation(tester, f.editor.switchLibrary(f.nextRoot));
    final count = f.reader.requests.length;
    old.events.add(null);
    await tester.pump(const Duration(seconds: 2));
    expect(f.reader.requests.length, count);
    f.files.watches.last.events.add(null);
    f.files.watches.last.events.add(null);
    await tester.pump(const Duration(seconds: 2));
    expect(f.reader.requests.length, count + 1);
  });
  scenario(
    'overlapping library requests are rejected rather than interleaved',
    (tester, f) async {
      final pause = f.files.preparePause = PausePoint();
      final first = f.editor.switchLibrary(f.nextRoot);
      await tester.pump();
      expect(
        (await _joinLibraryOperation(
          tester,
          f.editor.switchLibrary(p.join(f.run.path, 'third')),
        )).outcome,
        OperationOutcome.conflict,
      );
      pause.resume();
      expect((await _joinLibraryOperation(tester, first)).isSuccess, isTrue);
      expect(f.events.where((event) => event == 'commit'), hasLength(1));
    },
  );
  scenario(
    'an attachment picker owns its library until cancellation completes',
    (tester, f) async {
      await f.load();
      final pause = f.files.pickerPause = PausePoint();
      final attachment = f.editor.pickAttachment();
      await tester.pump();
      expect(pause.started.isCompleted, isTrue);
      expect(
        (await _joinLibraryOperation(
          tester,
          f.editor.switchLibrary(f.nextRoot),
        )).outcome,
        OperationOutcome.conflict,
      );
      expect(f.events, isEmpty);
      pause.resume();
      await attachment;
      expect(
        (await _joinLibraryOperation(
          tester,
          f.editor.switchLibrary(f.nextRoot),
        )).isSuccess,
        isTrue,
      );
    },
  );
  scenario(
    'library preparation error messages contain no raw service details',
    (tester, f) async {
      f.files.failPrepare = true;
      final result = await _joinLibraryOperation(
        tester,
        f.editor.switchLibrary(f.nextRoot),
      );
      expect(result.outcome, OperationOutcome.ioFailure);
      expect(result.message, isNot(contains('synthetic-prepare-detail')));
    },
  );
  scenario('disposal during preparation cancels without changing settings', (
    tester,
    f,
  ) async {
    final pause = f.files.preparePause = PausePoint();
    final operation = f.editor.switchLibrary(f.nextRoot);
    await tester.pump();
    f.dispose();
    pause.resume();
    expect(
      (await _joinLibraryOperation(tester, operation)).outcome,
      OperationOutcome.conflict,
    );
    expect(f.settings.root, f.originalRoot);
    expect(f.files.watches.every((watch) => watch.closed), isTrue);
  });
  scenario('disposal during acknowledged commit closes the prepared watcher', (
    tester,
    f,
  ) async {
    final pause = f.settings.commitPause = PausePoint();
    final operation = f.editor.switchLibrary(f.nextRoot);
    await tester.pump();
    f.dispose();
    pause.resume();
    await _joinLibraryOperation(tester, operation);
    expect(f.settings.root, f.nextRoot);
    expect(f.files.watches.every((watch) => watch.closed), isTrue);
  });
  scenario(
    'the legacy settings writer is refused before draft decisions or IO',
    (tester, f) async {
      f.settings.supported = false;
      f.editor.titleController.text = 'Retain new note';
      expect(
        (await _joinLibraryOperation(
          tester,
          f.editor.switchLibrary(f.nextRoot),
        )).outcome,
        OperationOutcome.rejectedInput,
      );
      expect(f.events, isEmpty);
      expect(f.files.writeAttempts, 0);
    },
  );
}

// Cancellation can return Dart's root-zone null future. Let that continuation
// run without moving operation creation, race control or debounce timers out
// of fake async. Bound the join rather than awaiting an unpumped future.
Future<T> _joinLibraryOperation<T>(
  WidgetTester tester,
  Future<T> operation,
) async {
  var completed = false;
  operation.then<void>(
    (_) {
      completed = true;
    },
    onError: (Object error, StackTrace stackTrace) {
      completed = true;
    },
  );
  for (var turn = 0; !completed && turn < 20; turn++) {
    await tester.pump();
    if (completed) {
      break;
    }
    await tester.runAsync(() async {
      await Future<void>.delayed(Duration.zero);
    });
  }
  await tester.pump();
  expect(
    completed,
    isTrue,
    reason: 'Library operation exceeded 20 async turns.',
  );
  return await operation;
}

class _Fixture {
  _Fixture() {
    run = Directory.systemTemp.createTempSync('future-notes-validation-');
    originalRoot = p.join(run.path, 'library');
    nextRoot = p.join(run.path, 'other');
    final environment = StorageEnvironment.validation(
      validationRoot: run.path,
      dataRoot: originalRoot,
      settingsFile: p.join(run.path, 'configuration', 'settings.json'),
    );
    settings = _Settings(environment, originalRoot, events);
    files = _Files(originalRoot, events);
    reader = _Reader(environment);
    editor = ContentViewModel(
      fileService: files,
      encryptionService: SyntheticCipher(),
      settings: settings,
      backgroundService: reader,
      onDraftDecision: (_) async => decision,
    );
  }
  late final Directory run;
  late final String originalRoot;
  late final String nextRoot;
  late final _Settings settings;
  late final _Files files;
  late final _Reader reader;
  late final ContentViewModel editor;
  final events = <String>[];
  DraftDecision decision = DraftDecision.cancel;
  bool disposed = false;
  Future<void> load() async {
    files.seed(
      'existing.enc',
      jsonEncode({
        'id': 'synthetic-id',
        'title': 'Original',
        'content': 'Synthetic body',
        'isLocked': false,
        'timestamp': 1700000000000,
        'attachments': [],
      }),
    );
    expect((await editor.loadNote('existing.enc')).isSuccess, isTrue);
  }

  void dispose() {
    if (!disposed) {
      disposed = true;
      editor.dispose();
    }
  }

  Future<void> close() async {
    dispose();
    for (final watch in files.watches) {
      await watch.events.close();
    }
    settings.themeModeNotifier.dispose();
    await deleteValidationRun(run);
  }
}

class _Settings extends SettingsService {
  _Settings(StorageEnvironment environment, this.root, this.events)
    : super.withStorage(storage: environment);
  String root;
  final List<String> events;
  bool supported = true;
  bool failCommit = false;
  PausePoint? commitPause;
  @override
  bool get supportsRecoverableLibrarySwitch => supported;
  @override
  Future<void> init() async {}

  @override
  Future<String> getUserDataPath() async => root;
  @override
  Future<void> commitLibraryPath(
    String path, {
    required String expectedRoot,
    required bool Function() canCommit,
  }) async {
    if (root != expectedRoot || !canCommit()) {
      throw const SettingsPersistenceFailure(OperationOutcome.conflict);
    }
    events.add('commit');
    await commitPause?.wait();
    if (failCommit) {
      throw const SettingsPersistenceFailure(OperationOutcome.ioFailure);
    }
    root = path;
  }
}

class _Files extends MemoryNoteFiles implements LibraryFileService {
  _Files(super.libraryRoot, this.events);
  final List<String> events;
  final watches = <_Watch>[];
  final released = <String>[];
  PausePoint? preparePause;
  PausePoint? pickerPause;
  bool failPrepare = false;
  bool failWatch = false;
  bool failRelease = false;
  var generation = 1;
  @override
  bool get supportsLibrarySwitch => true;
  @override
  Future<FilePickerResult?> pickFile({List<String>? allowedExtensions}) async {
    pickerCalls++;
    await pickerPause?.wait();
    return null;
  }

  @override
  Future<String> getUserDataPath() async => libraryRoot;
  @override
  Future<StorageBinding> currentLibrary() async {
    return StorageBinding(libraryRoot, generation);
  }

  @override
  Future<StorageBinding> prepareLibrary(String root) async {
    events.add('prepare');
    await preparePause?.wait();
    if (failPrepare) throw StateError('synthetic-prepare-detail');
    return StorageBinding(root, ++generation);
  }

  @override
  Future<LibraryWatch> openLibraryWatch(StorageBinding binding) async {
    if (watches.isNotEmpty) events.add('watch');
    if (failWatch) throw StateError('synthetic-watch-detail');
    final watch = _Watch(binding);
    watches.add(watch);
    return watch;
  }

  @override
  void publishLibrary(StorageBinding binding) {
    events.add('publish');
    libraryRoot = binding.root;
  }

  @override
  Future<void> releaseLibrary(StorageBinding binding) async {
    events.add('release');
    if (failRelease) throw StateError('synthetic-release-detail');
    released.add(binding.root);
  }
}

class _Watch implements LibraryWatch {
  _Watch(this.binding);
  @override
  final StorageBinding binding;
  final events = StreamController<void>.broadcast(sync: true);
  bool closed = false;
  @override
  bool get failed => false;
  @override
  Stream<void> get changes => events.stream;
  @override
  Future<void> close() async {
    closed = true;
  }
}

class _Reader extends BackgroundService {
  _Reader(StorageEnvironment environment) : super(environment: environment);
  final snapshots = StreamController<DiscoverySnapshot>.broadcast();
  final requests = <String>[];
  DiscoveryRequest? desired;
  @override
  Future<void> init() async {}

  @override
  Stream<DiscoverySnapshot> get discoveriesStream => snapshots.stream;
  @override
  bool isCurrent(DiscoveryRequest request) =>
      desired?.matches(request) ?? false;
  @override
  void invalidateRequests() {
    desired = null;
  }

  @override
  void loadRecentFiles(String path) {
    requests.add(path);
    desired = DiscoveryRequest(path, requests.length, requests.length);
  }

  void publish() {
    snapshots.add(
      DiscoverySnapshot(desired!, [
        RecentFile(
          path: 'synthetic.enc',
          fullPath: p.join(desired!.directoryPath, 'synthetic.enc'),
          title: 'Synthetic listing',
        ),
      ], isFinal: true),
    );
  }

  @override
  void dispose() {
    snapshots.close();
    super.dispose();
  }
}
