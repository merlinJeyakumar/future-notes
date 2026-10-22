import 'dart:async';
import 'dart:io';

import 'package:flutter_application_1/core/storage/owned_write.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../support/validation_directory.dart';

void main() {
  test(
    'Mac owned-write diagnostics preserve guards without disclosing paths',
    () async {
      final run = await createValidationRun();
      try {
        final allowed = p.join(run.path, 'allowed-output');
        final allowedTarget = OwnedWriteTarget.forPath(allowed);
        await allowedTarget.validate(allowed, macDiagnosticStage: 20);
        await expectLater(
          allowedTarget.validate(allowed, macDiagnosticStage: 20),
          throwsStateError,
        );

        final existing = File(p.join(run.path, 'existing-output'));
        await existing.writeAsBytes([17], flush: true);
        final existingLogs = <String>[];
        await runZoned(
          () => expectLater(
            OwnedWriteTarget.forPath(
              existing.path,
            ).validate(existing.path, macDiagnosticStage: 21),
            throwsFormatException,
          ),
          zoneSpecification: ZoneSpecification(
            print: (_, _, _, line) => existingLogs.add(line),
          ),
        );
        expect(existingLogs, [
          'FN_OWNED_WRITE_GUARD stage=21 predicate=2 type=1',
        ]);

        expect(run.path, startsWith('/private/var/'));
        final aliasRoot = run.path.replaceFirst('/private/var/', '/var/');
        final aliasOutput = p.join(aliasRoot, 'aliased-output');
        final aliasLogs = <String>[];
        await runZoned(
          () => expectLater(
            OwnedWriteTarget.forPath(
              aliasOutput,
            ).validate(aliasOutput, macDiagnosticStage: 22),
            throwsFormatException,
          ),
          zoneSpecification: ZoneSpecification(
            print: (_, _, _, line) => aliasLogs.add(line),
          ),
        );
        expect(aliasLogs, [
          'FN_OWNED_WRITE_GUARD stage=22 predicate=4 type=-1',
        ]);
        for (final line in [...existingLogs, ...aliasLogs]) {
          expect(line, isNot(contains(run.path)));
          expect(line, isNot(contains(p.basename(existing.path))));
          expect(line, isNot(contains(p.basename(aliasOutput))));
        }
      } finally {
        await deleteValidationRun(run);
      }
    },
    skip: !Platform.isMacOS,
  );
}
