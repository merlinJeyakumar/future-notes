import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../operations/operation_result.dart';
import 'attachment_file_actions.dart';

/// Linux local-file integration. Native code owns the private cache and the
/// portal descriptor handoff; a Dart path alone never authorizes external open.
class LinuxDesktopActions implements AttachmentFileActions {
  LinuxDesktopActions({
    MethodChannel channel = const MethodChannel('future_notes/desktop_linux'),
  }) : _channel = channel;

  final MethodChannel _channel;
  bool _disposed = false;
  Future<void>? _disposing;

  @override
  Future<String> cacheRoot({String? validationRoot}) async {
    if (_disposed) throw StateError('The Linux file actions are closed.');
    if (validationRoot != null) {
      throw ArgumentError('The Linux cache must be native-owned.');
    }
    final root = await _channel.invokeMethod<String>('cacheRoot');
    if (root == null || !_localPath(root)) {
      throw const FormatException('Invalid native cache location.');
    }
    return root;
  }

  @override
  Future<OperationResult<void>> openFile(String path) =>
      _invoke('openFile', path);

  /// Reveal accepts a verified local library file/directory. It does not confer
  /// attachment-opening authority or accept internal/external URI schemes.
  Future<OperationResult<void>> revealFile(String path) =>
      _invoke('revealFile', path);

  Future<OperationResult<void>> _invoke(String method, String path) async {
    if (_disposed) {
      return const OperationResult.failure(
        OperationOutcome.cancelled,
        'The file action is closed.',
      );
    }
    if (!_localPath(path)) {
      return const OperationResult.failure(
        OperationOutcome.rejectedInput,
        'A local file is required.',
      );
    }
    try {
      await _channel.invokeMethod<void>(method, {'path': path});
      return const OperationResult.success();
    } on PlatformException catch (error) {
      if (error.code == 'cancelled') {
        return const OperationResult.failure(
          OperationOutcome.cancelled,
          'The file action was cancelled.',
        );
      }
      return OperationResult.failure(
        error.code == 'invalid_path'
            ? OperationOutcome.rejectedInput
            : OperationOutcome.ioFailure,
        method == 'openFile'
            ? 'No application could open this attachment.'
            : 'The file could not be shown in its folder.',
      );
    } on MissingPluginException {
      return const OperationResult.failure(
        OperationOutcome.ioFailure,
        'Linux file integration is unavailable.',
      );
    }
  }

  @override
  Future<void> dispose() => _disposing ??= _dispose();

  Future<void> _dispose() async {
    _disposed = true;
    try {
      await _channel.invokeMethod<void>('dispose');
    } on PlatformException {
      // Native window teardown may already have cancelled pending requests.
    } on MissingPluginException {
      // No native resources exist when the runner is unavailable.
    }
  }
}

bool _localPath(String path) =>
    p.posix.isAbsolute(path) &&
    !path.contains('\u0000') &&
    !p.posix.split(path).contains('..');
