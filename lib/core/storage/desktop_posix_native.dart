import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// Native desktop-only operations. Mobile keeps its established document and
/// private-file adapters. flock owns an open description, unlike Dart's POSIX
/// process-scoped record locks, so a second isolate cannot acquire the writer.
abstract interface class DesktopPosixOperations {
  int moveWithoutReplace(String source, String destination);
  void syncDirectory(String directory);
}

class DesktopPosixNative implements DesktopPosixOperations {
  DesktopPosixNative() {
    if (!supportedHost) throw UnsupportedError('Desktop POSIX host required.');
  }

  static bool get supportedHost => Platform.isMacOS || Platform.isLinux;
  static bool isNameConflict(int code) =>
      code == 17 || (Platform.isMacOS ? code == 66 : code == 39);
  static bool isLockBusy(int? code) => code == (Platform.isMacOS ? 35 : 11);
  late final _library = DynamicLibrary.process();
  late final _open = _library
      .lookupFunction<
        Int32 Function(Pointer<Utf8>, Int32),
        int Function(Pointer<Utf8>, int)
      >('open');
  late final _close = _library
      .lookupFunction<Int32 Function(Int32), int Function(int)>('close');
  late final _flock = _library
      .lookupFunction<Int32 Function(Int32, Int32), int Function(int, int)>(
        'flock',
      );
  late final _sync = _library
      .lookupFunction<Int32 Function(Int32), int Function(int)>('fsync');
  late final _error = _library
      .lookupFunction<Pointer<Int32> Function(), Pointer<Int32> Function()>(
        Platform.isMacOS ? '__error' : '__errno_location',
      );

  int get _flags => Platform.isMacOS ? 0x1000100 : 0xa0000;

  int _descriptor(String path, {bool write = false}) {
    final text = path.toNativeUtf8();
    try {
      // No O_CREAT varargs: the caller exclusively creates an owned lock first.
      final fd = _open(text, _flags | (write ? 2 : 0));
      if (fd < 0)
        throw FileSystemException(
          'Native storage open failed',
          '',
          OSError('', _error().value),
        );
      return fd;
    } finally {
      calloc.free(text);
    }
  }

  DesktopPosixLease lock(String path) {
    final fd = _descriptor(path, write: true);
    if (_flock(fd, 2 | 4) != 0) {
      final code = _error().value;
      _close(fd);
      throw FileSystemException(
        'Storage writer is unavailable',
        '',
        OSError('', code),
      );
    }
    return DesktopPosixLease(() {
      // Closing releases this description's lock. Do not unlink the lock file.
      if (_close(fd) != 0)
        throw const FileSystemException('Storage lease close failed');
    });
  }

  @override
  void syncDirectory(String directory) {
    if (FileSystemEntity.typeSync(directory, followLinks: false) !=
        FileSystemEntityType.directory) {
      throw const FileSystemException('A regular directory is required.');
    }
    final fd = _descriptor(directory);
    try {
      if (_sync(fd) != 0)
        throw const FileSystemException('Directory persistence is unavailable');
    } finally {
      if (_close(fd) != 0)
        throw const FileSystemException('Directory handle close failed');
    }
  }

  @override
  int moveWithoutReplace(String source, String destination) {
    final from = source.toNativeUtf8();
    final to = destination.toNativeUtf8();
    try {
      final int result;
      if (Platform.isMacOS) {
        final move = _library
            .lookupFunction<
              Int32 Function(Pointer<Utf8>, Pointer<Utf8>, Uint32),
              int Function(Pointer<Utf8>, Pointer<Utf8>, int)
            >('renamex_np');
        result = move(from, to, 4); // RENAME_EXCL; never ordinary rename().
      } else {
        if (!_library.providesSymbol('renameat2')) return 95;
        final move = _library
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
        result = move(-100, from, -100, to, 1); // RENAME_NOREPLACE.
      }
      return result == 0 ? 0 : _error().value;
    } finally {
      calloc.free(from);
      calloc.free(to);
    }
  }
}

class DesktopPosixLease {
  DesktopPosixLease(this._release);
  final void Function() _release;
  bool _closed = false;
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _release();
  }
}
