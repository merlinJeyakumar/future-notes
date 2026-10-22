import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_application_1/core/platform/macos_file_access.dart';
import 'package:flutter_application_1/core/storage/desktop_storage_bootstrap.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import '../support/validation_directory.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory run;
  late Directory documents;
  late File settings;
  const channel = MethodChannel('test/desktop-startup-permissions');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() async {
    run = await Directory.systemTemp.createTemp(
      'future-notes-validation-desktop-startup-',
    );
    run = Directory(await run.resolveSymbolicLinks());
    documents = Directory(p.join(run.path, 'Documents'));
    settings = File(p.join(documents.path, 'UserData', 'settings.json'));
  });
  tearDown(() async {
    messenger.setMockMethodCallHandler(channel, null);
    await deleteValidationRun(run);
  });
  Future<DesktopStoragePlan> resolve({bool mac = false}) =>
      DesktopStorageBootstrap.resolve(
        documentsDirectory: () async => documents,
        requiresMacosGrant: mac,
        access: const MacosFileAccess(channel: channel),
      );

  test(
    'fresh startup captures original location without creating or relocating it',
    () async {
      final plan = await resolve();
      expect(plan.environment.dataRoot, settings.parent.path);
      expect(plan.environment.settingsFile, settings.path);
      expect(await documents.exists(), isFalse);
    },
  );
  test(
    'existing settings and unknown fields remain byte-for-byte unchanged',
    () async {
      await settings.parent.create(recursive: true);
      final library = p.join(run.path, 'Selected notes – local');
      final text = jsonEncode({
        'customDataPath': library,
        'unknown': {'retained': true},
      });
      await settings.writeAsString(text);
      final plan = await resolve();
      expect(plan.environment.dataRoot, library);
      expect(await settings.readAsString(), text);
      expect(await Directory(library).exists(), isFalse);
    },
  );
  test(
    'missing/revoked Mac authority requires explicit selection without automatic prompts',
    () async {
      await settings.parent.create(recursive: true);
      final library = p.join(run.path, 'Selected');
      await settings.writeAsString(jsonEncode({'customDataPath': library}));
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return null;
      });
      await expectLater(
        resolve(mac: true),
        throwsA(isA<DesktopLibraryAccessRequired>()),
      );
      expect(calls.map((call) => call.method), ['restoreLibrary']);
      expect(calls.single.arguments, {'expectedPath': library});
      expect(await Directory(library).exists(), isFalse);
    },
  );
  test(
    'malformed and oversized settings fail closed without native prompts',
    () async {
      await settings.parent.create(recursive: true);
      for (final contents in [
        '{broken',
        jsonEncode({'customDataPath': 7}),
        ' ' * (65536 + 1),
      ]) {
        await settings.writeAsString(contents);
        await expectLater(resolve(mac: true), throwsFormatException);
        expect(await settings.readAsString(), contents);
      }
    },
  );
}
