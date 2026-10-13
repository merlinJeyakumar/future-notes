import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_application_1/features/dashboard/models/note_model.dart';
import 'package:flutter_application_1/features/dashboard/services/encryption_service.dart';

/// Generated exclusively from public synthetic data, never a user note/key.
/// Ciphertext is generated at test time to exercise the existing wire format.
class SyntheticNoteFixtures {
  SyntheticNoteFixtures._({
    required this.password,
    required this.rawNote,
    required this.legacyJson,
    required this.currentEnvelope,
    required this.protectedEnvelope,
    required this.htmlLegacyJson,
    required this.legacyAttachmentJson,
    required this.encryptedAttachments,
  });

  static const noteId = '00000000-0000-4000-8000-000000000001';
  static const attachmentId = '00000000-0000-4000-8000-000000000002';
  static const emptyAttachmentId = '00000000-0000-4000-8000-000000000003';
  static const storedTimestamp = 1700000000000;
  static const boundaryText =
      '  Synthetic indentation\n\nSynthetic Tamil: தமிழ்\n\n';

  final String password;
  final Map<String, dynamic> rawNote;
  final String legacyJson;
  final String currentEnvelope;
  final String protectedEnvelope;
  final String htmlLegacyJson;
  final String legacyAttachmentJson;
  final Map<String, Uint8List> encryptedAttachments;

  NoteModel get note => NoteModel.fromJson(rawNote);

  static Future<SyntheticNoteFixtures> create(
    IEncryptionService encryption,
  ) async {
    final random = Random.secure();
    final password = base64UrlEncode(
      List<int>.generate(24, (_) => random.nextInt(256)),
    );
    final raw = <String, dynamic>{
      'id': noteId,
      'title': 'Synthetic compatibility fixture',
      'content': jsonEncode([
        {'insert': boundaryText},
      ]),
      'isLocked': false,
      'timestamp': storedTimestamp,
      'attachments': [
        {
          'id': attachmentId,
          'fileName': 'synthetic.bin',
          'size': 5,
          'mimeType': 'application/octet-stream',
          'futureAttachmentField': {'retain': true},
        },
        {
          'id': emptyAttachmentId,
          'fileName': 'synthetic-empty.bin',
          'size': 0,
          'mimeType': 'application/octet-stream',
        },
      ],
      'futureNoteField': {'retain': true},
    };
    final legacyJson = jsonEncode(raw);
    final currentEnvelope = await encryption.encryptApp(legacyJson);
    final protected = Map<String, dynamic>.from(raw)
      ..['isLocked'] = true
      ..['content'] = await encryption.encrypt(
        raw['content'] as String,
        password: password,
      );

    final attachment = await encryption.encryptBinary(
      Uint8List.fromList([0, 1, 127, 128, 255]),
    );
    // The old buffered wrapper cannot reliably encrypt zero input. Retaining
    // the first padded block of this stream produces the existing format's
    // valid empty-file envelope: IV || encryption(PKCS7 full padding block).
    final paddedBlock = await encryption.encryptBinary(
      Uint8List.fromList(List<int>.filled(16, 16)),
    );
    final emptyAttachment = Uint8List.fromList(paddedBlock.sublist(0, 32));

    return SyntheticNoteFixtures._(
      password: password,
      rawNote: raw,
      legacyJson: legacyJson,
      currentEnvelope: currentEnvelope,
      protectedEnvelope: await encryption.encryptApp(jsonEncode(protected)),
      htmlLegacyJson: jsonEncode({
        ...raw,
        'content': '<p>  Synthetic HTML &amp; தமிழ்  </p>\n',
      }),
      legacyAttachmentJson: jsonEncode({
        ...raw,
        'attachments': [attachmentId, emptyAttachmentId],
      }),
      encryptedAttachments: {
        attachmentId: attachment,
        emptyAttachmentId: emptyAttachment,
      },
    );
  }
}
