import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../../core/storage/note_reference.dart';
import '../../../core/storage/streaming_file_cipher.dart';
import '../models/note_envelope.dart';
import 'encryption_service.dart';
import 'file_service.dart';
import 'note_codec.dart';
import 'pack_service.dart';

class ExistingImportNote {
  const ExistingImportNote(this.reference, this.decoded);
  final NoteReference reference;
  final DecodedNote decoded;
}

/// The full library inventory, independent of search, UI batches or passwords.
/// The note UID is opaque metadata; only resolved references grant file access.
class NoteImportService {
  const NoteImportService(this.files, this.cipher);
  final IFileService files;
  final IEncryptionService cipher;

  Future<ExistingImportNote?> find(String id, StorageBinding binding) async {
    ExistingImportNote? found;
    for (final name in await files.getRecentFiles()) {
      if (name == 'settings.json' || name.startsWith('.future-notes-')) {
        continue;
      }
      final reference = await files.resolveNote(name);
      // Legacy attachment-only folders have no note envelope of their own.
      if (reference == null) continue;
      if (!p.equals(reference.binding.root, binding.root) ||
          reference.binding.generation != binding.generation) {
        throw const FormatException('The selected library changed.');
      }
      if (reference.format == NoteStorageFormat.legacyFile) {
        final input = await File(reference.contentPath).open();
        try {
          final header = await input.read(6);
          final packs = PackService(cipher);
          if (packs.isZip(header) ||
              (header.length == 6 && packs.isPack(header) && header[4] == 1)) {
            continue; // Export packages do not publish a library note identity.
          }
        } finally {
          await input.close();
        }
      }
      if (await File(reference.contentPath).length() > 32 * 1024 * 1024) {
        if (name.startsWith('note_') ||
            p.extension(name).toLowerCase() == '.enc') {
          throw const FormatException(
            'Note metadata exceeds the import limit.',
          );
        }
        continue;
      }
      String? text;
      try {
        text = await files.readResolved(reference);
      } on FormatException {
        if (name.startsWith('note_') ||
            p.extension(name).toLowerCase() == '.enc') {
          throw const FormatException(
            'A note cannot be identified safely; import was stopped.',
          );
        }
        continue; // A binary export alongside notes is not another note.
      }
      if (text == null) {
        throw const FormatException(
          'A note is unavailable; import was stopped.',
        );
      }
      DecodedNote decoded;
      try {
        decoded = await NoteCodec.decode(
          text,
          decryptApp: cipher.decryptAppResult,
        );
      } on FormatException {
        if (name.startsWith('note_') ||
            p.extension(name).toLowerCase() == '.enc') {
          throw const FormatException(
            'A note cannot be identified safely; import was stopped.',
          );
        }
        continue; // Other library files are not note identities.
      }
      if (decoded.note.id != id) continue;
      if (found != null) {
        throw const FormatException(
          'Multiple notes have this ID. No note was replaced.',
        );
      }
      found = ExistingImportNote(reference.withModelId(id), decoded);
    }
    return found;
  }

  static Future<String> fingerprint(
    Map<String, dynamic> metadata,
    Map<String, StreamingFileSource> attachments, {
    String? cancellationFile,
  }) =>
      Isolate.run(() => _fingerprint(metadata, attachments, cancellationFile));

  static Future<String> _fingerprint(
    Map<String, dynamic> metadata,
    Map<String, StreamingFileSource> sources,
    String? cancellation,
  ) async {
    void check() {
      if (cancellation != null && File(cancellation).existsSync()) {
        throw const FileJobCancelled();
      }
    }

    final normalized = Map<String, dynamic>.from(metadata);
    final declared = metadata['attachments'] as List? ?? const [];
    final entries = <Map<String, dynamic>>[];
    for (var i = 0; i < declared.length; i++) {
      check();
      final entry = declared[i];
      final fields = entry is String
          ? <String, dynamic>{'id': entry}
          : Map<String, dynamic>.from(entry as Map);
      final source = sources[fields['id']];
      if (source == null) {
        throw const FormatException('An attachment is unavailable.');
      }
      final reader = await LegacyFileReader.open(source);
      final output = _DigestOutput();
      final input = sha256.startChunkedConversion(output);
      try {
        while (reader.remaining > 0) {
          check();
          input.add(
            await reader.read(
              min(StreamingFileCipher.window, reader.remaining),
            ),
          );
        }
        input.close();
      } finally {
        await reader.close();
      }
      entries.add({
        'metadata': {...fields, 'id': i},
        'payloadSha256': output.value.toString(),
      });
    }
    normalized['attachments'] = entries;
    check();
    return sha256
        .convert(utf8.encode(jsonEncode(_canonical(normalized))))
        .toString();
  }

  static dynamic _canonical(dynamic value) {
    if (value is Map) {
      final keys = value.keys.cast<String>().toList()..sort();
      return {for (final key in keys) key: _canonical(value[key])};
    }
    if (value is List) return value.map(_canonical).toList();
    return value;
  }
}

class _DigestOutput implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}
