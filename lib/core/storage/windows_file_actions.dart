import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:path/path.dart' as p;

import '../operations/operation_result.dart';
import 'storage_environment.dart';

abstract class StorageFileActions {
  Future<OperationResult<void>> moveWithoutReplace(
    String source,
    String destination,
  );
}

/// Metadata-only, same-volume move with native destination exclusion.
/// Dispatch through the storage owner worker before wiring to UI operations.
class WindowsFileActions implements StorageFileActions {
  WindowsFileActions({
    required this.root,
    required this.environment,
    this.nativeMove,
  });

  final String root;
  final StorageEnvironment environment;
  final int Function(String source, String destination)? nativeMove;
  late final _api = _WindowsMoveApi();

  Future<void> _verify(String location) async {
    if (!p.isAbsolute(root) ||
        p.split(root).contains('..') ||
        !p.isAbsolute(location) ||
        p.split(location).contains('..') ||
        !p.isWithin(p.normalize(root), p.normalize(location))) {
      throw ArgumentError('Move must remain inside its captured storage root.');
    }
    await environment.verifyLocation(location);
    var cursor = p.normalize(location);
    while (true) {
      if (await FileSystemEntity.type(cursor, followLinks: false) ==
          FileSystemEntityType.link) {
        throw StateError('Native moves cannot traverse links.');
      }
      final parent = p.dirname(cursor);
      if (p.equals(parent, cursor)) break;
      cursor = parent;
    }
  }

  @override
  Future<OperationResult<void>> moveWithoutReplace(
    String source,
    String destination,
  ) async {
    if (!Platform.isWindows) {
      return const OperationResult.failure(
        OperationOutcome.rejectedInput,
        'Native move is unsupported on this platform.',
      );
    }
    try {
      // Validate both strings before native allocation or file access.
      final nativeSource = _extendedPath(source);
      final nativeDestination = _extendedPath(destination);
      await _verify(source);
      await _verify(destination);
      if (p.equals(p.normalize(source), p.normalize(destination))) {
        return const OperationResult.failure(
          OperationOutcome.rejectedInput,
          'Source and destination must differ.',
        );
      }
      final type = await FileSystemEntity.type(source, followLinks: false);
      if (type != FileSystemEntityType.file &&
          type != FileSystemEntityType.notFound) {
        return const OperationResult.failure(
          OperationOutcome.rejectedInput,
          'Only a regular file can be moved.',
        );
      }
      // Preexisting destinations need no native call. The move still enforces
      // exclusion atomically if another writer creates one after this check.
      if (await FileSystemEntity.type(destination, followLinks: false) !=
          FileSystemEntityType.notFound) {
        return const OperationResult.failure(
          OperationOutcome.conflict,
          'Move destination already exists.',
        );
      }
      final error = (nativeMove ?? _api.move)(nativeSource, nativeDestination);
      if (error == 0) return const OperationResult.success();
      if (error == 80 || error == 183) {
        return const OperationResult.failure(
          OperationOutcome.conflict,
          'Move destination already exists.',
        );
      }
      // The native error can be unavailable. An unknown failed result remains
      // a failure; occupied destination plus a retained
      // source establishes the no-replace conflict without guessing an errno.
      if (error == -1 &&
          await FileSystemEntity.type(destination, followLinks: false) !=
              FileSystemEntityType.notFound &&
          await FileSystemEntity.type(source, followLinks: false) ==
              FileSystemEntityType.file) {
        return const OperationResult.failure(
          OperationOutcome.conflict,
          'Move destination already exists; source retained.',
        );
      }
      return OperationResult.failure(
        OperationOutcome.ioFailure,
        'Native file move failed (Win32 error $error).',
      );
    } on _NativeMoveFailure catch (error) {
      return OperationResult.failure(
        error.mayHaveMoved
            ? OperationOutcome.recoveryRequired
            : OperationOutcome.ioFailure,
        'Native file operation or allocation cleanup failed.',
      );
    } on ArgumentError {
      return const OperationResult.failure(
        OperationOutcome.rejectedInput,
        'Invalid native move location.',
      );
    } on StateError {
      return const OperationResult.failure(
        OperationOutcome.rejectedInput,
        'Native move prerequisite failed.',
      );
    } on FileSystemException {
      return const OperationResult.failure(
        OperationOutcome.ioFailure,
        'Native move location could not be accessed.',
      );
    }
  }
}

