import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_application_1/core/operations/operation_result.dart';
import 'package:flutter_application_1/core/storage/external_file_export.dart';
import '../support/validation_directory.dart';
import 'package:flutter_application_1/core/storage/owned_stream_writer.dart';

void main() {
  late Directory root;
  setUp(() async {
    root = await createValidationRun();
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
  for (final verify in [false, true]) {
    test(
      'owned export verify=$verify retains predecessor without changing bytes',
      () async {
        final destination = p.join(root.path, 'owned.fnote');
        await File(destination).writeAsString('prior export', flush: true);
        final expected = await ExternalFileExport.reviewOwned(
          destination,
          verifyReadback: verify,
        );
        final writer = await OwnedStreamWriter.open(
          ExternalFileExport.candidatePath(destination),
        );
        await writer.add(List.filled(1024 * 1024, 42));
        final receipt = await writer.close(verifyReadback: verify);
        final result = await ExternalFileExport.publishOwned(
          receipt: receipt,
          destination: destination,
          expected: expected,
        );
        expect(result.isSuccess, isTrue, reason: result.message);
        expect(await File(destination).readAsBytes(), everyElement(42));
        expect(await receipt.isCurrent(), isFalse);
        expect(await receipt.isCurrent(destination), isTrue);
        expect(receipt.readbackBytes, verify ? receipt.length : 0);
        final previous = await root
            .list()
            .where((f) => f.path.endsWith('.previous'))
            .toList();
        expect(await File(previous.single.path).readAsString(), 'prior export');
      },
    );
  }
  test(
    'owned export refuses changed candidate and changed destination',
    () async {
      final destination = p.join(root.path, 'owned.fnote');
      final expected = await ExternalFileExport.reviewOwned(
        destination,
        verifyReadback: false,
      );
      final writer = await OwnedStreamWriter.open(
        ExternalFileExport.candidatePath(destination),
      );
      await writer.add([1, 2, 3]);
      final receipt = await writer.close();
      await File(destination).writeAsString('external');
      expect(
        (await ExternalFileExport.publishOwned(
          receipt: receipt,
          destination: destination,
          expected: expected,
        )).outcome,
        OperationOutcome.conflict,
      );
      await File(destination).delete();
      await File(receipt.path).writeAsBytes([4, 5, 6, 7]);
      expect(
        (await ExternalFileExport.publishOwned(
          receipt: receipt,
          destination: destination,
          expected: expected,
        )).outcome,
        OperationOutcome.conflict,
      );
      expect(await File(destination).exists(), isFalse);
    },
  );
}
