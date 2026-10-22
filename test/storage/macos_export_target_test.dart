import 'dart:async';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_application_1/core/platform/macos_file_access.dart';
import 'package:flutter_application_1/core/operations/operation_result.dart';
import 'package:flutter_application_1/core/storage/macos_export_target.dart';
import 'package:flutter_application_1/core/storage/owned_write.dart';
import 'package:flutter_application_1/core/storage/streaming_file_cipher.dart';
import 'package:flutter_application_1/features/dashboard/services/pack_service.dart';
import 'package:flutter_application_1/features/dashboard/services/streaming_pack_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import '../support/validation_directory.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/macos-export');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory run;
  late String candidate;
  late List<MethodCall> calls;
  var failPublish = false;
  setUp(() async {
    run = await Directory.systemTemp.createTemp(
      'future-notes-validation-macos-export-',
    );
    run = Directory(await run.resolveSymbolicLinks());
    candidate = p.join(run.path, '.future-notes-export-native.staged');
    calls = [];
    failPublish = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'chooseSaveTarget')
        return {
          'grantToken': 'native',
          'leaseToken': 'lease',
          'identity': 'native:destination',
          'path': p.join(run.path, 'result.fnote'),
          'candidate': candidate,
        };
      if (call.method == 'nextSaveCandidate') {
        candidate = p.join(run.path, '.future-notes-export-next.staged');
        return candidate;
      }
      if (call.method == 'publishSave' && failPublish) {
        throw PlatformException(code: 'recovery_required');
      }
      return null;
    });
  });
  tearDown(() async {
    messenger.setMockMethodCallHandler(channel, null);
    await deleteValidationRun(run);
  });
  Future<OwnedWriteReceipt> receipt(String path) async {
    final target = OwnedWriteTarget.forPath(path);
    await target.validate(path);
    const bytes = [1, 2, 3, 4];
    await File(path).writeAsBytes(bytes, flush: true);
    return OwnedWriteReceipt.closed(
      target: target,
      length: bytes.length,
      sha256Hex: sha256.convert(bytes).toString(),
      verifyReadback: false,
      payloadReadBytes: bytes.length,
    );
  }

  Future<MacosExportTarget> choose() async => (await MacosExportTarget.choose(
    'Meaningful title.fnote',
    access: const MacosFileAccess(channel: channel),
  ))!;

  test(
    'canonical replacement parent supports real package export and retry',
    () async {
      final alias = Directory(
        p.join(Directory.systemTemp.path, p.basename(run.path)),
      );
      final canonical = await alias.resolveSymbolicLinks();
      expect(p.equals(canonical, run.path), isTrue);
      expect(
        p.equals(await Directory(run.path).resolveSymbolicLinks(), run.path),
        isTrue,
      );

      final output = await choose();
      await File(candidate).writeAsBytes([99], flush: true);
      await expectLater(
        const StreamingPackService().exportPackage(
          metadata: const {
            'id': 'synthetic-macos-export',
            'title': 'Synthetic macOS export',
            'content': '',
            'isLocked': false,
            'timestamp': 1700000000000,
            'attachments': [
              {'id': 'synthetic', 'fileName': 'synthetic.bin', 'size': 3},
            ],
          },
          attachments: {
            'synthetic': StreamingFileSource(
              p.join(run.path, 'synthetic.med'),
              3,
            ),
          },
          format: ExportFormat.binary,
          destination: candidate,
          operationDirectory: p.join(run.path, 'preexisting-operation'),
        ),
        throwsFormatException,
      );
      final next = await output.nextCandidate();
      expect(p.dirname(next), run.path);
      expect(
        p.equals(
          await Directory(p.dirname(next)).resolveSymbolicLinks(),
          run.path,
        ),
        isTrue,
      );

      final source = File(p.join(run.path, 'synthetic.med'));
      await source.writeAsBytes([17, 23, 42], flush: true);
      final operation = await Directory(
        p.join(run.path, 'package-operation'),
      ).create();
      final prepared = await const StreamingPackService().exportPackage(
        metadata: const {
          'id': 'synthetic-macos-export',
          'title': 'Synthetic macOS export',
          'content': '',
          'isLocked': false,
          'timestamp': 1700000000000,
          'attachments': [
            {'id': 'synthetic', 'fileName': 'synthetic.bin', 'size': 3},
          ],
        },
        attachments: {'synthetic': StreamingFileSource(source.path, 3)},
        format: ExportFormat.binary,
        destination: candidate,
        operationDirectory: operation.path,
      );
      expect(prepared.path, candidate);
      expect((await output.publish(prepared)).isSuccess, isTrue);
      await output.close();
    },
    skip: !Platform.isMacOS,
  );
  test(
    'native replacement candidate is used once without a sibling transfer',
    () async {
      final output = await choose();
      final prepared = await receipt(candidate);
      expect(output.candidate, candidate);
      expect((await output.publish(prepared)).isSuccess, isTrue);
      expect(calls.last.method, 'publishSave');
      expect(calls.last.arguments, {
        'grantToken': 'native',
        'length': 4,
        'modifiedMicros': prepared.modifiedMicros,
        'changedMicros': prepared.changedMicros,
      });
      expect(
        (await output.publish(prepared)).outcome,
        OperationOutcome.rejectedInput,
      );
      expect(calls.where((call) => call.method == 'publishSave').length, 1);
      await output.close();
      expect(calls.last.method, 'release');
    },
  );
  test(
    'changed or unrelated receipt cannot reach native publication',
    () async {
      final output = await choose();
      final unrelated = await receipt(p.join(run.path, 'another.staged'));
      expect(
        (await output.publish(unrelated)).outcome,
        OperationOutcome.conflict,
      );
      expect(output.retainCandidate, isFalse);
      final prepared = await receipt(candidate);
      await File(candidate).writeAsBytes([9], flush: true);
      expect(
        (await output.publish(prepared)).outcome,
        OperationOutcome.conflict,
      );
      expect(calls.any((call) => call.method == 'publishSave'), isFalse);
      await output.close();
    },
  );
  test(
    'ambiguous save retains candidate and returns recovery instead of success',
    () async {
      final output = await choose();
      final prepared = await receipt(candidate);
      failPublish = true;
      final diagnostics = <String>[];
      await runZoned(
        () async => expect(
          (await output.publish(prepared)).outcome,
          OperationOutcome.recoveryRequired,
        ),
        zoneSpecification: ZoneSpecification(
          print: (_, _, _, line) => diagnostics.add(line),
        ),
      );
      expect(diagnostics, ['FN_MAC_EXPORT_PUBLISH failure=5']);
      expect(output.retainCandidate, isTrue);
      await output.close();
      expect(await File(candidate).readAsBytes(), [1, 2, 3, 4]);
    },
  );
}
