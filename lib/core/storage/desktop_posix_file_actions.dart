import 'dart:io';
import 'package:path/path.dart' as p;
import '../operations/operation_result.dart';
import 'desktop_posix_native.dart';
import 'storage_environment.dart';
import 'storage_file_actions.dart';

/// Desktop POSIX publication, distinct from mobile private export semantics.
/// Injected operations allow portable contract tests; actual native semantics
/// still require the target filesystem/host acceptance gate.
class DesktopPosixFileActions implements StorageFileActions {
  DesktopPosixFileActions({
    required this.root,
    required this.environment,
    DesktopPosixOperations? operations,
  }) : _operations = operations ?? DesktopPosixNative();
  final String root;
  final StorageEnvironment environment;
  final DesktopPosixOperations _operations;

  Future<void> _verify(String path) async {
    if (!p.isAbsolute(root) ||
        p.split(root).contains('..') ||
        !p.isAbsolute(path) ||
        p.split(path).contains('..') ||
        !p.isWithin(p.normalize(root), p.normalize(path))) {
      throw const FormatException('Move must remain inside its captured root.');
    }
    await environment.verifyLocation(path);
    var cursor = p.normalize(path);
    while (true) {
      if (await FileSystemEntity.type(cursor, followLinks: false) ==
          FileSystemEntityType.link) {
        throw const FormatException('Publication cannot traverse links.');
      }
      final parent = p.dirname(cursor);
      if (parent == cursor) break;
      cursor = parent;
    }
  }

  @override
  Future<OperationResult<void>> moveWithoutReplace(
    String source,
    String destination,
  ) async {
    var moved = false;
    try {
      await _verify(source);
      await _verify(destination);
      if (p.equals(source, destination) ||
          await FileSystemEntity.type(source, followLinks: false) !=
              FileSystemEntityType.file) {
        return const OperationResult.failure(
          OperationOutcome.rejectedInput,
          'A distinct regular source is required.',
        );
      }
      if (await FileSystemEntity.type(destination, followLinks: false) !=
          FileSystemEntityType.notFound) {
        return const OperationResult.failure(
          OperationOutcome.conflict,
          'Move destination already exists.',
        );
      }
      final code = _operations.moveWithoutReplace(source, destination);
      if (DesktopPosixNative.isNameConflict(code)) {
        return const OperationResult.failure(
          OperationOutcome.conflict,
          'Move destination already exists; source retained.',
        );
      }
      if (code != 0) {
        return const OperationResult.failure(
          OperationOutcome.ioFailure,
          'The filesystem could not publish without replacement; source retained.',
        );
      }
      moved = true;
      _operations.syncDirectory(p.dirname(destination));
      if (!p.equals(p.dirname(source), p.dirname(destination)))
        _operations.syncDirectory(p.dirname(source));
      return const OperationResult.success();
    } on FormatException {
      return OperationResult.failure(
        moved
            ? OperationOutcome.recoveryRequired
            : OperationOutcome.rejectedInput,
        'Invalid native publication path.',
      );
    } on ArgumentError {
      return OperationResult.failure(
        moved
            ? OperationOutcome.recoveryRequired
            : OperationOutcome.rejectedInput,
        'Invalid native publication path.',
      );
    } on StateError {
      return OperationResult.failure(
        moved
            ? OperationOutcome.recoveryRequired
            : OperationOutcome.rejectedInput,
        'Native publication could not be admitted.',
      );
    } catch (_) {
      return OperationResult.failure(
        moved ? OperationOutcome.recoveryRequired : OperationOutcome.ioFailure,
        'Native publication could not be acknowledged; retained material requires recovery.',
      );
    }
  }
}
