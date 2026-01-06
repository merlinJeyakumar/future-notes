import 'package:flutter/foundation.dart' hide Key;
import 'package:encrypt/encrypt.dart';
import 'dart:convert'; // For utf8
import 'dart:typed_data'; // For Uint8List

abstract class IEncryptionService {
  Future<String> encrypt(String plainText, {String? password});
  Future<String> decrypt(String encryptedText, {String? password});
  Future<Uint8List> encryptBinary(Uint8List data, {String? password});
  Future<Uint8List> decryptBinary(Uint8List data, {String? password});
  Future<String> encryptApp(String plainText);
  Future<String> decryptApp(String encryptedText);
}

class EncryptionService implements IEncryptionService {
  late final Key _defaultKey;
  static const String _appSecretKey = 'MySuperSecretAppKeyForJsonStore!';
  static const String _appIV = '1234567890123456';

  EncryptionService() {
    _defaultKey = Key.fromUtf8(_appSecretKey);
  }

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
    return compute(_encryptStringTask, {
      'text': plainText,
      'keyBytes': key.bytes,
    });
  }

  @override
  Future<String> decrypt(String encryptedText, {String? password}) async {
    final key = password != null ? _deriveKey(password) : _defaultKey;
    final defaultKey = _defaultKey;

    final res1 = await compute(_decryptStringTask, {
      'text': encryptedText,
      'keyBytes': key.bytes,
    });
    if (!res1.startsWith('Error decrypting')) return res1;

    if (password != null) {
      final res2 = await compute(_decryptStringTask, {
        'text': encryptedText,
        'keyBytes': defaultKey.bytes,
      });
      if (!res2.startsWith('Error decrypting')) return res2;
    }
    return res1;
  }

  @override
  Future<Uint8List> encryptBinary(Uint8List data, {String? password}) async {
    final key = password != null ? _deriveKey(password) : _defaultKey;
    return compute(_encryptBinaryTask, {'data': data, 'keyBytes': key.bytes});
  }

  @override
  Future<Uint8List> decryptBinary(Uint8List data, {String? password}) async {
    final key = password != null ? _deriveKey(password) : _defaultKey;
    final defaultKey = _defaultKey;

    final res1 = await compute(_decryptBinaryTask, {
      'data': data,
      'keyBytes': key.bytes,
    });
    if (res1.isNotEmpty) return res1;

    if (password != null) {
      final res2 = await compute(_decryptBinaryTask, {
        'data': data,
        'keyBytes': defaultKey.bytes,
      });
      if (res2.isNotEmpty) return res2;
    }
    return Uint8List(0);
  }

  @override
  Future<String> encryptApp(String plainText) async {
    final key = Key.fromUtf8(_appSecretKey);
    return compute(_encryptAppTask, {
      'text': plainText,
      'keyBytes': key.bytes,
      'iv': _appIV,
    });
  }

  @override
  Future<String> decryptApp(String encryptedText) async {
    final key = Key.fromUtf8(_appSecretKey);
    return compute(_decryptAppTask, {
      'text': encryptedText,
      'keyBytes': key.bytes,
      'iv': _appIV,
    });
  }
}

// --- Top Level Tasks ---

Future<String> _encryptStringTask(Map<String, dynamic> args) async {
  final text = args['text'] as String;
  final key = Key(args['keyBytes'] as Uint8List);
  final iv = IV.fromLength(16);
  final encrypter = Encrypter(AES(key));
  final encrypted = encrypter.encrypt(text, iv: iv);
  return "${iv.base64}:${encrypted.base64}";
}

Future<String> _decryptStringTask(Map<String, dynamic> args) async {
  try {
    final encryptedText = args['text'] as String;
    final key = Key(args['keyBytes'] as Uint8List);
    final encrypter = Encrypter(AES(key));

    if (encryptedText.contains(':')) {
      final parts = encryptedText.split(':');
      if (parts.length == 2) {
        final iv = IV.fromBase64(parts[0]);
        final encrypted = Encrypted.fromBase64(parts[1]);
        return encrypter.decrypt(encrypted, iv: iv);
      }
    }
    final iv = IV(key.bytes.sublist(0, 16));
    final encrypted = Encrypted.fromBase64(encryptedText);
    return encrypter.decrypt(encrypted, iv: iv);
  } catch (e) {
    return "Error decrypting: $e";
  }
}

Future<Uint8List> _encryptBinaryTask(Map<String, dynamic> args) async {
  final data = args['data'] as Uint8List;
  final key = Key(args['keyBytes'] as Uint8List);
  final iv = IV.fromLength(16);
  final encrypter = Encrypter(AES(key));
  final encrypted = encrypter.encryptBytes(data, iv: iv);
  final combined = BytesBuilder();
  combined.add(iv.bytes);
  combined.add(encrypted.bytes);
  return combined.toBytes();
}

Future<Uint8List> _decryptBinaryTask(Map<String, dynamic> args) async {
  try {
    final data = args['data'] as Uint8List;
    if (data.length < 16) return Uint8List(0);
    final key = Key(args['keyBytes'] as Uint8List);

    final ivBytes = data.sublist(0, 16);
    final cipherBytes = data.sublist(16);
    final iv = IV(ivBytes);
    final encrypted = Encrypted(cipherBytes);
    final encrypter = Encrypter(AES(key));
    return Uint8List.fromList(encrypter.decryptBytes(encrypted, iv: iv));
  } catch (e) {
    return Uint8List(0);
  }
}

Future<String> _encryptAppTask(Map<String, dynamic> args) async {
  final text = args['text'] as String;
  final key = Key(args['keyBytes'] as Uint8List);
  final ivStr = args['iv'] as String;
  final iv = IV.fromUtf8(ivStr);
  final encrypter = Encrypter(AES(key));
  final encrypted = encrypter.encrypt(text, iv: iv);
  return encrypted.base64;
}

Future<String> _decryptAppTask(Map<String, dynamic> args) async {
  try {
    final text = args['text'] as String;
    final key = Key(args['keyBytes'] as Uint8List);
    final ivStr = args['iv'] as String;
    final iv = IV.fromUtf8(ivStr);
    final encrypter = Encrypter(AES(key));
    final encrypted = Encrypted.fromBase64(text);
    return encrypter.decrypt(encrypted, iv: iv);
  } catch (e) {
    return "";
  }
}
