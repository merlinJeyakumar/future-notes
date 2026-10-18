import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/services.dart';
import '../storage/streaming_file_cipher.dart';
import '../storage/attachment_performance.dart';
import '../storage/owned_write.dart';

/// One implementation adapter; note/package formats and publication stay Dart
/// owned. Payload files never cross the channel during bulk transforms.
class AndroidNativeCipher {
  static const _channel = MethodChannel('future_notes/cipher');
  static bool ready = false;
  static String? _owner;
  static bool get hasOwnedWorker => ready && _owner != null;

  static Future<NativeChecksumSession?> checksumSession({
    bool Function()? cancelled,
  }) async {
    if (!hasOwnedWorker) return null;
    try {
      final id = await _channel.invokeMethod<String>('digestOpen', {
        'owner': _owner,
      });
      if (id == null) throw StateError('Native checksum owner missing.');
      return NativeChecksumSession._(id, cancelled);
    } on MissingPluginException {
      return null; // Existing adapters keep their established Dart checksum.
    }
  }

  static Future<void> _pace(
    Map<String, Object?> result,
    String id,
    bool Function()? cancelled,
  ) async {
    final worked = (result['cpuMicros'] as num).toDouble();
    var duty = (result['duty'] as num).toDouble();
    final waited = Stopwatch()..start();
    var refreshAt = 1000000;
    while (true) {
      if (cancelled?.call() == true) throw const FileJobCancelled();
      if (waited.elapsedMicroseconds >= refreshAt) {
        duty = (await _channel.invokeMethod<num>('sessionBudget', {
          'id': id,
        }))!.toDouble();
        refreshAt = waited.elapsedMicroseconds + 1000000;
      }
      if (!duty.isFinite ||
          duty < 0 ||
          duty > 1 ||
          !worked.isFinite ||
          worked < 0) {
        throw const FormatException('Invalid native stream budget.');
      }
      final debt = duty == 0
          ? 50000.0
          : worked * (1 - duty) / duty - waited.elapsedMicroseconds;
      if (debt <= 0) break;
      await Future<void>.delayed(
        Duration(microseconds: math.min(50000, debt.ceil())),
      );
    }
  }

  static void initialize(
    RootIsolateToken? token, {
    String? owner,
    bool enableNative = true,
  }) {
    if (!Platform.isAndroid || token == null) return;
    if (RootIsolateToken.instance == null) {
      BackgroundIsolateBinaryMessenger.ensureInitialized(token);
    }
    ready = enableNative;
    _owner = enableNative ? owner : null;
  }

