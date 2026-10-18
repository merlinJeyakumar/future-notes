import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:universal_html/html.dart' as html;
import 'package:uuid/uuid.dart';
import 'package:path/path.dart' as p;
import 'settings_service.dart';
import 'attachment_ownership.dart';
import '../../../core/storage/note_reference.dart';
import '../../../core/storage/commit_record.dart';
import '../../../core/storage/owned_note_persistence.dart';
import '../../../core/storage/storage_owner_worker.dart';
import '../../../core/storage/library_watch.dart';
import '../../../core/storage/streaming_file_cipher.dart';
import '../../../core/storage/attachment_transform_worker.dart';
import '../../../core/storage/owned_write.dart';
import '../../../core/storage/file_operation_progress.dart';
import '../../../core/operations/operation_result.dart';

abstract interface class LibraryFileService {
  bool get supportsLibrarySwitch;
  Future<StorageBinding> currentLibrary();
  Future<StorageBinding> prepareLibrary(String root);
  Future<LibraryWatch> openLibraryWatch(StorageBinding binding);
  void publishLibrary(StorageBinding binding);
  Future<void> releaseLibrary(StorageBinding binding);
}

/// Capabilities exposed by the transactional view-model adapters.
abstract interface class NoteMutationPolicy {
  bool get supportsExtendedNoteOperations;
}

/// Metadata-only reads; never hashes or decrypts an attachment payload.
abstract interface class AttachmentMetadataReader {
  Future<DateTime?> attachmentModified(NoteReference reference, String id);
}

abstract interface class NoteMetadataReader {
  Future<int> noteMetadataLength(NoteReference reference);
  Future<Uint8List> noteMetadataHeader(NoteReference reference, int length);
}

abstract interface class AttachmentSourceSession {
  Future<void> releaseAttachmentSources(NoteReference reference);
  Future<bool> isAttachmentSourceCurrent(
    NoteReference reference,
    String id,
    StreamingFileSource source,
  );
}

abstract interface class PickedSourceOwner {
  String? sourceDisplayName(String path);
  Future<void> releasePickedSource(String path);
}

abstract interface class PickedSourceRecovery {
  Map<String, Object?>? pickedSourceIdentity(String path);
  Future<PlatformFile> reopenPickedSource(Map<String, Object?> identity);
  Future<void> forgetPickedSource(Map<String, Object?> identity);
}

abstract interface class TransactionalNoteFiles {
  bool get usesOwnedStorage;
  Future<List<NoteReference>> pendingDeletions();
  Future<StreamingFileSource> attachmentSource(
    NoteReference reference,
    String id, {
    FileByteProgress? onProgress,
    FileReadCancellation? cancellation,
    bool verifyContent = true,
  });
  Future<NoteReference> commitGeneration(
    NoteReference reference,
    String content,
    List<PreparedAttachmentFile> attachments, {
    FileByteProgress? onProgress,
    void Function(FileOperationProgress)? onFileProgress,
  });
  Future<OperationResult<DeletionReport>> deleteResolved(
    NoteReference reference,
  );
  Future<Directory> createOperationDirectory(NoteReference reference);
  Future<void> removeOperationDirectory(Directory directory);
}

abstract interface class AttachmentCandidateOwner {
  Future<OwnedWriteTarget> createAttachmentCandidate(
    NoteReference reference,
    String attachmentId,
    Directory operation,
    int expectedBytes,
  );
}

abstract class IFileService {
  Future<FilePickerResult?> pickFile({List<String>? allowedExtensions});
  Future<void> saveFile(String content, String fileName);
  Future<void> saveNoteContent(String noteId, String content);
  Future<String> saveAttachment(Uint8List data, String noteId);
  Future<List<String>> getRecentFiles();
  Future<String?> readFile(String fileName);
  Future<Uint8List?> readAttachment(String noteId, String attachmentId);
  Future<void> deleteFile(String fileName);
  Future<FileStat?> getFileStats(String fileName);
  Future<String> getFullPath(String fileName);
  Future<String?> importFile(PlatformFile file);
  Stream<void> watchRecentFiles();
  Future<String> getUserDataPath();
  Future<NoteReference?> resolveNote(String fileName);
  Future<NoteReference> newNoteReference(String noteId);
  Future<String?> readResolved(NoteReference reference);
  Future<NoteReference> writeResolved(NoteReference reference, String content);
}

