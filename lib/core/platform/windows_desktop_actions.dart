import 'package:flutter/services.dart';
import '../operations/operation_result.dart';

abstract class DesktopActions {
  Future<String> cacheRoot({String? validationRoot});
  Future<OperationResult<void>> openFile(String path);
  Future<void> dispose();
}

class WindowsDesktopActions implements DesktopActions {
  static const _channel = MethodChannel('future_notes/desktop');
  @override
  Future<String> cacheRoot({String? validationRoot}) async =>
      (await _channel.invokeMethod<String>('cacheRoot', validationRoot))!;
  @override
  Future<OperationResult<void>> openFile(String path) =>
      _invoke('openFile', path);
  Future<OperationResult<void>> _invoke(
    String method, [
    String? argument,
  ]) async {
    try {
      await _channel.invokeMethod<void>(method, argument);
      return const OperationResult.success();
    } catch (_) {
      return const OperationResult.failure(
        OperationOutcome.ioFailure,
        'The Windows action could not be completed.',
      );
    }
  }

  @override
  Future<void> dispose() async {
    // File/cache actions own no subscriptions or window event handlers.
  }
}
