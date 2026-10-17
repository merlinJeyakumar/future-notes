import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/core/platform/system_capacity.dart';
import 'package:flutter_application_1/core/storage/attachment_performance.dart';
import 'package:flutter_application_1/core/storage/attachment_scheduler.dart';

void main() {
  const mib = 1024 * 1024;
  const device = SystemCapacity(
    processors: 8,
    availableBytes: 128 * mib,
    systemCpu: 0,
    processCpu: 0,
    detected: false,
    workerBytes: 16 * mib,
  );
  test('battery profile admits one bounded native job on modest memory', () {
    final budget = AttachmentBudget.calculate(
      device,
      const AttachmentPerformance(
        targetPercent: 40,
        maxParallel: 1,
        memoryMiB: 64,
      ),
    );
    expect(budget.slots, 1);
    expect(budget.memoryBytes, lessThanOrEqualTo(64 * mib));
    expect(budget.cpuCores, closeTo(.4, .001));
  });
  test(
    'native allowance still pauses under critical pressure and desktop keeps its allowance',
    () {
      const critical = SystemCapacity(
        processors: 8,
        availableBytes: 128 * mib,
        systemCpu: 0,
        processCpu: 0,
        detected: false,
        workerBytes: 16 * mib,
        capacityFactor: 0,
      );
      expect(
        AttachmentBudget.calculate(
          critical,
          AttachmentPerformance.defaults,
        ).slots,
        0,
      );
      expect(
        const SystemCapacity(
          processors: 8,
          availableBytes: mib,
          systemCpu: 0,
          processCpu: 0,
        ).workerBytes,
        64 * mib,
      );
      expect(
        AttachmentBudget.calculate(
          device,
          AttachmentPerformance.defaults,
        ).slots,
        1,
      );
    },
  );
}
