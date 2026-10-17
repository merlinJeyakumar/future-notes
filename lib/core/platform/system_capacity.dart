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
    this.capacityFactor = 1,
    this.thermalStatus = 0,
    this.memoryPressure = 0,
    this.workerBytes = 64 * 1024 * 1024,
  });
  final int processors;
  final int availableBytes;

  /// Normalized fractions across logical processors, sampled between calls.
  final double systemCpu;
  final double processCpu;
  final bool detected;
  final double capacityFactor;
  final int thermalStatus;
  final int memoryPressure;
  final int workerBytes;
}

/// Synchronous, bounded OS telemetry; no shell, benchmark files or network.
class SystemCapacityProbe {
  static SystemCapacity? _mobile;
  static DateTime? _mobileAt;
  static void reportMobile(Map<Object?, Object?> value) {
    final thermal = value['thermal'] as int? ?? 0;
    final pressure = value['memoryPressure'] as int? ?? 0;
    _mobile = SystemCapacity(
      processors: value['processors'] as int? ?? 1,
      availableBytes: value['availableBytes'] as int? ?? 0,
      systemCpu: (value['systemCpu'] as num?)?.toDouble() ?? 0,
      processCpu: (value['processCpu'] as num?)?.toDouble() ?? 0,
      detected: value['detected'] == true,
      thermalStatus: thermal,
      memoryPressure: pressure,
      workerBytes: (value['workerBytes'] as int? ?? 64 * 1024 * 1024).clamp(
        16 * 1024 * 1024,
        64 * 1024 * 1024,
      ),
      capacityFactor: math.min(
        pressure >= 2
            ? 0.0
            : pressure == 1
            ? .5
            : 1.0,
        thermal >= 5
            ? 0
            : thermal >= 4
            ? .2
            : thermal >= 3
            ? .5
            : 1,
      ),
    );
    _mobileAt = DateTime.now();
  }

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
    if ((Platform.isAndroid || Platform.isIOS) &&
        _mobile != null &&
        DateTime.now().difference(_mobileAt!).inSeconds < 5)
      return _last = _mobile!;
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
