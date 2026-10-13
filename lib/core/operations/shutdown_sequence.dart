import 'operation_result.dart';

enum ShutdownPhase { watchers, storage, complete, failed }

/// Retains ownership of one cleanup attempt even when an exit request times out.
/// Completed stages are not repeated after a genuine cleanup failure.
class ShutdownSequence {
  ShutdownSequence({
    required this.closeWatchers,
    required this.closeStorage,
    this.onPhase,
  });

  final Future<void> Function() closeWatchers;
  final Future<OperationResult<void>> Function() closeStorage;
  final void Function(ShutdownPhase)? onPhase;
  Future<OperationResult<void>>? _pending;
  bool _watchersClosed = false;
  bool _closed = false;
  ShutdownPhase _phase = ShutdownPhase.watchers;

  ShutdownPhase get phase => _phase;

  Future<OperationResult<void>> close() {
    if (_closed) {
      return Future.value(const OperationResult.success());
    }
    final current = _pending;
    if (current != null) {
      return current;
    }
    final operation = _run();
    _pending = operation;
    operation.then((result) {
      if (!result.isSuccess && identical(_pending, operation)) {
        _pending = null;
      }
    });
    return operation;
  }

  void _publish(ShutdownPhase phase) {
    _phase = phase;
    // Presentation must never interrupt resource cleanup.
    try {
      onPhase?.call(phase);
    } catch (_) {}
  }

  Future<OperationResult<void>> _run() async {
    try {
      if (!_watchersClosed) {
        _publish(ShutdownPhase.watchers);
        await closeWatchers();
        _watchersClosed = true;
      }
      _publish(ShutdownPhase.storage);
      final result = await closeStorage();
      if (!result.isSuccess) {
        _publish(ShutdownPhase.failed);
        return result;
      }
      _closed = true;
      _publish(ShutdownPhase.complete);
      return const OperationResult.success();
    } catch (_) {
      _publish(ShutdownPhase.failed);
      return const OperationResult.failure(
        OperationOutcome.recoveryRequired,
        'Storage cleanup requires retry.',
      );
    }
  }
}
