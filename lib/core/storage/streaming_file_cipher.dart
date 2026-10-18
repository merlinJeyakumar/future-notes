import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart' hide Digest;
import '../platform/android_native_cipher.dart';
import 'owned_write.dart';
import 'bounded_file_reader.dart';
import 'owned_stream_writer.dart';

/// A reopenable file or package record. Bounds are checked before opening and
/// after consumption; callers own the source until the operation settles.
class StreamingFileSource {
  const StreamingFileSource(
    this.path,
    this.length, {
    this.offset = 0,
    this.sha256Hex,
    this.modifiedMicros,
    this.receipt,
  });
  final String path;
  final int length;
  final int offset;
  final String? sha256Hex;
  final int? modifiedMicros;
  final OwnedWriteReceipt? receipt;
}

class CipherFileResult {
  const CipherFileResult(this.length, this.plaintextHash, [this.receipt]);
  final int length;
  final String plaintextHash;
  final OwnedWriteReceipt? receipt;
}

class FileJobCancelled implements Exception {
  const FileJobCancelled();
}

/// Bounded SIC/PKCS7 stream encoder used when framing and encryption share one
/// output pass. Uses the same key/IV implementation as existing .med files.
class FileCipherEncoder {
  FileCipherEncoder._(this.iv, this._cipher);
  final Uint8List iv;
  final _ReaderCipher _cipher;
  int _bytes = 0;
  static Future<FileCipherEncoder> open(
    String? password, {
    bool Function()? cancelled,
  }) async {
    final random = Random.secure();
    final iv = Uint8List.fromList(
      List.generate(16, (_) => random.nextInt(256)),
    );
    return FileCipherEncoder._(
      iv,
      await _ReaderCipher.create(password, iv, cancelled: cancelled),
    );
  }

  Future<Uint8List> add(Uint8List bytes) {
    _bytes += bytes.length;
    return _cipher.process(bytes);
  }

  Future<Uint8List> finish() => _cipher.process(
    Uint8List.fromList(List.filled(16 - _bytes % 16, 16 - _bytes % 16)),
  );
  Future<void> close() => _cipher.close();
}

typedef FileByteProgress = void Function(String phase, int bytes, int total);

/// Existing .med layout: 16-byte IV followed by AES-SIC / PKCS7 ciphertext.
/// This preserves legacy compatibility; successful padding is not authenticated
/// integrity. Only intentional export may produce a plaintext destination.
class StreamingFileCipher {
  static const window = 1024 * 1024;
  static const maxAttachmentBytes = 10 * 1024 * 1024 * 1024;
  static const _appKey = 'MySuperSecretAppKeyForJsonStore!';

  static Uint8List _key(String? password) {
    final bytes = utf8.encode(password ?? _appKey);
    if (password == null) return Uint8List.fromList(bytes);
    final key = Uint8List(32);
    key.setRange(0, min(32, bytes.length), bytes);
    return key;
  }

  static SICStreamCipher _cipher(String? password, Uint8List iv) =>
      SICStreamCipher(AESEngine())
        ..init(true, ParametersWithIV(KeyParameter(_key(password)), iv));

  static void _checkCancelled(bool Function()? cancelled) {
    if (cancelled?.call() == true) throw const FileJobCancelled();
  }

