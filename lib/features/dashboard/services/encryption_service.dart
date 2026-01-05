import 'package:encrypt/encrypt.dart';
import 'dart:convert'; // For utf8
import 'dart:typed_data'; // For Uint8List

abstract class IEncryptionService {
  String encrypt(String plainText, {String? password});
  String decrypt(String encryptedText, {String? password});
  Uint8List encryptBinary(Uint8List data, {String? password});
  Uint8List decryptBinary(Uint8List data, {String? password});
  String encryptApp(String plainText);
  String decryptApp(String encryptedText);
}

class EncryptionService implements IEncryptionService {
  late final Key _defaultKey;

  // Hardcoded App Secret Key (32 chars) for demonstration.
  static const String _appSecretKey = 'MySuperSecretAppKeyForJsonStore!';
  // Fixed IV for App Encryption (16 chars)
  static const String _appIV = '1234567890123456';

  EncryptionService() {
    // Default key/IV for when no password is provided
    _defaultKey = Key.fromLength(32);
  }

  Key _deriveKey(String password) {
    // Simple key derivation: Pad or truncate password to 32 bytes.
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
  String encrypt(String plainText, {String? password}) {
    final key = password != null ? _deriveKey(password) : _defaultKey;

    // Generate a Random IV for each encryption to ensure uniqueness
    final iv = IV.fromLength(16);

    final encrypter = Encrypter(AES(key));
    final encrypted = encrypter.encrypt(plainText, iv: iv);

    // Return combined IV and Ciphertext
    return "${iv.base64}:${encrypted.base64}";
  }

  @override
  String decrypt(String encryptedText, {String? password}) {
    try {
      final key = password != null ? _deriveKey(password) : _defaultKey;

      // Check for new format with IV prepended
      if (encryptedText.contains(':')) {
        final parts = encryptedText.split(':');
        if (parts.length == 2) {
          final iv = IV.fromBase64(parts[0]);
          final encrypted = Encrypted.fromBase64(parts[1]);
          final encrypter = Encrypter(AES(key));
          return encrypter.decrypt(encrypted, iv: iv);
        }
      }

      // Fallback: Legacy Deterministic IV
      final iv = IV(key.bytes.sublist(0, 16));

      final encrypter = Encrypter(AES(key));
      final encrypted = Encrypted.fromBase64(encryptedText);
      return encrypter.decrypt(encrypted, iv: iv);
    } catch (e) {
      return "Error decrypting: $e";
    }
  }

  @override
  Uint8List encryptBinary(Uint8List data, {String? password}) {
    final key = password != null ? _deriveKey(password) : _defaultKey;
    final iv = IV.fromLength(16);
    final encrypter = Encrypter(AES(key));

    final encrypted = encrypter.encryptBytes(data, iv: iv);

    // Combine IV + Encrypted Data
    final combined = BytesBuilder();
    combined.add(iv.bytes);
    combined.add(encrypted.bytes);
    return combined.toBytes();
  }

  @override
  Uint8List decryptBinary(Uint8List data, {String? password}) {
    try {
      final key = password != null ? _deriveKey(password) : _defaultKey;

      if (data.length < 16) throw Exception("Invalid data length");

      final ivBytes = data.sublist(0, 16);
      final cipherBytes = data.sublist(16);

      final iv = IV(ivBytes);
      final encrypted = Encrypted(cipherBytes);

      final encrypter = Encrypter(AES(key));
      return Uint8List.fromList(encrypter.decryptBytes(encrypted, iv: iv));
    } catch (e) {
      print("Error decrypting binary: $e");
      return Uint8List(0);
    }
  }

  @override
  String encryptApp(String plainText) {
    final key = Key.fromUtf8(_appSecretKey);
    final iv = IV.fromUtf8(_appIV); // Use Fixed IV
    final encrypter = Encrypter(AES(key));
    final encrypted = encrypter.encrypt(plainText, iv: iv);
    return encrypted.base64;
  }

  @override
  String decryptApp(String encryptedText) {
    try {
      final key = Key.fromUtf8(_appSecretKey);
      final iv = IV.fromUtf8(_appIV); // Use Fixed IV
      final encrypter = Encrypter(AES(key));
      final encrypted = Encrypted.fromBase64(encryptedText);
      return encrypter.decrypt(encrypted, iv: iv);
    } catch (e) {
      return "";
    }
  }
}
