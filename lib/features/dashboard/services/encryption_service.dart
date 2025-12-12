import 'package:encrypt/encrypt.dart';
import 'dart:convert'; // For utf8
import 'dart:typed_data'; // For Uint8List

abstract class IEncryptionService {
  String encrypt(String plainText, {String? password});
  String decrypt(String encryptedText, {String? password});
  String encryptApp(String plainText);
  String decryptApp(String encryptedText);
}

class EncryptionService implements IEncryptionService {
  late final Key _defaultKey;
  late final IV _defaultIV;

  // Hardcoded App Secret Key (32 chars) for demonstration.
  // In production, obfuscate or use secure storage if possible, though static analysis can find it.
  static const String _appSecretKey = 'MySuperSecretAppKeyForJsonStore!';

  EncryptionService() {
    // Default key/IV for when no password is provided
    _defaultKey = Key.fromLength(32);
    _defaultIV = IV.fromLength(16);
  }

  Key _deriveKey(String password) {
    // Simple key derivation: Pad or truncate password to 32 bytes.
    // In production, use PBKDF2 or Scrypt from 'pointycastle'.
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
    // Always generate a new IV for security, or use default if consistent IV needed (not recommended)
    // For this demo, we'll use a fixed IV for simplicity if password provided,
    // strictly to allow repeatable decryption in this session.
    // Ideally: generate random IV, prepend to ciphertext.
    final iv = password != null ? IV.fromLength(16) : _defaultIV;

    final encrypter = Encrypter(AES(key));
    final encrypted = encrypter.encrypt(plainText, iv: iv);
    return encrypted.base64;
  }

  @override
  String decrypt(String encryptedText, {String? password}) {
    try {
      final key = password != null ? _deriveKey(password) : _defaultKey;
      final iv = password != null ? IV.fromLength(16) : _defaultIV;

      final encrypter = Encrypter(AES(key));
      final encrypted = Encrypted.fromBase64(encryptedText);
      return encrypter.decrypt(encrypted, iv: iv);
    } catch (e) {
      return "Error decrypting: $e";
    }
  }

  @override
  String encryptApp(String plainText) {
    final key = Key.fromUtf8(_appSecretKey);
    final iv = IV.fromLength(16); // Fixed IV for app-level encryption (simple)
    final encrypter = Encrypter(AES(key));
    final encrypted = encrypter.encrypt(plainText, iv: iv);
    return encrypted.base64;
  }

  @override
  String decryptApp(String encryptedText) {
    try {
      final key = Key.fromUtf8(_appSecretKey);
      final iv = IV.fromLength(16);
      final encrypter = Encrypter(AES(key));
      final encrypted = Encrypted.fromBase64(encryptedText);
      return encrypter.decrypt(encrypted, iv: iv);
    } catch (e) {
      // Return null or empty or throw?
      // Returning empty string to signify failure/invalid format for now.
      return "";
    }
  }
}
