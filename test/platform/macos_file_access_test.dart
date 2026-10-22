import 'package:flutter/services.dart';
import 'package:flutter_application_1/core/platform/macos_file_access.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/macos_file_access');
  const access = MacosFileAccess(channel: channel);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> calls;

  Map<String, Object> grant({String lease = 'owner'}) => {
    'grantToken': 'native-grant',
    'leaseToken': lease,
    'path': '/Volumes/Local/Notes',
    'identity': '42:123',
  };

  setUp(() => calls = []);
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('selection cancellation never accepts or replaces a library', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    expect(await access.chooseLibrary(), isNull);
    expect(calls.map((call) => call.method), ['chooseLibrary']);
  });

  test('selection is accepted only after caller admission', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return call.method == 'chooseLibrary' ? grant() : null;
    });
    final selected = (await access.chooseLibrary())!;
    expect(selected.path, '/Volumes/Local/Notes');
    expect(selected.identity, '42:123');
    expect(calls.map((call) => call.method), ['chooseLibrary']);
    await selected.accept();
    expect(calls.last.arguments, {'grantToken': 'native-grant'});
    await selected.close();
    expect(calls.map((call) => call.method), [
      'chooseLibrary',
      'acceptLibrary',
      'release',
    ]);
  });

  test(
    'rejected selection releases its lease without replacing bookmark',
    () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return call.method == 'chooseLibrary' ? grant() : null;
      });
      final selected = (await access.chooseLibrary())!;
      await selected.close();
      await selected.close();
      expect(calls.map((call) => call.method), ['chooseLibrary', 'release']);
      expect(calls.last.arguments, {'leaseToken': 'owner'});
    },
  );

  test(
    'restoration supplies expected path and never requests a panel',
    () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return grant();
      });
      final restored = await access.restoreLibrary(
        expectedPath: '/Volumes/Local/Notes',
      );
      expect(restored!.identity, '42:123');
      expect(calls.single.method, 'restoreLibrary');
      expect(calls.single.arguments, {'expectedPath': '/Volumes/Local/Notes'});
    },
  );

  test(
    'denied or moved restoration preserves typed errors without prompts',
    () async {
      for (final code in [
        'access_denied',
        'library_changed',
        'entitlement_missing',
      ]) {
        calls.clear();
        messenger.setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          throw PlatformException(
            code: code,
            message: 'Choose the folder again.',
          );
        });
        await expectLater(
          access.restoreLibrary(expectedPath: '/Volumes/Local/Notes'),
          throwsA(
            isA<PlatformException>().having(
              (error) => error.code,
              'code',
              code,
            ),
          ),
        );
        expect(calls.single.method, 'restoreLibrary');
      }
    },
  );

  test('a job retains independent scope after its UI owner closes', () async {
    final liveLeases = <String>{};
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'chooseLibrary':
          liveLeases.add('owner');
          return grant();
        case 'acquire':
          liveLeases.add('job');
          return 'job';
        case 'release':
          liveLeases.remove((call.arguments as Map)['leaseToken']);
          return null;
      }
      fail('Unexpected native operation.');
    });
    final selected = (await access.chooseLibrary())!;
    final job = await selected.acquire();
    await selected.close();
    expect(liveLeases, {'job'});
    expect(selected.acquire(), throwsStateError);
    expect(() => selected.accept(), throwsStateError);
    await job.close();
    await job.close();
    expect(liveLeases, isEmpty);
    expect(calls.where((call) => call.method == 'release'), hasLength(2));
  });

  test('failed release can retry the same idempotent native lease', () async {
    var failures = 1;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'chooseLibrary') return grant();
      if (failures-- > 0) {
        throw PlatformException(code: 'temporary_unavailable');
      }
      return null;
    });
    final selected = (await access.chooseLibrary())!;
    await expectLater(selected.close(), throwsA(isA<PlatformException>()));
    await selected.close();
    expect(calls.where((call) => call.method == 'release'), hasLength(2));
  });

  test(
    'multiple input files retain separate leases with metadata only',
    () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return call.method == 'chooseInputs'
            ? [
                {
                  ...grant(lease: 'input-a'),
                  'name': 'Video A.mp4',
                  'length': 75000000,
                },
                {...grant(lease: 'input-b'), 'name': '資料 B.pdf', 'length': 123},
              ]
            : null;
      });
      final inputs = (await access.chooseInputs())!;
      expect(inputs.map((input) => input.name), ['Video A.mp4', '資料 B.pdf']);
      expect(inputs.first.length, 75000000);
      await inputs.first.close();
      await inputs.last.close();
      expect(calls.map((call) => call.method), [
        'chooseInputs',
        'release',
        'release',
      ]);
      expect(calls.skip(1).map((call) => call.arguments), [
        {'leaseToken': 'input-a'},
        {'leaseToken': 'input-b'},
      ]);
    },
  );

  test(
    'save cancellation grants no access and keeps prepared output',
    () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return null;
      });
      expect(
        await access.chooseSaveTarget(suggestedName: 'Meeting.fnote'),
        isNull,
      );
      expect(calls.single.method, 'chooseSaveTarget');
      expect(calls.single.arguments, {'suggestedName': 'Meeting.fnote'});
      await expectLater(
        access.chooseSaveTarget(suggestedName: '../Notes.fnote'),
        throwsArgumentError,
      );
      expect(calls, hasLength(1));
    },
  );
}
