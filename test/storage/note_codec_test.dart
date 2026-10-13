import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_application_1/core/operations/decryption_result.dart';
import 'package:flutter_application_1/features/dashboard/models/note_envelope.dart';
import 'package:flutter_application_1/features/dashboard/models/note_model.dart';
import 'package:flutter_application_1/features/dashboard/services/background_service.dart';
import 'package:flutter_application_1/features/dashboard/services/encryption_service.dart';
import 'package:flutter_application_1/features/dashboard/services/note_codec.dart';
import 'package:flutter_application_1/features/dashboard/services/pack_service.dart';

import '../support/synthetic_note_fixtures.dart';
import '../support/validation_directory.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final encryption = EncryptionService();
  final packages = PackService(encryption);
  late SyntheticNoteFixtures fixtures;
  setUpAll(() async {
    fixtures = await SyntheticNoteFixtures.create(encryption);
  });

  Future<DecodedNote> decode(String source) =>
      NoteCodec.decode(source, decryptApp: encryption.decryptAppResult);

  test(
    'current and plaintext envelopes preserve IDs, timestamps and unknown fields',
    () async {
      final legacy = await decode(fixtures.legacyJson);
      final current = await decode(fixtures.currentEnvelope);
      expect(legacy.kind, NoteEnvelopeKind.legacyJson);
      expect(current.kind, NoteEnvelopeKind.appEncrypted);
      for (final decoded in [legacy, current]) {
        expect(decoded.metadata, fixtures.rawNote);
        expect(decoded.note.id, SyntheticNoteFixtures.noteId);
        expect(decoded.note.timestamp, SyntheticNoteFixtures.storedTimestamp);
      }
    },
  );

  test(
    'worker and async readers recognize the same five legacy/current variants',
    () async {
      for (final source in [
        fixtures.legacyJson,
        fixtures.currentEnvelope,
        fixtures.protectedEnvelope,
        fixtures.htmlLegacyJson,
        fixtures.legacyAttachmentJson,
      ]) {
        final asynchronous = await decode(source);
        final synchronous = NoteCodec.decodeSync(
          source,
          decryptApp: EncryptionService.decryptAppResultSync,
        );
        expect(synchronous.metadata, asynchronous.metadata);
        expect(synchronous.kind, asynchronous.kind);
        expect(synchronous.note.content, asynchronous.note.content);
      }
    },
  );

  test(
    'plaintext recognition succeeds without invoking a failing decryptor',
    () async {
      var calls = 0;
      final decoded = await NoteCodec.decode(
        fixtures.legacyJson,
        decryptApp: (_) async {
          calls++;
          return const DecryptionResult.failure(
            DecryptionFailure.invalidCiphertext,
          );
        },
      );
      expect(decoded.metadata, fixtures.rawNote);
      expect(calls, 0);
    },
  );

  test(
    'structured schemas with wrong field types are rejected without fallback',
    () async {
      var calls = 0;
      for (final changed in [
        {...fixtures.rawNote, 'id': ''},
        {...fixtures.rawNote, 'title': 7},
        {...fixtures.rawNote, 'content': null},
        {...fixtures.rawNote, 'isLocked': 'false'},
        {...fixtures.rawNote, 'timestamp': 1.5},
      ]) {
        await expectLater(
          NoteCodec.decode(
            jsonEncode(changed),
            decryptApp: (_) async {
              calls++;
              return DecryptionResult.success(fixtures.legacyJson);
            },
          ),
          throwsFormatException,
        );
      }
      expect(calls, 0);
    },
  );

  test(
    'failed crypto and malformed envelopes produce sanitized failures',
    () async {
      for (final source in ['', 'not-an-envelope', '{', '[]']) {
        await expectLater(
          NoteCodec.decode(
            source,
            decryptApp: (_) async => const DecryptionResult.failure(
              DecryptionFailure.invalidCiphertext,
            ),
          ),
          throwsFormatException,
        );
      }
      await expectLater(
        NoteCodec.decode(
          'synthetic-ciphertext',
          decryptApp: (_) async {
            throw StateError('Private failure detail must not escape.');
          },
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            'Unsupported or damaged note envelope.',
          ),
        ),
      );
    },
  );

  test('mixed, duplicate and malformed attachments are rejected', () {
    for (final declarations in <Object>[
      {},
      [
        'a',
        {'id': 'b'},
      ],
      ['a', 'a'],
      [
        {'id': 'a'},
        {'id': 'a'},
      ],
      [
        {'id': 'a', 'size': -1},
      ],
      [
        {'id': 'a', 'fileName': 9},
      ],
      [
        {'id': 'a', 'mimeType': false},
      ],
    ]) {
      expect(
        () => NoteCodec.decodeMetadata(
          jsonEncode({...fixtures.rawNote, 'attachments': declarations}),
        ),
        throwsFormatException,
      );
    }
  });

  test('decoded metadata and attachment inventory cannot be mutated', () async {
    final decoded = await decode(fixtures.legacyJson);
    expect(() => decoded.metadata['title'] = 'Changed', throwsUnsupportedError);
    final nested = decoded.metadata['futureNoteField'] as Map;
    expect(() => nested['retain'] = false, throwsUnsupportedError);
    final attachments = decoded.metadata['attachments'] as List;
    expect(() => attachments.clear(), throwsUnsupportedError);
    expect(() => decoded.note.attachments.clear(), throwsUnsupportedError);
  });

  test(
    'plaintext, HTML and delta body strings retain exact boundary whitespace',
    () async {
      for (final body in [
        SyntheticNoteFixtures.boundaryText,
        ' \n<p>  Synthetic HTML  </p>\n ',
        '  [{"insert":"synthetic\\n"}] \n',
        '',
      ]) {
        final decoded = await decode(
          jsonEncode({...fixtures.rawNote, 'content': body}),
        );
        expect(decoded.note.content, body);
        expect(decoded.metadata['content'], body);
      }
    },
  );

  test(
    'binary-v1 packages retain unknown metadata and legacy attachment representation',
    () async {
      final decoded = await decode(fixtures.legacyAttachmentJson);
      final bytes = await packages.createPack(
        decoded.note,
        fixtures.encryptedAttachments,
        noteMetadata: decoded.metadata,
      );
      final extracted = await packages.extractPack(bytes);
      expect(extracted, isNotNull);
      expect(extracted!.metadata, decoded.metadata);
      expect(
        extracted.attachments.keys.toSet(),
        fixtures.encryptedAttachments.keys.toSet(),
      );
      // The old model reader still recognizes the unchanged JSON record shape.
      expect(NoteModel.fromJson(extracted.metadata).id, decoded.note.id);
    },
  );

  test('ZIP packages retain unknown note and attachment metadata', () async {
    final decoded = await decode(fixtures.currentEnvelope);
    final bytes = await packages.createZipPack(
      decoded.note,
      fixtures.encryptedAttachments,
      noteMetadata: decoded.metadata,
    );
    final extracted = await packages.extractZipPack(bytes);
    expect(extracted, isNotNull);
    expect(extracted!.metadata, decoded.metadata);
    expect(
      NoteModel.fromJson(extracted.metadata).content,
      decoded.note.content,
    );
  });

  test(
    'mismatched package metadata is rejected before archive creation',
    () async {
      final decoded = await decode(fixtures.legacyJson);
      final mismatch = {...decoded.metadata, 'id': 'different-synthetic-id'};
      await expectLater(
        packages.createPack(
          decoded.note,
          fixtures.encryptedAttachments,
          noteMetadata: mismatch,
        ),
        throwsFormatException,
      );
      await expectLater(
        packages.createZipPack(
          decoded.note,
          fixtures.encryptedAttachments,
          noteMetadata: mismatch,
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'discovery recognizes legacy and locked/current notes without rewriting them',
    () async {
      final run = await Directory.systemTemp.createTemp(
        'future-notes-validation-',
      );
      addTearDown(() => deleteValidationRun(run));
      var index = 0;
      for (final source in [
        fixtures.legacyJson,
        fixtures.currentEnvelope,
        fixtures.protectedEnvelope,
      ]) {
        final file = File(p.join(run.path, 'synthetic-${index++}.enc'));
        await file.writeAsString(source, flush: true);
        final before = await file.stat();
        final entry = await readRecentNote(file);
        expect(entry, isNotNull);
        expect(entry!.title, fixtures.note.title);
        expect(
          entry.created,
          DateTime.fromMillisecondsSinceEpoch(
            SyntheticNoteFixtures.storedTimestamp,
          ),
        );
        expect(entry.modified, before.modified);
        expect(entry.isLocked, source == fixtures.protectedEnvelope);
        expect(await file.readAsString(), source);
        expect((await file.stat()).modified, before.modified);
      }
      final undated = File(
        p.join(run.path, 'synthetic-undisplayable-date.enc'),
      );
      final source = jsonEncode({
        ...fixtures.rawNote,
        'timestamp': 8640000000000001,
      });
      await undated.writeAsString(source, flush: true);
      final entry = await readRecentNote(undated);
      expect(entry, isNotNull);
      expect(entry!.created, isNull);
      expect((await decode(source)).note.timestamp, 8640000000000001);
      expect(await undated.readAsString(), source);
    },
  );

  test('discovery rejects damaged structured and encrypted notes', () async {
    final run = await Directory.systemTemp.createTemp(
      'future-notes-validation-',
    );
    addTearDown(() => deleteValidationRun(run));
    final file = File(p.join(run.path, 'synthetic-damaged.enc'));
    for (final source in [
      'not-a-ciphertext',
      '{"content":',
      jsonEncode({
        ...fixtures.rawNote,
        'attachments': ['a', 'a'],
      }),
    ]) {
      await file.writeAsString(source, flush: true);
      expect(await readRecentNote(file), isNull);
      expect(await file.readAsString(), source);
    }
  });
}
