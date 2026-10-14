import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_application_1/core/operations/operation_result.dart';
import 'package:flutter_application_1/core/storage/storage_environment.dart';
import 'package:flutter_application_1/features/dashboard/models/note_model.dart';
import 'package:flutter_application_1/features/dashboard/services/background_service.dart';
import 'package:flutter_application_1/features/dashboard/services/settings_service.dart';
import 'package:flutter_application_1/features/dashboard/viewmodels/content_viewmodel.dart';

import '../support/editor_harness.dart';
import '../support/validation_directory.dart';

void main() {
  void searchTest(
    String name,
    Future<void> Function(WidgetTester, _Fixture) body,
  ) {
    testWidgets(name, (tester) async {
      final fixture = _Fixture();
      addTearDown(fixture.close);
      try {
        await tester.pump();
        expect(fixture.reader.requests, hasLength(1));
        await body(tester, fixture);
        expect(fixture.files.writeAttempts, 0);
      } finally {
        fixture.disposeEditor();
        await tester.pump(const Duration(seconds: 1));
      }
    });
  }

  Future<void> search(
    WidgetTester tester,
    _Fixture fixture,
    String query,
  ) async {
    fixture.editor.setSearchQuery(query);
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> joinCleanup(WidgetTester tester, Future<void> closing) async {
    var completed = false;
    Object? failure;
    closing.then<void>(
      (_) {
        completed = true;
      },
      onError: (Object error) {
        failure = error;
        completed = true;
      },
    );
    for (var i = 0; i < 50 && !completed; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 1)),
      );
      await tester.pump();
    }
    expect(completed, isTrue, reason: 'Read-only cleanup did not acknowledge.');
    expect(failure, isNull);
  }

  searchTest(
    'shutdown stops a queued search and closes its read-only scanner',
    (tester, f) async {
      f.publish(['Synthetic Alpha']);
      f.editor.setSearchQuery('Alpha');
      final requests = f.reader.requests.length;
      await joinCleanup(tester, f.editor.closeLibraryResources());
      await f.editor.loadRecentFiles();
      await tester.pump(const Duration(seconds: 3));
      expect(f.reader.closed, isTrue);
      expect(f.reader.requests.length, requests);
      expect(f.filters, isEmpty);
    },
  );

  searchTest('shutdown rejects a search result that finishes during cleanup', (
    tester,
    f,
  ) async {
    f.publish(['Synthetic Alpha', 'Synthetic Beta']);
    await search(tester, f, 'Alpha');
    final pending = f.filters.single;
    await joinCleanup(tester, f.editor.closeLibraryResources());
    pending.result.complete([pending.files.first]);
    await tester.pump();
    expect(f.editor.recentFiles, isEmpty);
    f.editor.setSearchQuery('');
    expect(f.editor.recentFiles.length, 2);
    expect(f.reader.closed, isTrue);
  });

  searchTest('a delayed older query cannot replace the newer search', (
    tester,
    f,
  ) async {
    f.publish(['Alpha', 'Beta']);
    await search(tester, f, 'Alpha');
    final old = f.filters.single;
    await search(tester, f, 'Beta');
    final current = f.filters.last;
    current.result.complete([current.files.last]);
    await tester.pump();
    expect(f.editor.recentFiles.single.title, 'Beta');
    old.result.complete([old.files.first]);
    await tester.pump();
    expect(f.editor.recentFiles.single.title, 'Beta');
  });

  searchTest('clearing a query invalidates its active computation', (
    tester,
    f,
  ) async {
    f.publish(['Alpha', 'Beta']);
    await search(tester, f, 'Alpha');
    f.editor.setSearchQuery('');
    f.filters.single.result.complete([f.filters.single.files.first]);
    await tester.pump();
    expect(f.editor.recentFiles.map((file) => file.title), ['Alpha', 'Beta']);
  });

  searchTest(
    'a new inventory invalidates an active search and schedules its replacement',
    (tester, f) async {
      f.publish(['Old Alpha']);
      await search(tester, f, 'Alpha');
      final old = f.filters.single;
      f.publish(['New Alpha']);
      expect(f.editor.recentFiles, isEmpty);
      await tester.pump(const Duration(milliseconds: 300));
      final current = f.filters.last;
      old.result.complete(old.files);
      await tester.pump();
      expect(f.editor.recentFiles, isEmpty);
      current.result.complete(current.files);
      await tester.pump();
      expect(f.editor.recentFiles.single.title, 'New Alpha');
    },
  );

  searchTest('queued stale discovery does not replace the current inventory', (
    tester,
    f,
  ) async {
    final before = f.reader.requests.single;
    await f.editor.loadRecentFiles();
    f.publish(['Current']);
    f.reader.publish([f.file('Stale')], request: before);
    expect(f.editor.recentFiles.single.title, 'Current');
    expect(f.filters, isEmpty);
  });

  searchTest(
    'disposal during filtering rejects publication and further queries',
    (tester, f) async {
      f.publish(['Alpha']);
      await search(tester, f, 'Alpha');
      final pending = f.filters.single;
      f.disposeEditor();
      f.editor.setSearchQuery('Late');
      pending.result.complete(pending.files);
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(f.filters, hasLength(1));
    },
  );

  searchTest('current filter failure is sanitized and preserves the editor', (
    tester,
    f,
  ) async {
    f.publish(['Alpha']);
    final document = f.editor.quillController.document;
    await search(tester, f, 'Alpha');
    f.filters.single.result.completeError(
      StateError('synthetic-sensitive-filter-detail'),
    );
    await tester.pump();
    final result = f.editor.operationResultNotifier.value!;
    expect(result.outcome, OperationOutcome.ioFailure);
    expect(
      result.message,
      isNot(contains('synthetic-sensitive-filter-detail')),
    );
    expect(identical(f.editor.quillController.document, document), isTrue);
    expect(tester.takeException(), isNull);
  });

  searchTest(
    'an older filter failure cannot report against a newer successful query',
    (tester, f) async {
      f.publish(['Alpha', 'Beta']);
      await search(tester, f, 'Alpha');
      final old = f.filters.single;
      await search(tester, f, 'Beta');
      final current = f.filters.last;
      current.result.complete([current.files.last]);
      old.result.completeError(StateError('synthetic-stale-error'));
      await tester.pump();
      expect(f.editor.recentFiles.single.title, 'Beta');
      expect(f.editor.operationResultNotifier.value, isNull);
    },
  );

  searchTest(
    'clearing before debounce cancels filtering without redundant work',
    (tester, f) async {
      f.publish(['Alpha']);
      f.editor.setSearchQuery('Alpha');
      f.editor.setSearchQuery('');
      await tester.pump(const Duration(milliseconds: 300));
      expect(f.filters, isEmpty);
      expect(f.editor.recentFiles.single.title, 'Alpha');
    },
  );

  searchTest(
    'an older resolved path cannot redirect the newer library request',
    (tester, f) async {
      final olderPath = Completer<String>();
      f.files.pathResults.add(olderPath.future);
      final old = f.editor.loadRecentFiles();
      f.files.libraryRoot = p.join(f.run.path, 'other-library');
      await f.editor.loadRecentFiles();
      olderPath.complete(f.environment.dataRoot!);
      await old;
      expect(f.reader.requests, hasLength(2));
      expect(f.reader.requests.last.directoryPath, f.files.libraryRoot);
    },
  );

  searchTest(
    'a stale path-resolution failure cannot report against the newer library',
    (tester, f) async {
      final olderPath = Completer<String>();
      f.files.pathResults.add(olderPath.future);
      final old = f.editor.loadRecentFiles();
      f.files.libraryRoot = p.join(f.run.path, 'other-library');
      await f.editor.loadRecentFiles();
      olderPath.completeError(StateError('synthetic-stale-path-detail'));
      await old;
      expect(f.editor.operationResultNotifier.value, isNull);
      expect(f.reader.requests.last.directoryPath, f.files.libraryRoot);
    },
  );

  searchTest(
    'inventory replacement before debounce filters only the latest immutable list',
    (tester, f) async {
      f.publish(['Old Alpha']);
      f.editor.setSearchQuery('Alpha');
      f.publish(['Latest Alpha']);
      await tester.pump(const Duration(milliseconds: 300));
      expect(f.filters, hasLength(1));
      final job = f.filters.single;
      expect(job.files.single.title, 'Latest Alpha');
      expect(() => job.files.clear(), throwsUnsupportedError);
      job.result.complete(job.files);
      await tester.pump();
      expect(f.editor.recentFiles.single.title, 'Latest Alpha');
    },
  );
}

