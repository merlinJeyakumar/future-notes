import 'dart:isolate';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../operations/operation_result.dart';
import 'native_storage_primitives.dart';
import 'storage_environment.dart';
import 'windows_file_actions.dart';
import 'posix_file_actions.dart';

/// Only explicit export destinations use this helper. Candidates live beside
/// the reviewed destination; replacement never truncates the old export.
class ExternalFileExport {
  static Future<StorageRevision> review(String destination) => Isolate.run(
    () => NativeStoragePrimitives(
      const StorageEnvironment.production(),
    ).captureRevision(destination),
  );
  static String candidatePath(String destination) => p.join(
    p.dirname(destination),
    '.future-notes-export-${const Uuid().v4()}.staged',
  );

  static Future<OperationResult<void>> publish({
    required String candidate,
    required String destination,
    required StorageRevision expected,
  }) => Isolate.run(() async {
    final primitives = NativeStoragePrimitives(
      const StorageEnvironment.production(),
    );
    final StorageFileActions actions = Platform.isAndroid || Platform.isIOS
        ? PosixFileActions(p.dirname(destination))
        : WindowsFileActions(
            root: p.dirname(destination),
            environment: const StorageEnvironment.production(),
          );
    String? prior;
    try {
      if (!p.isAbsolute(destination) ||
          !p.equals(p.dirname(candidate), p.dirname(destination)) ||
          !p.basename(candidate).startsWith('.future-notes-export-')) {
        return const OperationResult.failure(
          OperationOutcome.rejectedInput,
          'Invalid export destination.',
        );
      }
      final staged = await primitives.captureRevision(candidate);
      if (!staged.exists) {
        return const OperationResult.failure(
          OperationOutcome.ioFailure,
          'Export candidate is unavailable.',
        );
      }
      if (!(await primitives.captureRevision(destination)).matches(expected)) {
        return const OperationResult.failure(
          OperationOutcome.conflict,
          'The export destination changed.',
        );
      }
      if (expected.exists) {
        prior = p.join(
          p.dirname(destination),
          '.future-notes-export-${const Uuid().v4()}.previous',
        );
        final moved = await actions.moveWithoutReplace(destination, prior);
        if (!moved.isSuccess) {
          return OperationResult.failure(
            moved.outcome,
            'The existing export could not be retained.',
          );
        }
        if (!(await primitives.captureRevision(prior)).matches(expected)) {
          return const OperationResult.failure(
            OperationOutcome.recoveryRequired,
            'The prior export changed during replacement.',
          );
        }
      }
      final published = await actions.moveWithoutReplace(
        candidate,
        destination,
      );
      if (!published.isSuccess) {
        if (prior != null &&
            !(await primitives.captureRevision(destination)).exists) {
          await actions.moveWithoutReplace(prior, destination);
        }
        return OperationResult.failure(
          published.outcome,
          'Export publication failed; the prior copy was retained.',
        );
      }
      if (!(await primitives.captureRevision(destination)).matches(staged)) {
        return const OperationResult.failure(
          OperationOutcome.recoveryRequired,
          'Export verification failed; retained copies require inspection.',
        );
      }
      // Prior exports remain as explicit rollback material until manual cleanup.
      return const OperationResult.success();
    } catch (_) {
      return const OperationResult.failure(
        OperationOutcome.recoveryRequired,
        'Export publication failed; retained copies require inspection.',
      );
    }
  });
}
