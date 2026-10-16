import 'dart:async';

/// Quota debt uses measured compute, never elapsed time across file I/O or sleep.
class PreparationPacer {
  PreparationPacer({
    required this.workedMicros,
    required this.duty,
    required this.cancelled,
    int Function()? nowMicros,
    Future<void> Function(Duration)? sleep,
  }) : _now = nowMicros ?? _clock(),
       _sleep = sleep ?? Future<void>.delayed;
  final int Function() workedMicros;
  final double Function() duty;
  final bool Function() cancelled;
  final int Function() _now;
  final Future<void> Function(Duration) _sleep;
  static int Function() _clock() {
    final clock = Stopwatch()..start();
    return () => clock.elapsedMicroseconds;
  }

  Future<void> cooperate() async {
    final worked = workedMicros();
    final start = _now();
    while (!cancelled()) {
      final quota = duty();
      if (quota <= 0) {
        await _sleep(const Duration(milliseconds: 50));
        continue;
      }
      final remaining = worked * (1 - quota) / quota - (_now() - start);
      if (remaining <= 0) return;
      await _sleep(Duration(microseconds: remaining.ceil().clamp(1, 50000)));
    }
  }
}
