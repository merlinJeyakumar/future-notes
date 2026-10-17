import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../platform/library_documents.dart';

/// Admission is evidence about this provider now, not a promise of atomic
/// rename, unlimited capacity or future availability. Never probes note files.
class LibraryAdmissionProbe {
  const LibraryAdmissionProbe(this.documents);
  final LibraryDocuments documents;

  Future<void> verify(LibraryLocation library) async {
    final random = Random.secure();
    final suffix = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final root = await documents.root(library);
    if (!root.isDirectory) {
      throw const LibraryAccessException('not_folder', 'Select a folder.');
    }
    final probe = await documents.create(
      library,
      root,
      '.future-notes-probe-$suffix',
      directory: true,
    );
    final owned = <LibraryDocument>[];
    try {
      final folder = await documents.create(
        library,
        probe,
        'nested',
        directory: true,
      );
      owned.add(folder);
      var file = await documents.create(library, folder, 'candidate');
      owned.add(file);
      final payload = Uint8List.fromList(
        List.generate(65553, (_) => random.nextInt(256)),
      );
      await documents.append(
        library,
        file,
        Uint8List.sublistView(payload, 0, 32768),
        offset: 0,
      );
      await documents.append(
        library,
        file,
        Uint8List.sublistView(payload, 32768),
        offset: 32768,
      );
      await documents.flush(library, file);
      await _readback(library, file, payload);
      final renamed = await documents.rename(library, file, 'published');
      owned[owned.length - 1] = renamed;
      file = renamed;
      final inventory = await documents.children(library, folder);
      final matches = inventory.where((entry) => entry.name == 'published');
      if (matches.length != 1 ||
          matches.single.token != file.token ||
          inventory.any((entry) => entry.name == 'candidate')) {
        throw const LibraryAccessException(
          'ambiguous_names',
          'This provider does not preserve unique exact filenames.',
        );
      }
      await _readback(library, file, payload);
      // Native adapters must reject an existing name rather than auto-renaming.
      LibraryDocument? collision;
      try {
        collision = await documents.create(library, folder, 'published');
      } on LibraryAccessException catch (error) {
        if (error.code != 'name_exists') rethrow;
      }
      if (collision != null) {
        if (collision.token != file.token) owned.add(collision);
        throw const LibraryAccessException(
          'unsafe_create',
          'This provider cannot safely create exact filenames.',
        );
      }
    } finally {
      // Delete only objects returned from our disposable probe. Do not traverse
      // or remove unrecognized provider objects when cleanup fails.
      Object? cleanupFailure;
      for (final document in owned.reversed) {
        try {
          await documents.delete(library, document);
        } catch (error) {
          cleanupFailure ??= error;
        }
      }
      try {
        await documents.delete(library, probe);
      } catch (error) {
        cleanupFailure ??= error;
      }
      if (cleanupFailure != null) {
        throw const LibraryAccessException(
          'probe_cleanup',
          'The selected folder could not complete its access probe.',
        );
      }
    }
  }

  Future<void> _readback(
    LibraryLocation library,
    LibraryDocument file,
    Uint8List expected,
  ) async {
    final output = BytesBuilder(copy: false);
    var offset = 0;
    while (offset < expected.length) {
      final bytes = await documents.read(
        library,
        file,
        offset: offset,
        length: min(8192, expected.length - offset),
      );
      if (bytes.isEmpty) break;
      output.add(bytes);
      offset += bytes.length;
    }
    final tail = await documents.read(
      library,
      file,
      offset: expected.length,
      length: 1,
    );
    if (offset != expected.length ||
        tail.isNotEmpty ||
        sha256.convert(output.takeBytes()) != sha256.convert(expected)) {
      throw const LibraryAccessException(
        'readback_failed',
        'The selected folder did not preserve all written bytes.',
      );
    }
  }
}
