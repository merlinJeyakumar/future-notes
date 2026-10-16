import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;
import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart' as win;

class SystemCapacity {
  const SystemCapacity({
    required this.processors,
    required this.availableBytes,
    required this.systemCpu,
    required this.processCpu,
    this.detected = true,
  });
  final int processors;
  final int availableBytes;

  /// Normalized fractions across logical processors, sampled between calls.
  final double systemCpu;
  final double processCpu;
  final bool detected;
}

/// Synchronous, bounded OS telemetry; no shell, benchmark files or network.
class SystemCapacityProbe {
  final _clock = Stopwatch()..start();
  int _sampledAt = -1000;
  SystemCapacity? _last;
  int? _total;
  int? _idle;
  int? _process;

  SystemCapacity sample() {
    if (_last != null && _clock.elapsedMilliseconds - _sampledAt < 250) {
      return _last!;
    }
    _sampledAt = _clock.elapsedMilliseconds;
    try {
      if (Platform.isWindows) return _last = _windows();
      if (Platform.isLinux) return _last = _linux();
    } catch (_) {
      /* Unknown telemetry uses the conservative one-worker path. */
    }
    return SystemCapacity(
      processors: Platform.numberOfProcessors,
      availableBytes: 0,
      systemCpu: 0,
      processCpu: 0,
      detected: false,
    );
  }

  SystemCapacity _rates(int total, int idle, int process, int memory) {
    final elapsed = _total == null ? 0 : total - _total!;
    final busy = elapsed <= 0
        ? 0.0
        : (1 - (idle - _idle!) / elapsed).clamp(0.0, 1.0);
    final app = elapsed <= 0
        ? 0.0
        : ((process - _process!) / elapsed).clamp(0.0, 1.0);
    _total = total;
    _idle = idle;
    _process = process;
    return SystemCapacity(
      processors: math.max(1, Platform.numberOfProcessors),
      availableBytes: math.max(0, memory),
      systemCpu: busy,
      processCpu: app,
      detected: elapsed > 0,
    );
  }

  SystemCapacity _windows() {
    final times = calloc<win.FILETIME>(7);
    final memory = calloc<win.MEMORYSTATUSEX>()
      ..ref.dwLength = sizeOf<win.MEMORYSTATUSEX>();
    int ticks(int index) =>
        (times[index].dwHighDateTime << 32) | times[index].dwLowDateTime;
    try {
      if (win.GetSystemTimes(times, times + 1, times + 2) == 0 ||
          win.GetProcessTimes(
                win.GetCurrentProcess(),
                times + 3,
                times + 4,
                times + 5,
                times + 6,
              ) ==
              0 ||
          win.GlobalMemoryStatusEx(memory) == 0) {
        throw const OSError('Capacity unavailable.');
      }
      return _rates(
        ticks(1) + ticks(2),
        ticks(0),
        ticks(5) + ticks(6),
        memory.ref.ullAvailPhys,
      );
    } finally {
      calloc.free(times);
      calloc.free(memory);
    }
  }

  SystemCapacity _linux() {
    final fields = File('/proc/stat')
        .readAsLinesSync()
        .first
        .split(RegExp(r'\s+'))
        .skip(1)
        .take(8)
        .map(int.parse)
        .toList();
    final stat = File('/proc/self/stat').readAsStringSync();
    final process = stat.substring(stat.lastIndexOf(')') + 2).split(' ');
    final memory = RegExp(
      r'MemAvailable:\s+(\d+)',
    ).firstMatch(File('/proc/meminfo').readAsStringSync());
    if (memory == null) throw const OSError('Memory unavailable.');
    return _rates(
      fields.reduce((a, b) => a + b),
      fields[3] + fields[4],
      int.parse(process[11]) + int.parse(process[12]),
      int.parse(memory[1]!) * 1024,
    );
  }
}
