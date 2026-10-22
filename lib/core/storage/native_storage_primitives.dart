import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../operations/operation_result.dart';
import 'storage_environment.dart';
import 'desktop_posix_native.dart';

/// Content and filesystem identity used for optimistic conflict checks.
/// This is a checked read, not an atomic snapshot or a filesystem transaction.
class StorageRevision {
  const StorageRevision.missing()
    : length = null,
      sha256Hex = null,
      modifiedMicros = null;

  const StorageRevision.present(
    int length,
    String sha256Hex,
    int modifiedMicros,
  ) : length = length,
      sha256Hex = sha256Hex,
      modifiedMicros = modifiedMicros;

  final int? length;
  final String? sha256Hex;
  final int? modifiedMicros;
  bool get exists => sha256Hex != null;

  bool matches(StorageRevision other) =>
      length == other.length &&
      sha256Hex == other.sha256Hex &&
      modifiedMicros == other.modifiedMicros;
}

class StorageFileMetadata {
  const StorageFileMetadata(this.length, this.modifiedMicros);
  final int length;
  final int modifiedMicros;
}

/// Own this coordinator in one isolate; dispatch lease work to that owner.
/// Other/older writers may ignore locks, so commits must also check revisions.
class NativeStoragePrimitives {
  NativeStoragePrimitives(this.environment);

  final StorageEnvironment environment;
  static const ioWindow = 1024 * 1024;
  static final _localOwners = <String>{};

  /// POSIX needs directory persistence as well as a flushed file. Only newly
  /// created directories are synced; this never reads a note or attachment.
  /// Existing Windows/mobile creation semantics remain unchanged.
  Future<void> prepareParent(String location) async {
    await _verify(location);
    if (!DesktopPosixNative.supportedHost) {
      await File(location).parent.create(recursive: true);
      await _verify(location);
      return;
    }
    final missing = <String>[];
    var cursor = p.dirname(location);
    while (true) {
      final type = await FileSystemEntity.type(cursor, followLinks: false);
      if (type == FileSystemEntityType.directory) break;
      if (type != FileSystemEntityType.notFound ||
          p.dirname(cursor) == cursor) {
        throw const FileSystemException(
          'A regular storage directory is required.',
        );
      }
      await environment.verifyLocation(cursor);
      missing.add(cursor);
      cursor = p.dirname(cursor);
    }
    final native = DesktopPosixNative();
    for (final directory in missing.reversed) {
      await _verify(directory);
      await Directory(directory).create();
      await _verify(directory);
      native.syncDirectory(p.dirname(directory));
    }
    await _verify(location);
  }

  Future<void> persistParent(String location) async {
    if (!DesktopPosixNative.supportedHost) return;
    await _verify(location);
    DesktopPosixNative().syncDirectory(p.dirname(location));
  }

  Future<void> _verify(String location) async {
    if (!p.isAbsolute(location) || p.split(location).contains('..')) {
      throw ArgumentError('An absolute storage location is required.');
    }
    await environment.verifyLocation(location);
    var cursor = p.normalize(location);
    while (true) {
      if (await FileSystemEntity.type(cursor, followLinks: false) ==
          FileSystemEntityType.link) {
        throw StateError('Storage locations cannot traverse links.');
      }
      final parent = p.dirname(cursor);
      if (p.equals(parent, cursor)) break;
      cursor = parent;
    }
  }

  Future<StorageRevision> captureRevision(
    String location, {
    Future<void> Function(int bytesRead)? onChunk,
    void Function(int length)? onStart,
    void Function()? beginCompute,
    void Function()? endCompute,
  }) async {
    await _verify(location);
    final type = await FileSystemEntity.type(location, followLinks: false);
    if (type != FileSystemEntityType.file &&
        type != FileSystemEntityType.notFound) {
      throw StateError('Storage target is not a regular file.');
    }
    final file = File(location);
    final RandomAccessFile handle;
    try {
      handle = await file.open();
    } on FileSystemException catch (error) {
      // stat/exists may collapse permission failures into notFound. Only an
      // explicit OS missing-file/path result grants the missing revision.
      final code = error.osError?.errorCode;
      if (code == 2 || (Platform.isWindows && code == 3)) {
        return const StorageRevision.missing();
      }
      rethrow;
    }
    late FileStat before;
    final digest = _DigestSink();
    final input = sha256.startChunkedConversion(digest);
    var processed = 0;
    try {
      before = await file.stat();
      if (before.type != FileSystemEntityType.file) {
        throw StateError('Storage target changed before revision capture.');
      }
      onStart?.call(before.size);
      while (true) {
        final bytes = await handle.read(ioWindow);
        if (bytes.isEmpty) break;
        beginCompute?.call();
        try {
          input.add(bytes);
        } finally {
          endCompute?.call();
        }
        processed += bytes.length;
        if (onChunk != null) await onChunk(processed);
      }
      input.close();
    } finally {
      await handle.close();
    }
    await _verify(location);
    final after = await file.stat();
    if (after.type != FileSystemEntityType.file ||
        processed != before.size ||
        before.size != after.size ||
        before.modified != after.modified ||
        before.changed != after.changed) {
      throw StateError('Storage target changed during revision capture.');
    }
    return StorageRevision.present(
      processed,
      digest.value!.toString(),
      after.modified.microsecondsSinceEpoch,
    );
  }