  /// Call in an owned worker. Rekeying streams plaintext between two cipher
  /// states without a plaintext temporary file.
  static Future<CipherFileResult> transform({
    required StreamingFileSource source,
    required String destination,
    required bool decryptSource,
    required bool encryptDestination,
    String? sourcePassword,
    String? destinationPassword,
    bool Function()? cancelled,
    Future<void> Function()? cooperate,
    void Function()? beginCompute,
    void Function()? endCompute,
    FileByteProgress? progress,
    int maxPlaintextBytes = maxAttachmentBytes,
    bool verifyOutput = true,
    int? expectedPlaintextBytes,
    bool requireWholeSource = false,
    double Function()? duty,
    bool useNative = true,
    OwnedWriteTarget? ownedTarget,
  }) async {
    await ownedTarget?.validate(destination);
    if (useNative && AndroidNativeCipher.ready) {
      return AndroidNativeCipher.transform(
        source: source,
        destination: destination,
        decryptSource: decryptSource,
        encryptDestination: encryptDestination,
        sourcePassword: sourcePassword,
        destinationPassword: destinationPassword,
        cancelled: cancelled,
        duty: duty,
        progress: progress,
        maxPlaintextBytes: maxPlaintextBytes,
        verifyOutput: verifyOutput,
        expectedPlaintextBytes: expectedPlaintextBytes,
        requireWholeSource: requireWholeSource,
        ownedTarget: ownedTarget,
      );
    }
    if (source.offset < 0 || source.length < 0 || source.path == destination) {
      throw const FormatException('Invalid streaming source.');
    }
    final file = File(source.path);
    final before = await file.stat();
    if (!verifyOutput &&
        (!decryptSource || encryptDestination) &&
        ownedTarget == null) {
      throw const FormatException(
        'Output readback is mandatory for writes and rekeying.',
      );
    }
    if (before.type != FileSystemEntityType.file ||
        source.offset + source.length > before.size) {
      throw const FormatException('Source is missing or truncated.');
    }
    if (source.modifiedMicros != null &&
        source.modifiedMicros != before.modified.microsecondsSinceEpoch) {
      throw const FormatException('Captured source revision changed.');
    }
    if (requireWholeSource &&
        (source.offset != 0 || source.length != before.size)) {
      throw const FormatException('Attachment framing changed.');
    }
    if (decryptSource &&
        (source.length < 32 || (source.length - 16) % 16 != 0)) {
      throw const FormatException('Invalid legacy ciphertext length.');
    }
    if (!decryptSource && source.length > maxPlaintextBytes) {
      throw const FormatException('Attachment exceeds the allowed size.');
    }
    // Never truncate an existing object, including a prior failed attempt.
    final output = File(destination);
    if (ownedTarget?.sink == null) await output.create(exclusive: true);
    BoundedFileReader? input;
    RandomAccessFile? sink;
    final plaintextDigest = _DigestSink();
    final hash = sha256.startChunkedConversion(plaintextDigest);
    final outputDigest = _DigestSink();
    final outputHash = encryptDestination
        ? sha256.startChunkedConversion(outputDigest)
        : null;
    final sourceDigest = _DigestSink();
    // No unused second hash when the source has no captured expected digest.
    final sourceHash = source.sha256Hex == null
        ? null
        : sha256.startChunkedConversion(sourceDigest);
    var plaintextBytes = 0;
    var written = 0;
    final clock = Stopwatch()..start();
    var lastProgress = -100;
    void report(String phase, int bytes, {bool force = false}) {
      if (force || clock.elapsedMilliseconds - lastProgress >= 100) {
        progress?.call(phase, bytes, source.length);
        lastProgress = clock.elapsedMilliseconds;
      }
    }

    try {
      _checkCancelled(cancelled);
      input = await BoundedFileReader.openPath(file.path);
      await input.setPosition(source.offset);
      sink = await output.open(mode: FileMode.writeOnly);
      SICStreamCipher? decoder;
      if (decryptSource) {
        final iv = await input.read(16);
        if (iv.length != 16) throw const FormatException('Truncated IV.');
        decoder = _cipher(sourcePassword, iv);
        sourceHash?.add(iv);
      }
      SICStreamCipher? encoder;
      if (encryptDestination) {
        final random = Random.secure();
        final iv = Uint8List.fromList(
          List.generate(16, (_) => random.nextInt(256)),
        );
        encoder = _cipher(destinationPassword, iv);
        await sink.writeFrom(iv);
        outputHash?.add(iv);
        written = 16;
      }
      var remaining = source.length - (decryptSource ? 16 : 0);
      var consumed = decryptSource ? 16 : 0;
      var retained = Uint8List(0);
      final phase = decryptSource ? 'Decrypting' : 'Encrypting';
      report(phase, consumed, force: true);
      while (remaining > 0) {
        _checkCancelled(cancelled);
        await cooperate?.call();
        _checkCancelled(cancelled);
        final bytes = await input.read(min(window, remaining));
        if (bytes.isEmpty) throw const FormatException('Short source read.');
        late Uint8List encoded;
        beginCompute?.call();
        try {
          sourceHash?.add(bytes);
          remaining -= bytes.length;
          consumed += bytes.length;
          var plain = bytes;
          if (decoder != null) {
            final decoded = decoder.process(bytes);
            final joined = Uint8List(retained.length + decoded.length)
              ..setAll(0, retained)
              ..setAll(retained.length, decoded);
            if (remaining > 0) {
              final keep = min(16, joined.length);
              plain = Uint8List.sublistView(joined, 0, joined.length - keep);
              retained = Uint8List.fromList(
                joined.sublist(joined.length - keep),
              );
            } else {
              plain = joined;
            }
          }
          if (decoder != null && remaining == 0) {
            final padding = plain.last;
            if (padding < 1 ||
                padding > 16 ||
                padding > plain.length ||
                plain
                    .sublist(plain.length - padding)
                    .any((v) => v != padding)) {
              throw const FormatException('Invalid legacy padding.');
            }
            plain = Uint8List.sublistView(plain, 0, plain.length - padding);
          }
          plaintextBytes += plain.length;
          if (plaintextBytes > maxPlaintextBytes) {
            throw const FormatException('Attachment exceeds the allowed size.');
          }
          hash.add(plain);
          encoded = encoder == null ? plain : encoder.process(plain);
        } finally {
          endCompute?.call();
        }
        await sink.writeFrom(encoded);
        outputHash?.add(encoded);
        written += encoded.length;
        report(phase, consumed);
      }
      if (encoder != null) {
        final padding = 16 - plaintextBytes % 16;
        final tail = encoder.process(
          Uint8List.fromList(List.filled(padding, padding)),
        );
        await sink.writeFrom(tail);
        outputHash?.add(tail);
        written += tail.length;
      }
      hash.close();
      outputHash?.close();
      if (expectedPlaintextBytes != null &&
          plaintextBytes != expectedPlaintextBytes) {
        throw const FormatException(
          'Decrypted length differs from declared metadata.',
        );
      }
      sourceHash?.close();
      if (source.sha256Hex != null &&
          source.sha256Hex != sourceDigest.value.toString()) {
        throw const FormatException('Captured source content changed.');
      }
      if (decryptSource && encryptDestination) {
        report('Encrypting', source.length, force: true);
      }
      await sink.flush();
      await sink.close();
      sink = null;
      await input.close();
      input = null;
      final after = await file.stat();
      if (before.size != after.size ||
          before.modified != after.modified ||
          before.changed != after.changed ||
          after.type != before.type) {
        throw const FormatException('Source changed during transformation.');
      }
      _checkCancelled(cancelled);
      if (verifyOutput) {
        report('Verifying', 0, force: true);
        final verified = await _plaintextHash(
          StreamingFileSource(destination, written),
          password: destinationPassword,
          encrypted: encryptDestination,
          cancelled: cancelled,
          cooperate: cooperate,
          beginCompute: beginCompute,
          endCompute: endCompute,
          verifiedBytes: (bytes) =>
              report('Verifying', min(source.length, bytes)),
        );
        if (verified != plaintextDigest.value.toString()) {
          throw const FormatException('Staged transformation mismatch.');
        }
        report('Verifying', source.length, force: true);
      }
      _checkCancelled(cancelled);
      final receipt = ownedTarget == null
          ? null
          : await OwnedWriteReceipt.closed(
              target: ownedTarget,
              length: written,
              sha256Hex: (encryptDestination ? outputDigest : plaintextDigest)
                  .value
                  .toString(),
              verifyReadback: verifyOutput,
              payloadReadBytes: source.length,
              readbackBytes: verifyOutput ? written : 0,
            );
      return CipherFileResult(
        written,
        plaintextDigest.value.toString(),
        receipt,
      );
    } catch (_) {
      await sink?.close();
      sink = null;
      await input?.close();
      input = null;
      // The exclusively-created destination belongs to this attempt only.
      if (ownedTarget?.sink == null && await output.exists())
        await output.delete();
      rethrow;
    } finally {
      await input?.close();
      await sink?.close();
    }
  }

