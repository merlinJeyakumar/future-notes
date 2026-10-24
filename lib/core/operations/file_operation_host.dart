enum FileOperationKind { processing, opening, saving, deleting, recovery }

/// Opt-in runtime lifetime only. Storage serialization and recovery stay owned
/// by the existing file service; default desktop services do not implement it.
abstract interface class FileOperationHost {
  Future<T> runFileOperation<T>(
    FileOperationKind kind,
    Future<T> Function() action,
  );
}
