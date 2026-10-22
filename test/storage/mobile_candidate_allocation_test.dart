import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/core/platform/library_documents.dart';
import 'package:flutter_application_1/core/platform/mobile_library_documents.dart';
import 'package:flutter_application_1/features/dashboard/services/provider_note_files.dart';
import '../support/memory_library_documents.dart';
import '../support/validation_directory.dart';

class _Documents extends MobileLibraryDocuments {
  _Documents() : super(kind: LibraryLocationKind.appleBookmark);
  final memory = MemoryLibraryDocuments();
  @override
  Future<LibraryDocument> root(LibraryLocation library) => memory.root(library);
  @override
  Future<List<LibraryDocument>> children(
    LibraryLocation library,
    LibraryDocument parent,
  ) => memory.children(library, parent);
  @override
  Future<LibraryDocument> create(
    LibraryLocation library,
    LibraryDocument parent,
    String name, {
    bool directory = false,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 3));
    return memory.create(library, parent, name, directory: directory);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'concurrent first-file candidates share one folder without payload reads',
    () async {
      final run = await createValidationRun();
      final docs = _Documents();
      const library = LibraryLocation(
        kind: LibraryLocationKind.appleBookmark,
        token: 'synthetic',
      );
      final files = ProviderNoteFiles(
        documents: docs,
        location: library,
        libraryId: 'aaaa0000-0000-0000-0000-000000000000',
        privateRoot: run.path,
      );
      try {
        final ref = await files.newNoteReference('synthetic');
        final first = await files.createOperationDirectory(ref);
        final second = await files.createOperationDirectory(ref);
        final outputs = await Future.wait([
          files.createAttachmentCandidate(ref, 'first', first, 32),
          files.createAttachmentCandidate(ref, 'second', second, 32),
        ]);
        expect(outputs[0].path, isNot(outputs[1].path));
        final root = await docs.root(library);
        final folders = await docs.children(library, root);
        expect(folders.length, 1);
        expect(
          (await docs.children(library, folders.single)).map((e) => e.name),
          ['attachments'],
        );
        expect(docs.memory.readBytesByName, isEmpty);
        await files.removeOperationDirectory(first);
        await files.removeOperationDirectory(second);
      } finally {
        await files.close();
        await deleteValidationRun(run);
      }
    },
  );
}
