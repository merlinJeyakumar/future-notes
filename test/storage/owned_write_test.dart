import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_application_1/core/storage/owned_write.dart';
import 'package:flutter_application_1/core/storage/streaming_file_cipher.dart';
import '../support/validation_directory.dart';

void main() {
  late Directory run;
  setUp(() async => run = await createValidationRun());
  tearDown(() => deleteValidationRun(run));
  for (final verify in [false, true]) {
    test(
      'owned encrypted write verify=$verify has exact inline checksum and pass counts',
      () async {
        final source = File(p.join(run.path, 'source'));
        await source.writeAsString('Synthetic payload' * 1024);
        final destination = p.join(run.path, 'cipher.med');
        final phases = <String>[];
        final result = await StreamingFileCipher.transform(
          source: StreamingFileSource(source.path, await source.length()),
          destination: destination,
          decryptSource: false,
          encryptDestination: true,
          ownedTarget: OwnedWriteTarget.forPath(destination),
          verifyOutput: verify,
          useNative: false,
          progress: (phase, _, _) => phases.add(phase),
        );
        final receipt = result.receipt!;
        expect(await receipt.isCurrent(), isTrue);
        expect(receipt.payloadReadBytes, await source.length());
        expect(receipt.readbackBytes, verify ? result.length : 0);
        expect(phases.contains('Verifying'), verify);
        expect(
          receipt.sha256Hex,
          sha256.convert(await File(destination).readAsBytes()).toString(),
        );
        final plain = p.join(run.path, 'plain');
        await StreamingFileCipher.transform(
          source: StreamingFileSource(destination, result.length),
          destination: plain,
          decryptSource: true,
          encryptDestination: false,
          verifyOutput: false,
          useNative: false,
        );
        expect(await File(plain).readAsBytes(), await source.readAsBytes());
        await File(destination).writeAsBytes([1, 2, 3]);
        expect(await receipt.isCurrent(), isFalse);
      },
    );
  }
  test(
    'owned target cannot overwrite a picked input or existing candidate',
    () async {
      final file = File(p.join(run.path, 'picked'));
      await file.writeAsString('keep original');
      await expectLater(
        OwnedWriteTarget.forPath(file.path).validate(file.path),
        throwsFormatException,
      );
      expect(await file.readAsString(), 'keep original');
    },
  );
  test(
    'receipts cannot acknowledge existing picked files or be issued twice',
    () async {
      final file = File(p.join(run.path, 'picked-unowned'));
      await file.writeAsString('unchanged');
      await expectLater(
        OwnedWriteReceipt.closed(
          target: OwnedWriteTarget.forPath(file.path),
          length: 9,
          sha256Hex: sha256.convert(await file.readAsBytes()).toString(),
          verifyReadback: false,
          payloadReadBytes: 0,
        ),
        throwsFormatException,
      );
      expect(await file.readAsString(), 'unchanged');
    },
  );
}