String _extendedPath(String value) {
  if (!p.windows.isAbsolute(value) ||
      value.contains('\u0000') ||
      value.startsWith(r'\\?\') ||
      value.startsWith(r'\\.\') ||
      p.windows.split(value).contains('..')) {
    throw ArgumentError('Invalid native path.');
  }
  final normalized = p.windows.normalize(value);
  final rootPrefix = p.windows.rootPrefix(normalized);
  final relative = normalized.substring(rootPrefix.length);
  for (final part in relative.split('\\')) {
    if (part.isEmpty ||
        part.endsWith(' ') ||
        part.endsWith('.') ||
        RegExp(r'[<>:"|?*\x00-\x1f]').hasMatch(part) ||
        RegExp(
          r'^(con|prn|aux|nul|com[1-9]|lpt[1-9])(\..*)?$',
          caseSensitive: false,
        ).hasMatch(part)) {
      throw ArgumentError('Invalid native path component.');
    }
  }
  final extended = normalized.startsWith('\\\\')
      ? '\\\\?\\UNC\\${normalized.substring(2)}'
      : '\\\\?\\$normalized';
  if (extended.codeUnits.length >= 32767)
    throw ArgumentError('Native path is too long.');
  return extended;
}

class _WindowsMoveApi {
  _WindowsMoveApi() {
    final kernel = ffi.DynamicLibrary.open('kernel32.dll');
    _getHeap = kernel
        .lookupFunction<
          ffi.Pointer<ffi.Void> Function(),
          ffi.Pointer<ffi.Void> Function()
        >('GetProcessHeap');
    _alloc = kernel
        .lookupFunction<
          ffi.Pointer<ffi.Void> Function(
            ffi.Pointer<ffi.Void>,
            ffi.Uint32,
            ffi.UintPtr,
          ),
          ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Void>, int, int)
        >('HeapAlloc');
    _free = kernel
        .lookupFunction<
          ffi.Int32 Function(
            ffi.Pointer<ffi.Void>,
            ffi.Uint32,
            ffi.Pointer<ffi.Void>,
          ),
          int Function(ffi.Pointer<ffi.Void>, int, ffi.Pointer<ffi.Void>)
        >('HeapFree');
    _move = kernel
        .lookupFunction<
          ffi.Int32 Function(
            ffi.Pointer<ffi.Uint16>,
            ffi.Pointer<ffi.Uint16>,
            ffi.Uint32,
          ),
          int Function(ffi.Pointer<ffi.Uint16>, ffi.Pointer<ffi.Uint16>, int)
        >('MoveFileExW');
    _lastError = kernel.lookupFunction<ffi.Uint32 Function(), int Function()>(
      'GetLastError',
      isLeaf: true,
    );
  }

  late final ffi.Pointer<ffi.Void> Function() _getHeap;
  late final ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Void>, int, int)
  _alloc;
  late final int Function(ffi.Pointer<ffi.Void>, int, ffi.Pointer<ffi.Void>)
  _free;
  late final int Function(ffi.Pointer<ffi.Uint16>, ffi.Pointer<ffi.Uint16>, int)
  _move;
  late final int Function() _lastError;

  ffi.Pointer<ffi.Uint16> _utf16(ffi.Pointer<ffi.Void> heap, String value) {
    final units = value.codeUnits;
    final allocated = _alloc(heap, 0, (units.length + 1) * 2);
    if (allocated.address == 0) throw const _NativeMoveFailure(false);
    final pointer = allocated.cast<ffi.Uint16>();
    try {
      final buffer = pointer.asTypedList(units.length + 1);
      buffer.setRange(0, units.length, units);
      buffer[units.length] = 0;
      return pointer;
    } catch (_) {
      _free(heap, 0, allocated);
      throw const _NativeMoveFailure(false);
    }
  }

  int move(String source, String destination) {
    final heap = _getHeap();
    if (heap.address == 0) throw const _NativeMoveFailure(false);
    ffi.Pointer<ffi.Uint16>? from;
    ffi.Pointer<ffi.Uint16>? to;
    var moved = false;
    try {
      from = _utf16(heap, source);
      to = _utf16(heap, destination);
      // No REPLACE_EXISTING, COPY_ALLOWED or deferred/reboot operation.
      // Bind before the move and avoid a VM transition when reading its
      // thread-local error. Only this short accessor is a leaf call; the move
      // itself may block and must remain a normal FFI call.
      final readError = _lastError;
      final result = _move(from, to, 0);
      final error = result == 0 ? readError() : 0;
      moved = result != 0;
      if (moved) return 0;
      // A failed native result must never become success if no error is set.
      return error == 0 ? -1 : error;
    } finally {
      var freed = true;
      if (to != null) freed = _free(heap, 0, to.cast()) != 0 && freed;
      if (from != null) freed = _free(heap, 0, from.cast()) != 0 && freed;
      if (!freed) throw _NativeMoveFailure(moved);
    }
  }
}

class _NativeMoveFailure implements Exception {
  const _NativeMoveFailure(this.mayHaveMoved);
  final bool mayHaveMoved;
}
