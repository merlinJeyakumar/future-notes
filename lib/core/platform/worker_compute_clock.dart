import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;
import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart' as win;

/// Measure only synchronous work on the current isolate thread. A pair must
/// never cross an await: isolate continuations may move to another OS thread.
/// Windows thread CPU excludes suspension, scheduling waits and file I/O.
class WorkerComputeClock {
  WorkerComputeClock({int Function()? cpuMicros}) : _injected = cpuMicros;
  final int Function()? _injected;
  final _fallback = Stopwatch();
  Pointer<win.FILETIME>? _times;
  Pointer<_ThreadTime>? _androidTimes;
  static final _androidClock = Platform.isAndroid
      ? DynamicLibrary.open('libc.so').lookupFunction<
          Int32 Function(Int32, Pointer<_ThreadTime>),
          int Function(int, Pointer<_ThreadTime>)
        >('clock_gettime')
      : null;
  int? _start;
  int _worked = 0;
  int? _read() {
    if (_injected != null) return _injected();
    if (Platform.isAndroid) {
      final time = _androidTimes ??= calloc<_ThreadTime>();
      if (_androidClock!(3, time) != 0) return null; // CLOCK_THREAD_CPUTIME_ID
      return time.ref.seconds * 1000000 + time.ref.nanoseconds ~/ 1000;
    }
    if (!Platform.isWindows) return null;
    final times = _times ??= calloc<win.FILETIME>(4);
    if (win.GetThreadTimes(
          win.GetCurrentThread(),
          times,
          times + 1,
          times + 2,
          times + 3,
        ) ==
        0) {
      return null;
    }
    int ticks(int i) =>
        (times[i].dwHighDateTime << 32) | times[i].dwLowDateTime;
    return (ticks(2) + ticks(3)) ~/ 10;
  }

  void begin() {
    _start = _read();
    _fallback
      ..reset()
      ..start();
  }

  void end() {
    _fallback.stop();
    final end = _read();
    _worked += _start != null && end != null
        ? math.max(0, end - _start!)
        : _fallback.elapsedMicroseconds;
  }

  int take() {
    final value = _worked;
    _worked = 0;
    return value;
  }

  void close() {
    if (_androidTimes != null) {
      calloc.free(_androidTimes!);
      _androidTimes = null;
    }
    if (_times != null) {
      calloc.free(_times!);
      _times = null;
    }
  }
}

final class _ThreadTime extends Struct {
  @Long()
  external int seconds;
  @Long()
  external int nanoseconds;
}
