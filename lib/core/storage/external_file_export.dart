import 'dart:isolate';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../operations/operation_result.dart';
import 'native_storage_primitives.dart';
import 'storage_environment.dart';
import 'storage_file_actions_factory.dart';
import 'owned_write.dart';

/// A destination observation, not a payload checksum. Legacy callers continue
/// to use the checked review/publish API below.
class OwnedExportReview {
  OwnedExportReview._(this.path, this.stat, this.checked);
  final String path;
  final FileStat stat;
  final StorageRevision? checked;
}

/// Only explicit export destinations use this helper. Candidates live beside
/// the reviewed destination; replacement never truncates the old export.
class ExternalFileExport {
  static Future<OwnedExportReview> reviewOwned(
    String destination, {
    required bool verifyReadback,
  }) async {
    final type = await FileSystemEntity.type(destination, followLinks: false);
    if (type != FileSystemEntityType.file &&
        type != FileSystemEntityType.notFound) {
      throw const FormatException('Export destination must be a regular file.');
    }
    return OwnedExportReview._(
      destination,
      await File(destination).stat(),
      verifyReadback ? await review(destination) : null,
    );
  }

  static Future<OperationResult<void>> publishOwned({
    required OwnedWriteReceipt receipt,
    required String destination,
    required OwnedExportReview expected,
  }) async {
    if (expected.checked != null) {
      return publish(
        candidate: receipt.path,
        destination: destination,
        expected: expected.checked!,
      );
    }
    return Isolate.run(() async {
      if (!p.equals(expected.path, destination) ||
          !p.isAbsolute(destination) ||
          !p.equals(p.dirname(receipt.path), p.dirname(destination)) ||
          !p.basename(receipt.path).startsWith('.future-notes-export-')) {
        return const OperationResult.failure(
          OperationOutcome.rejectedInput,
          'Invalid owned export.',
        );
      }
      final actions = storageFileActions(
        root: p.dirname(destination),
        environment: const StorageEnvironment.production(),
      );
      bool same(FileStat a, FileStat b, {bool moved = false}) =>
          a.type == b.type &&
          a.size == b.size &&
          a.modified == b.modified &&
          (moved || a.changed == b.changed);
      Future<bool> regularOrAbsent(String path) async {
        final type = await FileSystemEntity.type(path, followLinks: false);
        return type == FileSystemEntityType.file ||
            type == FileSystemEntityType.notFound;
      }

      String? prior;
      try {
        if (!await receipt.isCurrent()) {
          return const OperationResult.failure(
            OperationOutcome.conflict,
            'Export candidate changed.',
          );
        }
        if (!await regularOrAbsent(destination) ||
            !same(expected.stat, await File(destination).stat())) {
          return const OperationResult.failure(
            OperationOutcome.conflict,
            'The export destination changed.',
          );
        }
        if (expected.stat.type == FileSystemEntityType.file) {
          prior = p.join(
            p.dirname(destination),
            '.future-notes-export-${const Uuid().v4()}.previous',
          );
          final moved = await actions.moveWithoutReplace(destination, prior);
          if (!moved.isSuccess)
            return OperationResult.failure(
              moved.outcome,
              'The existing export could not be retained.',
            );
          if (!same(expected.stat, await File(prior).stat(), moved: true)) {
            return const OperationResult.failure(
              OperationOutcome.recoveryRequired,
              'The predecessor changed; retained copies require inspection.',
            );
          }
        }
        final moved = await actions.moveWithoutReplace(
          receipt.path,
          destination,
        );
        if (!moved.isSuccess) {
          if (prior != null && !await File(destination).exists())
            await actions.moveWithoutReplace(prior, destination);
          return OperationResult.failure(
            moved.outcome,
            'Export publication failed; the prior copy was retained.',
          );
        }
        if (!await receipt.isCurrent(destination)) {
          return const OperationResult.failure(
            OperationOutcome.recoveryRequired,
            'Export identity changed during publication.',
          );
        }
        return const OperationResult.success();
      } catch (_) {
        return const OperationResult.failure(
          OperationOutcome.recoveryRequired,
          'Export publication failed; retained copies require inspection.',
        );
      }
    });
  }

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
    final actions = storageFileActions(
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
