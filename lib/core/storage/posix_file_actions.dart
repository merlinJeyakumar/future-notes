import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;
import '../operations/operation_result.dart';
import 'native_storage_primitives.dart';
import 'storage_environment.dart';
import 'windows_file_actions.dart';

/// App-private export publication on mobile POSIX filesystems. Modern Android
/// uses renameat2(RENAME_NOREPLACE); other runtimes retain link()/unlink().
/// Neither operation replaces a destination or removes an unpublished source.
/// Selected document providers use their separate generation protocol.
class PosixFileActions implements StorageFileActions {
  const PosixFileActions(this.root);
  final String root;
  @override
  Future<OperationResult<void>> moveWithoutReplace(
    String source,
    String destination,
  ) async {
    if (!(Platform.isAndroid || Platform.isIOS) ||
        !p.isAbsolute(root) ||
        !p.equals(p.dirname(source), root) ||
        !p.equals(p.dirname(destination), root) ||
        source == destination) {
      return const OperationResult.failure(
        OperationOutcome.rejectedInput,
        'Invalid private export publication.',
      );
    }
    final primitives = NativeStoragePrimitives(
      const StorageEnvironment.production(),
    );
    try {
      await primitives.inspectMetadata(source);
      await primitives.captureRevision(destination);
      final library = Platform.isAndroid
          ? DynamicLibrary.open('libc.so')
          : DynamicLibrary.process();
      final from = source.toNativeUtf8();
      final to = destination.toNativeUtf8();
      try {
        // Android app policy can deny hard links (EACCES) even in app-owned
        // cache directories. API 30+ exposes the kernel's no-replace rename;
        // do not substitute ordinary rename(), which could overwrite a file.
        if (Platform.isAndroid && library.providesSymbol('renameat2')) {
          final rename = library
              .lookupFunction<
                Int32 Function(
                  Int32,
                  Pointer<Utf8>,
                  Int32,
                  Pointer<Utf8>,
                  Uint32,
                ),
                int Function(int, Pointer<Utf8>, int, Pointer<Utf8>, int)
              >('renameat2');
          const atCurrentWorkingDirectory = -100;
          const noReplace = 1;
          return rename(
                    atCurrentWorkingDirectory,
                    from,
                    atCurrentWorkingDirectory,
                    to,
                    noReplace,
                  ) ==
                  0
              ? const OperationResult.success()
              : const OperationResult.failure(
                  OperationOutcome.ioFailure,
                  'The export could not be moved without replacement. Retained copies were preserved.',
                );
        }
        final link = library
            .lookupFunction<
              Int32 Function(Pointer<Utf8>, Pointer<Utf8>),
              int Function(Pointer<Utf8>, Pointer<Utf8>)
            >('link');
        if (link(from, to) != 0)
          return const OperationResult.failure(
            OperationOutcome.ioFailure,
            'The destination could not be created without replacement.',
          );
      } finally {
        calloc.free(from);
        calloc.free(to);
      }
      await File(source).delete();
      return const OperationResult.success();
    } catch (_) {
      return const OperationResult.failure(
        OperationOutcome.recoveryRequired,
        'Private export publication requires recovery; copies were retained.',
      );
    }
  }
}
