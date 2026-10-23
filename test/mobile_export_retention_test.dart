import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_application_1/core/platform/mobile_export.dart';
import 'package:flutter_application_1/core/storage/external_file_export.dart';
import 'package:flutter_application_1/core/storage/owned_stream_writer.dart';
import 'package:flutter_application_1/core/storage/owned_write.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'support/validation_directory.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const files = MethodChannel('future_notes/files');
  const paths = MethodChannel('plugins.flutter.io/path_provider');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory run;
  final owned = <String>[];

  setUp(() async {
    run = await createValidationRun();
    owned.clear();
  });
  tearDown(() async {
    await MobileExport.discardAll(owned);
    messenger.setMockMethodCallHandler(files, null);
    messenger.setMockMethodCallHandler(paths, null);
    await deleteValidationRun(run);
  });

  test(
    'Android startup removes orphan exports without waiting for another export',
    () async {
      final retained = await Directory(
        p.join(run.path, 'files', 'prepared-exports'),
      ).create(recursive: true);
      final orphan = await Directory(
        p.join(retained.path, 'future-notes-export-interrupted'),
      ).create();
      await File(
        p.join(orphan.path, '.future-notes-export-pending.staged'),
      ).writeAsString('synthetic interrupted export');
      final unrelated = await Directory(
        p.join(retained.path, 'other-private-material'),
      ).create();
      final unrelatedFile = await File(
        p.join(unrelated.path, 'keep'),
      ).writeAsString('synthetic unrelated data');
      messenger.setMockMethodCallHandler(files, (call) async {
        expect(call.method, 'exportRoot');
        return retained.path;
      });

      await MobileExport.initialize(operatingSystem: 'android');

      expect(await orphan.exists(), isFalse);
      expect(await unrelatedFile.readAsString(), 'synthetic unrelated data');
      // A later application initialization must not retire live ownership.
      final path = await MobileExport.destination(
        'live-export.fnote',
        operatingSystem: 'android',
      );
      owned.add(path);
      await File(path).writeAsString('synthetic active export');
      await Future.wait([
        MobileExport.initialize(operatingSystem: 'android'),
        MobileExport.initialize(operatingSystem: 'android'),
      ]);
      expect(await File(path).readAsString(), 'synthetic active export');
      expect(await unrelatedFile.readAsString(), 'synthetic unrelated data');
    },
  );

  test('startup export cleanup remains Android-only', () async {
    var calls = 0;
    messenger.setMockMethodCallHandler(files, (_) async {
      calls++;
      throw PlatformException(code: 'unexpected-native-call');
    });
    messenger.setMockMethodCallHandler(paths, (_) async {
      calls++;
      throw PlatformException(code: 'unexpected-path-call');
    });
    await MobileExport.initialize(operatingSystem: 'ios');
    await MobileExport.initialize(operatingSystem: 'windows');
    expect(calls, 0);
    expect(await run.list().toList(), isEmpty);
  });

  test(
    'Android active export survives temporary-cache eviction and keeps Save/Share ownership',
    () async {
      final temporary = await Directory(p.join(run.path, 'cache')).create();
      final retained = await Directory(
        p.join(run.path, 'files', 'prepared-exports'),
      ).create(recursive: true);
      await File(p.join(temporary.path, 'discardable')).writeAsString('cache');
      var temporaryRequests = 0;
      messenger.setMockMethodCallHandler(paths, (_) async {
        temporaryRequests++;
        return temporary.path;
      });
      final actions = <String>[];
      var saveAttempts = 0;
      messenger.setMockMethodCallHandler(files, (call) async {
        if (call.method == 'exportRoot') return retained.path;
        final path = (call.arguments as Map)['path'] as String;
        expect(path, owned.single);
        expect(await File(path).exists(), isTrue);
        actions.add(call.method);
        if (call.method == 'saveExport') return ++saveAttempts > 1;
        if (call.method == 'shareExport') return true;
        throw UnsupportedError(call.method);
      });

      final destination = await MobileExport.destination(
        'Synthetic export.fnote',
        operatingSystem: 'android',
      );
      owned.add(destination);
      expect(p.isWithin(retained.path, destination), isTrue);
      expect(p.isWithin(temporary.path, destination), isFalse);
      expect(temporaryRequests, 0);
      final review = await ExternalFileExport.reviewOwned(
        destination,
        verifyReadback: false,
      );
      final candidate = ExternalFileExport.candidatePath(destination);
      final writer = await OwnedStreamWriter.open(candidate);
      final first = Uint8List.fromList(
        List.generate(256 * 1024, (i) => i % 251),
      );
      final last = Uint8List.fromList([5, 8, 13, 21, 34]);
      final expected = [...first, ...last];
      try {
        await writer.add(first);
        await temporary.delete(recursive: true);
        await writer.add(last);
        final receipt = await writer.close();
        expect(receipt.readbackBytes, 0);
        expect(receipt.sha256Hex, sha256.convert(expected).toString());
        expect(await receipt.isCurrent(), isTrue);
        final published = await ExternalFileExport.publishOwned(
          receipt: receipt,
          destination: destination,
          expected: review,
        );
        expect(published.isSuccess, isTrue, reason: published.message);
        expect(await receipt.isCurrent(destination), isTrue);
        expect(await File(destination).readAsBytes(), expected);
        expect(await MobileExport.save(destination), isFalse);
        expect(await File(destination).exists(), isTrue);
        expect(await MobileExport.sharePrepared(destination), isTrue);
        expect(await MobileExport.save(destination), isTrue);
        expect(await File(destination).readAsBytes(), expected);
        expect(actions, ['saveExport', 'shareExport', 'saveExport']);
        final unowned = await File(
          p.join(run.path, 'unowned.fnote'),
        ).writeAsString('not an export');
        await expectLater(MobileExport.save(unowned.path), throwsStateError);
        await expectLater(
          MobileExport.sharePrepared(unowned.path),
          throwsStateError,
        );
        expect(actions, hasLength(3));
      } finally {
        await writer.abort();
      }
    },
  );

  test('Android root failure cannot silently fall back to OS cache', () async {
    var temporaryRequests = 0;
    messenger.setMockMethodCallHandler(paths, (_) async {
      temporaryRequests++;
      return run.path;
    });
    messenger.setMockMethodCallHandler(files, (_) async {
      throw PlatformException(code: 'private_export_unavailable');
    });
    await expectLater(
      MobileExport.destination('synthetic.fnote', operatingSystem: 'android'),
      throwsA(isA<PlatformException>()),
    );
    expect(temporaryRequests, 0);
    expect(await run.list().toList(), isEmpty);
  });

  test('Android rejects a noncanonical native export root', () async {
    messenger.setMockMethodCallHandler(files, (_) async => 'relative/exports');
    await expectLater(
      MobileExport.destination('synthetic.fnote', operatingSystem: 'android'),
      throwsStateError,
    );
    expect(await run.list().toList(), isEmpty);
  });

  for (final remove in [false, true]) {
    test(
      'owned output still rejects ${remove ? 'missing' : 'truncated'} data',
      () async {
        final output = File(p.join(run.path, 'synthetic.fnote'));
        final target = OwnedWriteTarget.forPath(output.path);
        await target.validate(output.path);
        final bytes = [1, 2, 3, 4];
        await output.writeAsBytes(bytes);
        if (remove) {
          await output.delete();
        } else {
          await output.writeAsBytes([1]);
        }
        await expectLater(
          OwnedWriteReceipt.closed(
            target: target,
            length: bytes.length,
            sha256Hex: sha256.convert(bytes).toString(),
            verifyReadback: false,
            payloadReadBytes: bytes.length,
          ),
          throwsFormatException,
        );
      },
    );
  }
}