  static Future<String> _plaintextHash(
    StreamingFileSource source, {
    required String? password,
    required bool encrypted,
    bool Function()? cancelled,
    Future<void> Function()? cooperate,
    void Function()? beginCompute,
    void Function()? endCompute,
    void Function(int bytes)? verifiedBytes,
  }) async {
    final input = await File(source.path).open();
    final digest = _DigestSink();
    final hash = sha256.startChunkedConversion(digest);
    try {
      SICStreamCipher? cipher;
      var remaining = source.length;
      var retained = Uint8List(0);
      if (encrypted) {
        final iv = await input.read(16);
        cipher = _cipher(password, iv);
        remaining -= 16;
      }
      while (remaining > 0) {
        _checkCancelled(cancelled);
        await cooperate?.call();
        _checkCancelled(cancelled);
        final bytes = await input.read(min(window, remaining));
        if (bytes.isEmpty) {
          throw const FormatException('Short verification read.');
        }
        beginCompute?.call();
        try {
          remaining -= bytes.length;
          var plain = bytes;
          if (cipher != null) {
            final decoded = cipher.process(bytes);
            final joined = Uint8List(retained.length + decoded.length)
              ..setAll(0, retained)
              ..setAll(retained.length, decoded);
            if (remaining > 0) {
              final keep = min(16, joined.length);
              plain = Uint8List.sublistView(joined, 0, joined.length - keep);
              retained = Uint8List.fromList(
                joined.sublist(joined.length - keep),
              );
            } else {
              plain = joined;
            }
          }
          if (cipher != null && remaining == 0) {
            final padding = plain.last;
            if (padding < 1 ||
                padding > 16 ||
                padding > plain.length ||
                plain
                    .sublist(plain.length - padding)
                    .any((v) => v != padding)) {
              throw const FormatException('Invalid verification padding.');
            }
            plain = Uint8List.sublistView(plain, 0, plain.length - padding);
          }
          hash.add(plain);
        } finally {
          endCompute?.call();
        }
        verifiedBytes?.call(source.length - remaining);
      }
      hash.close();
      return digest.value.toString();
    } finally {
      await input.close();
    }
  }
}

