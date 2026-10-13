import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_application_1/core/operations/operation_result.dart';
import 'package:flutter_application_1/core/storage/storage_environment.dart';
import 'package:flutter_application_1/core/storage/windows_file_actions.dart';

import '../support/validation_directory.dart';

void main() {
  late Directory run;
  late String root;
  late WindowsFileActions moves;
  setUp(() async {
    run = await Directory.systemTemp.createTemp('future-notes-validation-');
    root = p.join(run.path, 'library');
    await Directory(root).create();
    moves = WindowsFileActions(
      root: root,
      environment: StorageEnvironment.validation(
        validationRoot: run.path,
        dataRoot: root,
        settingsFile: p.join(run.path, 'configuration', 'settings.json'),
      ),
    );
  });
  tearDown(() => deleteValidationRun(run));

  test(
    'Windows native move publishes exact bytes to an absent destination',
    () async {
      final source = File(p.join(root, 'synthetic.staged'));
      final destination = File(p.join(root, 'synthetic.enc'));
      await source.writeAsBytes([0, 1, 127, 128, 255], flush: true);
      expect(
        (await moves.moveWithoutReplace(
          source.path,
          destination.path,
        )).isSuccess,
        isTrue,
      );
      expect(await source.exists(), isFalse);
      expect(await destination.readAsBytes(), [0, 1, 127, 128, 255]);
    },
    skip: !Platform.isWindows,
  );

  test(
    'Windows native destination conflict preserves both objects',
    () async {
      final source = File(p.join(root, 'synthetic.staged'));
      final destination = File(p.join(root, 'synthetic.enc'));
      await source.writeAsString('Synthetic candidate', flush: true);
      await destination.writeAsString('Synthetic external object', flush: true);
      final result = await moves.moveWithoutReplace(
        source.path,
        destination.path,
      );
      expect(await source.readAsString(), 'Synthetic candidate');
      expect(await destination.readAsString(), 'Synthetic external object');
      expect(result.outcome, OperationOutcome.conflict, reason: result.message);
    },
    skip: !Platform.isWindows,
  );

  test(
    'Windows UTF-16 names retain Tamil and surrogate pairs',
    () async {
      final source = File(p.join(root, 'synthetic-தமிழ்-😀.staged'));
      final destination = File(p.join(root, 'synthetic-தமிழ்-🎯.enc'));
      await source.writeAsString('Synthetic Unicode fixture', flush: true);
      expect(
        (await moves.moveWithoutReplace(
          source.path,
          destination.path,
        )).isSuccess,
        isTrue,
      );
      expect(await destination.readAsString(), 'Synthetic Unicode fixture');
    },
    skip: !Platform.isWindows,
  );

  test(
    'Windows native failures preserve source and allow later retry',
    () async {
      final source = File(p.join(root, 'synthetic.staged'));
      final destination = File(p.join(root, 'missing-parent', 'synthetic.enc'));
      await source.writeAsString('Synthetic retained candidate', flush: true);
      expect(
        (await moves.moveWithoutReplace(source.path, destination.path)).outcome,
        OperationOutcome.ioFailure,
      );
      expect(await source.readAsString(), 'Synthetic retained candidate');
      await destination.parent.create();
      expect(
        (await moves.moveWithoutReplace(
          source.path,
          destination.path,
        )).isSuccess,
        isTrue,
      );
    },
    skip: !Platform.isWindows,
  );

  test(
    'Windows move rejects traversal, stream, NUL, device and same-object paths',
    () async {
      final source = File(p.join(root, 'synthetic.staged'));
      await source.writeAsString('Synthetic original', flush: true);
      for (final destination in [
        source.path,
        p.join(root, '..', 'outside.enc'),
        p.join(root, 'bad:stream'),
        p.join(root, 'bad\u0000name'),
        p.join(root, 'CON'),
        p.join(root, 'alias.'),
        p.join(run.path, 'outside.enc'),
      ]) {
        expect(
          (await moves.moveWithoutReplace(source.path, destination)).outcome,
          OperationOutcome.rejectedInput,
        );
        expect(await source.readAsString(), 'Synthetic original');
      }
    },
    skip: !Platform.isWindows,
  );

  test(
    'Windows missing source reports failure without destination creation',
    () async {
      final source = File(p.join(root, 'missing.staged'));
      final destination = File(p.join(root, 'synthetic.enc'));
      expect(
        (await moves.moveWithoutReplace(source.path, destination.path)).outcome,
        OperationOutcome.ioFailure,
      );
      expect(await destination.exists(), isFalse);
    },
    skip: !Platform.isWindows,
  );

  test(
    'Windows file move rejects directory sources without changing them',
    () async {
      final source = Directory(p.join(root, 'synthetic-directory'));
      await source.create();
      final result = await moves.moveWithoutReplace(
        source.path,
        p.join(root, 'destination'),
      );
      expect(result.outcome, OperationOutcome.rejectedInput);
      expect(await source.exists(), isTrue);
    },
    skip: !Platform.isWindows,
  );

  test(
    'Windows extended-length paths move without truncating names',
    () async {
      final nested = Directory(p.join(root, 'a' * 100, 'b' * 100));
      await nested.create(recursive: true);
      final source = File(p.join(nested.path, 'synthetic-தமிழ்.staged'));
      final destination = File(p.join(nested.path, 'synthetic-தமிழ்.enc'));
      expect(destination.path.length, greaterThan(260));
      await source.writeAsString(
        'Synthetic extended-path fixture',
        flush: true,
      );
      expect(
        (await moves.moveWithoutReplace(
          source.path,
          destination.path,
        )).isSuccess,
        isTrue,
      );
      expect(
        await destination.readAsString(),
        'Synthetic extended-path fixture',
      );
    },
    skip: !Platform.isWindows,
  );
}
