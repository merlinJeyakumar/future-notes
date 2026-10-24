import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/core/operations/file_operation_host.dart';
import 'package:flutter_application_1/core/platform/android_file_operations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('future_notes/jobs');
  final calls = <MethodCall>[];
  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return null;
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );

  testWidgets(
    'I/O waits for service acknowledgement and releases after completion',
    (tester) async {
      final admitted = Completer<void>();
      final finished = Completer<int>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            if (call.method == 'beginFileOperation') await admitted.future;
            return null;
          });
      final host = AndroidFileOperations(operatingSystem: 'android');
      var began = false;
      final result = host.runFileOperation(FileOperationKind.deleting, () {
        began = true;
        return finished.future;
      });
      await tester.pump();
      expect(began, isFalse);
      admitted.complete();
      await tester.pump();
      expect(began, isTrue);
      await tester.pump(const Duration(seconds: 21));
      expect(
        calls.where((c) => c.method == 'fileOperationHeartbeat'),
        hasLength(1),
      );
      expect(calls.any((c) => c.method == 'endFileOperation'), isFalse);
      finished.complete(7);
      await tester.pump();
      expect(await result, 7);
      expect(calls.last.method, 'endFileOperation');
      expect(calls.first.arguments['id'], calls.last.arguments['id']);
    },
  );

  testWidgets(
    'nested work outliving caller retains exactly one service lease',
    (tester) async {
      final child = Completer<void>();
      final host = AndroidFileOperations(operatingSystem: 'android');
      late Future<void> nested;
      final root = host.runFileOperation(
        FileOperationKind.processing,
        () async {
          nested = host.runFileOperation(
            FileOperationKind.saving,
            () => child.future,
          );
        },
      );
      await tester.pump();
      await root;
      expect(calls.map((c) => c.method), ['beginFileOperation']);
      child.complete();
      await tester.pump();
      await nested;
      expect(calls.map((c) => c.method), [
        'beginFileOperation',
        'endFileOperation',
      ]);
    },
  );

  test(
    'start denial prevents I/O; failure releases an admitted lease',
    () async {
      final host = AndroidFileOperations(operatingSystem: 'android');
      var io = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            throw PlatformException(code: 'foreground_denied');
          });
      await expectLater(
        host.runFileOperation(FileOperationKind.saving, () async {
          io = true;
        }),
        throwsA(isA<PlatformException>()),
      );
      expect(io, isFalse);
      expect(calls, hasLength(1));
      calls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return null;
          });
      await expectLater(
        host.runFileOperation(
          FileOperationKind.saving,
          () async => throw StateError('synthetic'),
        ),
        throwsStateError,
      );
      expect(calls.map((c) => c.method), [
        'beginFileOperation',
        'endFileOperation',
      ]);
    },
  );

  test(
    'other platforms preserve existing execution without native calls',
    () async {
      for (final platform in ['windows', 'macos', 'linux', 'ios']) {
        expect(
          await AndroidFileOperations(
            operatingSystem: platform,
          ).runFileOperation(FileOperationKind.saving, () async => platform),
          platform,
        );
      }
      expect(calls, isEmpty);
    },
  );
}