class _DigestSink implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest digest) => value = digest;
  @override
  void close() {}
}

/// Bounded sequential reader for encrypted package framing. It validates the
/// last PKCS7 block before admitting a plaintext length, then consumes exactly
/// that length without materializing the package or staging plaintext payloads.
class LegacyFileReader {
  LegacyFileReader._(
    this._file,
    this._before,
    this._input,
    this._cipher,
    this.remaining,
    this._source,
    this._rawDigest,
    this._rawHash,
  );
  final File _file;
  final FileStat _before;
  final BoundedFileReader _input;
  final _ReaderCipher? _cipher;
  final StreamingFileSource _source;
  final _DigestSink _rawDigest;
  final ByteConversionSink _rawHash;
  int remaining;
  static Future<LegacyFileReader> open(
    StreamingFileSource source, {
    bool encrypted = false,
    String? password,
    bool Function()? cancelled,
  }) async {
    final file = File(source.path);
    final before = await file.stat();
    if (source.offset < 0 ||
        source.length < 0 ||
        source.offset + source.length > before.size ||
        before.type != FileSystemEntityType.file) {
      throw const FormatException('Invalid package source.');
    }
    final input = await BoundedFileReader.openPath(file.path);
    final digest = _DigestSink();
    final hash = sha256.startChunkedConversion(digest);
    try {
      await input.setPosition(source.offset);
      if (source.modifiedMicros != null &&
          source.modifiedMicros != before.modified.microsecondsSinceEpoch) {
        throw const FormatException('Captured package revision changed.');
      }
      if (!encrypted) {
        return LegacyFileReader._(
          file,
          before,
          input,
          null,
          source.length,
          source,
          digest,
          hash,
        );
      }
      if (source.length < 32 || (source.length - 16) % 16 != 0) {
        throw const FormatException('Invalid encrypted package length.');
      }
      final iv = await input.read(16);
      if (iv.length != 16) throw const FormatException('Truncated package IV.');
      if (source.sha256Hex != null) hash.add(iv);
      final blocks = (source.length - 16) ~/ 16;
      final counter = Uint8List.fromList(iv);
      var carry = blocks - 1;
      for (var i = 15; i >= 0 && carry > 0; i--) {
        final value = counter[i] + (carry & 255);
        counter[i] = value & 255;
        carry = (carry >> 8) + (value >> 8);
      }
      if (carry != 0) throw const FormatException('Cipher counter overflow.');
      await input.setPosition(source.offset + source.length - 16);
      final tail = await input.read(16);
      if (tail.length != 16) {
        throw const FormatException('Truncated package tail.');
      }
      final plaintext = AndroidNativeCipher.ready
          ? await AndroidNativeCipher.buffer(
              tail,
              StreamingFileCipher._key(password),
              counter,
              encrypt: false,
              padding: false,
            )
          : StreamingFileCipher._cipher(password, counter).process(tail);
      final padding = plaintext.last;
      if (padding < 1 ||
          padding > 16 ||
          plaintext.sublist(16 - padding).any((v) => v != padding)) {
        throw const FormatException('Invalid package padding.');
      }
      await input.setPosition(source.offset + 16);
      return LegacyFileReader._(
        file,
        before,
        input,
        await _ReaderCipher.create(password, iv, cancelled: cancelled),
        source.length - 16 - padding,
        source,
        digest,
        hash,
      );
    } catch (_) {
      await input.close();
      rethrow;
    }
  }

