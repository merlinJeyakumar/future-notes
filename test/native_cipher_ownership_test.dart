import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/core/platform/android_native_cipher.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('future_notes/cipher');
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