class FileService
    implements
        IFileService,
        LibraryFileService,
        NoteMutationPolicy,
        TransactionalNoteFiles,
        AttachmentMetadataReader {
  FileService({SettingsService? settings, StorageOwner? storageOwner})
    : _settings = settings ?? SettingsService() {
    if (storageOwner != null) {
      _ownedNotes = OwnedNotePersistence(
        environment: _settings.storageEnvironment,
        owner: storageOwner,
      );
    }
  }

  final SettingsService _settings;
  OwnedNotePersistence? _ownedNotes;
  @override
  bool get usesOwnedStorage => _ownedNotes != null;
  @override
  bool get supportsExtendedNoteOperations => true;
  bool get noteCleanupPending => _ownedNotes?.cleanupPending ?? false;
  @override
  Future<List<NoteReference>> pendingDeletions() async {
    final binding = await _captureBinding();
    return _ownedNotes == null
        ? []
        : await _ownedNotes!.pendingDeletions(binding);
  }

  Future<void> closePersistence() async {
    await _ownedNotes?.close();
  }

  @override
  Future<DateTime?> attachmentModified(
    NoteReference reference,
    String id,
  ) async {
    if (kIsWeb) return null;
    await _verifyReference(reference);
    if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(id) ||
        !p.isAbsolute(reference.attachmentLocation) ||
        !p.isWithin(reference.binding.root, reference.attachmentLocation)) {
      throw ArgumentError('Invalid captured attachment location.');
    }
    final target = p.join(reference.attachmentLocation, '$id.med');
    await _settings.verifyStoragePath(target);
    final stat = await File(target).stat();
    return stat.type == FileSystemEntityType.file ? stat.modified : null;
  }

  @override
  Future<StreamingFileSource> attachmentSource(
    NoteReference reference,
    String id, {
    FileByteProgress? onProgress,
    FileReadCancellation? cancellation,
    bool verifyContent = true,
  }) async {
    await _verifyReference(reference);
    if (_ownedNotes == null) {
      throw UnsupportedError('Owned attachment source required.');
    }
    return _ownedNotes!.attachmentSource(
      reference,
      id,
      onProgress: onProgress,
      cancellation: cancellation,
      verifyContent: verifyContent,
    );
  }

  @override
  Future<NoteReference> commitGeneration(
    NoteReference reference,
    String content,
    List<PreparedAttachmentFile> attachments, {
    FileByteProgress? onProgress,
    void Function(FileOperationProgress)? onFileProgress,
  }) async {
    await _verifyReference(reference);
    if (_ownedNotes == null) {
      throw UnsupportedError('Owned generation commit required.');
    }
    return _ownedNotes!.commit(
      reference,
      content,
      attachments: attachments,
      onProgress: onProgress,
      onFileProgress: onFileProgress,
    );
  }

  @override
  Future<OperationResult<DeletionReport>> deleteResolved(
    NoteReference reference,
  ) async {
    await _verifyReference(reference);
    if (_ownedNotes == null) throw UnsupportedError('Owned deletion required.');
    if (await _ownedNotes!.needsDeletionOwnershipCheck(reference)) {
      final ownership = await verifyAttachmentOwnership(
        reference,
        _settings.storageEnvironment,
      );
      if (!ownership.isSuccess)
        return OperationResult.failure(ownership.outcome, ownership.message);
    }
    return _ownedNotes!.delete(reference);
  }

  @override
  Future<Directory> createOperationDirectory(NoteReference reference) async {
    if (_ownedNotes == null) {
      throw UnsupportedError('Owned operation required.');
    }
    await _verifyReference(reference);
    final target = p.posix.joinAll(
      p.split(p.relative(reference.contentPath, from: reference.binding.root)),
    );
    final location = reference.binding.child(
      '.future-notes-storage/sources/${CommitRecord.objectIdentity(target)}',
    );
    await _settings.storageEnvironment.verifyLocation(
      location,
      allowRunRoot: true,
    );
    final root = Directory(location);
    await root.create(recursive: true);
    return root.createTemp('attachment-operation-');
  }

  @override
  Future<void> removeOperationDirectory(Directory directory) async {
    final parts = p.split(directory.path);
    if (parts.length < 4 ||
        parts[parts.length - 4] != '.future-notes-storage' ||
        parts[parts.length - 3] != 'sources' ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(parts[parts.length - 2]) ||
        !p.basename(directory.path).startsWith('attachment-operation-')) {
      throw ArgumentError('Unowned operation directory.');
    }
    await _settings.storageEnvironment.verifyLocation(directory.path);
    if (!await directory.exists()) return;
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File) throw StateError('Unexpected operation object.');
      await _settings.storageEnvironment.verifyLocation(entity.path);
      await entity.delete();
    }
    await directory.delete();
  }

  void _rejectUnintegratedMutation() {
    if (_ownedNotes != null) {
      throw UnsupportedError(
        'This workflow is pending owned note-mutation integration.',
      );
    }
  }

  Future<NoteReference> _captureReference(
    NoteReference reference, {
    bool newObject = false,
  }) async => _ownedNotes == null
      ? reference
      : await _ownedNotes!.capture(reference, newObject: newObject);
  String? _boundRoot;
  int _rootGeneration = 0;
  int _nextRootGeneration = 0;
  @override
  bool get supportsLibrarySwitch =>
      _ownedNotes != null && _settings.supportsRecoverableLibrarySwitch;

  @override
  Future<StorageBinding> currentLibrary() => _captureBinding();

  @override
  Future<StorageBinding> prepareLibrary(String root) async {
    if (!p.isAbsolute(root) || p.split(root).contains('..')) {
      throw ArgumentError('Absolute library required.');
    }
    final canonical = StorageBinding(root, ++_nextRootGeneration);
    _settings.storageEnvironment.validateLibraryCandidate(canonical.root);
    await _ownedNotes?.prepareLibrary(canonical.root);
    await _settings.verifyStoragePath(canonical.root);
    return canonical;
  }

  @override
  Future<LibraryWatch> openLibraryWatch(StorageBinding binding) {
    if (kIsWeb) throw UnsupportedError('Native watching is unavailable.');
    return NativeLibraryWatch.open(
      binding,
      verify: _settings.verifyStoragePath,
    );
  }

  @override
  void publishLibrary(StorageBinding binding) {
    _boundRoot = binding.root;
    _rootGeneration = binding.generation;
  }

  @override
  Future<void> releaseLibrary(StorageBinding binding) async {
    await _ownedNotes?.releaseLibrary(binding.root);
  }

  Future<StorageBinding> _captureBinding() async {
    final binding = StorageBinding(await _settings.getUserDataPath(), 0);
    await _ownedNotes?.prepareLibrary(binding.root);
    if (_boundRoot != binding.root) {
      _boundRoot = binding.root;
      _rootGeneration = ++_nextRootGeneration;
    }
    return StorageBinding(binding.root, _rootGeneration);
  }

  @override
  Future<NoteReference?> resolveNote(String fileName) async {
    final binding = await _captureBinding();
    final direct = binding.child(fileName);
    await _settings.verifyStoragePath(direct);
    if (fileName.startsWith('note_')) {
      final folderId = fileName.substring(5);
      final contentPath = binding.child('$fileName/note_content_$folderId.enc');
      await _settings.verifyStoragePath(contentPath);
      if (await File(contentPath).exists()) {
        return _captureReference(
          NoteReference(
            binding: binding,
            fileName: fileName,
            format: NoteStorageFormat.folder,
            contentPath: contentPath,
            attachmentLocation: binding.child('$fileName/attachments'),
          ),
        );
      }
    }
    if (!await File(direct).exists()) return null;
    return _captureReference(
      NoteReference(
        binding: binding,
        fileName: fileName,
        format: NoteStorageFormat.legacyFile,
        contentPath: direct,
        attachmentLocation: binding.root,
      ),
    );
  }

  @override
  Future<NoteReference> newNoteReference(String noteId) async {
    final binding = await _captureBinding();
    final fileName = 'note_$noteId';
    return _captureReference(
      NoteReference(
        binding: binding,
        fileName: fileName,
        format: NoteStorageFormat.folder,
        contentPath: binding.child('$fileName/note_content_$noteId.enc'),
        attachmentLocation: binding.child('$fileName/attachments'),
        modelId: noteId,
      ),
      newObject: true,
    );
  }

  Future<void> _verifyReference(NoteReference reference) async {
    // References cannot grant access to a target outside their captured library.
    if (!p.isAbsolute(reference.contentPath) ||
        !p.isWithin(reference.binding.root, reference.contentPath)) {
      throw ArgumentError('Invalid captured content location.');
    }
    final expected = reference.binding.child(
      p.relative(reference.contentPath, from: reference.binding.root),
    );
    if (!p.equals(expected, reference.contentPath)) {
      throw ArgumentError('Invalid captured content location.');
    }
    await _settings.verifyStoragePath(reference.contentPath);
  }

  @override
  Future<String?> readResolved(NoteReference reference) async {
    if (kIsWeb) return null;
    await _verifyReference(reference);
    if (_ownedNotes != null) {
      return _ownedNotes!.read(reference);
    }
    final file = File(reference.contentPath);
    if (!await file.exists()) return null;
    return file.readAsString();
  }

  @override
  Future<NoteReference> writeResolved(
    NoteReference reference,
    String content,
  ) async {
    if (kIsWeb) throw UnsupportedError('Native persistence is unavailable.');
    await _verifyReference(reference);
    if (_ownedNotes != null) {
      return _ownedNotes!.commit(reference, content);
    }
    final file = File(reference.contentPath);
    await file.parent.create(recursive: true);
    // Replaced by verified recoverable commits in Stage 2. Do not activate this
    // intermediate writer on a real library or describe it as durable.
    await file.writeAsString(content, flush: true);
    return reference;
  }

  @override
  Future<FilePickerResult?> pickFile({List<String>? allowedExtensions}) async {
    return await FilePicker.platform.pickFiles(
      type: allowedExtensions != null ? FileType.custom : FileType.any,
      allowedExtensions: allowedExtensions,
    );
  }

  @override
  Future<String> saveAttachment(Uint8List data, String noteId) async {
    _rejectUnintegratedMutation();
    if (kIsWeb) return "";

    final attachmentsFolderPath = await _settings.getAttachmentsFolderPath(
      noteId,
    );
    final attachmentsDir = Directory(attachmentsFolderPath);
    if (!await attachmentsDir.exists()) {
      await attachmentsDir.create(recursive: true);
    }

    final attachmentId = const Uuid().v4();
    final filePath = await _settings.getAttachmentFilePath(
      noteId,
      attachmentId,
    );
    final file = File(filePath);
    await file.writeAsBytes(data);

    return attachmentId;
  }

  @override
  Future<Uint8List?> readAttachment(String noteId, String attachmentId) async {
    if (kIsWeb) return null;
    try {
      final filePath = await _settings.getAttachmentFilePath(
        noteId,
        attachmentId,
      );
      final file = File(filePath);

      if (await file.exists()) {
        return await file.readAsBytes();
      }
    } catch (e) {
      print("Error reading attachment: $e");
    }
    return null;
  }

  @override
  Future<void> saveFile(String content, String fileName) async {
    _rejectUnintegratedMutation();
    if (kIsWeb) {
      final bytes = utf8.encode(content);
      final blob = html.Blob([bytes]);
      final url = html.Url.createObjectUrlFromBlob(blob);
      html.AnchorElement(href: url)
        ..setAttribute("download", fileName)
        ..click();
      html.Url.revokeObjectUrl(url);
    } else {
      final userDataPath = await _settings.getUserDataPath();
      final userDataDir = Directory(userDataPath);
      if (!await userDataDir.exists()) {
        await userDataDir.create(recursive: true);
      }

      final file = File(await _settings.getLibraryFilePath(fileName));
      await file.writeAsString(content);
    }
  }

  @override
  Future<void> saveNoteContent(String noteId, String content) async {
    _rejectUnintegratedMutation();
    if (kIsWeb) return;

    final noteFolderPath = await _settings.getNoteFolderPath(noteId);
    final noteDir = Directory(noteFolderPath);
    if (!await noteDir.exists()) {
      await noteDir.create(recursive: true);
    }

    final noteFilePath = await _settings.getNoteFilePath(noteId);
    final file = File(noteFilePath);
    await file.writeAsString(content);
    print('Saved note to: ${file.path}');
  }

  @override
  Stream<void> watchRecentFiles() async* {
    if (kIsWeb) return;
    final watch = await openLibraryWatch(await currentLibrary());
    try {
      yield* watch.changes;
    } finally {
      await watch.close();
    }
  }

  @override
  Future<List<String>> getRecentFiles() async {
    if (kIsWeb) return [];
    if (_ownedNotes != null) {
      final binding = await _captureBinding();
      final entities = await Directory(
        binding.root,
      ).list(followLinks: false).toList();
      return entities
          .where(
            (entity) =>
                (entity is File &&
                    !p.basename(entity.path).startsWith('.future-notes-')) ||
                (entity is Directory &&
                    p.basename(entity.path).startsWith('note_')),
          )
          .map((entity) => p.basename(entity.path))
          .toList();
    }

    final userDataPath = await _settings.getUserDataPath();
    final userDataDir = Directory(userDataPath);
    final List<String> files = [];

    if (await userDataDir.exists()) {
      final entities = userDataDir.listSync();

      // Files directly in folder
      files.addAll(
        entities.whereType<File>().map((e) => e.uri.pathSegments.last),
      );

      // note_ folders directly in folder
      files.addAll(
        entities
            .whereType<Directory>()
            .where((d) => d.uri.pathSegments.last.startsWith('note_'))
            .map((e) => e.uri.pathSegments.last),
      );
    }
    return files;
  }

  @override
  Future<String?> readFile(String fileName) async {
    if (kIsWeb) return null;
    if (_ownedNotes != null) {
      final reference = await resolveNote(fileName);
      return reference == null ? null : readResolved(reference);
    }
    try {
      // Check if it's a note folder
      if (fileName.startsWith('note_')) {
        final noteId = fileName.replaceFirst('note_', '');
        final noteFilePath = await _settings.getNoteFilePath(noteId);
        final noteFile = File(noteFilePath);
        if (await noteFile.exists()) {
          return await noteFile.readAsString();
        }
      }

      // Fallback to legacy file directly in folder
      final file = File(await _settings.getLibraryFilePath(fileName));
      if (await file.exists()) {
        return await file.readAsString();
      }
    } catch (e) {
      print("Error reading file: $e");
    }
    return null;
  }

  @override
  Future<void> deleteFile(String fileName) async {
    _rejectUnintegratedMutation();
    if (kIsWeb) return;
    try {
      if (fileName.startsWith('note_')) {
        final noteId = fileName.replaceFirst('note_', '');
        final noteFolderPath = await _settings.getNoteFolderPath(noteId);
        final noteDir = Directory(noteFolderPath);
        if (await noteDir.exists()) {
          await noteDir.delete(recursive: true);
          print("Deleted note folder: ${noteDir.path}");
          return;
        }
      }

      final file = File(await _settings.getLibraryFilePath(fileName));
      if (await file.exists()) {
        await file.delete();
        print("Deleted file: ${file.path}");
      }
    } catch (e) {
      print("Error deleting file: $e");
    }
  }

  @override
  Future<FileStat?> getFileStats(String fileName) async {
    if (kIsWeb) return null;
    try {
      if (fileName.startsWith('note_')) {
        final noteId = fileName.replaceFirst('note_', '');
        final noteFilePath = await _settings.getNoteFilePath(noteId);
        final noteFile = File(noteFilePath);
        if (await noteFile.exists()) return await noteFile.stat();
      }

      final file = File(await _settings.getLibraryFilePath(fileName));
      if (await file.exists()) {
        return await file.stat();
      }
    } catch (e) {
      print("Error getting stats: $e");
    }
    return null;
  }

  @override
  Future<String> getFullPath(String fileName) async {
    if (kIsWeb) return fileName;
    try {
      if (fileName.startsWith('note_')) {
        final noteId = fileName.replaceFirst('note_', '');
        return await _settings.getNoteFolderPath(noteId);
      }
      return await _settings.getLibraryFilePath(fileName);
    } catch (e) {
      if (_settings.storageEnvironment.hasOwnedStorage) rethrow;
      return fileName;
    }
  }

  @override
  Future<String?> importFile(PlatformFile file) async {
    _rejectUnintegratedMutation();
    if (kIsWeb) return null;
    try {
      final userDataPath = await _settings.getUserDataPath();
      final userDataDir = Directory(userDataPath);
      if (!await userDataDir.exists()) {
        await userDataDir.create(recursive: true);
      }

      final String fileName = file.name;
      final String destinationPath = await _settings.getLibraryFilePath(
        fileName,
      );

      if (file.path != null) {
        await File(file.path!).copy(destinationPath);
        print("Imported file to: $destinationPath");
        return fileName;
      }
    } catch (e) {
      print("Error importing file: $e");
    }
    return null;
  }

  @override
  Future<String> getUserDataPath() async {
    if (kIsWeb) return '';
    if (_ownedNotes != null) {
      return (await _captureBinding()).root;
    }
    try {
      final userDataPath = await _settings.getUserDataPath();
      final userDataDir = Directory(userDataPath);
      if (!await userDataDir.exists()) {
        await userDataDir.create(recursive: true);
        print("Created UserData directory at: ${userDataDir.path}");
      }
      return userDataDir.path;
    } catch (e) {
      if (_settings.storageEnvironment.hasOwnedStorage) rethrow;
      return '';
    }
  }
}

/// Sources were opened by the native drop grant owner; paths are live FD leases.
abstract interface class NativeDropSourceOwner {
  PlatformFile adoptDroppedSource(Map<Object?, Object?> source);
}

abstract interface class AttachmentStagingCapacity {
  Future<void> checkStagingCapacity(int inputLength);
}

abstract interface class InterruptedStagingOwner {
  Future<void> discardInterruptedStaging(
    String directoryName,
    String attachmentId,
  );
}
