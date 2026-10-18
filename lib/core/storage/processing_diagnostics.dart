import 'dart:convert';

/// Numeric, content-free counters. No names, paths, identifiers or credentials.
class ProcessingDiagnostics {
  static void completed({
    required int operation,
    required int elapsedMicros,
    required int readBytes,
    required int writtenBytes,
    required int readbackBytes,
  }) {
    // Kept separate from error messages and user-facing progress text.
    print(
      'FN_PAYLOAD_IO ${jsonEncode(<String, int>{'operation': operation, 'elapsed_us': elapsedMicros, 'transform_read_bytes': readBytes, 'write_bytes': writtenBytes, 'readback_bytes': readbackBytes})}',
    );
  }
}
