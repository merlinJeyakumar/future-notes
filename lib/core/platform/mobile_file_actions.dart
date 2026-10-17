import 'package:flutter/services.dart';
import '../operations/operation_result.dart';
import 'attachment_file_actions.dart';

class MobileFileActions
    implements AttachmentFileActions, RevocableAttachmentActions {
  static const channel = MethodChannel('future_notes/files');
  @override
  Future<String> cacheRoot({String? validationRoot}) async {
    if (validationRoot != null)
      throw StateError('A mobile validation root must be native-owned.');
    return (await channel.invokeMethod<String>('cacheRoot'))!;
  }

  Future<String> privateRoot() async =>
      (await channel.invokeMethod<String>('privateRoot'))!;
  @override
  Future<OperationResult<void>> openFile(String path) async {
    try {
      await channel.invokeMethod<void>('openFile', {'path': path});
      return const OperationResult.success();
    } on PlatformException {
      return const OperationResult.failure(
        OperationOutcome.ioFailure,
        'No application could open this attachment.',
      );
    }
  }

  @override
  Future<void> revokeFiles(List<String> paths) =>
      channel.invokeMethod<void>('revokeFiles', {'paths': paths});
  @override
  Future<void> dispose() async {}
}
