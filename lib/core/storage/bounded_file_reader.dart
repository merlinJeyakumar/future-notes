import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:archive/archive.dart' as archive;
import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';

/// A bounded, read-only cursor. Android SAF descriptors remain capabilities;
/// never reopen their /proc endpoint or turn their URI into a filesystem path.
/// Parent source ownership must remain live until this reader has closed.
class BoundedFileReader extends archive.AbstractFileHandle
    implements Finalizable {
  BoundedFileReader._(
    this._file,
    this._fd,
    this._grant,
    this._path,
    this.length,
  );
  static const window = 1024 * 1024;
  static const channel = MethodChannel('future_notes/documents');
  final RandomAccessFile? _file;
  final int? _fd;
  final Map<Object?, Object?>? _grant;
  final String _path;
  @override
  final int length;
  int _position = 0;
  bool _closed = false;
  Pointer<Uint8>? _buffer;
  Future<void>? _closing;
  static final _finalizer = NativeFinalizer(calloc.nativeFree);
  static final _pread = DynamicLibrary.open('libc.so')
      .lookupFunction<
        IntPtr Function(Int32, Pointer<Void>, IntPtr, Int64),
        int Function(int, Pointer<Void>, int, int)
      >('pread64');
  static final _errno = DynamicLibrary.open('libc.so')
      .lookupFunction<Pointer<Int32> Function(), Pointer<Int32> Function()>(
        '__errno',
      );

  static Future<BoundedFileReader> openPath(String path) async {
    if (Platform.isAndroid &&
        RegExp(r'^/proc/self/fd/[0-9]+$').hasMatch(path)) {
      final grant = await channel.invokeMapMethod<Object?, Object?>(
        'borrowReader',
        {'path': path},
      );
      if (grant == null ||
          grant['fd'] is! int ||
          grant['length'] is! int ||
          (grant['length'] as int) < 0) {
        throw const FileSystemException('Granted reader is unavailable.');
      }
      return BoundedFileReader._(
        null,
        grant['fd'] as int,
        grant,
        path,
        grant['length'] as int,
      );
    }
    final file = await File(path).open();
    return BoundedFileReader._(file, null, null, path, await file.length());
  }

  @override
  bool get isOpen => !_closed;
  @override
  bool open({archive.FileAccess mode = archive.FileAccess.read}) =>
      !_closed && mode == archive.FileAccess.read;
  @override
  int get position => _position;
  @override
  set position(int value) {
    if (_closed || value < 0 || value > length)
      throw const FormatException('Read cursor exceeds its bound.');
    _position = value;
    _file?.setPositionSync(value);
  }

  Future<void> setPosition(int value) async {
    position = value;
  }

  Future<Uint8List> read(int count) async {
    if (count < 0 || count > window)
      throw const FormatException('Read window exceeds its bound.');
    final bytes = Uint8List(math.min(count, length - position));
    final read = readInto(bytes);
    return read == bytes.length ? bytes : Uint8List.sublistView(bytes, 0, read);
  }

  @override
  int readInto(Uint8List buffer, [int? length]) {
    final count = math.min(length ?? buffer.length, this.length - position);
    if (_closed || count < 0 || count > window || count > buffer.length)
      throw const FormatException('Invalid read window.');
    if (count == 0) return 0;
    final int read;
    if (_file != null) {
      read = _file.readIntoSync(buffer, 0, count);
    } else {
      if (_buffer == null) {
        _buffer = calloc<Uint8>(window);
        _finalizer.attach(this, _buffer!.cast<Void>(), detach: this);
      }
      var result = _pread(_fd!, _buffer!.cast<Void>(), count, position);
      var interrupts = 0;
      while (result < 0 && _errno().value == 4 && interrupts++ < 8) {
        result = _pread(_fd, _buffer!.cast<Void>(), count, position);
      }
      read = result;
      if (read < 0)
        throw const FileSystemException('Granted descriptor read failed.');
      if (read > count)
        throw const FormatException('Invalid granted read length.');
      buffer.setRange(0, read, _buffer!.asTypedList(read));
    }
    _position += read;
    return read;
  }

  @override
  void writeFromSync(List<int> buffer, [int start = 0, int? end]) =>
      throw UnsupportedError('Read-only source.');
  @override
  void closeSync() {
    if (_closed) return;
    _closed = true;
    _file?.closeSync();
    if (_buffer != null) {
      _finalizer.detach(this);
      _buffer!.asTypedList(window).fillRange(0, window, 0);
      calloc.free(_buffer!);
      _buffer = null;
    }
    _closing = _grant == null
        ? Future.value()
        : channel.invokeMethod<void>('checkReader', {'path': _path, ..._grant});
  }

  @override
  Future<void> close() async {
    closeSync();
    await _closing;
  }
}
