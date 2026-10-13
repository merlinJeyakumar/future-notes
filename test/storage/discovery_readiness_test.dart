import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_application_1/core/operations/operation_result.dart';
import 'package:flutter_application_1/core/storage/storage_environment.dart';
import 'package:flutter_application_1/features/dashboard/services/background_service.dart';

import '../support/validation_directory.dart';

void main() {
  late Directory run;
  late StorageEnvironment environment;
  late List<BackgroundService> services;
  setUp(() async {
    run = await Directory.systemTemp.createTemp('future-notes-validation-');
    environment = StorageEnvironment.validation(
      validationRoot: run.path,
      dataRoot: p.join(run.path, 'library'),
      settingsFile: p.join(run.path, 'configuration', 'settings.json'),
    );
    await Directory(environment.dataRoot!).create();
    services = [];
  });
  tearDown(() async {
    for (final service in services) {
      service.dispose();
    }
    await deleteValidationRun(run);
  });

  BackgroundService service({
    BackgroundWorkerLauncher? launcher,
    Duration timeout = const Duration(seconds: 10),
  }) {
    final result = BackgroundService(
      environment: environment,
      launcher: launcher,
      startupTimeout: timeout,
    );
    services.add(result);
    return result;
  }

  TypeMatcher<BackgroundServiceFailure> failure(OperationOutcome outcome) =>
      isA<BackgroundServiceFailure>().having(
        (error) => error.outcome,
        'outcome',
        outcome,
      );

  Future<Isolate> launch(
    void Function(BackgroundWorkerStart) entry,
    BackgroundWorkerStart start,
    SendPort exits,
    SendPort errors,
  ) => Isolate.spawn(
    entry,
    start,
    onExit: exits,
    onError: errors,
    errorsAreFatal: true,
  );

  test(
    'awaited handshake delivers the first real synthetic library scan',
    () async {
      final file = File(p.join(environment.dataRoot!, 'synthetic.enc'));
      await file.writeAsString(
        jsonEncode({
          'id': 'synthetic-id',
          'title': 'Synthetic title',
          'content': 'Synthetic body',
          'isLocked': false,
          'timestamp': 1700000000000,
          'attachments': [],
        }),
        flush: true,
      );
      final scanner = service();
      await scanner.init();
      expect(scanner.isReady, isTrue);
      final listed = scanner.recentFilesStream.first;
      scanner.loadRecentFiles(environment.dataRoot!);
      final files = await listed;
      expect(files.single.path, 'synthetic.enc');
      expect(files.single.title, 'Synthetic title');
      expect(await file.readAsString(), contains('Synthetic body'));
      expect(() => files.clear(), throwsUnsupportedError);
    },
  );

  test(
    'concurrent and repeated initialization starts only one reader',
    () async {
      var launches = 0;
      final scanner = service(
        launcher: (start, exits, errors) {
          launches++;
          return launch(BackgroundService.workerEntry, start, exits, errors);
        },
      );
      await Future.wait([scanner.init(), scanner.init()]);
      await scanner.init();
      expect(launches, 1);
      expect(scanner.isReady, isTrue);
      final listed = scanner.recentFilesStream.first;
      scanner.loadRecentFiles(environment.dataRoot!);
      expect(await listed, isEmpty);
    },
  );

  test('scan before readiness is rejected instead of silently lost', () async {
    final scanner = service();
    expect(
      () => scanner.loadRecentFiles(environment.dataRoot!),
      throwsA(failure(OperationOutcome.rejectedInput)),
    );
    await scanner.init();
    final listed = scanner.recentFilesStream.first;
    scanner.loadRecentFiles(environment.dataRoot!);
    expect(await listed, isEmpty);
  });

  test('missing handshake reaches a typed bounded startup failure', () async {
    final scanner = service(
      timeout: const Duration(milliseconds: 40),
      launcher: (start, exits, errors) =>
          launch(_silentReader, start, exits, errors),
    );
    final event = scanner.errorsStream.first;
    await expectLater(
      scanner.init(),
      throwsA(failure(OperationOutcome.ioFailure)),
    );
    expect((await event).outcome, OperationOutcome.ioFailure);
    expect(scanner.isReady, isFalse);
    expect(
      () => scanner.loadRecentFiles(environment.dataRoot!),
      throwsA(failure(OperationOutcome.ioFailure)),
    );
  });

  test(
    'launch errors expose a sanitized outcome without raw details',
    () async {
      final scanner = service(
        launcher: (start, exits, errors) async {
          throw StateError('synthetic-sensitive-launch-detail');
        },
      );
      final event = scanner.errorsStream.first;
      await expectLater(
        scanner.init(),
        throwsA(
          failure(OperationOutcome.ioFailure).having(
            (error) => error.toString(),
            'sanitized error',
            isNot(contains('synthetic-sensitive-launch-detail')),
          ),
        ),
      );
      expect(
        (await event).message,
        isNot(contains('synthetic-sensitive-launch-detail')),
      );
      expect(scanner.isReady, isFalse);
    },
  );

  test('reader exit before handshake settles startup', () async {
    final scanner = service(
      launcher: (start, exits, errors) =>
          launch(_exitBeforeHandshake, start, exits, errors),
    );
    await expectLater(
      scanner.init(),
      throwsA(failure(OperationOutcome.ioFailure)),
    );
    expect(scanner.isReady, isFalse);
  });

  test(
    'dispose rejects initialization and scan without starting a reader',
    () async {
      var launches = 0;
      final scanner = service(
        launcher: (start, exits, errors) {
          launches++;
          return launch(BackgroundService.workerEntry, start, exits, errors);
        },
      );
      scanner.dispose();
      scanner.dispose();
      await expectLater(
        scanner.init(),
        throwsA(failure(OperationOutcome.cancelled)),
      );
      expect(
        () => scanner.loadRecentFiles(environment.dataRoot!),
        throwsA(failure(OperationOutcome.cancelled)),
      );
      expect(launches, 0);
    },
  );

  test('scan error text is sanitized and permits a later refresh', () async {
    final scanner = service(
      launcher: (start, exits, errors) =>
          launch(_scanErrorReader, start, exits, errors),
    );
    await scanner.init();
    final event = scanner.errorsStream.first;
    scanner.loadRecentFiles(environment.dataRoot!);
    final error = await event;
    expect(error.outcome, OperationOutcome.ioFailure);
    expect(error.message, isNot(contains('synthetic-sensitive-scan-detail')));
    expect(scanner.isReady, isTrue);
    final listed = scanner.recentFilesStream.first;
    scanner.loadRecentFiles(environment.dataRoot!);
    expect(await listed, isEmpty);
  });

  test(
    'unexpected ready reader exit invalidates later scan requests',
    () async {
      final scanner = service(
        launcher: (start, exits, errors) =>
            launch(_exitOnScanReader, start, exits, errors),
      );
      await scanner.init();
      final event = scanner.errorsStream.first;
      scanner.loadRecentFiles(environment.dataRoot!);
      expect((await event).outcome, OperationOutcome.ioFailure);
      expect(scanner.isReady, isFalse);
      expect(
        () => scanner.loadRecentFiles(environment.dataRoot!),
        throwsA(failure(OperationOutcome.ioFailure)),
      );
    },
  );

  test('invalid startup deadline refuses to launch the reader', () async {
    var launches = 0;
    final scanner = service(
      timeout: Duration.zero,
      launcher: (start, exits, errors) {
        launches++;
        return launch(BackgroundService.workerEntry, start, exits, errors);
      },
    );
    await expectLater(
      scanner.init(),
      throwsA(failure(OperationOutcome.rejectedInput)),
    );
    expect(launches, 0);
  });
}

// Injected workers below perform no filesystem operations and own no writer
// handles. Timeout/disposal may terminate only these read-only test isolates.
void _silentReader(BackgroundWorkerStart start) {
  ReceivePort().listen((_) {});
}

void _exitBeforeHandshake(BackgroundWorkerStart start) {}

void _scanErrorReader(BackgroundWorkerStart start) {
  final commands = ReceivePort();
  start.replies.send(commands.sendPort);
  var requests = 0;
  commands.listen((message) {
    requests++;
    start.replies.send(
      requests == 1
          ? DiscoveryScanFailure(message as DiscoveryRequest)
          : DiscoverySnapshot(
              message as DiscoveryRequest,
              const [],
              isFinal: true,
            ),
    );
  });
}

void _exitOnScanReader(BackgroundWorkerStart start) {
  final commands = ReceivePort();
  start.replies.send(commands.sendPort);
  commands.listen((_) => Isolate.exit());
}
