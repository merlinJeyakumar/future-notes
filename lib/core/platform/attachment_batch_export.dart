/// Explicit external export of a reviewed selection. The platform owns fresh
/// destinations and cleanup; the note coordinator owns preparation/cancellation.
abstract interface class AttachmentBatchExport {
  Future<String> destination(String fileName);
  Future<bool> publish(List<String> paths);
  Future<void> cleanup(Iterable<String> paths);
}