  /// Path and file metadata only: no payload scan or writer-queue request.
  Future<StorageFileMetadata> inspectMetadata(String location) async {
    await _verify(location);
    final stat = await File(location).stat();
    if (stat.type != FileSystemEntityType.file)
      throw const FileSystemException('Attachment is unavailable.');
    return StorageFileMetadata(stat.size, stat.modified.microsecondsSinceEpoch);
  }

  Future<OperationResult<WriterLease>> acquireLease(String location) async {
    await _verify(location);
    final name = p.basename(location);
    if (!name.startsWith('.future-notes-') || !name.endsWith('.lock')) {
      return const OperationResult.failure(
        OperationOutcome.rejectedInput,
        'An app-owned lock location is required.',
      );
    }
    final normalized = p.normalize(location);
    final identity = Platform.isWindows ? normalized.toLowerCase() : normalized;
    // Reserve before any await: POSIX locks alone are per process, not per handle.
    if (!_localOwners.add(identity)) {
      return const OperationResult.failure(
        OperationOutcome.conflict,
        'Storage writer is already owned.',
      );
    }
    RandomAccessFile? handle;
    var transferred = false;
    try {
      await prepareParent(location);
      await _verify(location);
      if (DesktopPosixNative.supportedHost) {
        if (await FileSystemEntity.type(location, followLinks: false) ==
            FileSystemEntityType.notFound) {
          try {
            await File(location).create(exclusive: true);
          } on FileSystemException {
            // Another cooperating owner may have created the lock; the native
            // open-description lock below decides ownership without unlinking.
          }
        }
        await _verify(location);
        if (await FileSystemEntity.type(location, followLinks: false) !=
            FileSystemEntityType.file) {
          throw const FileSystemException('A regular lock file is required.');
        }
        final native = DesktopPosixNative().lock(location);
        transferred = true;
        return OperationResult.success(
          WriterLease._native(
            native.close,
            () => _localOwners.remove(identity),
          ),
        );
      }
      handle = await File(location).open(mode: FileMode.append);
      try {
        await handle.lock(FileLock.exclusive);
      } on FileSystemException {
        return const OperationResult.failure(
          OperationOutcome.conflict,
          'Storage writer lease is unavailable.',
        );
      }
      final lease = WriterLease._(handle, () => _localOwners.remove(identity));
      transferred = true;
      return OperationResult.success(lease);
    } on FileSystemException catch (error) {
      if (DesktopPosixNative.supportedHost &&
          DesktopPosixNative.isLockBusy(error.osError?.errorCode)) {
        return const OperationResult.failure(
          OperationOutcome.conflict,
          'Storage writer lease is unavailable.',
        );
      }
      return const OperationResult.failure(
        OperationOutcome.ioFailure,
        'Storage writer lease could not be opened.',
      );
    } finally {
      if (!transferred) {
        try {
          if (handle != null) await handle.close();
        } finally {
          _localOwners.remove(identity);
        }
      }
    }
  }
}

/// Keeps the same handle locked until explicit release. Never delete lock files:
/// unlinking them can let another writer lock a different filesystem object.
class WriterLease {
  WriterLease._(this._handle, this._releaseOwner) : _nativeClose = null;
  WriterLease._native(this._nativeClose, this._releaseOwner) : _handle = null;

  final RandomAccessFile? _handle;
  final Future<void> Function()? _nativeClose;
  final void Function() _releaseOwner;
  Future<void>? _closing;

  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    if (_nativeClose != null) {
      await _nativeClose();
      _releaseOwner();
      return;
    }
    final handle = _handle!;
    try {
      await handle.unlock();
    } finally {
      // Keep ownership reserved if closing the handle fails.
      await handle.close();
      _releaseOwner();
    }
  }
}

class _DigestSink implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) {
    value = data;
  }

  @override
  void close() {}
}
