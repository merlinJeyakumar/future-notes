import 'package:flutter/foundation.dart' hide Key;
import 'package:encrypt/encrypt.dart';
import 'dart:convert'; // For utf8
import 'dart:typed_data'; // For Uint8List
import 'package:flutter/services.dart' show ServicesBinding, RootIsolateToken;
import '../../../core/platform/android_native_cipher.dart';
import '../../../core/operations/decryption_result.dart';

abstract class IEncryptionService {
  Future<String> encrypt(String plainText, {String? password});
  // Legacy adapters remain for buffered package/protection paths awaiting their
  // own staged repair. New readers must use typed result methods below.
  Future<String> decrypt(String encryptedText, {String? password});
  Future<Uint8List> encryptBinary(Uint8List data, {String? password});
  Future<Uint8List> decryptBinary(Uint8List data, {String? password});
  Future<String> encryptApp(String plainText);
  Future<String> decryptApp(String encryptedText);
  Future<DecryptionResult<String>> decryptResult(
    String encryptedText, {
    String? password,
  });
  Future<DecryptionResult<Uint8List>> decryptBinaryResult(
    Uint8List data, {
    String? password,
  });
  Future<DecryptionResult<String>> decryptAppResult(String encryptedText);
}

class EncryptionService implements IEncryptionService {
  final bool useNative;
  late final Key _defaultKey;
  static const String _appSecretKey = 'MySuperSecretAppKeyForJsonStore!';
  static const String _appIV = '1234567890123456';

  EncryptionService({this.useNative = true}) {
    _defaultKey = Key.fromUtf8(_appSecretKey);
  }

  Future<T> _compute<T>(
    ComputeCallback<Map<String, dynamic>, T> task,
    Map<String, dynamic> args,
  ) => compute(task, {
    ...args,
    if (useNative && AndroidNativeCipher.ready)
      'nativeToken': ServicesBinding.rootIsolateToken,
  });

  Key _deriveKey(String password) {
    final bytes = utf8.encode(password);
    if (bytes.length >= 32) {
      return Key(bytes.sublist(0, 32));
    } else {
      final padded = List<int>.from(bytes)
        ..addAll(List.filled(32 - bytes.length, 0));
      return Key(Uint8List.fromList(padded));
    }
  }

  @override
  Future<String> encrypt(String plainText, {String? password}) async {
    final key = password != null ? _deriveKey(password) : _defaultKey;
    return _compute(_encryptStringTask, {
      'text': plainText,
      'keyBytes': key.bytes,
    });
  }

  @override
  Future<String> decrypt(String encryptedText, {String? password}) async {
    final result = await decryptResult(encryptedText, password: password);
    return result.isSuccess ? result.value! : 'Error decrypting';
  }

  @override
  Future<DecryptionResult<String>> decryptResult(
    String encryptedText, {
    String? password,
  }) async {
    final key = password != null ? _deriveKey(password) : _defaultKey;
    final defaultKey = _defaultKey;

    final res1 = await _compute(_decryptStringTask, {
      'text': encryptedText,
      'keyBytes': key.bytes,
    });
    if (res1.isSuccess) return res1;

    if (password != null) {
      final res2 = await _compute(_decryptStringTask, {
        'text': encryptedText,
        'keyBytes': defaultKey.bytes,
      });
      if (res2.isSuccess) {
        return DecryptionResult.success(res2.value!, usedLegacyFallback: true);
      }
    }
    return res1;
  }

  @override
  Future<Uint8List> encryptBinary(Uint8List data, {String? password}) async {
    final key = password != null ? _deriveKey(password) : _defaultKey;
    return _compute(_encryptBinaryTask, {'data': data, 'keyBytes': key.bytes});
  }

  @override
  Future<Uint8List> decryptBinary(Uint8List data, {String? password}) async {
    final result = await decryptBinaryResult(data, password: password);
    return result.isSuccess ? result.value! : Uint8List(0);
  }