class _FilterJob {
  _FilterJob(this.files, this.query);
  final List<RecentFile> files;
  final String query;
  final result = Completer<List<RecentFile>>();
}

class _Fixture {
  _Fixture() {
    run = Directory.systemTemp.createTempSync('future-notes-validation-');
    environment = StorageEnvironment.validation(
      validationRoot: run.path,
      dataRoot: p.join(run.path, 'library'),
      settingsFile: p.join(run.path, 'configuration', 'settings.json'),
    );
    settings = _Settings(environment);
    files = _Files(environment.dataRoot!);
    reader = _Reader(environment);
    editor = ContentViewModel(
      fileService: files,
      encryptionService: SyntheticCipher(),
      settings: settings,
      backgroundService: reader,
      filterRecentFiles: (files, query) {
        final job = _FilterJob(files, query);
        filters.add(job);
        return job.result.future;
      },
    );
  }
  late final Directory run;
  late final StorageEnvironment environment;
  late final _Settings settings;
  late final _Files files;
  late final _Reader reader;
  late final ContentViewModel editor;
  final filters = <_FilterJob>[];
  bool disposed = false;
  RecentFile file(String title) => RecentFile(
    path: '$title.enc',
    fullPath: p.join(environment.dataRoot!, '$title.enc'),
    title: title,
  );
  void publish(List<String> titles) =>
      reader.publish(titles.map(file).toList());
  void disposeEditor() {
    if (disposed) {
      return;
    }
    disposed = true;
    editor.dispose();
  }