  Future<Uint8List> read(int count) async {
    if (count < 0 || count > remaining || count > 32 * 1024 * 1024) {
      throw const FormatException('Package record exceeds its bound.');
    }
    final output = Uint8List(count);
    var offset = 0;
    while (offset < count) {
      final bytes = await _input.read(
        min(StreamingFileCipher.window, count - offset),
      );
      if (bytes.isEmpty) {
        throw const FormatException('Truncated package record.');
      }
      if (_source.sha256Hex != null) _rawHash.add(bytes);
      output.setAll(
        offset,
        _cipher == null ? bytes : await _cipher.process(bytes),
      );
      offset += bytes.length;
    }
    remaining -= count;
    return output;
  }

  Future<OwnedWriteReceipt> copyTo(
    String destination,
    int length, {
    bool Function()? cancelled,
    bool verifyWrites = false,
    void Function(int bytes, int total)? onProgress,
  }) async {
    if (length < 0 || length > remaining) {
      throw const FormatException('Truncated package attachment.');
    }
    // An unencrypted package record is already a bounded byte slice. Keep the
    // copy and streamed checksum in the existing owned native worker; do not
    // shuttle its payload through Dart. A captured whole-source checksum still
    // uses the sequential reader so that its validation remains intact.
    if (_cipher == null &&
        _source.sha256Hex == null &&
        AndroidNativeCipher.hasOwnedWorker &&
        // Native dispatch/polling costs more than a small sequential copy.
        length >= 4 * StreamingFileCipher.window) {
      StreamingFileCipher._checkCancelled(cancelled);
      final start = _input.position;
      onProgress?.call(0, length);
      final target = OwnedWriteTarget.forPath(destination);
      final copied = await StreamingFileCipher.transform(
        source: StreamingFileSource(
          _source.path,
          length,
          offset: start,
          modifiedMicros: _before.modified.microsecondsSinceEpoch,
        ),
        destination: destination,
        decryptSource: false,
        encryptDestination: false,
        ownedTarget: target,
        verifyOutput: verifyWrites,
        cancelled: cancelled,
        expectedPlaintextBytes: length,
        maxPlaintextBytes: StreamingFileCipher.maxAttachmentBytes + 32,
        progress: (_, bytes, total) => onProgress?.call(bytes, total),
      );
      await _input.setPosition(start + length);
      remaining -= length;
      onProgress?.call(length, length);
      return copied.receipt!;
    }
    final output = await OwnedStreamWriter.open(
      destination,
      cancelled: cancelled,
    );
    try {
      var left = length;
      onProgress?.call(0, length);
      while (left > 0) {
        StreamingFileCipher._checkCancelled(cancelled);
        final count = min(left, StreamingFileCipher.window);
        await output.add(await read(count));
        output.payloadReadBytes += count;
        left -= count;
        onProgress?.call(length - left, length);
      }
      return await output.close(verifyReadback: verifyWrites);
    } catch (_) {
      await output.abort();
      rethrow;
    }
  }

  Future<void> close() async {
    try {
      if (remaining == 0) {
        final padding = _source.offset + _source.length - _input.position;
        if (padding > 0 && padding <= 16) {
          final bytes = await _input.read(padding);
          if (_source.sha256Hex != null) _rawHash.add(bytes);
        }
        _rawHash.close();
        if (_source.sha256Hex != null &&
            _source.sha256Hex != _rawDigest.value.toString()) {
          throw const FormatException('Captured package content changed.');
        }
      }
    } finally {
      try {
        await _input.close();
      } finally {
        await _cipher?.close();
      }
    }
    final after = await _file.stat();
    if (_before.size != after.size ||
        _before.modified != after.modified ||
        _before.changed != after.changed) {
      throw const FormatException('Package source changed during reading.');
    }
  }
}

class _ReaderCipher {
  _ReaderCipher(this.dart, this.native);
  final SICStreamCipher? dart;
  final NativeCipherSession? native;
  static Future<_ReaderCipher> create(
    String? password,
    Uint8List iv, {
    bool Function()? cancelled,
  }) async => AndroidNativeCipher.ready
      ? _ReaderCipher(
          null,
          await AndroidNativeCipher.session(
            StreamingFileCipher._key(password),
            iv,
            cancelled: cancelled,
          ),
        )
      : _ReaderCipher(StreamingFileCipher._cipher(password, iv), null);
  Future<Uint8List> process(Uint8List bytes) async =>
      native != null ? await native!.process(bytes) : dart!.process(bytes);
  Future<void> close() async {
    await native?.close();
  }
}
