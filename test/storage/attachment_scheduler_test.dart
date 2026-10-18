import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/core/platform/system_capacity.dart';
import 'package:flutter_application_1/core/storage/attachment_performance.dart';
import 'package:flutter_application_1/core/storage/attachment_scheduler.dart';

const gib = 1024 * 1024 * 1024;
SystemCapacity capacity({
  int cpu = 8,
  int memory = 8 * gib,
  double system = 0,
  double app = 0,
  bool detected = true,
}) => SystemCapacity(
  processors: cpu,
  availableBytes: memory,
  systemCpu: system,
  processCpu: app,
  detected: detected,
);

void main() {
  test(
    'export scans default off and independently respect saved preferences on every backend',
    () {
      for (final metadata in [null, <String, Object>{}]) {
        final defaults = AttachmentPerformance.fromJson(metadata);
        expect(defaults.exportChecks(mobile: true), (
          checkSource: false,
          verifyOutput: false,
        ));
        expect(defaults.exportChecks(mobile: false), (
          checkSource: false,
          verifyOutput: false,
        ));
        expect(defaults.validateExportedBackup, isFalse);
        expect(defaults.validateBackupExport(mobile: true), isFalse);
        expect(defaults.validateBackupExport(mobile: false), isFalse);
        expect(defaults.verifyLargeFileWrites, isFalse);
      }
      for (final check in [false, true]) {
        for (final verify in [false, true]) {
          final policy = AttachmentPerformance.defaults.copyWith(
            checkBeforeOpen: check,
            verifyAfterOpen: verify,
          );
          final reopened = AttachmentPerformance.fromJson(policy.toJson());
          expect(reopened.exportChecks(mobile: true), (
            checkSource: check,
            verifyOutput: verify,
          ));
          expect(reopened.exportChecks(mobile: false), (
            checkSource: check,
            verifyOutput: verify,
          ));
          final backup = reopened.copyWith(validateExportedBackup: true);
          expect(AttachmentPerformance.fromJson(backup.toJson()), backup);
          expect(backup.validateBackupExport(mobile: true), isTrue);
          expect(
            backup.copyWith(memoryMiB: 256).validateExportedBackup,
            isTrue,
          );
          expect(
            backup
                .copyWith(validateExportedBackup: false)
                .validateBackupExport(mobile: true),
            isFalse,
          );
        }
      }
    },
  );
  test('profiles default to 70 percent and reject unsafe persisted limits', () {
    expect(AttachmentPerformance.fromJson(null).targetPercent, 70);
    expect(AttachmentPerformance.fromJson(null).checkBeforeOpen, isFalse);
    expect(AttachmentPerformance.fromJson({}).verifyAfterOpen, isFalse);
    for (final json in [
      {'targetPercent': 0},
      {'targetPercent': 100},
      {'maxParallel': -1},
      {'memoryMiB': 1},
      {'maxParallel': '4'},
      {'checkBeforeOpen': 'false'},
      {'verifyAfterOpen': 1},
      {'validateExportedBackup': 'false'},
      {'verifyLargeFileWrites': 'false'},
    ]) {
      expect(() => AttachmentPerformance.fromJson(json), throwsFormatException);
    }
    final profile = AttachmentPerformance.defaults.copyWith(
      maxParallel: 4,
      memoryMiB: 256,
      checkBeforeOpen: true,
      verifyAfterOpen: true,
      validateExportedBackup: true,
      verifyLargeFileWrites: true,
    );
    expect(AttachmentPerformance.fromJson(profile.toJson()), profile);
  });

  for (final processors in [1, 2, 8, 64]) {
    test(
      'adapts to $processors logical processors without a machine-specific limit',
      () {
        final budget = AttachmentBudget.calculate(
          capacity(cpu: processors),
          AttachmentPerformance.defaults,
        );
        expect(budget.cpuCores, closeTo(processors * .7, .001));
        expect(budget.slots, (processors * .7).ceil());
        expect(budget.memoryBytes, (8 * gib * .7).floor());
      },
    );
  }

  test(
    'discounts other programs, not its own CPU, and respects advanced ceilings',
    () {
      final profile = AttachmentPerformance.defaults.copyWith(
        maxParallel: 2,
        memoryMiB: 128,
      );
      final budget = AttachmentBudget.calculate(
        capacity(system: .8, app: .3),
        profile,
      );
      expect(budget.cpuCores, closeTo(2.8, .001));
      expect(budget.slots, 2);
      expect(budget.memoryBytes, 128 * 1024 * 1024);
      expect(
        AttachmentBudget.calculate(
          capacity(memory: 32 * 1024 * 1024),
          profile,
        ).slots,
        0,
      );
      final fallback = AttachmentBudget.calculate(
        capacity(detected: false),
        profile,
      );
      expect(fallback.slots, 1);
      expect(fallback.cpuCores, .7);
    },
  );

  test(
    'one shared budget admits, pauses on pressure and resumes queued work',
    () async {
      var reading = capacity(cpu: 2);
      final scheduler = AttachmentScheduler(sample: () => reading);
      final gates = List.generate(3, (_) => Completer<void>());
      final started = <int>[];
      final quotas = <int, double>{};
      final work = List.generate(
        3,
        (i) => scheduler.schedule(
          () async {
            started.add(i);
            await gates[i].future;
          },
          cancelled: () => false,
          quota: (duty) => quotas[i] = duty,
        ),
      );
      scheduler.refresh();
      expect(started, [0, 1]);
      expect(scheduler.status.value!.queued, 1);
      expect(quotas[0], closeTo(.7, .001));
      reading = capacity(cpu: 2, memory: 1);
      scheduler.refresh();
      expect(quotas[0], 0);
      expect(quotas[1], 0);
      reading = capacity(cpu: 2);
      scheduler.configure(
        AttachmentPerformance.defaults.copyWith(maxParallel: 1),
      );
      expect(quotas[0], 1);
      expect(quotas[1], 0);
      gates[0].complete();
      gates[1].complete();
      await Future.wait(work.take(2));
      expect(started, [0, 1, 2]);
      gates[2].complete();
      await Future.wait(work);
      expect(scheduler.status.value!.active, 0);
      await scheduler.close();
    },
  );

  test(
    'queued cancellation never starts IO and telemetry failures stay conservative',
    () async {
      final gate = Completer<void>();
      var cancelled = false;
      var starts = 0;
      final scheduler = AttachmentScheduler(
        sample: () => throw StateError('unavailable'),
      );
      final first = scheduler.schedule(
        () => gate.future,
        cancelled: () => false,
        quota: (_) {},
      );
      final second = scheduler.schedule(
        () async {
          starts++;
        },
        cancelled: () => cancelled,
        quota: (_) {},
      );
      scheduler.refresh();
      expect(scheduler.status.value!.active, 1);
      cancelled = true;
      scheduler.refresh();
      await second;
      expect(starts, 0);
      gate.complete();
      await first;
      await scheduler.close();
    },
  );

  test('host telemetry returns bounded CPU and available memory', () async {
    final probe = SystemCapacityProbe();
    final initial = probe.sample();
    expect(initial.processors, greaterThan(0));
    await Future<void>.delayed(const Duration(milliseconds: 280));
    final sample = probe.sample();
    expect(sample.systemCpu, inInclusiveRange(0, 1));
    expect(sample.processCpu, inInclusiveRange(0, 1));
    expect(sample.availableBytes, greaterThan(0));
    expect(sample.detected, isTrue);
  });
}
