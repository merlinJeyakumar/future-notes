import 'dart:typed_data';
import 'package:flutter_application_1/core/platform/library_documents.dart';

class MemoryLibraryDocuments implements LibraryDocuments {
  MemoryLibraryDocuments() {
    nodes['root'] = _Node('', 'root', true);
  }
  final nodes = <String, _Node>{};
  String? fault;
  int next = 0;
  int largestWrite = 0;
  final readBytesByName = <String, int>{};
  final renames = <String>[];
  _Node _node(LibraryDocument doc) =>
      nodes[doc.token] ??
      (throw const LibraryAccessException(
        'missing_document',
        'Synthetic missing document',
      ));
  LibraryDocument _metadata(String id) {
    final node = nodes[id]!;
    return LibraryDocument(
      token: id,
      name: node.name,
      isDirectory: node.directory,
      length: node.bytes.length,
      modifiedMillis: 1,
    );
  }

  @override
  Future<LibraryLocation?> selectLocalFolder() async => null;
  @override
  Future<LibraryDocument> root(LibraryLocation library) async =>
      _metadata('root');
  @override
  Future<LibraryDocument> stat(
    LibraryLocation library,
    LibraryDocument document,
  ) async {
    _node(document);
    return _metadata(document.token);
  }

  @override
  Future<List<LibraryDocument>> children(
    LibraryLocation library,
    LibraryDocument parent,
  ) async => [
    for (final entry in nodes.entries)
      if (entry.value.parent == parent.token) _metadata(entry.key),
  ];
  @override
  Future<LibraryDocument> create(
    LibraryLocation library,
    LibraryDocument parent,
    String name, {
    bool directory = false,
  }) async {
    validateDocumentName(name);
    if ((await children(library, parent)).any((e) => e.name == name)) {
      throw const LibraryAccessException('name_exists', 'Synthetic duplicate');
    }
    final id = 'opaque-${next++}';
    nodes[id] = _Node(parent.token, name, directory);
    return _metadata(id);
  }

  @override
  Future<Uint8List> read(
    LibraryLocation library,
    LibraryDocument document, {
    required int offset,
    required int length,
  }) async {
    validateDocumentRange(offset, length);
    if (fault == 'permission_revoked') {
      throw const LibraryAccessException(
        'permission_revoked',
        'Synthetic revoked grant',
      );
    }
    final bytes = _node(document).bytes;
    readBytesByName.update(
      document.name,
      (n) => n + (bytes.length - offset).clamp(0, length),
      ifAbsent: () => (bytes.length - offset).clamp(0, length),
    );
    return offset >= bytes.length
        ? Uint8List(0)
        : Uint8List.fromList(
            bytes.sublist(offset, (offset + length).clamp(0, bytes.length)),
          );
  }

  @override
  Future<void> append(
    LibraryLocation library,
    LibraryDocument document,
    Uint8List bytes, {
    required int offset,
  }) async {
    validateDocumentRange(offset, bytes.length);
    if (fault == 'full_disk') {
      throw const LibraryAccessException('full_disk', 'Synthetic full disk');
    }
    final node = _node(document);
    if (offset != node.bytes.length) {
      throw const LibraryAccessException(
        'revision_changed',
        'Synthetic changed length',
      );
    }
    if (bytes.length > largestWrite) largestWrite = bytes.length;
    node.bytes.addAll(
      fault == 'short_write' ? bytes.sublist(0, bytes.length - 1) : bytes,
    );
  }

  @override
  Future<void> flush(LibraryLocation library, LibraryDocument document) async {
    _node(document);
  }

  @override
  Future<LibraryDocument> rename(
    LibraryLocation library,
    LibraryDocument document,
    String name,
  ) async {
    if (fault == 'sd_removed') {
      throw const LibraryAccessException('unavailable', 'Synthetic SD removal');
    }
    final node = _node(document);
    if (nodes.values.any((e) => e.parent == node.parent && e.name == name)) {
      throw const LibraryAccessException('name_exists', 'Synthetic duplicate');
    }
    final id = 'renamed-${next++}';
    nodes.remove(document.token);
    node.name = name;
    nodes[id] = node;
    renames.add(name);
    return _metadata(id);
  }

  @override
  Future<void> delete(LibraryLocation library, LibraryDocument document) async {
    if ((await children(library, document)).isNotEmpty) {
      throw StateError('Unexpected recursive removal');
    }
    nodes.remove(document.token);
  }

  void corrupt(LibraryDocument document, List<int> bytes) {
    _node(document).bytes
      ..clear()
      ..addAll(bytes);
  }

  void duplicateName(LibraryDocument document) {
    final old = _node(document);
    nodes['duplicate-${next++}'] = _Node(old.parent, old.name, old.directory)
      ..bytes.addAll(old.bytes);
  }
}

class _Node {
  _Node(this.parent, this.name, this.directory);
  final String parent;
  String name;
  final bool directory;
  final bytes = <int>[];
}
