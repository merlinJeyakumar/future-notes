import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/core/platform/android_native_cipher.dart';
import 'package:flutter_application_1/core/storage/streaming_file_cipher.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('future_notes/cipher');
  for (final paused in [false, true]) {
    test(
      'native stream pacing preserves bytes and cancellation while paused=$paused',
      () async {
        var cancelled = false;
        var closed = false;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              if (call.method == 'sessionOpen') return 'synthetic-session';
              if (call.method == 'sessionClose') {
                closed = true;
                return null;
              }
              expect(call.method, 'sessionProcessMeasured');
              return {
                'data': call.arguments['data'],
                'cpuMicros': 20000,
                'duty': paused ? 0.0 : .5,
              };
            });
        final session = await AndroidNativeCipher.session(
          Uint8List(32),
          Uint8List(16),
          cancelled: () => cancelled,
        );
        final timer = paused
            ? Timer(const Duration(milliseconds: 10), () => cancelled = true)
            : null;
        try {
          final watch = Stopwatch()..start();
          final task = session.process(Uint8List.fromList([1, 2, 3]));
          if (paused) {
            await expectLater(task, throwsA(isA<FileJobCancelled>()));
          } else {
            expect(await task, [1, 2, 3]);
            expect(watch.elapsedMicroseconds, greaterThanOrEqualTo(15000));
          }
        } finally {
          timer?.cancel();
          await session.close();
          expect(closed, isTrue);
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(channel, null);
        }
      },
    );
  }
  test('native stream resumes when capacity becomes available', () async {
    var samples = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          switch (call.method) {
            case 'sessionOpen':
              return 'synthetic-session';
            case 'sessionClose':
              return null;
            case 'sessionBudget':
              samples++;
              return .7;
            case 'sessionProcessMeasured':
              return {
                'data': call.arguments['data'],
                'cpuMicros': 2000,
                'duty': 0.0,
              };
            default:
              throw StateError('Unexpected native method');
          }
        });
    final session = await AndroidNativeCipher.session(
      Uint8List(32),
      Uint8List(16),
    );
    try {
      expect(await session.process(Uint8List.fromList([4, 5])), [4, 5]);
      expect(samples, greaterThanOrEqualTo(1));
    } finally {
      await session.close();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    }
  });
  test(
    'owner release waits for native acknowledgement across a transport error',
    () async {
      var calls = 0;
      var complete = false;
      final reached = Completer<void>();
      final ack = Completer<void>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'releaseOwner');
            calls++;
            if (calls == 1) {
              throw PlatformException(code: 'synthetic_transport_failure');
            }
            reached.complete();
            await ack.future;
            return null;
          });
      try {
        final released = AndroidNativeCipher.releaseOwner(
          'synthetic-owner',
        ).then((_) => complete = true);
        await reached.future;
        expect(calls, 2);
        expect(complete, isFalse);
        ack.complete();
        await released;
        expect(complete, isTrue);
      } finally {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      }
    },
  );
}
