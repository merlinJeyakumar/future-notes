import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_application_1/core/operations/operation_result.dart';
import 'package:flutter_application_1/core/storage/storage_environment.dart';
import 'package:flutter_application_1/features/dashboard/models/note_model.dart';
import 'package:flutter_application_1/features/dashboard/services/background_service.dart';

import '../support/validation_directory.dart';

void main() {
  late Directory run;
  late StorageEnvironment environment;
  late List<BackgroundService> readers;
  late List<ReceivePort> audits;
  setUp(() async {
    run = await Directory.systemTemp.createTemp('future-notes-validation-');
    environment = StorageEnvironment.validation(
      validationRoot: run.path,
      dataRoot: p.join(run.path, 'library'),
      settingsFile: p.join(run.path, 'configuration', 'settings.json'),
    );
    await Directory(environment.dataRoot!).create();
    readers = [];
    audits = [];
  });
  tearDown(() async {
    for (final reader in readers) {
      reader.dispose();
    }
    for (final audit in audits) {
      audit.close();
    }
    await deleteValidationRun(run);
  });

  Future<_ControlledReader> controlled() async {
    final audit = ReceivePort();
    audits.add(audit);
    final messages = StreamIterator<dynamic>(audit);
    final reader = BackgroundService(
      environment: environment,
      launcher: (start, exits, errors) => Isolate.spawn(
        _controlledEntry,
        <Object>[start, audit.sendPort],
        onExit: exits,
        onError: errors,
      ),
    );
    readers.add(reader);
    await reader.init();
    expect(await messages.moveNext(), isTrue);
    return _ControlledReader(reader, messages, messages.current as SendPort);
  }

  RecentFile file(String title) => RecentFile(
    path: '$title.enc',
    fullPath: p.join(environment.dataRoot!, '$title.enc'),
    title: title,
  );

  test(
    'one active scan retains only the latest of a hundred pending requests',
    () async {
      final c = await controlled();
      c.reader.loadRecentFiles(environment.dataRoot!);
      final first = await c.next();
      for (var i = 0; i < 100; i++) {
        c.reader.loadRecentFiles(environment.dataRoot!);
      }
      c.control.send(DiscoverySnapshot(first, const [], isFinal: true));
      final latest = await c.next();
      expect(latest.requestId, first.requestId + 100);
      expect(latest.rootGeneration, first.rootGeneration);
      final listed = c.reader.recentFilesStream.first;
      c.control.send(
        DiscoverySnapshot(latest, [file('Latest')], isFinal: true),
      );
      expect((await listed).single.title, 'Latest');
    },
  );

  test('superseded partial and final results never publish', () async {
    final c = await controlled();
    final published = <DiscoverySnapshot>[];
    final subscription = c.reader.discoveriesStream.listen(published.add);
    addTearDown(subscription.cancel);
    c.reader.loadRecentFiles(environment.dataRoot!);
    final before = await c.next();
    c.reader.loadRecentFiles(environment.dataRoot!);
    c.control.send(
      DiscoverySnapshot(before, [file('Old partial')], isFinal: false),
    );
    c.control.send(
      DiscoverySnapshot(before, [file('Old final')], isFinal: true),
    );
    final after = await c.next();
    final listed = c.reader.discoveriesStream.first;
    c.control.send(DiscoverySnapshot(after, [file('Current')], isFinal: true));
    await listed;
    expect(published.map((snapshot) => snapshot.files.single.title), [
      'Current',
    ]);
  });

  test(
    'changing roots changes generation and rejects prior library replies',
    () async {
      final c = await controlled();
      c.reader.loadRecentFiles(environment.dataRoot!);
      final old = await c.next();
      final secondRoot = p.join(run.path, 'other-library');
      c.reader.loadRecentFiles(secondRoot);
      c.control.send(
        DiscoverySnapshot(old, [file('Old library')], isFinal: true),
      );
      final next = await c.next();
      expect(next.directoryPath, secondRoot);
      expect(next.rootGeneration, old.rootGeneration + 1);
      expect(c.reader.isCurrent(old), isFalse);
      expect(c.reader.isCurrent(next), isTrue);
    },
  );

  test(
    'path-resolution invalidation drops earlier pending work immediately',
    () async {
      final c = await controlled();
      c.reader.loadRecentFiles(environment.dataRoot!);
      final first = await c.next();
      c.reader.loadRecentFiles(environment.dataRoot!);
      c.reader.invalidateRequests();
      expect(c.reader.isCurrent(first), isFalse);
      c.control.send(DiscoverySnapshot(first, const [], isFinal: true));
      c.reader.loadRecentFiles(environment.dataRoot!);
      final latest = await c.next();
      expect(latest.requestId, first.requestId + 2);
    },
  );

  test(
    'unmatched and late terminal messages cannot advance another request',
    () async {
      final c = await controlled();
      c.reader.loadRecentFiles(environment.dataRoot!);
      final first = await c.next();
      c.reader.loadRecentFiles(environment.dataRoot!);
      final unknown = DiscoveryRequest(
        first.directoryPath,
        first.rootGeneration,
        99999,
      );
      c.control.send(DiscoverySnapshot(unknown, const [], isFinal: true));
      c.control.send(DiscoverySnapshot(first, const [], isFinal: true));
      final current = await c.next();
      final listed = c.reader.recentFilesStream.first;
      c.control.send(DiscoveryScanFailure(first));
      c.control.send(DiscoverySnapshot(first, const [], isFinal: true));
      c.control.send(
        DiscoverySnapshot(current, [file('Current')], isFinal: true),
      );
      expect((await listed).single.title, 'Current');
      expect(c.reader.isReady, isTrue);
    },
  );

  test(
    'superseded scan failure is silent and starts the latest pending scan',
    () async {
      final c = await controlled();
      final failures = <OperationResult<void>>[];
      final subscription = c.reader.errorsStream.listen(failures.add);
      addTearDown(subscription.cancel);
      c.reader.loadRecentFiles(environment.dataRoot!);
      final old = await c.next();
      c.reader.loadRecentFiles(environment.dataRoot!);
      c.control.send(DiscoveryScanFailure(old));
      final current = await c.next();
      final listed = c.reader.recentFilesStream.first;
      c.control.send(DiscoverySnapshot(current, const [], isFinal: true));
      await listed;
      expect(failures, isEmpty);
    },
  );

  test('current scan failure is typed and a refresh can retry', () async {
    final c = await controlled();
    c.reader.loadRecentFiles(environment.dataRoot!);
    final first = await c.next();
    final failed = c.reader.errorsStream.first;
    c.control.send(DiscoveryScanFailure(first));
    expect((await failed).outcome, OperationOutcome.ioFailure);
    expect(c.reader.isReady, isTrue);
    c.reader.loadRecentFiles(environment.dataRoot!);
    final next = await c.next();
    expect(next.requestId, greaterThan(first.requestId));
    final listed = c.reader.recentFilesStream.first;
    c.control.send(DiscoverySnapshot(next, const [], isFinal: true));
    expect(await listed, isEmpty);
  });

  test(
    'disposal rejects queued work and closes publication during an active scan',
    () async {
      final c = await controlled();
      c.reader.loadRecentFiles(environment.dataRoot!);
      final active = await c.next();
      c.reader.loadRecentFiles(environment.dataRoot!);
      final closed = c.reader.discoveriesStream.toList();
      c.reader.dispose();
      c.control.send(DiscoverySnapshot(active, [file('Late')], isFinal: true));
      expect(await closed, isEmpty);
      expect(
        () => c.reader.loadRecentFiles(environment.dataRoot!),
        throwsA(
          isA<BackgroundServiceFailure>().having(
            (error) => error.outcome,
            'outcome',
            OperationOutcome.cancelled,
          ),
        ),
      );
    },
  );

  Future<List<DiscoverySnapshot>> realScan(int count) async {
    for (var i = 0; i < count; i++) {
      await File(
        p.join(environment.dataRoot!, 'synthetic-$i.enc'),
      ).writeAsString(
        jsonEncode({
          'id': 'synthetic-$i',
          'title': 'Synthetic $i',
          'content': 'Synthetic body',
          'isLocked': false,
          'timestamp': 1700000000000,
          'attachments': [],
        }),
      );
    }
    final reader = BackgroundService(environment: environment);
    readers.add(reader);
    await reader.init();
    final snapshots = <DiscoverySnapshot>[];
    final done = Completer<void>();
    final subscription = reader.discoveriesStream.listen((snapshot) {
      snapshots.add(snapshot);
      if (snapshot.isFinal) {
        done.complete();
      }
    });
    addTearDown(subscription.cancel);
    reader.loadRecentFiles(environment.dataRoot!);
    await done.future;
    return snapshots;
  }

  test(
    'large real synthetic inventory publishes one initial batch and one final list',
    () async {
      final snapshots = await realScan(125);
      expect(snapshots.map((snapshot) => snapshot.files.length), [10, 125]);
      expect(snapshots.map((snapshot) => snapshot.isFinal), [false, true]);
      expect(snapshots.first.request.matches(snapshots.last.request), isTrue);
      expect(() => snapshots.last.files.clear(), throwsUnsupportedError);
    },
  );

  test(
    'ten or fewer actual synthetic notes produce only the final snapshot',
    () async {
      final snapshots = await realScan(10);
      expect(snapshots, hasLength(1));
      expect(snapshots.single.files, hasLength(10));
      expect(snapshots.single.isFinal, isTrue);
    },
  );

  test('invalid root input is rejected before sending any request', () async {
    final c = await controlled();
    for (final path in [
      'relative-library',
      '${environment.dataRoot!}${p.separator}..${p.separator}other',
    ]) {
      expect(
        () => c.reader.loadRecentFiles(path),
        throwsA(
          isA<BackgroundServiceFailure>().having(
            (error) => error.outcome,
            'outcome',
            OperationOutcome.rejectedInput,
          ),
        ),
      );
    }
    c.reader.loadRecentFiles(environment.dataRoot!);
    expect((await c.next()).requestId, 1);
  });
}

class _ControlledReader {
  _ControlledReader(this.reader, this.messages, this.control);
  final BackgroundService reader;
  final StreamIterator<dynamic> messages;
  final SendPort control;
  Future<DiscoveryRequest> next() async {
    if (!await messages.moveNext()) {
      throw StateError('Test audit closed.');
    }
    return messages.current as DiscoveryRequest;
  }
}

// This test reader performs no filesystem operations and owns no writer leases.
void _controlledEntry(List<Object> arguments) {
  final start = arguments[0] as BackgroundWorkerStart;
  final audit = arguments[1] as SendPort;
  final controls = ReceivePort();
  final commands = ReceivePort();
  audit.send(controls.sendPort);
  start.replies.send(commands.sendPort);
  commands.listen(audit.send);
  controls.listen(start.replies.send);
}
