import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:flutter/services.dart';

import '../../../core/storage/note_reference.dart';
import '../../../core/storage/streaming_file_cipher.dart';
import '../models/note_envelope.dart';
import 'encryption_service.dart';
import 'file_service.dart';
import 'note_codec.dart';
import 'pack_service.dart';
import 'provider_note_files.dart';

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
    final provider = files is ProviderNoteFiles
        ? files as ProviderNoteFiles
        : null;
    final candidates = await provider?.discoveryCandidates();
    final byName = {for (final entry in candidates ?? []) entry.name: entry};
    for (final name
        in candidates?.map((e) => e.name) ?? await files.getRecentFiles()) {
      if (name == 'settings.json' || name.startsWith('.future-notes-')) {
        continue;
      }
      final reference = provider == null
          ? await files.resolveNote(name)
          : (await provider.inspectDiscoveryCandidate(
              byName[name]!,
            ))?.reference;
      // Legacy attachment-only folders have no note envelope of their own.
      if (reference == null) continue;
      if (!p.equals(reference.binding.root, binding.root) ||
          reference.binding.generation != binding.generation) {
        throw const FormatException('The selected library changed.');
      }
      if (reference.format == NoteStorageFormat.legacyFile) {
        if (files is NoteMetadataReader) {
          final header = await (files as NoteMetadataReader).noteMetadataHeader(
            reference,
            6,
          );
          final packs = PackService(cipher);
          if (packs.isZip(header) ||
              (header.length == 6 && packs.isPack(header) && header[4] == 1))
            continue;
        } else {
          final input = await File(reference.contentPath).open();
          try {
            final header = await input.read(6);
            final packs = PackService(cipher);
            if (packs.isZip(header) ||
                (header.length == 6 &&
                    packs.isPack(header) &&
                    header[4] == 1)) {
              continue; // Export packages do not publish a library note identity.
            }
          } finally {
            await input.close();
          }
        }
      }
      final metadataLength = files is NoteMetadataReader
          ? await (files as NoteMetadataReader).noteMetadataLength(reference)
          : await File(reference.contentPath).length();
      if (metadataLength > 32 * 1024 * 1024) {
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
    FileByteProgress? onProgress,
  }) async {
    final port = onProgress == null ? null : ReceivePort();
    final drained = Completer<void>();
    final subscription = port?.listen((event) {
      if (event == null) {
        if (!drained.isCompleted) drained.complete();
      } else if (event is (String, int, int)) {
        onProgress?.call(event.$1, event.$2, event.$3);
      }
    });
    try {
      final result = await _fingerprintInIsolate(
        metadata,
        attachments,
        cancellationFile,
        port?.sendPort,
        Platform.isAndroid ? ServicesBinding.rootIsolateToken : null,
      );
      if (port != null) {
        await drained.future.timeout(
          const Duration(seconds: 2),
          onTimeout: () {},
        );
      }
      return result;
    } finally {
      await subscription?.cancel();
      port?.close();
    }
  }

  static Future<String> _fingerprintInIsolate(
    Map<String, dynamic> metadata,
    Map<String, StreamingFileSource> sources,
    String? cancel,
    SendPort? progress,
    RootIsolateToken? token,
  ) => Isolate.run(() async {
    try {
      // SAF sources are retained native capabilities, not ordinary paths.
      // Their bounded readers must borrow/check the granted descriptor through
      // platform channels from this worker before comparing ciphertext bytes.
      if (token != null) {
        BackgroundIsolateBinaryMessenger.ensureInitialized(token);
      }
      return await _fingerprint(metadata, sources, cancel, progress);
    } finally {
      progress?.send(null);
    }
  });

  static Future<String> _fingerprint(
    Map<String, dynamic> metadata,
    Map<String, StreamingFileSource> sources,
    String? cancellation,
    SendPort? progress,
  ) async {
    void check() {
      if (cancellation != null && File(cancellation).existsSync()) {
        throw const FileJobCancelled();
      }
    }

    final normalized = Map<String, dynamic>.from(metadata);
    final declared = metadata['attachments'] as List? ?? const [];
    final entries = <Map<String, dynamic>>[];
    final clock = Stopwatch()..start();
    var last = -200;
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
      final receipt = source.receipt;
      final name = fields['fileName'] as String? ?? 'Attachment ${i + 1}';
      void report(int bytes) {
        if (bytes == 0 ||
            bytes == source.length ||
            clock.elapsedMilliseconds - last >= 200) {
          last = clock.elapsedMilliseconds;
          progress?.send((name, bytes, source.length));
        }
      }

      report(0);
      String payloadHash;
      if (receipt != null &&
          source.offset == 0 &&
          source.length == receipt.length &&
          source.path == receipt.path &&
          await receipt.isCurrent()) {
        payloadHash = receipt.sha256Hex;
      } else {
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
            report(source.length - reader.remaining);
          }
          input.close();
        } finally {
          await reader.close();
        }
        payloadHash = output.value.toString();
      }
      report(source.length);
      entries.add({
        'metadata': {...fields, 'id': i},
        'payloadSha256': payloadHash,
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
