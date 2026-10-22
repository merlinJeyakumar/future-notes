import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/core/operations/operation_result.dart';
import 'package:flutter_application_1/core/platform/linux_desktop_actions.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('future_notes/desktop_linux');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('cache location is native-owned and rejects arbitrary roots', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return '/home/synthetic/.cache/future-notes/attachment-preview';
    });
    final actions = LinuxDesktopActions();
    expect(await actions.cacheRoot(), contains('/future-notes/'));
    expect(calls.single.method, 'cacheRoot');
    expect(calls.single.arguments, isNull);
    await expectLater(
      actions.cacheRoot(validationRoot: '/tmp/other'),
      throwsArgumentError,
    );
    expect(calls.length, 1);
  });

  test('malformed native cache responses fail without a fallback', () async {
    final actions = LinuxDesktopActions();
    for (final response in [null, 'relative', 'fnotes://attachment/id']) {
      messenger.setMockMethodCallHandler(channel, (_) async => response);
      await expectLater(actions.cacheRoot(), throwsFormatException);
    }
  });

  test('local open and reveal preserve Unicode and spaces', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    final actions = LinuxDesktopActions();
    const path = '/home/synthetic/cache/குறிப்பு image.png';
    expect((await actions.openFile(path)).isSuccess, isTrue);
    expect((await actions.revealFile(path)).isSuccess, isTrue);
    expect(calls.map((call) => call.method), ['openFile', 'revealFile']);
    expect(calls.map((call) => call.arguments), [
      {'path': path},
      {'path': path},
    ]);
  });

  test('URI schemes and traversal never reach the native launcher', () async {
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (_) async {
      calls++;
      return null;
    });
    final actions = LinuxDesktopActions();
    for (final path in [
      'fnotes://attachment/id',
      'note://id',
      'file:///tmp/file',
      'https://example.invalid',
      'relative',
      '/tmp/../private/file',
      '/tmp/file\u0000other',
    ]) {
      expect(
        (await actions.openFile(path)).outcome,
        OperationOutcome.rejectedInput,
      );
      expect(
        (await actions.revealFile(path)).outcome,
        OperationOutcome.rejectedInput,
      );
    }
    expect(calls, 0);
  });

  test('portal cancellation and failures remain typed and sanitized', () async {
    final actions = LinuxDesktopActions();
    for (final (code, expected) in [
      ('cancelled', OperationOutcome.cancelled),
      ('invalid_path', OperationOutcome.rejectedInput),
      ('portal_unavailable', OperationOutcome.ioFailure),
      ('portal_failed', OperationOutcome.ioFailure),
    ]) {
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => throw PlatformException(
          code: code,
          message: 'synthetic private diagnostic',
        ),
      );
      final result = await actions.openFile('/tmp/synthetic');
      expect(result.outcome, expected);
      expect(result.message, isNot(contains('private diagnostic')));
    }
  });

  test(
    'dispose cancels native presentation once and prevents new work',
    () async {
      var calls = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'dispose');
        calls++;
        return null;
      });
      final actions = LinuxDesktopActions();
      await actions.dispose();
      await actions.dispose();
      expect(calls, 1);
      expect(
        (await actions.openFile('/tmp/synthetic')).outcome,
        OperationOutcome.cancelled,
      );
      await expectLater(actions.cacheRoot(), throwsStateError);
    },
  );
}
