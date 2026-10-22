import '../operations/operation_result.dart';

/// Host publication primitive. A failed/ambiguous move never authorizes deleting
/// either object. Higher-level journals retain recovery ownership.
abstract class StorageFileActions {
  Future<OperationResult<void>> moveWithoutReplace(
    String source,
    String destination,
  );
}
