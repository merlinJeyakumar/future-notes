import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../../../core/storage/file_operation_progress.dart';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import '../../../core/operations/operation_result.dart';
import '../../../core/platform/library_documents.dart';
import '../../../core/platform/android_native_cipher.dart';
import '../../../core/platform/mobile_library_documents.dart';
import '../../../core/platform/mobile_library_events.dart';
import '../../../core/storage/native_storage_primitives.dart';
import '../../../core/storage/note_reference.dart';
import '../../../core/storage/permanent_deletion.dart';
import '../../../core/storage/owned_note_persistence.dart'
    show PreparedAttachmentFile;
import '../../../core/storage/provider_document_io.dart';
import '../../../core/storage/provider_generation_store.dart';
import '../../../core/storage/attachment_transform_worker.dart';
import '../../../core/storage/streaming_file_cipher.dart';
import '../../../core/storage/bounded_file_reader.dart';
import '../../../core/storage/storage_owner_worker.dart';
import '../../../core/storage/owned_write.dart';
import 'package:uuid/uuid.dart';
import 'file_service.dart';

/// Live provider-backed notes. Private files are operation staging only; note
/// reads and acknowledgements always come from the selected provider.
class ProviderNoteFiles
    implements
        IFileService,
        AttachmentFilePicker,
        TransactionalNoteFiles,
        NoteMutationPolicy,
        NoteMetadataReader,
        AttachmentMetadataReader,
        AttachmentSourceSession,
        PickedSourceOwner,
        ImportSourceReader,
        PickedSourceRecovery,
        NativeDropSourceOwner,
        AttachmentStagingCapacity,
        InterruptedStagingOwner,
        AttachmentCandidateOwner {
  ProviderNoteFiles({
    required this.documents,
    required this.location,
    required this.libraryId,
    required this.privateRoot,
  }) : io = ProviderDocumentIo(documents, location),
       binding = StorageBinding(
         p.join(privateRoot, 'document-identities', libraryId),
         1,
       ) {
    if (!RegExp(r'^[a-f0-9-]{36}$').hasMatch(libraryId) ||
        !p.isAbsolute(privateRoot)) {
      throw ArgumentError(
        'A captured library identity and native private root are required.',
      );
    }
    store = ProviderGenerationStore(io);
    owner = StorageOwnerRoot(1, binding.root, libraryId);
  }
  final MobileLibraryDocuments documents;
  final LibraryLocation location;
  final String libraryId;
  final String privateRoot;
  final ProviderDocumentIo io;
  final StorageBinding binding;
  late final ProviderGenerationStore store;
  late final StorageOwnerRoot owner;
  final _changes = StreamController<void>.broadcast();
  final _leases = <String, _SourceLease>{};
  final _operations = <String>{};
  final _outputs = <String, (LibraryOutputSinkLease, String)>{};

  @override
  Future<OwnedWriteTarget> createAttachmentCandidate(
    NoteReference reference,
    String attachmentId,
    Directory operation,
    int expectedBytes,
  ) async {
    final ref = _reference(reference);
    if (!_operations.contains(operation.path))
      throw StateError('Unowned attachment operation.');
    validateDocumentName('$attachmentId.med');
    final parent = await io.directory(_attachmentPath(ref));
    try {
      if (Platform.isAndroid && !AndroidNativeCipher.ready) {
        throw const LibraryAccessException(
          'unsupported_sink',
          'Use one encrypted transfer with the Dart fallback.',
        );
      }
      final sink = await documents.openOutputSink(
        location,
        parent,
        '.future-notes-owned-${const Uuid().v4()}.pending',
      );
      final available = await documents.availableBytes(location, sink.document);
      if (available != null && available < expectedBytes + 16 * 1024 * 1024) {
        await documents.closeOutputSink(sink);
        await documents.delete(location, sink.document);
        throw const LibraryAccessException(
          'capacity_exceeded',
          'The selected filesystem does not have enough free space for this attachment.',
        );
      }
      _outputs[sink.lease] = (sink, operation.path);
      return OwnedWriteTarget.forSink(sink);
    } on LibraryAccessException catch (error) {
      if (error.code != 'unsupported_sink') rethrow;
      if (Platform.isAndroid) {
        final free = await const MethodChannel(
          'future_notes/files',
        ).invokeMethod<int>('privateAvailableBytes');
        if (free != null && free < expectedBytes + 16 * 1024 * 1024)
          throw const LibraryAccessException(
            'capacity_exceeded',
            'Private attachment staging space is unavailable.',
          );
      }
      return OwnedWriteTarget.forPath(
        p.join(operation.path, '${const Uuid().v4()}.med'),
      );
    }
  }

  final _picked = <String, Map<Object?, Object?>>{};
  Future<void> Function()? _stopWatch;
  bool _closed = false;
  @override
  Future<void> discardInterruptedStaging(
    String directoryName,
    String attachmentId,
  ) async {
    if (!RegExp(r'^operation-[A-Za-z0-9]+$').hasMatch(directoryName) ||
        !RegExp(r'^[a-f0-9-]{36}$').hasMatch(attachmentId))
      throw const FormatException('Invalid staging identity.');
    final directory = Directory(
      p.join(privateRoot, 'operations', directoryName),
    );
    if (_operations.contains(directory.path))
      throw StateError('An active operation owns this staging directory.');
    final type = await FileSystemEntity.type(
      directory.path,
      followLinks: false,
    );
    if (type == FileSystemEntityType.notFound) return;
    if (type != FileSystemEntityType.directory)
      throw const FormatException('Unknown staging object retained.');
    final entries = await directory.list(followLinks: false).toList();
    if (entries.any(
      (e) => e is! File || p.basename(e.path) != '$attachmentId.med',
    ))
      throw const FormatException('Unknown staging contents retained.');
    for (final file in entries) {
      await file.delete();
    }
    await directory.delete();
  }

  @override
  Future<void> checkStagingCapacity(int inputLength) async {
    if (!Platform.isAndroid) return;
    final available = (await const MethodChannel(
      'future_notes/files',
    ).invokeMethod<int>('privateAvailableBytes'))!;
    if (available < 16 * 1024 * 1024) {
      throw const LibraryAccessException(
        'capacity_exceeded',
        'The device does not have enough private staging space for this attachment.',
      );
    }
  }

  @override
  bool get usesOwnedStorage => true;
  @override
  bool get supportsExtendedNoteOperations => true;

  Future<void> initialize() async {
    final recovery = await store.recover();
    if (!recovery.isSuccess)
      throw LibraryAccessException('recovery_required', recovery.message!);
    _stopWatch = MobileLibraryEvents.listen(location.token, () {
      if (!_closed) _changes.add(null);
    });
  }

  _ProviderReference _reference(NoteReference reference) {
    if (_closed ||
        reference is! _ProviderReference ||
        reference.binding.root != binding.root ||
        reference.binding.generation != binding.generation) {
      throw const LibraryAccessException(
        'stale_reference',
        'The selected library or note changed.',
      );
    }
    return reference;
  }

  StorageRevision _revision(ProviderRevision? revision) => revision == null
      ? const StorageRevision.missing()
      : StorageRevision.present(revision.length, revision.hash, 0);
  ProviderRevision? _providerRevision(StorageRevision? revision) =>
      revision == null || !revision.exists
      ? null
      : ProviderRevision(revision.length!, revision.sha256Hex!);

  /// Discovery inspects metadata and at most 256 bytes before admitting a file.
  /// Legacy filenames are unrestricted; exports and other payloads are never
  /// resolved (and therefore never hashed) as note metadata.
  Future<List<LibraryDocument>> discoveryCandidates() async => [
    for (final doc in await documents.children(
      location,
      await documents.root(location),
    ))
      if (!doc.name.startsWith('.') &&
          doc.name != 'settings.json' &&
          (!doc.isDirectory || doc.name.startsWith('note_')))
        doc,
  ];

  Future<({NoteReference reference, LibraryDocument metadata})?>
  inspectDiscoveryCandidate(
    LibraryDocument entry, {
    LibraryDocument? envelope,
  }) async {
    validateDocumentName(entry.name);
    final content = envelope ?? await discoveryEnvelope(entry);
    if (content == null) {
      // Older libraries keep attachment-only note_<id> folders alongside a
      // separate legacy note file. Absence of a canonical envelope does not
      // make that attachment directory an independent note identity.
      return null;
    }
    if (content.isDirectory) {
      throw const FormatException('Note metadata is not a file.');
    }
    final length = content.length;
    if (length == null || length < 0 || length > 32 * 1024 * 1024) {
      if (!entry.isDirectory &&
          !entry.name.startsWith('note_') &&
          !entry.name.endsWith('.enc')) {
        return null;
      }
      throw const LibraryAccessException(
        'metadata_limit',
        'Note metadata exceeds the supported limit.',
      );
    }
    if (length == 0) {
      if (entry.isDirectory ||
          entry.name.startsWith('note_') ||
          entry.name.endsWith('.enc')) {
        throw const FormatException('Note metadata is empty.');
      }
      return null;
    }
    final header = await documents.read(
      location,
      content,
      offset: 0,
      length: length.clamp(0, 256),
    );
    // Plain JSON or the legacy app-encrypted base64 envelope. A bounded
    // prefix only admits a candidate; NoteCodec still validates the full note.
    final prefix = String.fromCharCodes(header).trimLeft();
    final candidate =
        length > 0 &&
        (prefix.isEmpty ||
            prefix.startsWith('{') ||
            RegExp(r'^[A-Za-z0-9+/=_%-]+$').hasMatch(prefix));
    if (!candidate) {
      if (entry.isDirectory ||
          entry.name.startsWith('note_') ||
          entry.name.endsWith('.enc')) {
        throw const FormatException('Unrecognized note metadata.');
      }
      return null;
    }
    final reference = await resolveNote(entry.name);
    if (reference == null) {
      throw const FormatException('Note metadata disappeared.');
    }
    return (reference: reference, metadata: content);
  }

  Future<LibraryDocument?> discoveryEnvelope(LibraryDocument entry) async {
    validateDocumentName(entry.name);
    return entry.isDirectory
        ? await io.child(entry, 'note_content_${entry.name.substring(5)}.enc')
        : entry;
  }

  @override
  Future<NoteReference?> resolveNote(String fileName) async {
    validateDocumentName(fileName);
    final root = await documents.root(location);
    final entry = await io.child(root, fileName);
    if (entry == null) return null;
    if (entry.isDirectory && !fileName.startsWith('note_')) return null;
    final path = entry.isDirectory
        ? [fileName, 'note_content_${fileName.substring(5)}.enc']
        : [fileName];
    final content = entry.isDirectory
        ? await io.child(entry, path.last)
        : entry;
    if (content == null || content.isDirectory) return null;
    if (content.length == null || content.length! > 32 * 1024 * 1024) {
      throw const LibraryAccessException(
        'metadata_limit',
        'Note metadata exceeds the supported limit.',
      );
    }
    return _ProviderReference(
      binding: binding,
      fileName: fileName,
      documentPath: path,
      format: entry.isDirectory
          ? NoteStorageFormat.folder
          : NoteStorageFormat.legacyFile,
      revision: _revision(await io.revision(content)),
      owner: owner,
    );
  }

  @override
  Future<NoteReference> newNoteReference(String noteId) async {
    final name = 'note_$noteId';
    validateDocumentName(name);
    if (await io.resolve([name]) != null)
      throw const LibraryAccessException(
        'name_exists',
        'The new note storage identity is already occupied.',
      );
    return _ProviderReference(
      binding: binding,
      fileName: name,
      documentPath: [name, 'note_content_$noteId.enc'],
      format: NoteStorageFormat.folder,
      revision: const StorageRevision.missing(),
      owner: owner,
      modelId: noteId,
    );
  }

  @override
  Future<String?> readResolved(NoteReference reference) async {
    final ref = _reference(reference);
    final doc = await io.resolve(ref.documentPath);
    if (doc == null) return null;
    if (doc.length == null || doc.length! > 32 * 1024 * 1024)
      throw const FormatException('Note metadata exceeds limit.');
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in ProviderByteSource(io, doc, doc.length!).open()) {
      bytes.add(chunk);
    }
    final fresh = await io.resolve(ref.documentPath);
    if (fresh == null ||
        !_providerRevision(
          ref.storageRevision,
        )!.matches(await io.revision(fresh))) {
      throw const LibraryAccessException(
        'revision_changed',
        'The note changed while opening.',
      );
    }
    return utf8.decode(bytes.takeBytes());
  }

  @override
  Future<NoteReference> writeResolved(
    NoteReference reference,
    String content,
  ) => commitGeneration(reference, content, const []);

  @override
  Future<NoteReference> commitGeneration(
    NoteReference reference,
    String content,
    List<PreparedAttachmentFile> attachments, {
    FileByteProgress? onProgress,
    void Function(FileOperationProgress)? onFileProgress,
  }) async {
    final ref = _reference(reference);
    final mutations = <ProviderMutation>[];
    final seen = <String>{};
    for (final attachment in attachments) {
      validateDocumentName('${attachment.id}.med');
      if (!seen.add(attachment.id))
        throw const FormatException('Duplicate attachment storage identity.');
      final path = [..._attachmentPath(ref), '${attachment.id}.med'];
      final existing = await io.resolve(path);
      final proof = attachment.source.receipt;
      if (proof?.target.sink != null &&
          (!_outputs.containsKey(proof!.target.lease) ||
              attachment.source.path != proof.path ||
              !await proof.isCurrent())) {
        throw const FormatException('Attachment output ownership changed.');
      }
      mutations.add(
        ProviderMutation(
          path: path,
          source: _FileSource(attachment.source),
          expected: existing == null ? null : await io.revision(existing),
          envelope: false,
          displayName: attachment.fileName,
          verifyReadback: attachment.source.receipt?.verifyReadback ?? true,
          expectedSourceHash: attachment.source.receipt?.sha256Hex,
          ownedCandidate: proof?.target.sink == null ? null : proof,
          sourceReceipt: proof?.target.sink == null ? proof : null,
        ),
      );
    }
    mutations.add(
      ProviderMutation(
        path: ref.documentPath,
        source: _MemorySource(utf8.encode(content)),
        expected: _providerRevision(ref.storageRevision),
        envelope: true,
      ),
    );
    final result = await store.commit(
      mutations,
      onProgress: onProgress,
      onFileProgress: onFileProgress,
    );
    if (!result.isSuccess)
      throw LibraryAccessException(result.outcome.name, result.message!);
    final acknowledged = await resolveNote(ref.fileName);
    if (acknowledged == null)
      throw const LibraryAccessException(
        'readback_failed',
        'The acknowledged note could not be resolved.',
      );
    if (!_closed) _changes.add(null);
    return acknowledged.withModelId(ref.modelId ?? '');
  }

  List<String> _attachmentPath(_ProviderReference ref) {
    if (ref.format == NoteStorageFormat.folder)
      return [ref.fileName, 'attachments'];
    if (ref.modelId == null || ref.modelId!.isEmpty)
      throw const FormatException('Legacy attachment identity unavailable.');
    final folder = 'note_${ref.modelId}';
    validateDocumentName(folder);
    return [folder, 'attachments'];
  }

  @override
  Future<StreamingFileSource> attachmentSource(
    NoteReference reference,
    String id, {
    FileByteProgress? onProgress,
    FileReadCancellation? cancellation,
    bool verifyContent = true,
  }) async {
    final ref = _reference(reference);
    validateDocumentName('$id.med');
    final doc = await io.resolve([..._attachmentPath(ref), '$id.med']);
    if (doc == null || doc.isDirectory)
      throw const LibraryAccessException(
        'missing_attachment',
        'Attachment unavailable.',
      );
    final key = '${ref.contentPath}:$id';
    var lease = _leases[key];
    if (lease != null && !lease.matches(doc)) {
      await documents.closeSource(location, lease.source.lease);
      _leases.remove(key);
      lease = null;
    }
    if (cancellation?.cancelled == true) throw const FileJobCancelled();
    String? hash;
    if (verifyContent) {
      onProgress?.call('Checking attachment', 0, doc.length ?? 0);
      hash = (await io.revision(
        doc,
        cancelled: () => cancellation?.cancelled == true,
        onProgress: (bytes, total) =>
            onProgress?.call('Checking attachment', bytes, total),
      )).hash;
    }
    lease ??= _SourceLease(
      await documents.openSource(location, doc),
      doc,
      ref.contentPath,
    );
    _leases[key] = lease;
    final stat = await File(lease.source.path).stat();
    if (stat.type != FileSystemEntityType.file ||
        stat.size != doc.length ||
        stat.size < 0)
      throw const FormatException('Native document source changed.');
    return StreamingFileSource(
      lease.source.path,
      stat.size,
      sha256Hex: hash,
      modifiedMicros: stat.modified.microsecondsSinceEpoch,
    );
  }

  @override
  Future<bool> isAttachmentSourceCurrent(
    NoteReference reference,
    String id,
    StreamingFileSource source,
  ) async {
    final ref = _reference(reference);
    final lease = _leases['${ref.contentPath}:$id'];
    final doc = await io.resolve([..._attachmentPath(ref), '$id.med']);
    return lease != null &&
        doc != null &&
        lease.matches(doc) &&
        source.path == lease.source.path;
  }

  @override
  Future<void> releaseAttachmentSources(NoteReference reference) async {
    for (final entry in _leases.entries.toList()) {
      if (entry.value.note == reference.contentPath) {
        await documents.closeSource(location, entry.value.source.lease);
        _leases.remove(entry.key);
      }
    }
  }

  @override
  Future<DateTime?> attachmentModified(
    NoteReference reference,
    String id,
  ) async {
    validateDocumentName('$id.med');
    final doc = await io.resolve([
      ..._attachmentPath(_reference(reference)),
      '$id.med',
    ]);
    return doc?.modifiedMillis == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(doc!.modifiedMillis!);
  }

  @override
  Future<Directory> createOperationDirectory(NoteReference reference) async {
    _reference(reference);
    final root = Directory(p.join(privateRoot, 'operations'));
    await root.create(recursive: true);
    final operation = await root.createTemp('operation-');
    _operations.add(operation.path);
    return operation;
  }

  @override
  Future<void> removeOperationDirectory(Directory directory) async {
    if (!_operations.contains(directory.path) ||
        !p.isWithin(p.join(privateRoot, 'operations'), directory.path))
      throw StateError('Unowned operation directory.');
    for (final entry
        in _outputs.entries
            .where((e) => e.value.$2 == directory.path)
            .toList()) {
      final sink = entry.value.$1;
      try {
        // Only an unadopted, exact owned pending identity can be discarded.
        // Transaction candidates and ambiguous renamed objects stay recoverable.
        final current = await io.child(sink.parent, sink.document.name);
        if (current?.token == sink.document.token)
          await documents.delete(location, current!);
      } catch (_) {
        /* Retain ambiguous provider objects. */
      }
      await documents.closeOutputSink(sink);
      _outputs.remove(entry.key);
    }
    if (await directory.exists()) {
      await for (final child in directory.list(followLinks: false)) {
        if (child is! File)
          throw StateError('Unexpected operation object retained.');
        await child.delete();
      }
      await directory.delete();
    }
    _operations.remove(directory.path);
  }

  @override
  Future<List<NoteReference>> pendingDeletions() async => const [];
  @override
  Future<OperationResult<DeletionReport>> deleteResolved(
    NoteReference reference,
  ) async {
    final ref = _reference(reference);
    final revision = _providerRevision(ref.storageRevision);
    if (revision == null)
      return const OperationResult.failure(
        OperationOutcome.conflict,
        'This note no longer has a captured revision.',
      );
    await releaseAttachmentSources(reference);
    final result = await store.deleteNote(ref.documentPath, revision);
    if (!_closed) _changes.add(null);
    return result;
  }

  @override
  Future<List<String>> getRecentFiles() async => [
    for (final doc in await documents.children(
      location,
      await documents.root(location),
    ))
      if (!doc.name.startsWith('.') &&
          doc.name != 'settings.json' &&
          (!doc.isDirectory || doc.name.startsWith('note_')))
        doc.name,
  ];
  @override
  Future<int> noteMetadataLength(NoteReference reference) async =>
      (await io.resolve(_reference(reference).documentPath))?.length ??
      (throw const FormatException('Missing note metadata.'));
  @override
  Future<Uint8List> noteMetadataHeader(
    NoteReference reference,
    int length,
  ) async {
    final doc = (await io.resolve(_reference(reference).documentPath))!;
    return documents.read(location, doc, offset: 0, length: length);
  }

  @override
  Future<Uint8List> readImportHeader(String source) async {
    final reader = await BoundedFileReader.openPath(source);
    try {
      return await reader.read(6);
    } finally {
      await reader.close();
    }
  }

  @override
  Future<FilePickerResult?> pickFile({List<String>? allowedExtensions}) async {
    const channel = MethodChannel('future_notes/documents');
    final selected = await channel.invokeMethod<Map<Object?, Object?>>(
      'pickFile',
    );
    if (selected == null) return null;
    final path = selected['path'] as String;
    final name = selected['name'] as String;
    _picked[path] = selected;
    if (allowedExtensions != null &&
        !allowedExtensions
            .map((e) => e.toLowerCase())
            .contains(p.extension(name).replaceFirst('.', '').toLowerCase())) {
      await releasePickedSource(path);
      throw const FormatException(
        'Choose a file with one of the supported extensions.',
      );
    }
    return FilePickerResult([
      PlatformFile(name: name, path: path, size: selected['length'] as int),
    ]);
  }

  @override
  Future<FilePickerResult?> pickAttachments() async {
    const channel = MethodChannel('future_notes/documents');
    final sources = await channel.invokeListMethod<Object?>('pickFiles');
    if (sources == null || sources.isEmpty) return null;
    final adopted = <PlatformFile>[];
    try {
      for (final source in sources) {
        adopted.add(
          adoptDroppedSource(Map<Object?, Object?>.from(source as Map)),
        );
      }
      return FilePickerResult(adopted);
    } catch (_) {
      for (final source in sources) {
        if (source is Map && source['lease'] is String) {
          final path = source['path'];
          if (path is String) _picked.remove(path);
          await channel.invokeMethod<void>('closePickedSource', {
            'lease': source['lease'],
          });
        }
      }
      rethrow;
    }
  }

  @override
  PlatformFile adoptDroppedSource(Map<Object?, Object?> source) {
    if (_closed ||
        source['path'] is! String ||
        source['lease'] is! String ||
        source['name'] is! String ||
        source['length'] is! int)
      throw const FormatException('Invalid dropped source.');
    final path = source['path'] as String;
    _picked[path] = source;
    return PlatformFile(
      name: source['name'] as String,
      path: path,
      size: source['length'] as int,
    );
  }

  @override
  String? sourceDisplayName(String path) => _picked[path]?['name'] as String?;
  @override
  Map<String, Object?>? pickedSourceIdentity(String path) {
    final source = _picked[path];
    return source == null
        ? null
        : {'document': source['identity'], 'length': source['length']};
  }

  @override
  Future<PlatformFile> reopenPickedSource(Map<String, Object?> identity) async {
    final selected = (await const MethodChannel('future_notes/documents')
        .invokeMethod<Map<Object?, Object?>>('reopenPickedSource', {
          'identity': identity['document'],
        }))!;
    final path = selected['path'] as String;
    _picked[path] = selected;
    return PlatformFile(
      name: selected['name'] as String,
      path: path,
      size: selected['length'] as int,
    );
  }

  @override
  Future<void> forgetPickedSource(Map<String, Object?> identity) =>
      const MethodChannel('future_notes/documents').invokeMethod<void>(
        'forgetPickedSource',
        {'identity': identity['document']},
      );

  @override
  Future<void> releasePickedSource(String path) async {
    final selected = _picked.remove(path);
    if (selected != null)
      await const MethodChannel(
        'future_notes/documents',
      ).invokeMethod<void>('closePickedSource', {'lease': selected['lease']});
  }

  @override
  Future<String?> readFile(String fileName) async {
    final ref = await resolveNote(fileName);
    return ref == null ? null : readResolved(ref);
  }

  @override
  Future<String> getFullPath(String fileName) async =>
      (await resolveNote(fileName))!.contentPath;
  @override
  Future<FileStat?> getFileStats(String fileName) async {
    final ref = await resolveNote(fileName);
    if (ref == null) return null;
    final doc = (await io.resolve(_reference(ref).documentPath))!;
    final source = await documents.openSource(location, doc);
    try {
      return await File(source.path).stat();
    } finally {
      await documents.closeSource(location, source.lease);
    }
  }

  @override
  Future<String> getUserDataPath() async => binding.root;
  @override
  Stream<void> watchRecentFiles() => _changes.stream;
  Future<void> close() async {
    if (_closed) return;
    try {
      await _stopWatch?.call();
    } catch (_) {
      /* Selection grants may have been revoked; close all private leases anyway. */
    }
    for (final lease in _leases.values) {
      await documents.closeSource(location, lease.source.lease);
    }
    _leases.clear();
    for (final output in _outputs.values) {
      try {
        await documents.closeOutputSink(output.$1);
      } catch (_) {
        /* Native process death also closes handles. */
      }
    }
    _outputs.clear();
    for (final path in _picked.keys.toList()) {
      await releasePickedSource(path);
    }
    _closed = true;
    await _changes.close();
  }

  // All shared editor mutations use the captured transactional methods above.
  // Reject accidental legacy fallbacks rather than write into private storage.
  @override
  Future<void> saveFile(String content, String fileName) =>
      Future.error(UnsupportedError('Use a captured note transaction.'));
  @override
  Future<void> saveNoteContent(String noteId, String content) =>
      Future.error(UnsupportedError('Use a captured note transaction.'));
  @override
  Future<String> saveAttachment(Uint8List data, String noteId) =>
      Future.error(UnsupportedError('Use streaming attachment publication.'));
  @override
  Future<Uint8List?> readAttachment(String noteId, String attachmentId) =>
      Future.error(UnsupportedError('Use a leased attachment source.'));
  @override
  Future<void> deleteFile(String fileName) =>
      Future.error(UnsupportedError('Use reviewed deletion.'));
  @override
  Future<String?> importFile(PlatformFile file) =>
      Future.error(UnsupportedError('Use UID-safe package import.'));
}

