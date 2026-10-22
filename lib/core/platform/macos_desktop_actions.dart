import '../operations/operation_result.dart';
import 'attachment_file_actions.dart';
import 'macos_file_access.dart';

class MacosDesktopActions implements AttachmentFileActions {
  const MacosDesktopActions({MacosFileAccess access = const MacosFileAccess()})
    : _access = access;
  final MacosFileAccess _access;

  @override
  Future<String> cacheRoot({String? validationRoot}) {
    if (validationRoot != null) {
      throw ArgumentError(
        'Use a test-owned cache adapter for isolated validation.',
      );
    }
    return _access.cacheRoot();
  }

  @override
  Future<OperationResult<void>> openFile(String path) async {
    try {
      await _access.openFile(path);
      return const OperationResult.success();
    } catch (_) {
      return const OperationResult.failure(
        OperationOutcome.ioFailure,
        'The attachment could not be opened.',
      );
    }
  }

  @override
  Future<void> dispose() async {}
}
