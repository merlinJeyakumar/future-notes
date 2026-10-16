import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../operations/operation_result.dart';

class DesktopWindowState {
  const DesktopWindowState({this.maximized = false, this.minimized = false});
  final bool maximized;
  final bool minimized;
}

abstract class WindowActions {
  ValueListenable<DesktopWindowState> get state;
  Future<OperationResult<void>> configureFrame(bool enabled);
  Future<OperationResult<void>> minimize();
  Future<OperationResult<void>> toggleMaximize();
  Future<OperationResult<void>> requestClose();
  Future<void> dispose();
}

/// Separate from cache/file actions so window state has one independent owner.
class WindowsWindowActions implements WindowActions {
  WindowsWindowActions() {
    _channel.setMethodCallHandler((call) async {
      if (_disposed || call.method != 'windowState') return;
      _publish(call.arguments);
    });
  }
  static const _channel = MethodChannel('future_notes/window');
  final _state = ValueNotifier(const DesktopWindowState());
  bool _disposed = false;
  @override
  ValueListenable<DesktopWindowState> get state => _state;
  void _publish(Object? value) {
    if (value is Map &&
        value['maximized'] is bool &&
        value['minimized'] is bool) {
      _state.value = DesktopWindowState(
        maximized: value['maximized'] as bool,
        minimized: value['minimized'] as bool,
      );
    }
  }

  Future<OperationResult<void>> _invoke(
    String method, [
    Object? argument,
  ]) async {
    if (_disposed) {
      return const OperationResult.failure(
        OperationOutcome.cancelled,
        'Window controls are closing.',
      );
    }
    try {
      final response = await _channel.invokeMethod<Object?>(method, argument);
      if (!_disposed) _publish(response);
      return const OperationResult.success();
    } catch (_) {
      return const OperationResult.failure(
        OperationOutcome.ioFailure,
        'The window action could not be completed.',
      );
    }
  }

  @override
  Future<OperationResult<void>> configureFrame(bool enabled) =>
      _invoke('setFrame', enabled);
  @override
  Future<OperationResult<void>> minimize() => _invoke('minimize');
  @override
  Future<OperationResult<void>> toggleMaximize() => _invoke('toggleMaximize');
  @override
  Future<OperationResult<void>> requestClose() => _invoke('close');
  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    try {
      await _channel.invokeMethod<Object?>('setFrame', false);
    } catch (_) {
      /* Engine may already be gone. */
    }
    _channel.setMethodCallHandler(null);
    _state.dispose();
  }
}
