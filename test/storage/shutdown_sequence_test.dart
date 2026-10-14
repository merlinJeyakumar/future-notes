import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/core/operations/operation_result.dart';
import 'package:flutter_application_1/core/operations/shutdown_sequence.dart';

void main() {
  testWidgets('slow cleanup completes the original exit wait without retry', (
    tester,
  ) async {
    final storage = Completer<OperationResult<void>>();
    var warnings = 0;
    var calls = 0;
    OperationResult<void>? response;
    final sequence = ShutdownSequence(
      closeWatchers: () async {},
      closeStorage: () {
        calls++;
        return storage.future;
      },
    );
    sequence.closeForExit(onSlow: () => warnings++).then((result) {
      response = result;
    });
    await tester.pump(const Duration(seconds: 11));
    expect(warnings, 1);
    expect(response, isNull);
    expect(calls, 1);
    storage.complete(const OperationResult.success());
    await tester.pump();
    expect(response?.isSuccess, isTrue);
    await tester.pump(const Duration(seconds: 11));
    expect(warnings, 1);
    expect(calls, 1);
  });

  testWidgets('fast cleanup cancels latency warning', (tester) async {
    var warnings = 0;
    final sequence = ShutdownSequence(
      closeWatchers: () async {},
      closeStorage: () async => const OperationResult.success(),
    );
    final closing = sequence.closeForExit(onSlow: () => warnings++);
    await tester.pump();
    expect((await closing).isSuccess, isTrue);
    await tester.pump(const Duration(seconds: 11));
    expect(warnings, 0);
  });

  testWidgets('failed exit wait retains failure for a deliberate retry', (
    tester,
  ) async {
    var warnings = 0;
    final sequence = ShutdownSequence(
      closeWatchers: () async {},
      closeStorage: () async => const OperationResult.failure(
        OperationOutcome.recoveryRequired,
        'Synthetic cleanup failure',
      ),
    );
    final closing = sequence.closeForExit(onSlow: () => warnings++);
    await tester.pump();
    expect((await closing).outcome, OperationOutcome.recoveryRequired);
    await tester.pump(const Duration(seconds: 11));
    expect(warnings, 0);
    expect(sequence.phase, ShutdownPhase.failed);
  });

  test('storage cannot release before watcher cleanup acknowledges', () async {
    final watchers = Completer<void>();
    var storageCloses = 0;
    final phases = <ShutdownPhase>[];
    final sequence = ShutdownSequence(
      closeWatchers: () => watchers.future,
      closeStorage: () async {
        storageCloses++;
        return const OperationResult.success();
      },
      onPhase: phases.add,
    );
    final closing = sequence.close();
    expect(storageCloses, 0);
    expect(identical(closing, sequence.close()), isTrue);
    watchers.complete();
    expect((await closing).isSuccess, isTrue);
    expect(phases, [
      ShutdownPhase.watchers,
      ShutdownPhase.storage,
      ShutdownPhase.complete,
    ]);
    expect((await sequence.close()).isSuccess, isTrue);
    expect(storageCloses, 1);
  });

  testWidgets(
    'timed out exit retains the same cleanup and late acknowledgement',
    (tester) async {
      final storage = Completer<OperationResult<void>>();
      var watcherCloses = 0;
      var storageCloses = 0;
      final sequence = ShutdownSequence(
        closeWatchers: () async {
          watcherCloses++;
        },
        closeStorage: () {
          storageCloses++;
          return storage.future;
        },
      );
      final owned = sequence.close();
      final exit = owned.timeout(const Duration(seconds: 10));
      Object? timeout;
      exit.then<void>(
        (_) {},
        onError: (Object error) {
          timeout = error;
        },
      );
      await tester.pump(const Duration(seconds: 10));
      expect(timeout, isA<TimeoutException>());
      expect(sequence.phase, ShutdownPhase.storage);
      expect(identical(owned, sequence.close()), isTrue);
      expect(watcherCloses, 1);
      expect(storageCloses, 1);
      storage.complete(const OperationResult.success());
      await tester.pump();
      expect((await owned).isSuccess, isTrue);
      expect(sequence.phase, ShutdownPhase.complete);
    },
  );

  test(
    'failed storage cleanup retries without closing watchers twice',
    () async {
      var watcherCloses = 0;
      var storageCloses = 0;
      final sequence = ShutdownSequence(
        closeWatchers: () async {
          watcherCloses++;
        },
        closeStorage: () async => ++storageCloses == 1
            ? const OperationResult.failure(
                OperationOutcome.recoveryRequired,
                'Synthetic cleanup failure',
              )
            : const OperationResult.success(),
      );
      expect((await sequence.close()).isSuccess, isFalse);
      expect(sequence.phase, ShutdownPhase.failed);
      expect((await sequence.close()).isSuccess, isTrue);
      expect(watcherCloses, 1);
      expect(storageCloses, 2);
    },
  );

  test(
    'watcher failure retains the stage and does not release storage',
    () async {
      var watcherCloses = 0;
      var storageCloses = 0;
      final sequence = ShutdownSequence(
        closeWatchers: () async {
          if (++watcherCloses == 1) {
            throw StateError('private synthetic detail');
          }
        },
        closeStorage: () async {
          storageCloses++;
          return const OperationResult.success();
        },
      );
      final failed = await sequence.close();
      expect(failed.outcome, OperationOutcome.recoveryRequired);
      expect(failed.message, isNot(contains('private')));
      expect(storageCloses, 0);
      expect((await sequence.close()).isSuccess, isTrue);
      expect(watcherCloses, 2);
      expect(storageCloses, 1);
    },
  );

  test('presentation failure cannot interrupt owned cleanup', () async {
    var storageCloses = 0;
    final sequence = ShutdownSequence(
      closeWatchers: () async {},
      closeStorage: () async {
        storageCloses++;
        return const OperationResult.success();
      },
      onPhase: (_) => throw StateError('Synthetic disposed presentation'),
    );
    expect((await sequence.close()).isSuccess, isTrue);
    expect(storageCloses, 1);
  });
}
