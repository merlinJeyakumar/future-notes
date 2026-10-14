import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_application_1/core/operations/operation_result.dart';
import 'package:flutter_application_1/core/storage/external_file_export.dart';
import '../support/validation_directory.dart';

void main() {
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('future-notes-validation-');
  });
  tearDown(() async {
    await deleteValidationRun(root);
  });
  test(
    'reviewed export replacement retains the complete previous file',
    () async {
      final destination = p.join(root.path, 'backup.fnote');
      await File(
        destination,
      ).writeAsString('previous complete export', flush: true);
      final expected = await ExternalFileExport.review(destination);
      final candidate = ExternalFileExport.candidatePath(destination);
      await File(candidate).writeAsString('new complete export', flush: true);
      final result = await ExternalFileExport.publish(
        candidate: candidate,
        destination: destination,
        expected: expected,
      );
      expect(result.isSuccess, isTrue, reason: result.message);
      expect(await File(destination).readAsString(), 'new complete export');
      final previous = await root
          .list()
          .where((entity) => entity.path.endsWith('.previous'))
          .toList();
      expect(previous, hasLength(1));
      expect(
        await File(previous.single.path).readAsString(),
        'previous complete export',
      );
    },
  );
  test(
    'destination revision conflict preserves external bytes and staged output',
    () async {
      final destination = p.join(root.path, 'backup.fnote');
      await File(destination).writeAsString('reviewed');
      final expected = await ExternalFileExport.review(destination);
      final candidate = ExternalFileExport.candidatePath(destination);
      await File(candidate).writeAsString('prepared');
      await File(destination).writeAsString('external change', flush: true);
      final result = await ExternalFileExport.publish(
        candidate: candidate,
        destination: destination,
        expected: expected,
      );
      expect(result.outcome, OperationOutcome.conflict);
      expect(await File(destination).readAsString(), 'external change');
      expect(await File(candidate).readAsString(), 'prepared');
    },
  );
}
