import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/core/operations/operation_result.dart';
import 'package:flutter_application_1/core/platform/window_actions.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('future_notes/window');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'native commands publish acknowledged state and dispose restores frame',
    () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return {
          'maximized': call.method == 'toggleMaximize',
          'minimized': call.method == 'minimize',
        };
      });
      final actions = WindowsWindowActions();
      expect((await actions.configureFrame(true)).isSuccess, isTrue);
      expect((await actions.minimize()).isSuccess, isTrue);
      expect(actions.state.value.minimized, isTrue);
      expect((await actions.toggleMaximize()).isSuccess, isTrue);
      expect(actions.state.value.maximized, isTrue);
      expect((await actions.requestClose()).isSuccess, isTrue);
      await actions.dispose();
      expect(calls.map((c) => c.method), [
        'setFrame',
        'minimize',
        'toggleMaximize',
        'close',
        'setFrame',
      ]);
      expect(calls.first.arguments, true);
      expect(calls.last.arguments, false);
      expect(
        (await actions.requestClose()).outcome,
        OperationOutcome.cancelled,
      );
    },
  );

  test(
    'native state notifications update restore label and ignore malformed data',
    () async {
      messenger.setMockMethodCallHandler(channel, (_) async => null);
      final actions = WindowsWindowActions();
      Future<void> notify(Object? arguments) async {
        final done = Completer<void>();
        messenger.handlePlatformMessage(
          channel.name,
          const StandardMethodCodec().encodeMethodCall(
            MethodCall('windowState', arguments),
          ),
          (_) => done.complete(),
        );
        await done.future;
      }

      await notify({'maximized': true, 'minimized': false});
      expect(actions.state.value.maximized, isTrue);
      await notify({'maximized': 'bad'});
      expect(actions.state.value.maximized, isTrue);
      await notify({'maximized': false, 'minimized': true});
      expect(actions.state.value.minimized, isTrue);
      await actions.dispose();
    },
  );

  test('native command failures are typed and do not change state', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => throw PlatformException(code: 'window'),
    );
    final actions = WindowsWindowActions();
    expect(
      (await actions.configureFrame(true)).outcome,
      OperationOutcome.ioFailure,
    );
    expect((await actions.minimize()).outcome, OperationOutcome.ioFailure);
    expect(
      (await actions.toggleMaximize()).outcome,
      OperationOutcome.ioFailure,
    );
    expect((await actions.requestClose()).outcome, OperationOutcome.ioFailure);
    expect(actions.state.value.minimized, isFalse);
    await actions.dispose();
  });
}