  @override
  Future<DecryptionResult<Uint8List>> decryptBinaryResult(
    Uint8List data, {
    String? password,
  }) async {
    final key = password != null ? _deriveKey(password) : _defaultKey;
    final defaultKey = _defaultKey;

    final res1 = await _compute(_decryptBinaryTask, {
      'data': data,
      'keyBytes': key.bytes,
    });
    if (res1.isSuccess) return res1;

    if (password != null) {
      final res2 = await _compute(_decryptBinaryTask, {
        'data': data,
        'keyBytes': defaultKey.bytes,
      });
      if (res2.isSuccess) {
        return DecryptionResult.success(res2.value!, usedLegacyFallback: true);
      }
    }
    return res1;
  }

  @override
  Future<String> encryptApp(String plainText) async {
    final key = Key.fromUtf8(_appSecretKey);
    return _compute(_encryptAppTask, {
      'text': plainText,
      'keyBytes': key.bytes,
      'iv': _appIV,
    });
  }

  @override
  Future<String> decryptApp(String encryptedText) async {
    final result = await decryptAppResult(encryptedText);
    return result.isSuccess ? result.value! : '';
  }

  @override
  Future<DecryptionResult<String>> decryptAppResult(
    String encryptedText,
  ) async {
    final key = Key.fromUtf8(_appSecretKey);
    return _compute(_decryptAppTask, {
      'text': encryptedText,
      'keyBytes': key.bytes,
      'iv': _appIV,
    });
  }

  /// Synchronous version of decryptApp for use inside isolates
  /// (compute cannot be called from within an isolate)
  static String decryptAppSync(String encryptedText) {
    final result = decryptAppResultSync(encryptedText);
    return result.isSuccess ? result.value! : '';
  }

  static DecryptionResult<String> decryptAppResultSync(String encryptedText) {
    try {
      final key = Key.fromUtf8(_appSecretKey);
      final iv = IV.fromUtf8(_appIV);
      final encrypter = Encrypter(AES(key));
      final encrypted = Encrypted.fromBase64(encryptedText);
      _validateLegacyCipher(iv.bytes, encrypted.bytes);
      return DecryptionResult.success(encrypter.decrypt(encrypted, iv: iv));
    } catch (e) {
      return const DecryptionResult.failure(
        DecryptionFailure.invalidCiphertext,
      );
    }
  }
}

// --- Top Level Tasks ---

Future<String> _encryptStringTask(Map<String, dynamic> args) async {
  final text = args['text'] as String;
  final key = Key(args['keyBytes'] as Uint8List);
  final iv = IV.fromLength(16);
  final encrypted = await _crypt(
    args,
    key,
    iv,
    Uint8List.fromList(utf8.encode(text)),
    true,
  );
  return "${iv.base64}:${base64Encode(encrypted)}";
}

Future<DecryptionResult<String>> _decryptStringTask(
  Map<String, dynamic> args,
) async {
  try {
    final encryptedText = args['text'] as String;
    final key = Key(args['keyBytes'] as Uint8List);

    if (encryptedText.contains(':')) {
      final parts = encryptedText.split(':');
      if (parts.length == 2) {
        final iv = IV.fromBase64(parts[0]);
        final encrypted = Encrypted.fromBase64(parts[1]);
        _validateLegacyCipher(iv.bytes, encrypted.bytes);
        return DecryptionResult.success(
          utf8.decode(await _crypt(args, key, iv, encrypted.bytes, false)),
        );
      }
    }
    final iv = IV(key.bytes.sublist(0, 16));
    final encrypted = Encrypted.fromBase64(encryptedText);
    _validateLegacyCipher(iv.bytes, encrypted.bytes);
    return DecryptionResult.success(
      utf8.decode(await _crypt(args, key, iv, encrypted.bytes, false)),
    );
  } catch (e) {
    return const DecryptionResult.failure(DecryptionFailure.invalidCiphertext);
  }
}

