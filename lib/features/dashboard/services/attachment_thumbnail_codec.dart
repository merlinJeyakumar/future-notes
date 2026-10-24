import 'dart:convert';
import 'dart:typed_data';
import 'encryption_service.dart';

/// Derived JPEG data only. Existing note/attachment encryption is unchanged.
/// A malformed optional thumbnail never prevents opening the note itself.
class AttachmentThumbnailCodec {
  static const maxBytes = 32 * 1024;
  static const maxText = 48 * 1024;
  static bool validJpeg(Uint8List bytes) {
    if (bytes.length < 12 ||
        bytes.length > maxBytes ||
        bytes[0] != 255 ||
        bytes[1] != 216)
      return false;
    var i = 2;
    while (i + 3 < bytes.length) {
      if (bytes[i++] != 255) return false;
      while (i < bytes.length && bytes[i] == 255) {
        i++;
      }
      if (i + 2 >= bytes.length) return false;
      final marker = bytes[i++];
      if (marker == 217 || marker == 218) return false;
      if (marker == 216 || marker == 1 || (marker >= 208 && marker <= 215))
        continue;
      final length = (bytes[i] << 8) | bytes[i + 1];
      if (length < 2 || i + length > bytes.length) return false;
      if (marker >= 192 && marker <= 207 && ![196, 200, 204].contains(marker)) {
        if (length < 8) return false;
        final height = (bytes[i + 3] << 8) | bytes[i + 4];
        final width = (bytes[i + 5] << 8) | bytes[i + 6];
        return width > 0 && width <= 160 && height > 0 && height <= 160;
      }
      i += length;
    }
    return false;
  }

  static Future<String?> seal(
    Uint8List? image,
    IEncryptionService cipher,
    String? password,
  ) async {
    if (image == null || !validJpeg(image)) return null;
    return 'v1:${base64Encode(await cipher.encryptBinary(image, password: password))}';
  }

  static Future<Uint8List?> open(
    String? text,
    IEncryptionService cipher,
    String? password,
  ) async {
    if (text == null || text.length > maxText || !text.startsWith('v1:'))
      return null;
    try {
      final encrypted = base64Decode(text.substring(3));
      if (encrypted.length > maxBytes + 64) return null;
      final result = await cipher.decryptBinaryResult(
        encrypted,
        password: password,
      );
      return result.isSuccess && validJpeg(result.value!) ? result.value : null;
    } catch (_) {
      return null;
    }
  }

  static Future<String?> rekey(
    String? text,
    IEncryptionService cipher,
    String? oldPassword,
    String? newPassword,
  ) async {
    if (text == null || oldPassword == newPassword) return text;
    final image = await open(text, cipher, oldPassword);
    // Retain malformed derived data for recovery; readers fall back to an icon.
    return image == null ? text : seal(image, cipher, newPassword);
  }
}
