import 'dart:typed_data';

/// An opaque platform location, never an operating-system file path.
enum LibraryLocationKind { fileSystem, androidTree, appleBookmark }

class LibraryLocation {
  const LibraryLocation({required this.kind, required this.token});
  final LibraryLocationKind kind;
  final String token;

  Map<String, Object> toJson() => {'kind': kind.name, 'token': token};

  factory LibraryLocation.fromJson(Map<String, Object?> json) {
    final kind = LibraryLocationKind.values.byName(json['kind'] as String);
    final token = json['token'] as String;
    if (token.isEmpty) throw const FormatException('Empty library handle.');
    return LibraryLocation(kind: kind, token: token);
  }
}

/// IDs and tokens are provider metadata. Callers must not join them as paths.
class LibraryDocument {
  const LibraryDocument({
    required this.token,
    required this.name,
    required this.isDirectory,
    required this.length,
    required this.modifiedMillis,
  });
  final String token;
  final String name;
  final bool isDirectory;
  final int? length;
  final int? modifiedMillis;

  factory LibraryDocument.fromJson(Map<Object?, Object?> json) =>
      LibraryDocument(
        token: json['token'] as String,
        name: json['name'] as String,
        isDirectory: json['directory'] as bool,
        length: json['length'] as int?,
        modifiedMillis: json['modified'] as int?,
      );
}

class LibraryAccessException implements Exception {
  const LibraryAccessException(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => message;
}

/// Bounded document operations. No URI-to-path conversion or implicit fallback.
/// Publication/recovery is a separate coordinator above these primitives.
abstract interface class LibraryDocuments {
  static const chunkBytes = 1024 * 1024;
  Future<LibraryLocation?> selectLocalFolder();
  Future<LibraryDocument> root(LibraryLocation library);
  Future<LibraryDocument> stat(
    LibraryLocation library,
    LibraryDocument document,
  );
  Future<List<LibraryDocument>> children(
    LibraryLocation library,
    LibraryDocument parent,
  );
  Future<LibraryDocument> create(
    LibraryLocation library,
    LibraryDocument parent,
    String name, {
    bool directory = false,
  });
  Future<Uint8List> read(
    LibraryLocation library,
    LibraryDocument document, {
    required int offset,
    required int length,
  });
  Future<void> append(
    LibraryLocation library,
    LibraryDocument document,
    Uint8List bytes, {
    required int offset,
  });
  Future<void> flush(LibraryLocation library, LibraryDocument document);

  /// Returns the new provider identity; rename is never assumed atomic.
  Future<LibraryDocument> rename(
    LibraryLocation library,
    LibraryDocument document,
    String name,
  );
  Future<void> delete(LibraryLocation library, LibraryDocument document);
}

void validateDocumentName(String name) {
  if (name.isEmpty ||
      name == '.' ||
      name == '..' ||
      name.length > 240 ||
      name.contains(RegExp(r'[/\\\x00-\x1f]'))) {
    throw const LibraryAccessException(
      'invalid_name',
      'Invalid document name.',
    );
  }
}

void validateDocumentRange(int offset, int length) {
  if (offset < 0 || length < 1 || length > LibraryDocuments.chunkBytes) {
    throw const LibraryAccessException('invalid_range', 'Invalid byte range.');
  }
}

/// Capacity of the filesystem backing an actual opened provider document.
abstract interface class LibraryCapacity {
  Future<int?> availableBytes(
    LibraryLocation library,
    LibraryDocument document,
  );
}

/// A newly created provider document held by its native owner. The path is an
/// owned open-handle endpoint, never a path guessed from a provider URI.
class LibraryOutputSinkLease {
  const LibraryOutputSinkLease({
    required this.library,
    required this.document,
    required this.parent,
    required this.lease,
    required this.path,
  });
  final LibraryLocation library;
  final LibraryDocument document;
  final LibraryDocument parent;
  final String lease;
  final String path;
}

abstract interface class LibraryOutputSinks {
  Future<LibraryOutputSinkLease> openOutputSink(
    LibraryLocation library,
    LibraryDocument parent,
    String name,
  );
  Future<LibraryDocument> checkOutputSink(LibraryOutputSinkLease sink);
  Future<void> closeOutputSink(LibraryOutputSinkLease sink);
}
