import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_application_1/core/storage/storage_environment.dart';
import 'package:flutter_application_1/features/dashboard/services/background_service.dart';

import '../support/validation_directory.dart';

void main() {
  late Directory run;
  late StorageEnvironment environment;
  final readers = <BackgroundService>[];
  late String selected;
  late String unadmitted;

  setUp(() async {
    run = await createValidationRun();
    environment = StorageEnvironment.recoverable(
      dataRoot: p.join(run.path, 'initial'),
      settingsFile: p.join(run.path, 'configuration', 'settings.json'),
    );
    selected = p.join(run.path, 'selected');
    unadmitted = p.join(run.path, 'unadmitted');
    for (final root in [environment.dataRoot!, selected, unadmitted]) {
      await Directory(root).create();
    }
    await writeNote(environment.dataRoot!, 'initial');
  });
  tearDown(() async {
    for (final reader in readers) {
      reader.dispose();
    }
    readers.clear();
    await deleteValidationRun(run);
  });

  Future<BackgroundService> start({bool? refreshStorageContext}) async {
    final reader = BackgroundService(
      environment: environment,
      refreshStorageContext: refreshStorageContext,
    );
    readers.add(reader);
    await reader.init();
    expect(
      (await scan(reader, environment.dataRoot!)).files.single.title,
      'initial',
    );
    return reader;
  }

  test('real worker sees late admission and subsequent saved notes', () async {
    // The isolate has already copied its startup allowlist before admission.
    final reader = await start(refreshStorageContext: true);
    await environment.admitSelectedLibrary(selected);
    await writeNote(selected, 'first');
    expect((await scan(reader, selected)).files.single.title, 'first');

    await writeNote(selected, 'second');
    expect(
      (await scan(reader, selected)).files.map((file) => file.title),
      unorderedEquals(['first', 'second']),
    );
    expect(
      (await scan(reader, environment.dataRoot!)).files.single.title,
      'initial',
    );

    // A path alone still cannot authorize another library, even if it exists.
    await writeNote(unadmitted, 'not-authorized');
    final rejected = reader.failuresStream.first.timeout(
      const Duration(seconds: 8),
    );
    reader.loadRecentFiles(unadmitted);
    expect((await rejected).request!.directoryPath, unadmitted);
    expect(reader.isReady, isTrue);
    expect((await scan(reader, selected)).files, hasLength(2));
  });

  test('startup-only context retains its existing root boundary', () async {
    final reader = await start(refreshStorageContext: false);
    await environment.admitSelectedLibrary(selected);
    final rejected = reader.failuresStream.first.timeout(
      const Duration(seconds: 8),
    );
    reader.loadRecentFiles(selected);
    expect((await rejected).request!.directoryPath, selected);
    expect(
      (await scan(reader, environment.dataRoot!)).files.single.title,
      'initial',
    );
  });

  test('host default refreshes admissions only on macOS', () async {
    final reader = await start();
    await environment.admitSelectedLibrary(selected);
    await writeNote(selected, 'selected');
    if (Platform.isMacOS) {
      expect((await scan(reader, selected)).files.single.title, 'selected');
    } else {
      final rejected = reader.failuresStream.first.timeout(
        const Duration(seconds: 8),
      );
      reader.loadRecentFiles(selected);
      expect((await rejected).request!.directoryPath, selected);
    }
  });
}

Future<DiscoverySnapshot> scan(BackgroundService reader, String root) async {
  final result = reader.discoveriesStream
      .firstWhere((snapshot) => snapshot.isFinal)
      .timeout(const Duration(seconds: 8));
  reader.loadRecentFiles(root);
  return result;
}

Future<void> writeNote(String root, String id) =>
    File(p.join(root, '$id.enc')).writeAsString(
      jsonEncode({
        'id': id,
        'title': id,
        'content': '',
        'isLocked': false,
        'timestamp': 1700000000000,
        'attachments': [],
      }),
      flush: true,
    );
