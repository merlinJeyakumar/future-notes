import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import '../operations/operation_result.dart';
import '../../features/dashboard/models/note_model.dart';
import 'note_reference.dart';
import 'attachment_transform_worker.dart';
import 'streaming_file_cipher.dart';
import 'owned_write.dart';
import 'attachment_performance.dart';

typedef AttachmentSourceResolver =
    Future<StreamingFileSource> Function(NoteReference reference, String id);
typedef CacheFileRemover = Future<void> Function(File file);
typedef AttachmentSourcePreparer =
    Future<StreamingFileSource> Function(
      NoteReference reference,
      String id, {
      FileByteProgress? onProgress,
      FileReadCancellation? cancellation,
      required bool verifyContent,
    });

class CachedAttachmentFile {
  const CachedAttachmentFile(this.path, this.length, this.key);
  final String path;
  final int length;
  final String key;
}

class CacheCleanupResult {
  const CacheCleanupResult(this.deferred);
  final int deferred;
}

class _Entry {
  _Entry(
    this.note,
    this.file,
    this.source,
    this.sourceModified,
    this.cachedModified,
    this.checkedSource,
    this.verifiedOutput,
  );
  final String note;
  final CachedAttachmentFile file;
  final StreamingFileSource source;
  final DateTime sourceModified;
  final DateTime cachedModified;
  final bool checkedSource;
  final bool verifiedOutput;
}

class _Preparation {
  _Preparation(this.note);
  final String note;
  bool cancelled = false;
  final readCancellation = FileReadCancellation();
  FileTransformJob? transform;
  late Future<OperationResult<CachedAttachmentFile>> result;
}

/// Plaintext only for an explicit Open action. Files are never note mutations.
class AttachmentOpenCache {
  AttachmentOpenCache({
    required this.rootResolver,
    required this.sourceResolver,
    this.sourcePreparer,
    this.performance,
    this.sourceValidator,
    AttachmentTransformWorker? worker,
    CacheFileRemover? removeFile,
  }) : _worker = worker ?? AttachmentTransformWorker(),
       _removeFile =
           removeFile ??
           ((file) async {
             await file.delete();
           });
  final Future<String> Function() rootResolver;
  final AttachmentSourceResolver sourceResolver;
  final AttachmentSourcePreparer? sourcePreparer;
  final AttachmentPerformance Function()? performance;
  final Future<bool> Function(
    NoteReference reference,
    String id,
    StreamingFileSource source,
  )?
  sourceValidator;
  final AttachmentTransformWorker _worker;
  final CacheFileRemover _removeFile;
  final _entries = <String, _Entry>{};
  final _preparing = <String, _Preparation>{};
  final _ownedFiles = <String>{};
  Directory? _session;
  RandomAccessFile? _lease;
  Future<void>? _initialization;
  bool _closed = false;
  Future<void> _manifestTail = Future.value();
  Future<CacheCleanupResult>? _closing;
  int transformCount = 0;
  String _noteKey(NoteReference reference) => sha256
      .convert(
        utf8.encode(
          Platform.isWindows
              ? p.normalize(reference.contentPath).toLowerCase()
              : p.normalize(reference.contentPath),
        ),
      )
      .toString();
  String keyFor(NoteReference reference, String id, int credentials) =>
      '${_noteKey(reference)}:$id:$credentials';

  CachedAttachmentFile? peek(
    NoteReference reference,
    String id,
    int credentials,
  ) => _entries[keyFor(reference, id, credentials)]?.file;
  List<CachedAttachmentFile> filesForNote(NoteReference reference) => _entries
      .values
      .where((entry) => entry.note == _noteKey(reference))
      .map((entry) => entry.file)
      .toList();

