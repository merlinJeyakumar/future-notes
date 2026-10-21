import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_application_1/core/operations/operation_result.dart';
import 'package:flutter_application_1/core/storage/native_storage_primitives.dart';
import 'package:flutter_application_1/core/storage/recoverable_store.dart';
import 'package:flutter_application_1/core/storage/storage_environment.dart';
import 'package:flutter_application_1/core/storage/storage_owner_worker.dart';
import 'package:flutter_application_1/core/storage/validation_app_services.dart';
import 'package:flutter_application_1/features/dashboard/services/settings_service.dart';
import 'package:flutter_application_1/main.dart';

import '../support/validation_directory.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory run;
  late StorageEnvironment environment;
  late ValidationAppServices runtime;
  _RuntimeOwner? owner;
  SettingsService? settings;
  var starts = 0;

  setUp(() async {
    owner = null;
    settings = null;
    starts = 0;
    run = await createValidationRun();
    environment = StorageEnvironment.validation(
      validationRoot: run.path,
      dataRoot: p.join(run.path, 'library'),
      settingsFile: p.join(run.path, 'configuration', 'settings.json'),
    );
    runtime = ValidationAppServices(
      environment: environment,
      startOwner: (env) async {
        starts++;
        final started = await StorageOwnerWorker.start(environment: env);
        if (!started.isSuccess)
          return OperationResult.failure(started.outcome, started.message);
        owner = _RuntimeOwner(started.value!);
        return OperationResult.success(owner!);
      },
    );
  });

  tearDown(() async {
    owner?.failReleaseRoot = null;
    expect((await runtime.close()).isSuccess, isTrue);
    settings?.themeModeNotifier.dispose();
    await deleteValidationRun(run);
  });

  test('production composition is rejected before starting an owner', () {
    expect(
      () => ValidationAppServices(
        environment: const StorageEnvironment.production(),
        startOwner: (_) async {
          starts++;
          return const OperationResult.failure(
            OperationOutcome.ioFailure,
            'Unused',
          );
        },
      ),
      throwsArgumentError,
    );
    expect(starts, 0);
  });

  test(
    'startup acquires settings and library before exposing UI services',
    () async {
      expect(() => runtime.files, throwsStateError);
      final first = runtime.initialize();
      expect(identical(first, runtime.initialize()), isTrue);
      expect((await first).isSuccess, isTrue);
      settings = runtime.settings;
      expect(starts, 1);
      expect(owner!.opened, [
        p.dirname(environment.settingsFile!),
        environment.dataRoot,
      ]);
      expect(runtime.files.supportsLibrarySwitch, isTrue);
      expect(await settings!.getUserDataPath(), environment.dataRoot);
      final reference = await runtime.files.newNoteReference(
        'synthetic-runtime',
      );
      final saved = await runtime.files.writeResolved(
        reference,
        'Synthetic runtime round trip',
      );
      expect(
        await runtime.files.readResolved(saved),
        'Synthetic runtime round trip',
      );
      expect(saved.storageOwner, isNotNull);
    },
  );

  test('startup leaves existing legacy bytes unchanged', () async {
    final fixture = File(p.join(environment.dataRoot!, 'synthetic.enc'));
    await fixture.parent.create(recursive: true);
    const body =
        '  {"id":"synthetic","content":" boundary whitespace ","unknown":true}  ';
    await fixture.writeAsString(body, flush: true);
    expect((await runtime.initialize()).isSuccess, isTrue);
    settings = runtime.settings;
    expect(await fixture.readAsString(), body);
    final reference = await runtime.files.resolveNote('synthetic.enc');
    expect(await runtime.files.readResolved(reference!), body);
  });

  test(
    'corrupt settings block UI and acquired roots can be released',
    () async {
      final file = File(environment.settingsFile!);
      await file.parent.create(recursive: true);
      await file.writeAsString('{broken synthetic settings', flush: true);
      final result = await runtime.initialize();
      expect(result.outcome, OperationOutcome.recoveryRequired);
      expect(runtime.isReady, isFalse);
      expect(() => runtime.files, throwsStateError);
      expect((await runtime.close()).isSuccess, isTrue);
      expect(owner!.releases, contains(p.dirname(environment.settingsFile!)));
      expect(await file.readAsString(), '{broken synthetic settings');
    },
  );

  test(
    'partial close retains owner and retries after independent root release',
    () async {
      expect((await runtime.initialize()).isSuccess, isTrue);
      settings = runtime.settings;
      owner!.failReleaseRoot = environment.dataRoot;
      final closed = await runtime.close();
      expect(closed.outcome, OperationOutcome.recoveryRequired);
      expect(runtime.isReady, isFalse);
      expect(owner!.closes, 0);
      expect(owner!.releases, contains(p.dirname(environment.settingsFile!)));
      expect(() => runtime.files, throwsStateError);
      owner!.failReleaseRoot = null;
      expect((await runtime.close()).isSuccess, isTrue);
      expect(owner!.closes, 1);
      expect((await runtime.close()).isSuccess, isTrue);
      expect(owner!.closes, 1);
    },
  );

  test('close before initialization prevents any owner start', () async {
    expect((await runtime.close()).isSuccess, isTrue);
    expect(
      (await runtime.initialize()).outcome,
      OperationOutcome.rejectedInput,
    );
    expect(starts, 0);
  });

  test(
    'close joins in-flight initialization without exposing services',
    () async {
      final entered = Completer<void>();
      final continueStartup = Completer<void>();
      runtime = ValidationAppServices(
        environment: environment,
        startOwner: (env) async {
          entered.complete();
          await continueStartup.future;
          final started = await StorageOwnerWorker.start(environment: env);
          expect(started.isSuccess, isTrue);
          owner = _RuntimeOwner(started.value!);
          return OperationResult.success(owner!);
        },
      );
      final initializing = runtime.initialize();
      await entered.future;
      final closing = runtime.close();
      expect(runtime.isReady, isFalse);
      continueStartup.complete();
      expect((await initializing).isSuccess, isTrue);
      expect((await closing).isSuccess, isTrue);
      expect(runtime.isReady, isFalse);
      expect(owner!.closes, 1);
    },
  );

  test(
    'startup exceptions are sanitized and never expose UI services',
    () async {
      runtime = ValidationAppServices(
        environment: environment,
        startOwner: (_) async {
          throw StateError('Synthetic sensitive failure detail');
        },
      );
      final result = await runtime.initialize();
      expect(result.outcome, OperationOutcome.recoveryRequired);
      expect(result.message, isNot(contains('sensitive')));
      expect(runtime.isReady, isFalse);
      expect((await runtime.close()).isSuccess, isTrue);
    },
  );

  testWidgets('application honors injected settings and dashboard', (
    tester,
  ) async {
    final injected = SettingsService.withStorage(storage: environment);
    // No filesystem futures are created in widget fake async.
    await tester.runAsync(() async {
      await injected.init();
      await injected.setThemeMode(ThemeMode.light);
    });
    await tester.pumpWidget(
      MyApp(settings: injected, home: const Text('Synthetic dashboard')),
    );
    expect(find.text('Synthetic dashboard'), findsOneWidget);
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.light,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    injected.themeModeNotifier.dispose();
  });
}

