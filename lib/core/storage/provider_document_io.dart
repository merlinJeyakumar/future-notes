import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import '../platform/library_documents.dart';

class ProviderRevision {
  const ProviderRevision(this.length, this.hash);
  final int length;
  final String hash;
  Map<String, Object> toJson() => {'length': length, 'sha256': hash};
  factory ProviderRevision.fromJson(Map<String, Object?> json) {
    final length = json['length'] as int;
    final hash = json['sha256'] as String;
    if (length < 0 || !RegExp(r'^[a-f0-9]{64}$').hasMatch(hash)) {
      throw const FormatException('Invalid provider revision.');
    }
    return ProviderRevision(length, hash);
  }
  bool matches(ProviderRevision? other) =>
      other != null && length == other.length && hash == other.hash;
}

abstract interface class BoundedByteSource {
  int get length;
  Stream<List<int>> open();
}

class ProviderByteSource implements BoundedByteSource {
  const ProviderByteSource(this.io, this.document, this.length);
  final ProviderDocumentIo io;
  final LibraryDocument document;
  @override
  final int length;
  @override
  Stream<List<int>> open() async* {
    var offset = 0;
    while (offset < length) {
      final bytes = await io.documents.read(
        io.library,
        document,
        offset: offset,
        length: math.min(LibraryDocuments.chunkBytes, length - offset),
      );
      if (bytes.isEmpty) {
        throw const LibraryAccessException(
          'short_read',
          'The document ended before its captured length.',
        );
      }
      offset += bytes.length;
      yield bytes;
    }
    final tail = await io.documents.read(
      io.library,
      document,
      offset: length,
      length: 1,
    );
    if (tail.isNotEmpty) {
      throw const LibraryAccessException(
        'revision_changed',
        'The document length changed while reading.',
      );
    }
  }
}

/// Exact-name lookup and verified streaming above opaque platform identities.
class ProviderDocumentIo {
  const ProviderDocumentIo(this.documents, this.library);
  final LibraryDocuments documents;
  final LibraryLocation library;

  Future<LibraryDocument?> child(LibraryDocument parent, String name) async {
    validateDocumentName(name);
    final matches = (await documents.children(
      library,
      parent,
    )).where((e) => e.name == name).toList();
    if (matches.length > 1) {
      throw const LibraryAccessException(
        'ambiguous_names',
        'Multiple documents share an exact filename. No object was selected.',
      );
    }
    return matches.isEmpty ? null : matches.single;
  }

  Future<LibraryDocument?> resolve(List<String> path) async {
    var current = await documents.root(library);
    for (final part in path) {
      if (!current.isDirectory) {
        throw const LibraryAccessException(
          'not_folder',
          'A library parent is not a folder.',
        );
      }
      final next = await child(current, part);
      if (next == null) return null;
      current = next;
    }
    return current;
  }

  Future<LibraryDocument> directory(List<String> path) async {
    var current = await documents.root(library);
    for (final part in path) {
      final existing = await child(current, part);
      current =
          existing ??
          await documents.create(library, current, part, directory: true);
      if (!current.isDirectory || current.name != part) {
        throw const LibraryAccessException(
          'not_folder',
          'The library directory is unavailable or ambiguous.',
        );
      }
    }
    return current;
  }

  Future<ProviderRevision> revision(
    LibraryDocument doc, {
    void Function(int, int)? onProgress,
    bool Function()? cancelled,
  }) async {
    if (doc.isDirectory || doc.length == null || doc.length! < 0) {
      throw const LibraryAccessException(
        'unknown_length',
        'The provider did not report a file length.',
      );
    }
    final digest = _Digest();
    final conversion = sha256.startChunkedConversion(digest);
    var bytes = 0;
    await for (final chunk in ProviderByteSource(
      this,
      doc,
      doc.length!,
    ).open()) {
      if (cancelled?.call() == true)
        throw const LibraryAccessException(
          'cancelled',
          'Document checking was cancelled.',
        );
      conversion.add(chunk);
      bytes += chunk.length;
      onProgress?.call(bytes, doc.length!);
    }
    conversion.close();
    return ProviderRevision(bytes, digest.value!.toString());
  }

  /// A new candidate only. Neither short writes nor readback failures acknowledge.
  Future<ProviderRevision> write(
    LibraryDocument doc,
    BoundedByteSource source, {
    void Function(String, int, int)? onProgress,
  }) async {
    if (source.length < 0) {
      throw const FormatException('Invalid source length.');
    }
    if (documents is LibraryCapacity) {
      final available = await (documents as LibraryCapacity).availableBytes(
        library,
        doc,
      );
      if (available != null && available < source.length + 16 * 1024 * 1024) {
        throw const LibraryAccessException(
          'capacity_exceeded',
          'The selected filesystem does not have enough free space for a verified candidate. Existing notes and recovery objects were retained.',
        );
      }
    }
    final digest = _Digest();
    final conversion = sha256.startChunkedConversion(digest);
    var offset = 0;
    await for (final chunk in source.open()) {
      for (
        var start = 0;
        start < chunk.length;
        start += LibraryDocuments.chunkBytes
      ) {
        final end = math.min(chunk.length, start + LibraryDocuments.chunkBytes);
        final bytes = Uint8List.fromList(chunk.sublist(start, end));
        if (offset + bytes.length > source.length) {
          throw const LibraryAccessException(
            'source_changed',
            'The source exceeded its captured length.',
          );
        }
        await documents.append(library, doc, bytes, offset: offset);
        conversion.add(bytes);
        offset += bytes.length;
        onProgress?.call('Publishing encrypted data', offset, source.length);
      }
    }
    conversion.close();
    if (offset != source.length) {
      throw const LibraryAccessException(
        'short_source',
        'The source ended before its captured length.',
      );
    }
    await documents.flush(library, doc);
    final refreshed = await documents.stat(library, doc);
    final expected = ProviderRevision(offset, digest.value!.toString());
    if (!expected.matches(
      await revision(
        refreshed,
        onProgress: (bytes, total) =>
            onProgress?.call('Verifying publication', bytes, total),
      ),
    )) {
      throw const LibraryAccessException(
        'readback_failed',
        'The staged document failed readback verification.',
      );
    }
    return expected;
  }
}

class _Digest implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}
