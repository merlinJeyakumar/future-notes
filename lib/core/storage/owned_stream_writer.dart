import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'owned_write.dart';
import 'streaming_file_cipher.dart';
import '../platform/android_native_cipher.dart';

/// A single sequential output pass. The only readback is explicit opt-in.
class OwnedStreamWriter {
  OwnedStreamWriter._(
    this.target,
    this._file,
    this._digest,
    this._hash,
    this._native,
  );
  final OwnedWriteTarget target;
  final RandomAccessFile _file;
  final _Digest _digest;
  final ByteConversionSink _hash;
  final NativeChecksumSession? _native;
  bool get nativeChecksums => _native != null;
  int get crc => _native?.crc ?? 0;
  Future<void> resetCrc() async => _native?.resetCrc();
  int length = 0;
  int payloadReadBytes = 0;
  bool _closed = false;
  static Future<OwnedStreamWriter> open(
    String path, {
    bool Function()? cancelled,
  }) async {
    final target = OwnedWriteTarget.forPath(path);
    await target.validate(path);
    final file = File(path);
    await file.create(exclusive: true);
    final digest = _Digest();
    final handle = await file.open(mode: FileMode.writeOnly);
    try {
      final native = await AndroidNativeCipher.checksumSession(
        cancelled: cancelled,
      );
      return OwnedStreamWriter._(
        target,
        handle,
        digest,
        sha256.startChunkedConversion(digest),
        native,
      );
    } catch (_) {
      await handle.close();
      await file.delete();
      rethrow;
    }
  }

  Future<void> add(List<int> bytes, {bool trackCrc = false}) async {
    if (_closed) throw StateError('Output is closed.');
    await _file.writeFrom(bytes);
    if (_native == null) {
      _hash.add(bytes);
    } else {
      final data = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
      for (
        var offset = 0;
        offset < data.length;
        offset += StreamingFileCipher.window
      ) {
        final end = offset + StreamingFileCipher.window < data.length
            ? offset + StreamingFileCipher.window
            : data.length;
        await _native.add(
          Uint8List.sublistView(data, offset, end),
          trackCrc: trackCrc,
        );
      }
    }
    length += bytes.length;
  }

  Future<void> number(
    int value,
    int width, {
    Endian endian = Endian.little,
  }) async {
    final data = ByteData(width);
    if (width == 2) {
      data.setUint16(0, value, endian);
    } else if (width == 4) {
      data.setUint32(0, value, endian);
    } else if (width == 8) {
      data.setUint64(0, value, endian);
    } else {
      throw ArgumentError('Invalid integer width.');
    }
    await add(data.buffer.asUint8List());
  }

  Future<OwnedWriteReceipt> close({
    bool verifyReadback = false,
    FileByteProgress? progress,
  }) async {
    if (_closed) throw StateError('Output is closed.');
    _closed = true;
    late final String digest;
    try {
      try {
        await _file.flush();
      } finally {
        await _file.close();
      }
      _hash.close();
      digest = _native == null
          ? _digest.value.toString()
          : await _native.finish();
    } catch (_) {
      await _native?.abort();
      rethrow;
    }
    if (verifyReadback) {
      var count = 0;
      final readback = _Digest();
      final hash = sha256.startChunkedConversion(readback);
      await for (final chunk in File(target.path).openRead()) {
        hash.add(chunk);
        count += chunk.length;
        progress?.call('Verifying', count, length);
      }
      hash.close();
      if (count != length || readback.value.toString() != digest) {
        throw const FormatException('Owned output readback mismatch.');
      }
    }
    return OwnedWriteReceipt.closed(
      target: target,
      length: length,
      sha256Hex: digest,
      verifyReadback: verifyReadback,
      payloadReadBytes: payloadReadBytes,
      readbackBytes: verifyReadback ? length : 0,
    );
  }

  Future<void> abort() async {
    try {
      if (!_closed) {
        _closed = true;
        await _file.close();
      }
    } finally {
      await _native?.abort();
    }
    if (await File(target.path).exists()) await File(target.path).delete();
  }
}

class _Digest implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}
