import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_application_1/core/platform/mobile_export.dart';
import 'package:flutter_application_1/core/storage/external_file_export.dart';
import 'support/validation_directory.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory run;
  final destinations = <String>[];
  setUp(() async {
    run = await createValidationRun();
    destinations.clear();
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await MobileExport.discardAll(destinations);
    await deleteValidationRun(run);
  });
  test('platform cache alias resolves before guarded export review', () async {
    final cache = await Directory(p.join(run.path, 'cache')).create();
    final alias = Link(p.join(run.path, 'alias'));
    await alias.create(cache.path);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'getTemporaryDirectory');
          return alias.path;
        });
    // An unresolved alias is still refused; the fix must not relax guards.
    await expectLater(
      ExternalFileExport.review(p.join(alias.path, 'unresolved.txt')),
      throwsStateError,
    );
    for (var i = 0; i < 2; i++) {
      final path = await MobileExport.destination('duplicate.txt');
      destinations.add(path);
      expect(p.isWithin(await cache.resolveSymbolicLinks(), path), isTrue);
      expect((await ExternalFileExport.review(path)).exists, isFalse);
      await File(path).writeAsString('synthetic $i');
    }
    expect(destinations.toSet().length, 2);
    expect(destinations.map(p.basename), [
      'duplicate.txt',
      'duplicate (2).txt',
    ]);
    expect(await File(destinations[0]).readAsString(), 'synthetic 0');
    expect(await File(destinations[1]).readAsString(), 'synthetic 1');
    await alias.delete();
  });
}
