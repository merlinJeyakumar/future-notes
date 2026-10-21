import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_application_1/core/platform/macos_file_access.dart';
import 'package:flutter_application_1/core/storage/storage_environment.dart';
import 'package:flutter_application_1/core/storage/storage_owner_worker.dart';
import 'package:flutter_application_1/features/dashboard/services/macos_file_service.dart';
import 'package:flutter_application_1/features/dashboard/services/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _Owner extends Fake implements StorageOwner {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/macos-picked-files');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> calls;
  late MacosFileService service;
  late Directory temporary;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp(
      'future-notes-validation-macos-input-',
    );
    temporary = Directory(await temporary.resolveSymbolicLinks());
    calls = [];
    service = MacosFileService(
      settings: SettingsService.withStorage(
        storage: StorageEnvironment.validation(
          validationRoot: temporary.path,
          dataRoot: '${temporary.path}${Platform.pathSeparator}library',
          settingsFile:
              '${temporary.path}${Platform.pathSeparator}settings.json',
        ),
      ),
      storageOwner: _Owner(),
      access: const MacosFileAccess(channel: channel),
    );
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'chooseInputs' ||
          call.method == 'retainDroppedInputs') {
        final count = (call.arguments as Map?)?['allowMultiple'] == false
            ? 1
            : 2;
        return [
          for (var i = 0; i < count; i++)
            {
              'grantToken': 'grant-$i',
              'leaseToken': 'lease-$i',
              'path': '${temporary.path}${Platform.pathSeparator}file-$i.txt',
              'identity': 'native-$i',
              'name': 'file-$i.txt',
              'length': i + 1,
            },
        ];
      }
      return null;
    });
  });
  tearDown(() async {
    await service.closePersistence();
    messenger.setMockMethodCallHandler(channel, null);
    // This test writes no payloads. An unexpected object makes cleanup fail.
    await temporary.delete();
  });

  test(
    'picker completion keeps independent scopes until each job releases',
    () async {
      final selected = (await service.pickAttachments())!;
      expect(selected.files.map((file) => file.size), [1, 2]);
      expect(calls.map((call) => call.method), ['chooseInputs']);
      expect(calls.first.arguments, {'allowMultiple': true});
      expect(
        service.sourceDisplayName(selected.files.last.path!),
        'file-1.txt',
      );
      await service.releasePickedSource(selected.files.last.path!);
      expect(calls.last.arguments, {'leaseToken': 'lease-1'});
      expect(
        service.sourceDisplayName(selected.files.first.path!),
        'file-0.txt',
      );
      await service.releasePickedSource(selected.files.first.path!);
      await service.releasePickedSource(selected.files.first.path!);
      expect(calls.where((call) => call.method == 'release').length, 2);
    },
  );

  test(
    'single import selection preserves native filter and source lease',
    () async {
      final result = (await service.pickFile(
        allowedExtensions: ['fnote', 'zip'],
      ))!;
      expect(calls.first.arguments, {
        'allowMultiple': false,
        'extensions': ['fnote', 'zip'],
      });
      expect(calls.any((call) => call.method == 'release'), isFalse);
      await service.releasePickedSource(result.files.first.path!);
    },
  );

  test(
    'drop authority is acquired before jobs and released at cleanup',
    () async {
      final files = await service.retainDroppedInputs([
        '/opaque/OS-issued-input',
      ]);
      expect(calls.first.method, 'retainDroppedInputs');
      expect(calls.length, 1);
      expect(files.length, 2);
      await service.closePersistence();
      expect(calls.where((call) => call.method == 'release').length, 2);
    },
  );
}
