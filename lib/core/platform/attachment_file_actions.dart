import '../operations/operation_result.dart';

/// Platform cache ownership and external opening, independent of window APIs.
abstract class AttachmentFileActions {
  Future<String> cacheRoot({String? validationRoot});
  Future<OperationResult<void>> openFile(String path);
  Future<void> dispose();
}

abstract interface class RevocableAttachmentActions {
  Future<void> revokeFiles(List<String> paths);
}
