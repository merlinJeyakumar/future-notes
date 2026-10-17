import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import '../platform/system_capacity.dart';
import 'attachment_performance.dart';

class AttachmentBudget {
  const AttachmentBudget(
    this.capacity,
    this.slots,
    this.cpuCores,
    this.memoryBytes, {
    this.active = 0,
    this.queued = 0,
  });
  final SystemCapacity capacity;
  final int slots;
  final double cpuCores;
  final int memoryBytes;
  final int active;
  final int queued;
  static const workerBytes = 64 * 1024 * 1024;

  factory AttachmentBudget.calculate(
    SystemCapacity capacity,
    AttachmentPerformance settings,
  ) {
    final fraction = settings.targetPercent / 100;
    final otherCpu = (capacity.systemCpu - capacity.processCpu).clamp(0.0, 1.0);
    final cores = capacity.detected
        ? capacity.processors *
              (1 - otherCpu) *
              fraction *
              capacity.capacityFactor
        : fraction * capacity.capacityFactor;
    var memory = (capacity.availableBytes * fraction).floor();
    if (settings.memoryMiB > 0) {
      memory = math.min(memory, settings.memoryMiB * 1024 * 1024);
    }
    var slots = math.min(cores.ceil(), memory ~/ capacity.workerBytes);
    if (!capacity.detected) {
      slots = capacity.availableBytes > 0 && memory < capacity.workerBytes
          ? 0
          : 1;
    }
    if (capacity.capacityFactor <= 0) slots = 0;
    if (settings.maxParallel > 0) slots = math.min(slots, settings.maxParallel);
    // One slot may be admitted with a fractional CPU duty, never with
    // insufficient detected working memory. Cold-start uses the same limits.
    return AttachmentBudget(capacity, slots.clamp(0, 256), cores, memory);
  }
}

/// One process-wide budget shared by writes, exports and decrypted opens.
/// Callers retain ownership/cancellation; only preparation is parallelized.
class AttachmentScheduler {
  AttachmentScheduler({
    SystemCapacity Function()? sample,
    this.pollInterval = const Duration(seconds: 1),
  }) : _sample = sample ?? SystemCapacityProbe().sample;
  static final shared = AttachmentScheduler();
  final SystemCapacity Function() _sample;
  final Duration pollInterval;
  AttachmentPerformance _settings = AttachmentPerformance.defaults;
  final _pending = Queue<_ScheduledPreparation>();
  final _active = <_ScheduledPreparation>{};
  Timer? _timer;
  bool _disposed = false;
  bool _pumping = false;
  final status = ValueNotifier<AttachmentBudget?>(null);
  static const maxQueued = 256;

  void configure(AttachmentPerformance settings) {
    _settings = settings;
    if (_active.isNotEmpty || _pending.isNotEmpty) refresh();
  }

  Future<void> schedule(
    Future<void> Function() run, {
    required bool Function() cancelled,
    required void Function(double) quota,
  }) {
    if (_disposed || _pending.length >= maxQueued) {
      throw StateError('Attachment preparation queue is full.');
    }
    final entry = _ScheduledPreparation(run, cancelled, quota);
    _pending.add(entry);
    _timer ??= Timer.periodic(pollInterval, (_) => refresh());
    // Defer admission until submit has installed cancellation ownership.
    scheduleMicrotask(refresh);
    return entry.done.future;
  }

  void refresh() {
    if (_disposed || _pumping) return;
    _pumping = true;
    try {
      SystemCapacity capacity;
      try {
        capacity = _sample();
      } catch (_) {
        capacity = const SystemCapacity(
          processors: 1,
          availableBytes: 0,
          systemCpu: 0,
          processCpu: 0,
          detected: false,
        );
      }
      final budget = AttachmentBudget.calculate(capacity, _settings);
      for (final entry in _pending.toList()) {
        if (entry.cancelled()) {
          _pending.remove(entry);
          entry.done.complete();
        }
      }
      while (_pending.isNotEmpty && _active.length < budget.slots) {
        final entry = _pending.removeFirst();
        _active.add(entry);
        entry.quota(
          (budget.cpuCores / math.max(1, budget.slots)).clamp(0.0, 1.0),
        );
        unawaited(_run(entry));
      }
      final running = math.min(_active.length, budget.slots);
      final duty = running == 0
          ? 0.0
          : (budget.cpuCores / running).clamp(0.0, 1.0);
      var index = 0;
      for (final entry in _active) {
        entry.quota(index++ < running ? duty : 0);
      }
      status.value = AttachmentBudget(
        capacity,
        budget.slots,
        budget.cpuCores,
        budget.memoryBytes,
        active: _active.length,
        queued: _pending.length,
      );
      if (_active.isEmpty && _pending.isEmpty) {
        _timer?.cancel();
        _timer = null;
      }
    } finally {
      _pumping = false;
    }
  }

  Future<void> _run(_ScheduledPreparation entry) async {
    try {
      await entry.run();
      entry.done.complete();
    } catch (error, stack) {
      entry.done.completeError(error, stack);
    } finally {
      _active.remove(entry);
      refresh();
    }
  }

  Future<void> close() async {
    if (_pending.isNotEmpty || _active.isNotEmpty) {
      await Future.wait(
        [..._active, ..._pending].map((entry) => entry.done.future),
      );
    }
    _disposed = true;
    _timer?.cancel();
    status.dispose();
  }
}

class _ScheduledPreparation {
  _ScheduledPreparation(this.run, this.cancelled, this.quota);
  final Future<void> Function() run;
  final bool Function() cancelled;
  final void Function(double) quota;
  final done = Completer<void>();
}
