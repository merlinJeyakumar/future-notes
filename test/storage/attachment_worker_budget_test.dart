import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/core/operations/operation_result.dart';
import 'package:flutter_application_1/core/platform/system_capacity.dart';
import 'package:flutter_application_1/core/storage/attachment_performance.dart';
import 'package:flutter_application_1/core/storage/attachment_scheduler.dart';
import 'package:flutter_application_1/core/storage/attachment_transform_worker.dart';
import 'package:flutter_application_1/core/storage/streaming_file_cipher.dart';
import '../support/validation_directory.dart';

void main() {
  test(
    'separate encryption and decryption workers share a bounded pool and drain on close',
    () async {
      final run = await Directory.systemTemp.createTemp(
        'future-notes-validation-',
      );
      const length = 2 * 1024 * 1024;
      final source = File('${run.path}/source');
      await source.writeAsBytes(
        Uint8List.fromList(List.generate(length, (i) => i % 251)),
      );
      final scheduler = AttachmentScheduler(
        sample: () => const SystemCapacity(
          processors: 4,
          availableBytes: 1024 * 1024 * 1024,
          systemCpu: .1,
          processCpu: 0,
        ),
      );
      scheduler.configure(
        AttachmentPerformance.defaults.copyWith(maxParallel: 2),
      );
      final first = AttachmentTransformWorker(scheduler: scheduler);
      final second = AttachmentTransformWorker(scheduler: scheduler);
      var maximum = 0;
      scheduler.status.addListener(() {
        final n = scheduler.status.value!.active;
        if (n > maximum) maximum = n;
      });
      try {
        FileTransformRequest request(int index) => FileTransformRequest(
          source: StreamingFileSource(source.path, length),
          destination: '${run.path}/cipher$index',
          decryptSource: false,
          encryptDestination: true,
          destinationPassword: 'synthetic',
        );
        final a = first.submit(request(1));
        final b = second.submit(request(2));
        final c = first.submit(request(3));
        final results = await Future.wait([a.result, b.result, c.result]);
        expect(results.every((r) => r.isSuccess), isTrue);
        expect(maximum, 2);
        expect(
          results.map((r) => r.value!.plaintextHash).toSet(),
          hasLength(1),
        );
        final opened = second.submit(
          FileTransformRequest(
            source: StreamingFileSource(
              '${run.path}/cipher1',
              results.first.value!.length,
            ),
            destination: '${run.path}/opened',
            decryptSource: true,
            encryptDestination: false,
            sourcePassword: 'synthetic',
          ),
        );
        final closing = Future.wait([first.close(), second.close()]);
        expect(
          (await opened.result).value!.plaintextHash,
          results.first.value!.plaintextHash,
        );
        await closing;
        expect(
          await File('${run.path}/opened').readAsBytes(),
          await source.readAsBytes(),
        );
        expect(scheduler.status.value!.active, 0);
      } finally {
        await first.close();
        await second.close();
        await scheduler.close();
        await deleteValidationRun(run);
      }
    },
  );

  test(
    'memory-pressure pause accepts cancellation and releases handles before close',
    () async {
      final run = await Directory.systemTemp.createTemp(
        'future-notes-validation-',
      );
      var available = 1024 * 1024 * 1024;
      final scheduler = AttachmentScheduler(
        sample: () => SystemCapacity(
          processors: 2,
          availableBytes: available,
          systemCpu: 0,
          processCpu: 0,
        ),
      );
      final worker = AttachmentTransformWorker(scheduler: scheduler);
      final source = File('${run.path}/source');
      await source.writeAsBytes(Uint8List(4 * 1024 * 1024));
      final paused = Completer<void>();
      try {
        final job = worker.submit(
          FileTransformRequest(
            source: StreamingFileSource(source.path, 4 * 1024 * 1024),
            destination: '${run.path}/partial',
            decryptSource: false,
            encryptDestination: true,
          ),
          onProgress: (_, bytes, _) {
            if (bytes > 0 && !paused.isCompleted) {
              available = 1;
              scheduler.refresh();
              paused.complete();
            }
          },
        );
        await paused.future.timeout(const Duration(seconds: 15));
        expect(
          (await job.cancel().timeout(const Duration(seconds: 5))).outcome,
          OperationOutcome.cancelled,
        );
        await worker.close();
        expect(await File('${run.path}/partial').exists(), isFalse);
        await source.rename('${run.path}/closed-handles');
      } finally {
        await worker.close();
        await scheduler.close();
        await deleteValidationRun(run);
      }
    },
  );
}
