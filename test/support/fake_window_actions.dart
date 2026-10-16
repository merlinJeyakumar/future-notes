import 'package:flutter/foundation.dart';
import 'package:flutter_application_1/core/operations/operation_result.dart';
import 'package:flutter_application_1/core/platform/window_actions.dart';

class FakeWindowActions implements WindowActions {
  @override
  final ValueNotifier<DesktopWindowState> state = ValueNotifier(
    const DesktopWindowState(),
  );
  final calls = <String>[];
  bool failConfigure = false;
  Future<OperationResult<void>> Function()? onMinimize;
  VoidCallback? onClose;
  @override
  Future<OperationResult<void>> configureFrame(bool enabled) async {
    calls.add('frame:$enabled');
    return failConfigure
        ? const OperationResult.failure(
            OperationOutcome.ioFailure,
            'Frame unavailable',
          )
        : const OperationResult.success();
  }

  @override
  Future<OperationResult<void>> minimize() async {
    calls.add('minimize');
    return onMinimize == null ? const OperationResult.success() : onMinimize!();
  }

  @override
  Future<OperationResult<void>> toggleMaximize() async {
    calls.add('maximize');
    state.value = DesktopWindowState(maximized: !state.value.maximized);
    return const OperationResult.success();
  }

  @override
  Future<OperationResult<void>> requestClose() async {
    calls.add('close');
    onClose?.call();
    return const OperationResult.success();
  }

  @override
  Future<void> dispose() async {
    state.dispose();
  }
}
