import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_application_1/core/platform/private_settings_store.dart';
import 'package:flutter_application_1/core/storage/storage_environment.dart';
import 'package:flutter_application_1/features/dashboard/services/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import '../support/validation_directory.dart';

class _Store implements PrivateSettingsStore {
  Map<String, dynamic>? metadata;
  bool failWrite = false;
  final writes = <Map<String, dynamic>>[];
  @override
  Future<Map<String, dynamic>?> read() async =>
      metadata == null ? null : Map.of(metadata!);
  @override
  Future<void> write(Map<String, dynamic> value) async {
    if (failWrite)
      throw const FileSystemException('Synthetic failed small write');
    writes.add(Map.of(value));
    metadata = Map.of(value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory run;
  late File legacy;
  late _Store store;
  late SettingsService settings;
  setUp(() async {
    run = await Directory.systemTemp.createTemp(
      'future-notes-validation-private-settings-',
    );
    run = Directory(await run.resolveSymbolicLinks());
    legacy = File(p.join(run.path, 'configuration', 'settings.json'));
    store = _Store();
    settings = SettingsService.withStorage(
      storage: StorageEnvironment.validation(
        validationRoot: run.path,
        dataRoot: p.join(run.path, 'library'),
        settingsFile: legacy.path,
      ),
      privateSettings: store,
    );
  });
  tearDown(() async {
    await settings.closePersistence();
    await deleteValidationRun(run);
  });

  test(
    'migration preserves original JSON, unknown fields and explicit checks',
    () async {
      await legacy.parent.create(recursive: true);
      final text = jsonEncode({
        'themeMode': ThemeMode.light.index,
        'unknown': {'kept': 'yes'},
        'attachmentPerformance': {'checkBeforeOpen': true},
      });
      await legacy.writeAsString(text);
      await settings.init();
      expect(await legacy.readAsString(), text);
      expect(settings.themeMode, ThemeMode.light);
      expect(settings.attachmentPerformance.checkBeforeOpen, isTrue);
      expect(store.metadata!['unknown'], {'kept': 'yes'});
      await settings.setThemeMode(ThemeMode.dark);
      expect(store.metadata!['unknown'], {'kept': 'yes'});
      expect(await legacy.readAsString(), text);
    },
  );
  test('missing preferences use default-off optional checks', () async {
    await settings.init();
    final checks = settings.attachmentPerformance.exportChecks(mobile: true);
    expect(checks.checkSource, isFalse);
    expect(checks.verifyOutput, isFalse);
    expect(
      settings.attachmentPerformance.validateBackupExport(mobile: true),
      isFalse,
    );
    expect(settings.attachmentPerformance.verifyLargeFileWrites, isFalse);
  });
  test(
    'failed publication retains displayed preferences and persisted metadata',
    () async {
      store.metadata = {'themeMode': ThemeMode.light.index, 'unknown': 4};
      await settings.init();
      store.failWrite = true;
      await expectLater(
        settings.setThemeMode(ThemeMode.dark),
        throwsA(isA<Exception>()),
      );
      expect(settings.themeMode, ThemeMode.light);
      expect(settings.themeModeNotifier.value, ThemeMode.light);
      expect(store.metadata, {
        'themeMode': ThemeMode.light.index,
        'unknown': 4,
      });
    },
  );
  test(
    'a malformed private record never falls back to the legacy writer',
    () async {
      store.metadata = {'themeMode': 999};
      await expectLater(settings.init(), throwsA(isA<Exception>()));
      expect(store.writes, isEmpty);
      expect(await legacy.exists(), isFalse);
    },
  );
  test(
    'queued preference updates retain both changes and close drains them',
    () async {
      store.metadata = {'unknown': 2};
      await settings.init();
      final first = settings.setThemeMode(ThemeMode.light);
      final second = settings.setCompressionLevel(CompressionLevel.none);
      await settings.closePersistence();
      await Future.wait([first, second]);
      expect(store.metadata!['themeMode'], ThemeMode.light.index);
      expect(store.metadata!['compressionLevel'], CompressionLevel.none.index);
      await expectLater(
        settings.setThemeMode(ThemeMode.dark),
        throwsA(isA<Exception>()),
      );
    },
  );

  test(
    'native channel is bounded and does not accept malformed JSON',
    () async {
      const channel = MethodChannel('test/private-settings-store');
      const native = NativePrivateSettingsStore(channel: channel);
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      var response = '[]';
      var writes = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'writeSettings') {
          writes++;
          return null;
        }
        return response;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      await expectLater(native.read(), throwsFormatException);
      response = ' ' * 65537;
      await expectLater(native.read(), throwsFormatException);
      await expectLater(
        native.write({'large': 'x' * 65537}),
        throwsFormatException,
      );
      expect(writes, 0);
      response = '{"retained":true}';
      expect(await native.read(), {'retained': true});
    },
  );
}
