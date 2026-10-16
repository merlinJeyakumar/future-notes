import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Opt-in candidate diagnostics: bounded frame samples, no content or timers.
class MotionFrameLog {
  MotionFrameLog({required double refreshRate, ValueChanged<String>? write})
    : _budget = 1000000 / (refreshRate > 0 ? refreshRate : 60),
      _write = write ?? debugPrint;
  final double _budget;
  final ValueChanged<String> _write;
  final _build = <int>[];
  final _raster = <int>[];
  int _overBudget = 0;
  bool _running = false;

  void start() {
    if (_running) return;
    _running = true;
    SchedulerBinding.instance.addTimingsCallback(record);
  }

  void record(List<FrameTiming> frames) {
    if (!_running) return;
    for (final frame in frames) {
      final build = frame.buildDuration.inMicroseconds;
      final raster = frame.rasterDuration.inMicroseconds;
      _build.add(build);
      _raster.add(raster);
      if (build > _budget || raster > _budget) _overBudget++;
      if (_build.length == 60) _flush();
    }
  }

  void _flush() {
    if (_build.isEmpty) return;
    _build.sort();
    _raster.sort();
    final index = (_build.length * .95).ceil() - 1;
    _write(
      'Motion frames: n=${_build.length} '
      'build_p95_ms=${(_build[index] / 1000).toStringAsFixed(2)} '
      'raster_p95_ms=${(_raster[index] / 1000).toStringAsFixed(2)} '
      'over_budget=$_overBudget budget_ms=${(_budget / 1000).toStringAsFixed(2)}',
    );
    _build.clear();
    _raster.clear();
    _overBudget = 0;
  }

  void stop() {
    if (!_running) return;
    _running = false;
    SchedulerBinding.instance.removeTimingsCallback(record);
    _flush();
  }
}