  Future<void> close() async {
    disposeEditor();
    settings.themeModeNotifier.dispose();
    await deleteValidationRun(run);
  }
}

// Injected settings/scanner/file services perform no native reads or writes.
class _Settings extends SettingsService {
  _Settings(StorageEnvironment environment)
    : super.withStorage(storage: environment);
  @override
  Future<void> init() async {}
}

class _Files extends MemoryNoteFiles {
  _Files(super.libraryRoot);
  final pathResults = <Future<String>>[];
  @override
  Future<String> getUserDataPath() =>
      pathResults.isEmpty ? Future.value(libraryRoot) : pathResults.removeAt(0);
  @override
  Stream<void> watchRecentFiles() => const Stream<void>.empty();
}

class _Reader extends BackgroundService {
  _Reader(StorageEnvironment environment) : super(environment: environment);
  final snapshots = StreamController<DiscoverySnapshot>.broadcast(sync: true);
  final requests = <DiscoveryRequest>[];
  DiscoveryRequest? desired;
  bool closed = false;
  @override
  bool get isReady => !closed;
  @override
  Future<void> init() async {}
  @override
  Stream<DiscoverySnapshot> get discoveriesStream => snapshots.stream;
  @override
  bool isCurrent(DiscoveryRequest request) =>
      !closed && desired != null && desired!.matches(request);
  @override
  void invalidateRequests() {
    desired = null;
  }

  @override
  void loadRecentFiles(String path) {
    desired = DiscoveryRequest(path, 1, requests.length + 1);
    requests.add(desired!);
  }

  void publish(List<RecentFile> files, {DiscoveryRequest? request}) => snapshots
      .add(DiscoverySnapshot(request ?? desired!, files, isFinal: true));
  @override
  void dispose() {
    if (closed) {
      return;
    }
    closed = true;
    snapshots.close();
    super.dispose();
  }
}
