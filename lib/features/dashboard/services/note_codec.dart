import 'dart:convert';
import '../../../core/operations/decryption_result.dart';

import '../models/note_envelope.dart';
import '../models/note_model.dart';

/// Shared recognition and validation for discovery, editor and package readers.
/// Decoding performs no migration, storage writes or editor normalization.
class NoteCodec {
  static Future<DecodedNote> decode(
    String source, {
    required Future<DecryptionResult<String>> Function(String) decryptApp,
  }) async {
    final plain = _plainMap(source);
    if (plain != null) return _validate(plain, NoteEnvelopeKind.legacyJson);
    try {
      final result = await decryptApp(source);
      if (!result.isSuccess) {
        throw const FormatException('Invalid encrypted envelope.');
      }
      return decodeMetadata(result.value!, kind: NoteEnvelopeKind.appEncrypted);
    } catch (_) {
      throw const FormatException('Unsupported or damaged note envelope.');
    }
  }

  /// Worker entry point: synchronous legacy crypto avoids nested compute calls.
  static DecodedNote decodeSync(
    String source, {
    required DecryptionResult<String> Function(String) decryptApp,
  }) {
    final plain = _plainMap(source);
    if (plain != null) return _validate(plain, NoteEnvelopeKind.legacyJson);
    try {
      final result = decryptApp(source);
      if (!result.isSuccess) {
        throw const FormatException('Invalid encrypted envelope.');
      }
      return decodeMetadata(result.value!, kind: NoteEnvelopeKind.appEncrypted);
    } catch (_) {
      throw const FormatException('Unsupported or damaged note envelope.');
    }
  }

  static DecodedNote decodeMetadata(
    String json, {
    NoteEnvelopeKind kind = NoteEnvelopeKind.legacyJson,
  }) {
    final map = _plainMap(json);
    if (map == null) {
      throw const FormatException('Invalid note metadata.');
    }
    return _validate(map, kind);
  }

  static Map<String, dynamic>? _plainMap(String source) {
    try {
      final decoded = jsonDecode(source);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  static DecodedNote _validate(
    Map<String, dynamic> map,
    NoteEnvelopeKind kind,
  ) {
    if (map['id'] is! String ||
        (map['id'] as String).isEmpty ||
        map['title'] is! String ||
        map['content'] is! String ||
        map['isLocked'] is! bool ||
        map['timestamp'] is! int) {
      throw const FormatException('Unsupported note schema.');
    }
    validateAttachmentDeclarations(map);
    try {
      final parsed = NoteModel.fromJson(map);
      final note = NoteModel(
        id: parsed.id,
        title: parsed.title,
        content: parsed.content,
        isLocked: parsed.isLocked,
        timestamp: parsed.timestamp,
        attachments: List.unmodifiable(parsed.attachments),
      );
      return DecodedNote(note, map, kind);
    } catch (_) {
      throw const FormatException('Invalid note metadata.');
    }
  }

  /// Metadata-only validation at note admission/unlock, never a payload scan.
  static void validateAttachmentDeclarations(Map<String, dynamic> map) {
    final attachments = map['attachments'];
    if (attachments != null) {
      if (attachments is! List) {
        throw const FormatException('Invalid attachment declarations.');
      }
      final legacy = attachments.isNotEmpty && attachments.first is String;
      final ids = <String>{};
      for (final attachment in attachments) {
        final String id;
        if (legacy) {
          if (attachment is! String || attachment.isEmpty) {
            throw const FormatException(
              'Invalid legacy attachment declaration.',
            );
          }
          id = attachment;
        } else {
          if (attachment is! Map<String, dynamic> ||
              attachment['id'] is! String ||
              (attachment['id'] as String).isEmpty ||
              (attachment['fileName'] != null &&
                  attachment['fileName'] is! String) ||
              (attachment['size'] != null &&
                  (attachment['size'] is! int ||
                      (attachment['size'] as int) < 0)) ||
              (attachment['mentionId'] != null &&
                  (attachment['mentionId'] is! String ||
                      (attachment['mentionId'] as String).isEmpty)) ||
              (attachment['mimeType'] != null &&
                  attachment['mimeType'] is! String)) {
            throw const FormatException('Invalid attachment metadata.');
          }
          id = attachment['id'] as String;
        }
        if (!ids.add(id)) {
          throw const FormatException('Duplicate attachment identity.');
        }
      }
    }
  }
}
