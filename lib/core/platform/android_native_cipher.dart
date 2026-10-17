import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import '../storage/streaming_file_cipher.dart';
import '../storage/attachment_performance.dart';

/// One implementation adapter; note/package formats and publication stay Dart
/// owned. Payload files never cross the channel during bulk transforms.
class AndroidNativeCipher {
  static const _channel = MethodChannel('future_notes/cipher');
  static bool ready = false;
  static String? _owner;

  static void initialize(RootIsolateToken? token, {String? owner}) {
    if (!Platform.isAndroid || token == null) return;
    if (RootIsolateToken.instance == null) {
      BackgroundIsolateBinaryMessenger.ensureInitialized(token);
    }
    ready = true;
    _owner = owner;
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
    Uint8List iv,
  ) async {
    final id = await _channel.invokeMethod<String>('sessionOpen', {
      'key': key,
      'iv': iv,
      'owner': _owner,
    });
    if (id == null) throw StateError('Native cipher session unavailable.');
    return NativeCipherSession._(id);
  }
}

class NativeCipherSession {
  NativeCipherSession._(this._id);
  final String _id;
  Future<Uint8List> process(Uint8List bytes) async {
    final result = await AndroidNativeCipher._channel.invokeMethod<Uint8List>(
      'sessionProcess',
      {'id': _id, 'data': bytes},
    );
    if (result == null || result.length != bytes.length) {
      throw const FormatException('Invalid native cipher stream.');
    }
    return result;
  }

  Future<void> close() => AndroidNativeCipher._channel.invokeMethod<void>(
    'sessionClose',
    {'id': _id},
  );
}