Future<Uint8List> _encryptBinaryTask(Map<String, dynamic> args) async {
  final data = args['data'] as Uint8List;
  final key = Key(args['keyBytes'] as Uint8List);
  final iv = IV.fromLength(16);
  final encrypted = await _crypt(args, key, iv, data, true);
  final combined = BytesBuilder();
  combined.add(iv.bytes);
  combined.add(encrypted);
  return combined.toBytes();
}

Future<DecryptionResult<Uint8List>> _decryptBinaryTask(
  Map<String, dynamic> args,
) async {
  try {
    final data = args['data'] as Uint8List;
    if (data.length < 32) {
      return const DecryptionResult.failure(
        DecryptionFailure.invalidCiphertext,
      );
    }
    final key = Key(args['keyBytes'] as Uint8List);

    final ivBytes = data.sublist(0, 16);
    final cipherBytes = data.sublist(16);
    _validateLegacyCipher(ivBytes, cipherBytes);
    final iv = IV(ivBytes);
    final encrypted = Encrypted(cipherBytes);
    return DecryptionResult.success(
      await _crypt(args, key, iv, encrypted.bytes, false),
    );
  } catch (e) {
    return const DecryptionResult.failure(DecryptionFailure.invalidCiphertext);
  }
}

Future<String> _encryptAppTask(Map<String, dynamic> args) async {
  final text = args['text'] as String;
  final key = Key(args['keyBytes'] as Uint8List);
  final ivStr = args['iv'] as String;
  final iv = IV.fromUtf8(ivStr);
  final encrypted = await _crypt(
    args,
    key,
    iv,
    Uint8List.fromList(utf8.encode(text)),
    true,
  );
  return base64Encode(encrypted);
}

Future<DecryptionResult<String>> _decryptAppTask(
  Map<String, dynamic> args,
) async {
  try {
    final text = args['text'] as String;
    final key = Key(args['keyBytes'] as Uint8List);
    final ivStr = args['iv'] as String;
    final iv = IV.fromUtf8(ivStr);
    final encrypted = Encrypted.fromBase64(text);
    _validateLegacyCipher(iv.bytes, encrypted.bytes);
    return DecryptionResult.success(
      utf8.decode(await _crypt(args, key, iv, encrypted.bytes, false)),
    );
  } catch (e) {
    return const DecryptionResult.failure(DecryptionFailure.invalidCiphertext);
  }
}

Future<Uint8List> _crypt(
  Map<String, dynamic> args,
  Key key,
  IV iv,
  Uint8List bytes,
  bool encrypt,
) async {
  final token = args['nativeToken'] as RootIsolateToken?;
  if (token != null && bytes.length <= 32 * 1024 * 1024) {
    AndroidNativeCipher.initialize(token);
    return AndroidNativeCipher.buffer(
      bytes,
      key.bytes,
      iv.bytes,
      encrypt: encrypt,
    );
  }
  if (encrypt) return _encryptCompatible(key, iv, bytes).bytes;
  return Uint8List.fromList(
    Encrypter(AES(key)).decryptBytes(Encrypted(bytes), iv: iv),
  );
}

Encrypted _encryptCompatible(Key key, IV iv, List<int> bytes) {
  if (bytes.isEmpty) {
    // The legacy writer cannot accept empty input. Encode its exact PKCS7
    // empty-message block explicitly, with the same SIC cipher and IV layout.
    return Encrypter(
      AES(key, padding: null),
    ).encryptBytes(List.filled(16, 16), iv: iv);
  }
  return Encrypter(AES(key)).encryptBytes(bytes, iv: iv);
}

void _validateLegacyCipher(Uint8List iv, Uint8List ciphertext) {
  // The existing AES-SIC/PKCS7 format always includes at least one full block.
  // Padding bytes are checked by the installed PKCS7 implementation.
  if (iv.length != 16 || ciphertext.isEmpty || ciphertext.length % 16 != 0) {
    throw const FormatException('Invalid legacy ciphertext framing.');
  }
}
