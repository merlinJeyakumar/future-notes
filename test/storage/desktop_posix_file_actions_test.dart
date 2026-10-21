import 'dart:io';
import 'dart:isolate';

import 'package:flutter_application_1/core/operations/operation_result.dart';
import 'package:flutter_application_1/core/storage/desktop_posix_file_actions.dart';
import 'package:flutter_application_1/core/storage/desktop_posix_native.dart';
import 'package:flutter_application_1/core/storage/storage_environment.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../support/validation_directory.dart';

void main() {
  late Directory run;
  late String root;
  late StorageEnvironment environment;

  setUp(() async {
    // macOS /var may alias /private/var. Capture the canonical temp root before
    // ownership checks and cleanup rather than weakening symlink rejection.
    final temporaryRoot = Directory(
      await Directory.systemTemp.resolveSymbolicLinks(),
    );
    run = await temporaryRoot.createTemp('future-notes-validation-');
    root = p.join(run.path, 'library');
    await Directory(root).create();
    environment = StorageEnvironment.validation(
      validationRoot: run.path,
      dataRoot: root,
      settingsFile: p.join(run.path, 'configuration', 'settings.json'),
    );
  });
  tearDown(() => deleteValidationRun(run));

  DesktopPosixFileActions actions(_Operations operations) =>
      DesktopPosixFileActions(
        root: root,
        environment: environment,
        operations: operations,
      );

  test(
    'collision after preflight retains candidate and racing destination',
    () async {
      final source = File(p.join(root, 'candidate.pending'));
      final destination = File(p.join(root, 'published.med'));
      await source.writeAsBytes([1, 2, 3], flush: true);
      final operations = _Operations(
        move: (_, to) {
          File(to).writeAsBytesSync([7, 8, 9], flush: true);
          return 17; // EEXIST on both Darwin and Linux.
        },
      );

      final result = await actions(
        operations,
      ).moveWithoutReplace(source.path, destination.path);

      expect(result.outcome, OperationOutcome.conflict);
      expect(await source.readAsBytes(), [1, 2, 3]);
      expect(await destination.readAsBytes(), [7, 8, 9]);
      expect(operations.moves, [(source.path, destination.path)]);
      expect(operations.synced, isEmpty);
    },
  );

  for (final error in [13, 18, 28, 95, -1]) {
    test(
      'native failure $error retains source without acknowledging a write',
      () async {
        final source = File(p.join(root, 'candidate.pending'));
        final destination = File(p.join(root, 'published.med'));
        await source.writeAsBytes([1, 2, 3], flush: true);
        final operations = _Operations(move: (_, __) => error);

        final result = await actions(
          operations,
        ).moveWithoutReplace(source.path, destination.path);

        expect(result.outcome, OperationOutcome.ioFailure);
        expect(await source.readAsBytes(), [1, 2, 3]);
        expect(await destination.exists(), isFalse);
        expect(operations.synced, isEmpty);
      },
    );
  }

  test(
    'an occupied destination is rejected before native publication',
    () async {
      final source = File(p.join(root, 'candidate.pending'));
      final destination = File(p.join(root, 'published.med'));
      await source.writeAsBytes([1], flush: true);
      await destination.writeAsBytes([2], flush: true);
      final operations = _Operations();

      final result = await actions(
        operations,
      ).moveWithoutReplace(source.path, destination.path);

      expect(result.outcome, OperationOutcome.conflict);
      expect(operations.moves, isEmpty);
      expect(await source.readAsBytes(), [1]);
      expect(await destination.readAsBytes(), [2]);
    },
  );

  test('same-parent publication acknowledges one directory only', () async {
    final source = File(p.join(root, 'candidate.pending'));
    final destination = File(p.join(root, 'published.med'));
    await source.writeAsBytes([0, 127, 255], flush: true);
    final operations = _Operations();

    final result = await actions(
      operations,
    ).moveWithoutReplace(source.path, destination.path);

    expect(result.isSuccess, isTrue);
    expect(await source.exists(), isFalse);
    expect(await destination.readAsBytes(), [0, 127, 255]);
    expect(operations.synced, [root]);
  });

  test(
    'nested publication syncs destination and source parents in order',
    () async {
      final source = File(
        p.join(root, '.journal', 'staging', 'candidate.pending'),
      );
      final destination = File(
        p.join(root, 'note-synthetic', 'attachment.med'),
      );
      await source.parent.create(recursive: true);
      await destination.parent.create(recursive: true);
      await source.writeAsBytes([4, 5, 6], flush: true);
      final operations = _Operations();

      final result = await actions(
        operations,
      ).moveWithoutReplace(source.path, destination.path);

      expect(result.isSuccess, isTrue);
      expect(await source.exists(), isFalse);
      expect(await destination.readAsBytes(), [4, 5, 6]);
      expect(operations.synced, [destination.parent.path, source.parent.path]);
    },
  );

  for (final failOnSync in [1, 2]) {
    test('post-move directory sync $failOnSync requires recovery', () async {
      final source = File(p.join(root, '.journal', 'candidate.pending'));
      final destination = File(
        p.join(root, 'note-synthetic', 'attachment.med'),
      );
      final predecessor = File(p.join(root, '.journal', 'predecessor.med'));
      await source.parent.create(recursive: true);
      await destination.parent.create(recursive: true);
      await source.writeAsBytes([4, 5, 6], flush: true);
      await predecessor.writeAsBytes([9, 9, 9], flush: true);
      var synced = 0;
      final operations = _Operations(
        sync: (_) {
          if (++synced == failOnSync) {
            throw const FileSystemException('Synthetic persistence failure');
          }
        },
      );

      final result = await actions(
        operations,
      ).moveWithoutReplace(source.path, destination.path);

      expect(result.outcome, OperationOutcome.recoveryRequired);
      expect(await source.exists(), isFalse);
      expect(await destination.readAsBytes(), [4, 5, 6]);
      expect(await predecessor.readAsBytes(), [9, 9, 9]);
      expect(operations.synced, hasLength(failOnSync));
    });
  }

  test(
    'post-move native lookup failures cannot report rejected input',
    () async {
      final source = File(p.join(root, 'candidate.pending'));
      final destination = File(p.join(root, 'published.med'));
      await source.writeAsBytes([4, 5, 6], flush: true);
      final operations = _Operations(
        sync: (_) {
          throw ArgumentError('Synthetic unavailable persistence symbol');
        },
      );

      final result = await actions(
        operations,
      ).moveWithoutReplace(source.path, destination.path);

      expect(result.outcome, OperationOutcome.recoveryRequired);
      expect(await source.exists(), isFalse);
      expect(await destination.readAsBytes(), [4, 5, 6]);
    },
  );

  test(
    'outside roots, traversal and aliases never reach native operations',
    () async {
      final source = File(p.join(root, 'candidate.pending'));
      await source.writeAsBytes([1], flush: true);
      for (final destination in [
        p.join(run.path, 'outside.med'),
        p.join(root, '..', 'traversal.med'),
        'relative.med',
        root,
        source.path,
      ]) {
        final operations = _Operations();
        final result = await actions(
          operations,
        ).moveWithoutReplace(source.path, destination);
        expect(
          result.outcome,
          OperationOutcome.rejectedInput,
          reason: destination,
        );
        expect(operations.moves, isEmpty);
        expect(await source.readAsBytes(), [1]);
      }
      final outside = File(p.join(run.path, 'outside.pending'));
      await outside.writeAsBytes([2], flush: true);
      final operations = _Operations();
      expect(
        (await actions(operations).moveWithoutReplace(
          outside.path,
          p.join(root, 'destination.med'),
        )).outcome,
        OperationOutcome.rejectedInput,
      );
      expect(operations.moves, isEmpty);
      expect(await outside.readAsBytes(), [2]);
    },
  );

  test('directory and missing sources cannot publish', () async {
    final directory = Directory(p.join(root, 'directory'));
    await directory.create();
    final operations = _Operations();
    for (final source in [directory.path, p.join(root, 'missing.pending')]) {
      final result = await actions(
        operations,
      ).moveWithoutReplace(source, p.join(root, 'destination.med'));
      expect(result.outcome, OperationOutcome.rejectedInput);
    }
    expect(operations.moves, isEmpty);
    expect(await directory.exists(), isTrue);
  });

  test(
    'symlink ancestors cannot redirect publication outside its root',
    () async {
      final outside = Directory(p.join(run.path, 'outside'));
      await outside.create();
      final link = Link(p.join(root, 'redirect'));
      try {
        await link.create(outside.path);
      } on FileSystemException catch (error) {
        if (Platform.isWindows && error.osError?.errorCode == 1314) {
          markTestSkipped('Windows account does not grant symlink creation.');
          return;
        }
        rethrow;
      }
      final source = File(p.join(root, 'candidate.pending'));
      await source.writeAsBytes([1], flush: true);
      final operations = _Operations();
      final result = await actions(
        operations,
      ).moveWithoutReplace(source.path, p.join(link.path, 'escaped.med'));
      expect(result.outcome, OperationOutcome.rejectedInput);
      expect(operations.moves, isEmpty);
      expect(await source.readAsBytes(), [1]);
      expect(await outside.list().isEmpty, isTrue);
      final sourceAlias = Link(p.join(root, 'source-alias.pending'));
      await sourceAlias.create(source.path);
      expect(
        (await actions(operations).moveWithoutReplace(
          sourceAlias.path,
          p.join(root, 'alias-destination.med'),
        )).outcome,
        OperationOutcome.rejectedInput,
      );
      expect(operations.moves, isEmpty);
      expect(await source.readAsBytes(), [1]);
    },
  );

  test(
    'native lease excludes another descriptor and another isolate',
    () async {
      final lock = File(p.join(root, '.future-notes-native-test.lock'));
      await lock.create(exclusive: true);
      final lease = DesktopPosixNative().lock(lock.path);
      try {
        expect(await _tryNativeLock(lock.path), Platform.isMacOS ? 35 : 11);
        expect(
          await _tryNativeLockInIsolate(lock.path),
          Platform.isMacOS ? 35 : 11,
        );
      } finally {
        await lease.close();
        await lease.close();
      }
      expect(await lock.exists(), isTrue);
      expect(await _tryNativeLock(lock.path), isNull);
    },
    skip: !DesktopPosixNative.supportedHost,
  );

  test(
    'actual desktop native publication excludes an occupied destination',
    () async {
      final source = File(p.join(root, 'native.pending'));
      final destination = File(p.join(root, 'native.med'));
      await source.writeAsBytes([1, 2, 3], flush: true);
      final native = DesktopPosixNative();
      final move = DesktopPosixFileActions(
        root: root,
        environment: environment,
        operations: native,
      );
      expect(
        (await move.moveWithoutReplace(
          source.path,
          destination.path,
        )).isSuccess,
        isTrue,
      );
      expect(await source.exists(), isFalse);
      expect(await destination.readAsBytes(), [1, 2, 3]);
      await source.writeAsBytes([4, 5, 6], flush: true);
      // Bypass Dart preflight to exercise native no-replace semantics themselves.
      expect(native.moveWithoutReplace(source.path, destination.path), 17);
      expect(await source.readAsBytes(), [4, 5, 6]);
      expect(await destination.readAsBytes(), [1, 2, 3]);
    },
    skip: !DesktopPosixNative.supportedHost,
  );
}

Future<int?> _tryNativeLock(String path) async {
  DesktopPosixLease? lease;
  try {
    lease = DesktopPosixNative().lock(path);
    return null;
  } on FileSystemException catch (error) {
    return error.osError?.errorCode ?? -1;
  } finally {
    await lease?.close();
  }
}

// A separate function captures only the path, avoiding the test closure's lease
// and native-library objects when the isolate is spawned.
Future<int?> _tryNativeLockInIsolate(String path) =>
    Isolate.run(() => _tryNativeLock(path));

class _Operations implements DesktopPosixOperations {
  _Operations({this.move, this.sync});
  final int Function(String, String)? move;
  final void Function(String)? sync;
  final moves = <(String, String)>[];
  final synced = <String>[];
  @override
  int moveWithoutReplace(String source, String destination) {
    moves.add((source, destination));
    if (move != null) return move!(source, destination);
    // Portable stand-in only; host-gated tests above own native claims.
    File(source).renameSync(destination);
    return 0;
  }

  @override
  void syncDirectory(String directory) {
    synced.add(directory);
    sync?.call(directory);
  }
}
