import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/core/platform/worker_compute_clock.dart';
import 'package:flutter_application_1/core/operations/operation_result.dart';
import 'package:flutter_application_1/core/storage/attachment_transform_worker.dart';
import 'package:flutter_application_1/core/storage/native_storage_primitives.dart';
import 'package:flutter_application_1/core/storage/note_reference.dart';
import 'package:flutter_application_1/core/storage/owned_note_persistence.dart';
import 'package:flutter_application_1/core/storage/preparation_pacer.dart';
import 'package:flutter_application_1/core/storage/recoverable_store.dart';
import 'package:flutter_application_1/core/storage/storage_environment.dart';
import 'package:flutter_application_1/core/storage/storage_owner_worker.dart';
import 'package:flutter_application_1/features/dashboard/models/attachment_job.dart';
import '../support/validation_directory.dart';
import '../support/editor_harness.dart' show PausePoint;
import 'owned_note_service_test.dart' show NoteTestOwner;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'CPU accounting excludes time outside synchronous work after a long suspend',
    () async {
      var cpu = 0;
      var now = 0;
      final meter = WorkerComputeClock(cpuMicros: () => cpu);
      meter.begin();
      cpu += 70000;
      meter.end();
      // Simulated sleep/IO adds ten minutes to elapsed time, not CPU time.
      now += 600000000;
      var rested = 0;
      final pacer = PreparationPacer(
        workedMicros: meter.take,
        duty: () => .7,
        cancelled: () => false,
        nowMicros: () => now,
        sleep: (delay) async {
          rested += delay.inMicroseconds;
          now += delay.inMicroseconds;
        },
      );
      await pacer.cooperate();
      expect(rested, inInclusiveRange(30000, 30001));
      now += 600000000;
      await pacer.cooperate();
      expect(rested, inInclusiveRange(30000, 30001));
      meter.close();
    },
  );

  test(
    'paused pacing accepts cancellation and a changed quota without accumulating wall-clock debt',
    () async {
      var cancelled = false;
      var quota = 0.0;
      var now = 0;
      var waits = 0;
      final pacer = PreparationPacer(
        workedMicros: () => 70000,
        duty: () => quota,
        cancelled: () => cancelled,
        nowMicros: () => now,
        sleep: (delay) async {
          now += delay.inMicroseconds;
          waits++;
          quota = 1;
        },
      );
      await pacer.cooperate();
      expect(waits, 1);
      quota = 0;
      cancelled = true;
      await pacer.cooperate();
      expect(waits, 1);
    },
  );

  test(
    'finalizing phase details publish immediately and remain noncancellable',
    () {
      final job = AttachmentJobState(
        const AttachmentJobSnapshot(
          id: 'synthetic',
          owner: 1,
          fileName: 'synthetic.bin',
          phase: AttachmentJobPhase.finalizing,
        ),
      );
      job.update(
        const AttachmentJobSnapshot(
          id: 'synthetic',
          owner: 1,
          fileName: 'synthetic.bin',
          phase: AttachmentJobPhase.finalizing,
          detail: 'Writing staged file',
          bytes: 1024,
          total: 2048,
        ),
      );
      expect(job.progress.value.bytes, 1024);
      job.update(
        const AttachmentJobSnapshot(
          id: 'synthetic',
          owner: 1,
          fileName: 'synthetic.bin',
          phase: AttachmentJobPhase.finalizing,
          detail: 'Verifying staged file',
          bytes: 0,
          total: 2048,
        ),
      );
      expect(job.progress.value.detail, 'Verifying staged file');
      expect(job.progress.value.cancellable, isFalse);
      job.dispose();
    },
  );

  late Directory run;
  late StorageEnvironment environment;
  late StorageOwnerWorker worker;
  setUp(() async {
    run = await createValidationRun();
    environment = StorageEnvironment.validation(
      validationRoot: run.path,
      dataRoot: '${run.path}/library',
      settingsFile: '${run.path}/configuration/settings.json',
    );
    worker = (await StorageOwnerWorker.start(environment: environment)).value!;
  });
  tearDown(() async {
    expect((await worker.close()).isSuccess, isTrue);
    await deleteValidationRun(run);
  });

  test(
    'immutable attachment checks progress independently of a pending writer commit and cancellation closes read handles',
    () async {
      final owner = NoteTestOwner(worker);
      final persistence = OwnedNotePersistence(
        environment: environment,
        owner: owner,
      );
      final binding = StorageBinding(environment.dataRoot!, 1);
      final content = File(
        binding.child('note_synthetic/note_content_synthetic.enc'),
      );
      await content.parent.create(recursive: true);
      await content.writeAsString('original synthetic envelope');
      final attached = File(
        binding.child('note_synthetic/attachments/synthetic.med'),
      );
      await attached.parent.create();
      final data = Uint8List.fromList(
        List.generate(2 * 1024 * 1024, (i) => i % 251),
      );
      await attached.writeAsBytes(data);
      final reference = await persistence.capture(
        NoteReference(
          binding: binding,
          fileName: 'note_synthetic',
          format: NoteStorageFormat.folder,
          contentPath: content.path,
          attachmentLocation: attached.parent.path,
          modelId: 'synthetic',
        ),
      );
      final pause = PausePoint();
      owner.commitPause = pause;
      final committing = persistence.commit(
        reference,
        'updated synthetic envelope',
      );
      await pause.started.future;
      final revisions = owner.revisions;
      var readBytes = 0;
      try {
        final source = await persistence
            .attachmentSource(
              reference,
              'synthetic',
              onProgress: (_, bytes, _) {
                readBytes = bytes;
              },
            )
            .timeout(const Duration(seconds: 10));
        expect(source.sha256Hex, sha256.convert(data).toString());
        expect(readBytes, data.length);
        expect(owner.revisions, revisions);
        final cancellation = FileReadCancellation();
        await expectLater(
          persistence.attachmentSource(
            reference,
            'synthetic',
            cancellation: cancellation,
            onProgress: (_, bytes, _) {
              if (bytes > 0) cancellation.cancel();
            },
          ),
          throwsA(
            isA<NotePersistenceFailure>().having(
              (e) => e.outcome,
              'outcome',
              OperationOutcome.cancelled,
            ),
          ),
        );
        await attached.rename('${attached.path}.closed-handles');
      } finally {
        pause.release.complete();
        await committing;
        await persistence.close();
      }
    },
  );

  test(
    'journal commit exposes real bounded bytes for every retained verification stage',
    () async {
      final root = (await worker.openRoot(environment.dataRoot!)).value!;
      final source = File('${run.path}/synthetic-source');
      await source.writeAsBytes(Uint8List(2 * 1024 * 1024));
      final phases = <String>{};
      final events = <(int, int)>[];
      var positiveBytes = 0;
      final result = await worker.commitWithProgress(
        root,
        target: 'synthetic.med',
        expected: const StorageRevision.missing(),
        source: CommitFileSource(source.path, await source.length()),
        onProgress: (phase, bytes, total) {
          phases.add(phase);
          events.add((bytes, total));
          if (bytes > 0) positiveBytes++;
        },
      );
      expect(result.isSuccess, isTrue, reason: result.message);
      for (final event in events) {
        expect(event.$1, inInclusiveRange(0, event.$2));
      }
      expect(positiveBytes, greaterThan(5));
      expect(
        phases,
        containsAll([
          'Checking prepared file',
          'Writing staged file',
          'Verifying staged file',
          'Confirming staged file',
          'Verifying published file',
          'Confirming commit',
        ]),
      );
      expect(
        result.value!.sha256Hex,
        sha256.convert(await source.readAsBytes()).toString(),
      );
      expect((await worker.releaseRoot(root)).isSuccess, isTrue);
    },
  );
}