  Future<void> initialize() => _initialization ??= _initialize().catchError((
    Object error,
    StackTrace stack,
  ) async {
    try {
      await _lease?.close();
    } catch (_) {}
    _lease = null;
    _session = null;
    _initialization = null;
    Error.throwWithStackTrace(error, stack);
  });
  Future<void> _initialize() async {
    final root = Directory(await rootResolver());
    if (!p.isAbsolute(root.path)) {
      throw const FormatException('Absolute cache root required.');
    }
    await _safe(root.path);
    if (!await root.exists()) {
      throw const FileSystemException('Cache root unavailable.');
    }
    // Never delete another live process's cache. Opaque manifests list only
    // files created by this service; unknown entries are retained.
    await for (final entity in root.list(followLinks: false)) {
      if (entity is! Directory || !_uuid(p.basename(entity.path))) continue;
      RandomAccessFile? lease;
      try {
        await _safe(entity.path);
        final leaseFile = File(p.join(entity.path, 'owner.lease'));
        if (!await leaseFile.exists()) continue;
        lease = await leaseFile.open(mode: FileMode.append);
        await lease.lock(FileLock.exclusive);
        final manifest = File(p.join(entity.path, 'cleanup.json'));
        await _safe(manifest.path);
        final names = <String>{};
        // Recover a truncated manifest from the strictly named files in this
        // dead, exclusively leased application-owned session directory.
        if (await manifest.exists() && await manifest.length() <= 1024 * 1024) {
          try {
            final data = jsonDecode(await manifest.readAsString());
            if (data is Map && data['version'] == 1 && data['files'] is List) {
              for (final name in data['files'] as List) {
                if (name is String && _cacheName(name)) names.add(name);
              }
            }
          } catch (_) {}
        }
        await for (final file in entity.list(followLinks: false)) {
          if (file is File && _cacheName(p.basename(file.path))) {
            names.add(p.basename(file.path));
          }
        }
        final remaining = <String>[];
        for (final name in names) {
          final file = File(p.join(entity.path, name));
          try {
            await _safe(file.path);
            if (await file.exists()) await _removeFile(file);
          } catch (_) {
            remaining.add(name);
          }
        }
        await manifest.writeAsString(
          jsonEncode({'version': 1, 'files': remaining}),
          flush: true,
        );
      } catch (_) {
        /* Other owner, sharing violation or unknown manifest. */
      } finally {
        if (lease != null) {
          try {
            await lease.close();
          } catch (_) {}
        }
      }
    }
    final session = Directory(p.join(root.path, const Uuid().v4()));
    await session.create();
    _session = session;
    _lease = await File(
      p.join(session.path, 'owner.lease'),
    ).open(mode: FileMode.append);
    await _lease!.lock(FileLock.exclusive);
    await _manifest();
  }

