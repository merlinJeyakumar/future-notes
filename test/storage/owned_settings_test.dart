import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_application_1/core/operations/operation_result.dart';
import 'package:flutter_application_1/core/storage/native_storage_primitives.dart';
import 'package:flutter_application_1/core/storage/owned_settings_persistence.dart';
import 'package:flutter_application_1/core/storage/recoverable_store.dart';
import 'package:flutter_application_1/core/storage/storage_environment.dart';
import 'package:flutter_application_1/core/storage/storage_owner_worker.dart';
import 'package:flutter_application_1/features/dashboard/services/settings_service.dart';

import '../support/validation_directory.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory run;
  late StorageEnvironment environment;
  late StorageOwnerWorker worker;
  late ControlledOwner owner;
  late SettingsService settings;
  late List<SettingsService> services;
  late int documentsRequests;
  late List<File> cleanupObstructions;

  setUp(() async {
    run = await Directory.systemTemp.createTemp('future-notes-validation-');
    environment = StorageEnvironment.validation(
      validationRoot: run.path,
      dataRoot: p.join(run.path, 'library'),
      settingsFile: p.join(run.path, 'configuration', 'settings.json'),
    );
    final started = await StorageOwnerWorker.start(environment: environment);
    expect(started.isSuccess, isTrue, reason: started.message);
    worker = started.value!;
    owner = ControlledOwner(worker);
    documentsRequests = 0;
    cleanupObstructions = [];
    services = [];
    settings = SettingsService.withStorage(
      storage: environment,
      storageOwner: owner,
      documentsDirectoryResolver: () async {
        documentsRequests++;
        throw StateError('Production resolution is forbidden.');
      },
    );
    services.add(settings);
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
    for (final service in services) {
      await service.closePersistence();
      service.themeModeNotifier.dispose();
    }
    expect((await worker.close()).isSuccess, isTrue);
    expect(documentsRequests, 0);
    await deleteValidationRun(run);
  });

  File getSettingsFile() => File(environment.settingsFile!);

  Future<void> fixture(String content) async {
    final file = getSettingsFile();
    await file.parent.create(recursive: true);
    await file.writeAsString(content, flush: true);
  }

  Future<File> obstructCleanup(CommitFileSource source) async {
    final sidecar = File(p.join(p.dirname(source.path), 'synthetic-sidecar'));
    await environment.verifyLocation(sidecar.path);
    cleanupObstructions.add(sidecar);
    await sidecar.writeAsString('Synthetic cleanup obstruction', flush: true);
    return sidecar;
  }

  TypeMatcher<SettingsPersistenceFailure> failure(OperationOutcome outcome) =>
      isA<SettingsPersistenceFailure>().having(
        (error) => error.outcome,
        'outcome',
        outcome,
      );

  test(
    'owned settings reject production before owner or Documents access',
    () async {
      final production = SettingsService.withStorage(
        storage: const StorageEnvironment.production(),
        storageOwner: owner,
        documentsDirectoryResolver: () async {
          documentsRequests++;
          throw StateError('Must not resolve');
        },
      );
      services.add(production);
      await expectLater(
        production.init(),
        throwsA(failure(OperationOutcome.rejectedInput)),
      );
      expect(owner.opens, 0);
      expect(await Directory(environment.dataRoot!).exists(), isFalse);
    },
  );

  test(
    'first settings Save is acknowledged with receipt and source cleanup',
    () async {
      await settings.init();
      await settings.init();
      expect(owner.opens, 1);
      expect(await getSettingsFile().exists(), isFalse);
      await settings.setThemeMode(ThemeMode.light);
      expect(settings.themeMode, ThemeMode.light);
      expect(
        jsonDecode(await getSettingsFile().readAsString())['themeMode'],
        ThemeMode.light.index,
      );
      final transactions = Directory(
        p.join(
          getSettingsFile().parent.path,
          '.future-notes-storage',
          'transactions',
        ),
      );
      expect(
        (await transactions.list().toList()).where(
          (entry) => entry.path.endsWith('.receipt'),
        ),
        hasLength(1),
      );
      expect(
        (await run.list().toList()).where(
          (entry) => p.basename(entry.path).startsWith('settings-operation-'),
        ),
        isEmpty,
      );
      expect(settings.settingsCleanupPending, isFalse);
      expect(await Directory(environment.dataRoot!).exists(), isFalse);
    },
  );

  test(
    'concurrent settings changes serialize and retain acknowledged fields',
    () async {
      final path = p.join(run.path, 'second-library');
      await Future.wait([
        settings.setThemeMode(ThemeMode.light),
        settings.setCompressionLevel(CompressionLevel.none),
        settings.setCustomDataPath(path),
        settings.setThemeMode(ThemeMode.system),
      ]);
      final saved = jsonDecode(await getSettingsFile().readAsString());
      expect(saved['themeMode'], ThemeMode.system.index);
      expect(saved['compressionLevel'], CompressionLevel.none.index);
      expect(saved['customDataPath'], path);
      expect(settings.themeMode, ThemeMode.system);
      expect(settings.compressionLevel, CompressionLevel.none);
      expect(settings.customDataPath, path);
      expect(owner.commits, 4);
    },
  );

  test(
    'theme and notifier publish only after commit acknowledgement',
    () async {
      await settings.init();
      final entered = Completer<void>();
      final release = Completer<void>();
      owner.beforeCommit = () async {
        entered.complete();
        await release.future;
      };
      var notifications = 0;
      settings.themeModeNotifier.addListener(() {
        notifications++;
        expect(settings.themeMode, settings.themeModeNotifier.value);
      });
      final saving = settings.setThemeMode(ThemeMode.light);
      await entered.future;
      expect(settings.themeMode, ThemeMode.dark);
      expect(settings.themeModeNotifier.value, ThemeMode.dark);
      expect(notifications, 0);
      expect(await getSettingsFile().exists(), isFalse);
      release.complete();
      await saving;
      expect(settings.themeMode, ThemeMode.light);
      expect(notifications, 1);
    },
  );

  test('commit failure retains theme and allows an explicit retry', () async {
    owner.failCommit = OperationOutcome.ioFailure;
    await expectLater(
      settings.setThemeMode(ThemeMode.light),
      throwsA(failure(OperationOutcome.ioFailure)),
    );
    expect(settings.themeMode, ThemeMode.dark);
    expect(settings.themeModeNotifier.value, ThemeMode.dark);
    expect(await getSettingsFile().exists(), isFalse);
    owner.failCommit = null;
    await settings.setThemeMode(ThemeMode.light);
    expect(settings.themeMode, ThemeMode.light);
  });

  test(
    'failed path setting retains effective library and fixed configuration',
    () async {
      await settings.init();
      owner.failCommit = OperationOutcome.ioFailure;
      await expectLater(
        settings.setCustomDataPath(p.join(run.path, 'candidate-library')),
        throwsA(failure(OperationOutcome.ioFailure)),
      );
      expect(settings.customDataPath, isNull);
      expect(await settings.getUserDataPath(), environment.dataRoot);
      expect(await settings.getSettingsFilePath(), environment.settingsFile);
      expect(await getSettingsFile().exists(), isFalse);
      expect(settings.settingsCleanupPending, isFalse);
    },
  );

  test(
    'copied settings retain unknown fields and exact baseline without startup rewrite',
    () async {
      final original = jsonEncode({
        'themeMode': ThemeMode.light.index,
        'compressionLevel': CompressionLevel.none.index,
        'customDataPath': p.join(run.parent.path, 'forbidden'),
        'extension': {
          'unknown': [1, true, 'synthetic'],
        },
      });
      await fixture(original);
      final originalStat = await getSettingsFile().stat();
      await settings.init();
      expect(await getSettingsFile().readAsString(), original);
      expect((await getSettingsFile().stat()).modified, originalStat.modified);
      expect(settings.themeMode, ThemeMode.light);
      expect(settings.compressionLevel, CompressionLevel.none);
      expect(await settings.getUserDataPath(), environment.dataRoot);
      expect(owner.commits, 0);
      await settings.setThemeMode(ThemeMode.dark);
      expect(jsonDecode(await getSettingsFile().readAsString())['extension'], {
        'unknown': [1, true, 'synthetic'],
      });
      final recoveries = Directory(
        p.join(
          getSettingsFile().parent.path,
          '.future-notes-storage',
          'recovery',
        ),
      );
      final baselines = (await recoveries.list(recursive: true).toList())
          .whereType<File>()
          .where((file) => p.basename(file.path) == 'baseline')
          .toList();
      expect(baselines, hasLength(1));
      expect(await baselines.single.readAsString(), original);
    },
  );

  test(
    'external same-size changes reject settings overwrite even with original mtime',
    () async {
      final original = jsonEncode({'themeMode': ThemeMode.dark.index});
      await fixture(original);
      await settings.init();
      final modified = (await getSettingsFile().stat()).modified;
      final external = jsonEncode({'themeMode': ThemeMode.light.index});
      expect(external.length, original.length);
      await fixture(external);
      await getSettingsFile().setLastModified(modified);
      await expectLater(
        settings.setCompressionLevel(CompressionLevel.none),
        throwsA(failure(OperationOutcome.conflict)),
      );
      expect(await getSettingsFile().readAsString(), external);
      expect(settings.compressionLevel, CompressionLevel.medium);
      expect(settings.themeMode, ThemeMode.dark);
    },
  );

  for (final invalid in [
    '{broken',
    jsonEncode({'compressionLevel': 2, 'themeMode': 99}),
    jsonEncode({'themeMode': 1, 'customDataPath': 12}),
  ]) {
    test(
      'malformed settings fail before partial publication: $invalid',
      () async {
        await fixture(invalid);
        await expectLater(
          settings.init(),
          throwsA(failure(OperationOutcome.rejectedInput)),
        );
        expect(settings.themeMode, ThemeMode.dark);
        expect(settings.compressionLevel, CompressionLevel.medium);
        await expectLater(
          settings.setThemeMode(ThemeMode.light),
          throwsA(failure(OperationOutcome.rejectedInput)),
        );
        expect(await getSettingsFile().readAsString(), invalid);
        expect(owner.commits, 0);
      },
    );
  }

  test('oversized settings are rejected without overwriting bytes', () async {
    final content = ' ' * (OwnedSettingsPersistence.maximumBytes + 1);
    await fixture(content);
    await expectLater(
      settings.init(),
      throwsA(failure(OperationOutcome.rejectedInput)),
    );
    expect(await getSettingsFile().length(), content.length);
    expect(owner.commits, 0);
  });

  test(
    'settings changed during load never publish prospective values',
    () async {
      await fixture(jsonEncode({'themeMode': ThemeMode.light.index}));
      owner.beforeRevision = (count) async {
        if (count == 2) {
          await fixture(jsonEncode({'themeMode': ThemeMode.system.index}));
        }
      };
      await expectLater(
        settings.init(),
        throwsA(failure(OperationOutcome.conflict)),
      );
      expect(settings.themeMode, ThemeMode.dark);
      expect(owner.commits, 0);
    },
  );

  test('settings lease conflict cannot fall back to a direct write', () async {
    await settings.init();
    final second = SettingsService.withStorage(
      storage: environment,
      storageOwner: worker,
    );
    services.add(second);
    await expectLater(
      second.init(),
      throwsA(failure(OperationOutcome.conflict)),
    );
    await expectLater(
      second.setThemeMode(ThemeMode.light),
      throwsA(failure(OperationOutcome.conflict)),
    );
    expect(await getSettingsFile().exists(), isFalse);
    await settings.setThemeMode(ThemeMode.system);
    expect(
      jsonDecode(await getSettingsFile().readAsString())['themeMode'],
      ThemeMode.system.index,
    );
  });

  test('startup recovery runs before settings values become visible', () async {
    final original = jsonEncode({'themeMode': ThemeMode.light.index});
    await fixture(original);
    final root = getSettingsFile().parent.path;
    final backend = await RecoverableStore.open(
      root: root,
      environment: environment,
      faultHook: (point, id) async {
        if (point == CommitBoundary.published) {
          throw StateError('synthetic interruption');
        }
      },
    );
    expect(backend.isSuccess, isTrue);
    final expected = await NativeStoragePrimitives(
      environment,
    ).captureRevision(getSettingsFile().path);
    final source = File(p.join(run.path, 'replacement.synthetic'));
    await source.writeAsString(
      jsonEncode({'themeMode': ThemeMode.dark.index}),
      flush: true,
    );
    final interrupted = await backend.value!.commit(
      target: 'settings.json',
      expected: expected,
      source: CommitFileSource(source.path, await source.length()),
    );
    expect(interrupted.outcome, OperationOutcome.recoveryRequired);
    await backend.value!.close();
    await settings.init();
    expect(settings.themeMode, ThemeMode.light);
    expect(await getSettingsFile().readAsString(), original);
    await settings.setCompressionLevel(CompressionLevel.none);
    expect(settings.compressionLevel, CompressionLevel.none);
  });

  test('ambiguous settings recovery cannot grant write authority', () async {
    final journal = File(
      p.join(
        getSettingsFile().parent.path,
        '.future-notes-storage',
        'transactions',
        '${'a' * 32}.json',
      ),
    );
    await journal.parent.create(recursive: true);
    await journal.writeAsString('{broken');
    await expectLater(
      settings.init(),
      throwsA(failure(OperationOutcome.recoveryRequired)),
    );
    await expectLater(
      settings.setThemeMode(ThemeMode.light),
      throwsA(failure(OperationOutcome.recoveryRequired)),
    );
    expect(await getSettingsFile().exists(), isFalse);
    expect(owner.commits, 0);
  });

  test(
    'close waits for accepted mutations and leaves independent library ownership alive',
    () async {
      await settings.init();
      final library = await worker.openRoot(environment.dataRoot!);
      expect(library.isSuccess, isTrue);
      final entered = Completer<void>();
      final release = Completer<void>();
      owner.beforeCommit = () async {
        entered.complete();
        await release.future;
      };
      final saving = settings.setThemeMode(ThemeMode.light);
      await entered.future;
      final closing = settings.closePersistence();
      await expectLater(
        settings.setCompressionLevel(CompressionLevel.none),
        throwsA(failure(OperationOutcome.rejectedInput)),
      );
      release.complete();
      await saving;
      await closing;
      expect(settings.themeMode, ThemeMode.light);
      expect(worker.isReady, isTrue);
      expect(
        (await worker.revision(library.value!, 'independent.enc')).isSuccess,
        isTrue,
      );
      expect((await worker.releaseRoot(library.value!)).isSuccess, isTrue);
      final fresh = await worker.openRoot(getSettingsFile().parent.path);
      expect(fresh.isSuccess, isTrue);
      expect((await worker.releaseRoot(fresh.value!)).isSuccess, isTrue);
    },
  );

  test(
    'close before queued initialization drains the accepted Save exactly once',
    () async {
      final saving = settings.setThemeMode(ThemeMode.light);
      final closing = settings.closePersistence();
      await saving;
      await closing;
      expect(settings.themeMode, ThemeMode.light);
      expect(owner.opens, 1);
      expect(owner.commits, 1);
    },
  );

  test(
    'close before init rejects later initialization without acquiring a lease',
    () async {
      await settings.closePersistence();
      await expectLater(
        settings.init(),
        throwsA(failure(OperationOutcome.rejectedInput)),
      );
      expect(owner.opens, 0);
    },
  );
  test(
    'acknowledged settings survive source cleanup failure and close retry',
    () async {
      await settings.init();
      late File sidecar;
      owner.beforeSourceCommit = (source) async {
        sidecar = await obstructCleanup(source);
      };
      await settings.setThemeMode(ThemeMode.light);
      expect(settings.themeMode, ThemeMode.light);
      expect(settings.themeModeNotifier.value, ThemeMode.light);
      expect(settings.settingsCleanupPending, isTrue);
      final acknowledged = await getSettingsFile().readAsString();
      final journal = Directory(
        p.join(getSettingsFile().parent.path, '.future-notes-storage'),
      );
      final retained = (await journal.list(recursive: true).toList())
          .map((entry) => p.relative(entry.path, from: journal.path))
          .toSet();
      await expectLater(
        settings.closePersistence(),
        throwsA(failure(OperationOutcome.ioFailure)),
      );
      expect(settings.settingsCleanupPending, isTrue);
      final reacquired = await worker.openRoot(getSettingsFile().parent.path);
      expect(reacquired.isSuccess, isTrue);
      expect((await worker.releaseRoot(reacquired.value!)).isSuccess, isTrue);
      await expectLater(
        settings.setThemeMode(ThemeMode.dark),
        throwsA(failure(OperationOutcome.rejectedInput)),
      );
      await sidecar.delete();
      await settings.closePersistence();
      expect(settings.settingsCleanupPending, isFalse);
      expect(await getSettingsFile().readAsString(), acknowledged);
      expect(
        (await journal.list(recursive: true).toList())
            .map((entry) => p.relative(entry.path, from: journal.path))
            .toSet(),
        retained,
      );
    },
  );

  test(
    'failed settings commit keeps its outcome despite source cleanup failure',
    () async {
      await settings.init();
      await settings.setCompressionLevel(CompressionLevel.none);
      final external = jsonEncode({
        'themeMode': ThemeMode.system.index,
        'external': true,
      });
      late File sidecar;
      owner.beforeSourceCommit = (source) async {
        sidecar = await obstructCleanup(source);
        await getSettingsFile().writeAsString(external, flush: true);
      };
      await expectLater(
        settings.setThemeMode(ThemeMode.light),
        throwsA(failure(OperationOutcome.conflict)),
      );
      expect(settings.themeMode, ThemeMode.dark);
      expect(settings.themeModeNotifier.value, ThemeMode.dark);
      expect(settings.settingsCleanupPending, isTrue);
      expect(await getSettingsFile().readAsString(), external);
      await expectLater(
        settings.closePersistence(),
        throwsA(failure(OperationOutcome.ioFailure)),
      );
      await sidecar.delete();
      await settings.closePersistence();
      expect(settings.settingsCleanupPending, isFalse);
      expect(await getSettingsFile().readAsString(), external);
    },
  );

  test(
    'thrown settings release error is sanitized and remains retryable',
    () async {
      await settings.init();
      final library = await worker.openRoot(environment.dataRoot!);
      expect(library.isSuccess, isTrue);
      var throwOnce = true;
      owner.beforeRelease = (root) async {
        if (throwOnce) {
          throwOnce = false;
          throw StateError('synthetic-sensitive-native-detail');
        }
      };
      await expectLater(
        settings.closePersistence(),
        throwsA(
          failure(OperationOutcome.recoveryRequired).having(
            (error) => error.toString(),
            'sanitized error',
            isNot(contains('synthetic-sensitive-native-detail')),
          ),
        ),
      );
      expect(
        (await worker.openRoot(getSettingsFile().parent.path)).outcome,
        OperationOutcome.conflict,
      );
      expect(
        (await worker.revision(library.value!, 'independent.enc')).isSuccess,
        isTrue,
      );
      await settings.closePersistence();
      final reacquired = await worker.openRoot(getSettingsFile().parent.path);
      expect(reacquired.isSuccess, isTrue);
      expect((await worker.releaseRoot(reacquired.value!)).isSuccess, isTrue);
      expect((await worker.releaseRoot(library.value!)).isSuccess, isTrue);
    },
  );

  test(
    'typed settings release failure retains its lease until close retry',
    () async {
      await settings.init();
      owner.failRelease = OperationOutcome.ioFailure;
      await expectLater(
        settings.closePersistence(),
        throwsA(failure(OperationOutcome.ioFailure)),
      );
      expect(
        (await worker.openRoot(getSettingsFile().parent.path)).outcome,
        OperationOutcome.conflict,
      );
      await expectLater(
        settings.setThemeMode(ThemeMode.light),
        throwsA(failure(OperationOutcome.rejectedInput)),
      );
      owner.failRelease = null;
      await settings.closePersistence();
      final reacquired = await worker.openRoot(getSettingsFile().parent.path);
      expect(reacquired.isSuccess, isTrue);
      expect((await worker.releaseRoot(reacquired.value!)).isSuccess, isTrue);
      expect(worker.isReady, isTrue);
    },
  );
}

class ControlledOwner implements StorageOwner {
  ControlledOwner(this.delegate);
  final StorageOwner delegate;
  int opens = 0;
  int revisions = 0;
  int commits = 0;
  OperationOutcome? failCommit;
  Future<void> Function()? beforeCommit;
  Future<void> Function(int count)? beforeRevision;
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
    await beforeRevision?.call(revisions);
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
    await beforeCommit?.call();
    await beforeSourceCommit?.call(source);
    if (failCommit != null) {
      return OperationResult.failure(failCommit!, 'Synthetic storage failure.');
    }
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