  /// Root coordinator joins native handles even if its Dart worker exited.
  /// A transport failure cannot be acknowledged as a completed cancellation.
  static Future<void> releaseOwner(String? owner) async {
    if (owner == null) return;
    while (true) {
      try {
        await _channel.invokeMethod<void>('releaseOwner', {'owner': owner});
        return;
      } on PlatformException {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      } on MissingPluginException {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
  }

  static Future<bool> probe() async {
    if (!Platform.isAndroid) return false;
    try {
      final value = await _channel.invokeMapMethod<String, Object?>(
        'capabilities',
      );
      return value?['native'] == true && value?['version'] == 1;
    } catch (_) {
      return false;
    } // Keep the established Dart path available.
  }

  static Future<void> configure(AttachmentPerformance settings) async {
    if (!ready) return;
    await _channel.invokeMethod<void>('configure', {
      'target': settings.targetPercent,
      'parallel': settings.maxParallel,
      'memory': settings.memoryMiB,
    });
  }

  static Future<Uint8List> buffer(
    Uint8List bytes,
    Uint8List key,
    Uint8List iv, {
    required bool encrypt,
    bool padding = true,
  }) async {
    final value = await _channel.invokeMethod<Uint8List>('buffer', {
      'data': bytes,
      'key': key,
      'iv': iv,
      'encrypt': encrypt,
      'padding': padding,
    });
    if (value == null) {
      throw const FormatException('Invalid native cipher response.');
    }
    return value;
  }

  static Future<CipherFileResult> transform({
    required StreamingFileSource source,
    required String destination,
    required bool decryptSource,
    required bool encryptDestination,
    String? sourcePassword,
    String? destinationPassword,
    bool Function()? cancelled,
    double Function()? duty,
    FileByteProgress? progress,
    int maxPlaintextBytes = StreamingFileCipher.maxAttachmentBytes,
    bool verifyOutput = true,
    int? expectedPlaintextBytes,
    bool requireWholeSource = false,
    OwnedWriteTarget? ownedTarget,
  }) async {
    final before = await File(source.path).stat();
    if (source.modifiedMicros != null &&
        source.modifiedMicros != before.modified.microsecondsSinceEpoch) {
      throw const FormatException('Captured source revision changed.');
    }
    final id = await _channel.invokeMethod<String>('start', {
      'source': source.path,
      'destination': destination,
      'offset': source.offset,
      'length': source.length,
      'sourceHash': source.sha256Hex,
      'decrypt': decryptSource,
      'encrypt': encryptDestination,
      'sourcePassword': sourcePassword,
      'destinationPassword': destinationPassword,
      'verify': verifyOutput,
      'writeLease': ownedTarget?.lease,
      'outputSink': ownedTarget?.sink?.lease,
      'maxPlain': maxPlaintextBytes,
      'expected': expectedPlaintextBytes,
      'whole': requireWholeSource,
      'duty': duty?.call() ?? 1.0,
      'owner': _owner,
    });
    if (id == null) {
      throw StateError('Native cipher did not acquire ownership.');
    }
    while (true) {
      final state = await _channel.invokeMapMethod<String, Object?>('poll', {
        'id': id,
        'cancel': cancelled?.call() == true,
        'duty': duty?.call() ?? 1.0,
      });
      if (state == null) throw StateError('Native cipher response missing.');
      if (state['done'] == true) {
        if (state['error'] == 'cancelled') throw const FileJobCancelled();
        if (state['error'] == 'input') {
          throw const FormatException(
            'Native cipher input or ciphertext is invalid.',
          );
        }
        if (state['error'] != null) {
          throw const FileSystemException('Native cipher preparation failed.');
        }
        final after = await File(source.path).stat();
        if (cancelled?.call() == true ||
            before.size != after.size ||
            before.modified != after.modified ||
            before.changed != after.changed ||
            before.type != after.type) {
          // Native success grants ownership of this exclusively-created output.
          await File(destination).delete();
          if (cancelled?.call() == true) throw const FileJobCancelled();
          throw const FormatException('Source changed during transformation.');
        }
        return CipherFileResult(
          state['length'] as int,
          state['hash'] as String,
          ownedTarget == null
              ? null
              : await OwnedWriteReceipt.closed(
                  target: ownedTarget,
                  length: state['length'] as int,
                  sha256Hex: state['outputHash'] as String,
                  verifyReadback: verifyOutput,
                  payloadReadBytes: source.length,
                  readbackBytes: verifyOutput ? state['length'] as int : 0,
                ),
        );
      }
      try {
        progress?.call(
          state['phase'] as String,
          state['bytes'] as int,
          state['total'] as int,
        );
      } catch (_) {
        /* Observer only. */
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  static Future<NativeCipherSession> session(
    Uint8List key,
    Uint8List iv, {
    bool Function()? cancelled,
  }) async {
    final id = await _channel.invokeMethod<String>('sessionOpen', {
      'key': key,
      'iv': iv,
      'owner': _owner,
    });
    if (id == null) throw StateError('Native cipher session unavailable.');
    return NativeCipherSession._(id, cancelled);
  }
}

class NativeCipherSession {
  NativeCipherSession._(this._id, this._cancelled);
  final String _id;
  final bool Function()? _cancelled;
  Future<Uint8List> process(Uint8List bytes) async {
    if (_cancelled?.call() == true) throw const FileJobCancelled();
    final result = await AndroidNativeCipher._channel
        .invokeMapMethod<String, Object?>('sessionProcessMeasured', {
          'id': _id,
          'data': bytes,
        });
    final data = result?['data'];
    if (data is! Uint8List || data.length != bytes.length) {
      throw const FormatException('Invalid native cipher stream.');
    }
    await AndroidNativeCipher._pace(result!, _id, _cancelled);
    return data;
  }

  Future<void> close() => AndroidNativeCipher._channel.invokeMethod<void>(
    'sessionClose',
    {'id': _id},
  );
}

/// Incremental SHA-256/ZIP CRC over bytes already being written. No file reads.
class NativeChecksumSession {
  NativeChecksumSession._(this._id, this._cancelled);
  final String _id;
  final bool Function()? _cancelled;
  bool _closed = false;
  int crc = 0;
  Future<void> add(Uint8List bytes, {bool trackCrc = false}) async {
    if (_closed) throw StateError('Checksum session closed.');
    final value = await AndroidNativeCipher._channel
        .invokeMapMethod<String, Object?>('digestProcess', {
          'id': _id,
          'data': bytes,
          'crc': trackCrc,
        });
    if (value == null || value['crc'] is! num)
      throw const FormatException('Invalid native checksum response.');
    crc = (value['crc'] as num).toInt();
    await AndroidNativeCipher._pace(value, _id, _cancelled);
  }

  Future<void> resetCrc() async {
    if (_closed) throw StateError('Checksum session closed.');
    await AndroidNativeCipher._channel.invokeMethod<void>('digestResetCrc', {
      'id': _id,
    });
    crc = 0;
  }

  Future<String> finish() async {
    if (_closed) throw StateError('Checksum session closed.');
    _closed = true;
    final hash = await AndroidNativeCipher._channel.invokeMethod<String>(
      'digestFinish',
      {'id': _id},
    );
    if (hash == null || !RegExp(r'^[a-f0-9]{64}$').hasMatch(hash))
      throw const FormatException('Invalid native checksum.');
    return hash;
  }

  Future<void> abort() async {
    if (_closed) return;
    _closed = true;
    await AndroidNativeCipher._channel.invokeMethod<void>('sessionClose', {
      'id': _id,
    });
  }
}