class _ProviderReference extends NoteReference {
  _ProviderReference({
    required StorageBinding binding,
    required String fileName,
    required this.documentPath,
    required NoteStorageFormat format,
    required StorageRevision revision,
    required StorageOwnerRoot owner,
    String? modelId,
  }) : super(
         binding: binding,
         fileName: fileName,
         format: format,
         modelId: modelId,
         contentPath: binding.child(documentPath.join('/')),
         attachmentLocation: binding.child('$fileName/attachments'),
         storageRevision: revision,
         storageOwner: owner,
       );
  final List<String> documentPath;
  @override
  NoteReference withModelId(String id) => _ProviderReference(
    binding: binding,
    fileName: fileName,
    documentPath: documentPath,
    format: format,
    revision: storageRevision!,
    owner: storageOwner!,
    modelId: id,
  );
  @override
  NoteReference withStorageRevision(
    StorageRevision revision,
    StorageOwnerRoot owner,
  ) => _ProviderReference(
    binding: binding,
    fileName: fileName,
    documentPath: documentPath,
    format: format,
    revision: revision,
    owner: owner,
    modelId: modelId,
  );
}

class _SourceLease {
  const _SourceLease(this.source, this.document, this.note);
  final NativeDocumentSource source;
  final LibraryDocument document;
  final String note;
  bool matches(LibraryDocument other) =>
      document.token == other.token &&
      document.length == other.length &&
      document.modifiedMillis == other.modifiedMillis;
}

class _FileSource implements BoundedByteSource {
  const _FileSource(this.source);
  final StreamingFileSource source;
  @override
  int get length => source.length;
  @override
  Stream<List<int>> open() async* {
    final before = await File(source.path).stat();
    if (source.receipt != null && !await source.receipt!.isCurrent()) {
      throw const FormatException('Prepared attachment changed.');
    }
    yield* File(
      source.path,
    ).openRead(source.offset, source.offset + source.length);
    final after = await File(source.path).stat();
    if (before.size != after.size ||
        before.modified != after.modified ||
        before.changed != after.changed) {
      throw const FormatException(
        'Prepared attachment changed during transfer.',
      );
    }
  }
}

class _MemorySource implements BoundedByteSource {
  const _MemorySource(this.bytes);
  final List<int> bytes;
  @override
  int get length => bytes.length;
  @override
  Stream<List<int>> open() => Stream.value(bytes);
}