class _RuntimeOwner implements StorageOwner {
  _RuntimeOwner(this.delegate);
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
  final opened = <String>[];
  final releases = <String>[];
  String? failReleaseRoot;
  var closes = 0;

  @override
  Future<OperationResult<StorageOwnerRoot>> openRoot(String root) {
    opened.add(root);
    return delegate.openRoot(root);
  }

  @override
  Future<OperationResult<StorageRevision>> revision(
    StorageOwnerRoot owner,
    String target,
  ) => delegate.revision(owner, target);
  @override
  Future<OperationResult<StorageRevision>> commit(
    StorageOwnerRoot owner, {
    required String target,
    required StorageRevision expected,
    required CommitFileSource source,
  }) => delegate.commit(
    owner,
    target: target,
    expected: expected,
    source: source,
  );
  @override
  RecoveryReport? recoveryFor(StorageOwnerRoot owner) =>
      delegate.recoveryFor(owner);
  @override
  Future<OperationResult<void>> releaseRoot(StorageOwnerRoot owner) {
    if (owner.root == failReleaseRoot)
      return Future.value(
        const OperationResult.failure(
          OperationOutcome.ioFailure,
          'Synthetic release failure',
        ),
      );
    releases.add(owner.root);
    return delegate.releaseRoot(owner);
  }

  @override
  Future<OperationResult<void>> close() {
    closes++;
    return delegate.close();
  }
}