  static bool _uuid(String name) => RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  ).hasMatch(name);
  static bool _cacheName(String name) =>
      RegExp(r'^[0-9a-f-]{36}\.(pending|[a-z0-9]{1,12})$').hasMatch(name);
  static Future<void> _safe(String path) async {
    var current = p.normalize(p.absolute(path));
    while (true) {
      final type = await FileSystemEntity.type(current, followLinks: false);
      if (type == FileSystemEntityType.link) {
        throw const FileSystemException('Linked cache path refused.');
      }
      final parent = p.dirname(current);
      if (parent == current) break;
      current = parent;
    }
  }

  Future<void> _manifest() {
    final writing = _manifestTail.then((_) async {
      if (_session == null) return;
      final file = File(p.join(_session!.path, 'cleanup.json'));
      await _safe(file.path);
      await file.writeAsString(
        jsonEncode({
          'version': 1,
          'files': _ownedFiles.map(p.basename).toList(),
        }),
        flush: true,
      );
    });
    _manifestTail = writing.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return writing;
  }

  Future<OperationResult<CachedAttachmentFile>> prepare(
    NoteReference reference,
    AttachmentModel attachment,
    int credentialGeneration, {
    String? password,
    FileByteProgress? onProgress,
  }) {
    if (_closed) {
      return Future.value(
        const OperationResult.failure(
          OperationOutcome.cancelled,
          'Attachment cache is closing.',
        ),
      );
    }
    final key = keyFor(reference, attachment.id, credentialGeneration);
    final previous = _preparing[key];
    if (previous != null) return previous.result;
    final operation = _Preparation(_noteKey(reference));
    _preparing[key] = operation;
    operation.result =
        _prepare(
          key,
          operation,
          reference,
          attachment,
          password,
          onProgress,
        ).whenComplete(() {
          if (identical(_preparing[key], operation)) _preparing.remove(key);
        });
    return operation.result;
  }

  Future<OperationResult<CachedAttachmentFile>> _prepare(
    String key,
    _Preparation operation,
    NoteReference reference,
    AttachmentModel attachment,
    String? password,
    FileByteProgress? progress,
  ) async {
    String? candidate;
    final policy = performance?.call() ?? AttachmentPerformance.defaults;
    try {
      await initialize();
      if (operation.cancelled || _closed) return _cancelled();
      final cached = _entries[key];
      if (cached != null) {
        await _safe(cached.file.path);
        final file = await File(cached.file.path).stat();
        final source = sourceValidator == null
            ? await File(cached.source.path).stat()
            : null;
        final sourceCurrent = sourceValidator == null
            ? source!.type == FileSystemEntityType.file &&
                  source.size == cached.source.length &&
                  source.modified == cached.sourceModified
            : await sourceValidator!(reference, attachment.id, cached.source);
        if ((!policy.checkBeforeOpen || cached.checkedSource) &&
            (!policy.verifyAfterOpen || cached.verifiedOutput) &&
            file.type == FileSystemEntityType.file &&
            file.size == cached.file.length &&
            file.modified == cached.cachedModified &&
            sourceCurrent) {
          return OperationResult.success(cached.file);
        }
        _entries.remove(key);
        await _removeOwned(cached.file.path);
      }
      progress?.call(
        policy.checkBeforeOpen ? 'Preparing' : 'Queued',
        0,
        attachment.size,
      );
      final source = sourcePreparer == null
          ? await sourceResolver(reference, attachment.id)
          : await sourcePreparer!(
              reference,
              attachment.id,
              onProgress: progress,
              cancellation: operation.readCancellation,
              verifyContent: policy.checkBeforeOpen,
            );
      final sourceStat = await File(source.path).stat();
      if (policy.checkBeforeOpen && source.sha256Hex == null) {
        throw const FormatException('A checked source digest is required.');
      }
      if (operation.cancelled || _closed) return _cancelled();
      final id = const Uuid().v4();
      candidate = p.join(_session!.path, '$id.pending');
      _ownedFiles.add(candidate);
      await _manifest(); // Receipt before creating any plaintext.
      var request = FileTransformRequest(
        source: source,
        destination: candidate,
        decryptSource: true,
        encryptDestination: false,
        sourcePassword: password,
        verifyOutput: policy.verifyAfterOpen,
        // Windows cache files already have a manifest owner and exclusive
        // creation. They are never adopted into library publication. Preserve
        // its existing open path, including valid short-name directory aliases.
        ownedTarget: Platform.isWindows
            ? null
            : OwnedWriteTarget.forPath(candidate),
        requireWholeSource: true,
        // Legacy entries may have size=0 meaning unknown rather than empty.
        expectedPlaintextBytes: attachment.size > 0 ? attachment.size : null,
      );
      transformCount++;
      progress?.call('Queued', 0, attachment.size);
      operation.transform = _worker.submit(request, onProgress: progress);
      var result = await operation.transform!.result;
      if (!result.isSuccess &&
          result.outcome == OperationOutcome.rejectedInput &&
          password != null &&
          !operation.cancelled &&
          !_closed) {
        await _removeOwned(candidate);
        candidate = p.join(_session!.path, '${const Uuid().v4()}.pending');
        _ownedFiles.add(candidate);
        await _manifest();
        request = FileTransformRequest(
          source: source,
          destination: candidate,
          decryptSource: true,
          encryptDestination: false,
          verifyOutput: policy.verifyAfterOpen,
          ownedTarget: Platform.isWindows
              ? null
              : OwnedWriteTarget.forPath(candidate),
          requireWholeSource: true,
          expectedPlaintextBytes: attachment.size > 0 ? attachment.size : null,
        );
        transformCount++;
        operation.transform = _worker.submit(request, onProgress: progress);
        result = await operation.transform!.result;
      }
      if (operation.cancelled || _closed) return _cancelled();
      if (!result.isSuccess) {
        return OperationResult.failure(
          result.outcome,
          'Attachment decryption could not be completed.',
        );
      }
      var extension = p
          .extension(attachment.fileName)
          .replaceFirst('.', '')
          .toLowerCase();
      if (!RegExp(r'^[a-z0-9]{1,12}$').hasMatch(extension)) extension = 'bin';
      final ready = p.join(_session!.path, '${const Uuid().v4()}.$extension');
      _ownedFiles.add(ready);
      await _manifest();
      await _safe(candidate);
      await File(candidate).rename(ready);
      _ownedFiles.remove(candidate);
      candidate = ready;
      await _manifest();
      if (operation.cancelled || _closed) return _cancelled();
      final completed = CachedAttachmentFile(ready, result.value!.length, key);
      final stat = await File(ready).stat();
      _entries[key] = _Entry(
        operation.note,
        completed,
        source,
        sourceStat.modified,
        stat.modified,
        policy.checkBeforeOpen,
        policy.verifyAfterOpen,
      );
      candidate = null;
      return OperationResult.success(completed);
    } catch (_) {
      if (operation.cancelled || _closed) return _cancelled();
      return const OperationResult.failure(
        OperationOutcome.ioFailure,
        'Attachment cache preparation failed.',
      );
    } finally {
      if (candidate != null) await _removeOwned(candidate);
    }
  }

  OperationResult<CachedAttachmentFile> _cancelled() =>
      const OperationResult.failure(
        OperationOutcome.cancelled,
        'Attachment opening cancelled.',
      );
  Future<void> cancel(
    NoteReference reference,
    String id,
    int credential,
  ) async {
    final job = _preparing[keyFor(reference, id, credential)];
    if (job == null) return;
    job.cancelled = true;
    job.readCancellation.cancel();
    await job.transform?.cancel();
    await job.result;
  }

  Future<void> _removeOwned(String path) async {
    if (_session == null ||
        !p.isWithin(_session!.path, path) ||
        !_ownedFiles.contains(path)) {
      return;
    }
    try {
      await _safe(path);
      final file = File(path);
      if (await file.exists()) await _removeFile(file);
      _ownedFiles.remove(path);
    } catch (_) {
      /* Sharing violation: retained manifest, retry next startup. */
    }
    try {
      await _manifest();
    } catch (_) {
      /* Original receipt retains failed cleanup paths. */
    }
  }

  Future<CacheCleanupResult> invalidateNote(NoteReference reference) async {
    final note = _noteKey(reference);
    final jobs = _preparing.values.where((job) => job.note == note).toList();
    for (final job in jobs) {
      job.cancelled = true;
      job.readCancellation.cancel();
      await job.transform?.cancel();
    }
    final paths = _entries.values
        .where((entry) => entry.note == note)
        .map((entry) => entry.file.path)
        .toList();
    _entries.removeWhere((_, entry) => entry.note == note);
    await Future.wait(jobs.map((job) => job.result));
    for (final path in paths) {
      await _removeOwned(path);
    }
    return CacheCleanupResult(paths.where(_ownedFiles.contains).length);
  }

  Future<CacheCleanupResult> close() => _closing ??= _close();
  Future<CacheCleanupResult> _close() async {
    _closed = true;
    try {
      await _initialization;
    } catch (_) {}
    final jobs = _preparing.values.toList();
    for (final job in jobs) {
      job.cancelled = true;
      job.readCancellation.cancel();
      await job.transform?.cancel();
    }
    _entries.clear();
    await Future.wait(jobs.map((job) => job.result));
    await _worker.close();
    for (final path in _ownedFiles.toList()) {
      await _removeOwned(path);
    }
    await _lease?.close();
    _lease = null;
    return CacheCleanupResult(_ownedFiles.length);
  }
}
