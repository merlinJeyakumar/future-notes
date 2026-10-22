import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart' as p;

import '../../../core/operations/operation_result.dart';
import '../../../core/storage/storage_environment.dart';

import '../models/note_model.dart';
import 'encryption_service.dart';
import 'note_codec.dart';

class BackgroundWorkerStart {
  const BackgroundWorkerStart(this.replies, this.environment);
  final SendPort replies;
  final StorageEnvironment environment;
}

typedef BackgroundWorkerLauncher =
    Future<Isolate> Function(
      BackgroundWorkerStart start,
      SendPort exits,
      SendPort errors,
    );

class BackgroundServiceFailure implements Exception {
  const BackgroundServiceFailure(this.outcome);
  final OperationOutcome outcome;
  @override
  String toString() => 'Discovery worker failed (${outcome.name}).';
}

/// Read-only discovery messages carry both root and request ownership.
class DiscoveryRequest {
  const DiscoveryRequest(
    this.directoryPath,
    this.rootGeneration,
    this.requestId,
  );
  final String directoryPath;
  final int rootGeneration;
  final int requestId;

  bool matches(DiscoveryRequest other) =>
      directoryPath == other.directoryPath &&
      rootGeneration == other.rootGeneration &&
      requestId == other.requestId;
}

/// Copies already-admitted roots into the read-only worker at dispatch time.
/// The worker still verifies the requested location before reading it.
class _ScopedDiscoveryRequest extends DiscoveryRequest {
  _ScopedDiscoveryRequest(DiscoveryRequest request, this.environment)
    : super(request.directoryPath, request.rootGeneration, request.requestId);
  final StorageEnvironment environment;
}

class DiscoverySnapshot {
  DiscoverySnapshot(
    this.request,
    List<RecentFile> files, {
    required this.isFinal,
  }) : files = List<RecentFile>.unmodifiable(files);
  final DiscoveryRequest request;
  final List<RecentFile> files;
  final bool isFinal;
}

class DiscoveryScanFailure {
  const DiscoveryScanFailure(this.request);
  final DiscoveryRequest request;
}

class DiscoveryFailureEvent {
  const DiscoveryFailureEvent(this.result, {this.request});
  final DiscoveryRequest? request;
  final OperationResult<void> result;
}

abstract interface class LibraryDiscovery {
  bool get isReady;
  DiscoveryRequest? get requestedScan;
  Stream<DiscoverySnapshot> get discoveriesStream;
  Stream<DiscoveryFailureEvent> get failuresStream;
  bool isCurrent(DiscoveryRequest request);
  Future<void> init();
  void invalidateRequests();
  void loadRecentFiles(String directoryPath);
  void dispose();
}

/// Provider hints may be broad (including resume). Reconcile cheap envelope
/// metadata in the background; explicit Refresh requests a fresh decode.
abstract interface class MetadataLibraryDiscovery implements LibraryDiscovery {
  void invalidateMetadataCache();
}

class BackgroundService implements LibraryDiscovery {
  BackgroundService({
    StorageEnvironment environment = const StorageEnvironment.production(),
    BackgroundWorkerLauncher? launcher,
    Duration startupTimeout = const Duration(seconds: 10),
    bool? refreshStorageContext,
  }) : _environment = environment,
       _launcher = launcher ?? _launch,
       _startupTimeout = startupTimeout,
       // Keep accepted other-platform discovery messages unchanged. Mac folder
       // grants can be admitted after this worker has started.
       _refreshStorageContext =
           refreshStorageContext ?? (!kIsWeb && Platform.isMacOS) {
    _receivePort.listen(_receive);
  }

  final StorageEnvironment _environment;
  final BackgroundWorkerLauncher _launcher;
  final Duration _startupTimeout;
  final bool _refreshStorageContext;
  Isolate? _isolate;
  SendPort? _sendPort;
  final ReceivePort _receivePort = ReceivePort();
  final _discoveries = StreamController<DiscoverySnapshot>.broadcast();
  final _errors = StreamController<OperationResult<void>>.broadcast();
  final _failures = StreamController<DiscoveryFailureEvent>.broadcast();
  final _ready = Completer<OperationResult<void>>();
  Future<void>? _initialization;
  bool _disposed = false;
  OperationOutcome? _failure;
  DiscoveryRequest? _active;
  DiscoveryRequest? _pending;
  DiscoveryRequest? _desired;
  String? _root;
  int _rootGeneration = 0;
  int _nextRequest = 0;

  bool get isReady => !_disposed && _failure == null && _sendPort != null;
  Stream<OperationResult<void>> get errorsStream => _errors.stream;
  Stream<DiscoveryFailureEvent> get failuresStream => _failures.stream;
  DiscoveryRequest? get requestedScan => _desired;

  Stream<DiscoverySnapshot> get discoveriesStream => _discoveries.stream;
  Stream<List<RecentFile>> get recentFilesStream =>
      discoveriesStream.map((snapshot) => snapshot.files);

  bool isCurrent(DiscoveryRequest request) =>
      isReady && _desired != null && _desired!.matches(request);

  Future<void> init() {
    if (_disposed || _failure != null) {
      return Future.error(
        BackgroundServiceFailure(
          _disposed ? OperationOutcome.cancelled : _failure!,
        ),
      );
    }
    return _initialization ??= _initialize();
  }

  Future<void> _initialize() async {
    try {
      if (_startupTimeout <= Duration.zero) {
        throw const BackgroundServiceFailure(OperationOutcome.rejectedInput);
      }
      final launching =
          _launcher(
            BackgroundWorkerStart(_receivePort.sendPort, _environment),
            _receivePort.sendPort,
            _receivePort.sendPort,
          ).then((created) {
            _isolate = created;
            if (_disposed || _failure != null) {
              created.kill(priority: Isolate.immediate);
            }
            return created;
          });
      await Future.wait<Object?>([
        launching,
        _ready.future,
      ], eagerError: true).timeout(_startupTimeout);
      final ready = await _ready.future;
      if (!ready.isSuccess || !isReady) {
        throw BackgroundServiceFailure(
          ready.isSuccess ? OperationOutcome.ioFailure : ready.outcome,
        );
      }
    } on BackgroundServiceFailure catch (failure) {
      _fail(failure.outcome);
      rethrow;
    } catch (_) {
      _fail(OperationOutcome.ioFailure);
      throw const BackgroundServiceFailure(OperationOutcome.ioFailure);
    }
  }

  static Future<Isolate> _launch(
    BackgroundWorkerStart start,
    SendPort exits,
    SendPort errors,
  ) => Isolate.spawn(
    workerEntry,
    start,
    onExit: exits,
    onError: errors,
    errorsAreFatal: true,
    debugName: 'future-notes-discovery',
  );

  void _receive(dynamic message) {
    if (_disposed || _failure != null) {
      return;
    }
    if (message is SendPort && _sendPort == null) {
      _sendPort = message;
      _ready.complete(const OperationResult.success());
    } else if (message is DiscoverySnapshot && isReady) {
      if (_active == null || !_active!.matches(message.request)) {
        return;
      }
      if (isCurrent(message.request)) {
        _discoveries.add(message);
      }
      if (message.isFinal) {
        _finishScan();
      }
    } else if (message is DiscoveryScanFailure && isReady) {
      if (_active == null || !_active!.matches(message.request)) {
        return;
      }
      if (isCurrent(message.request)) {
        _failures.add(
          DiscoveryFailureEvent(
            const OperationResult.failure(
              OperationOutcome.ioFailure,
              'The library scan failed. Retry refresh.',
            ),
            request: message.request,
          ),
        );
        _errors.add(
          const OperationResult.failure(
            OperationOutcome.ioFailure,
            'The library scan failed. Retry refresh.',
          ),
        );
      }
      _finishScan();
    } else {
      _fail(OperationOutcome.ioFailure);
    }
  }

  void _fail(OperationOutcome outcome) {
    if (_failure != null) {
      return;
    }
    _failure = outcome;
    _sendPort = null;
    invalidateRequests();
    _active = null;
    if (!_ready.isCompleted) {
      _ready.complete(
        OperationResult.failure(outcome, 'Discovery is unavailable.'),
      );
    }
    if (!_disposed) {
      _failures.add(
        DiscoveryFailureEvent(
          OperationResult.failure(outcome, 'Discovery is unavailable.'),
        ),
      );
      _errors.add(
        OperationResult.failure(outcome, 'Discovery is unavailable.'),
      );
    }
    _receivePort.close();
    // This isolate is a read-only scanner; it owns no writer lease or commits.
    _isolate?.kill(priority: Isolate.immediate);
  }

  /// Invalidate publication immediately, before asynchronous root resolution.
  void invalidateRequests() {
    _desired = null;
    _pending = null;
  }

  void _finishScan() {
    _active = null;
    _dispatchPending();
  }

  void _dispatchPending() {
    if (!isReady || _active != null || _pending == null) {
      return;
    }
    _active = _pending;
    _pending = null;
    _sendPort!.send(
      _refreshStorageContext
          ? _ScopedDiscoveryRequest(_active!, _environment)
          : _active!,
    );
  }

  void loadRecentFiles(String directoryPath) {
    if (!isReady) {
      throw BackgroundServiceFailure(
        _disposed
            ? OperationOutcome.cancelled
            : _failure ?? OperationOutcome.rejectedInput,
      );
    }
    if (!p.isAbsolute(directoryPath) || p.split(directoryPath).contains('..')) {
      throw const BackgroundServiceFailure(OperationOutcome.rejectedInput);
    }
    final root = p.normalize(directoryPath);
    if (_root != root) {
      _root = root;
      _rootGeneration++;
    }
    final request = DiscoveryRequest(root, _rootGeneration, ++_nextRequest);
    _desired = request;
    // One active descriptor and only the latest pending descriptor.
    _pending = request;
    _dispatchPending();
  }

  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _fail(OperationOutcome.cancelled);
    _discoveries.close();
    _errors.close();
    _failures.close();
  }

  /// Read-only worker entry, also exposed for deterministic test launchers.
  static void workerEntry(BackgroundWorkerStart start) async {
    await start.environment.verifyConfiguredPaths();
    final commands = ReceivePort();
    start.replies.send(commands.sendPort);
    DiscoveryRequest? pending;
    var running = false;
    Future<void> drain() async {
      running = true;
      while (pending != null) {
        final request = pending!;
        pending = null;
        try {
          final environment = request is _ScopedDiscoveryRequest
              ? request.environment
              : start.environment;
          if (environment.dataRoot != start.environment.dataRoot ||
              environment.settingsFile != start.environment.settingsFile ||
              environment.validationRoot != start.environment.validationRoot) {
            throw const FormatException('Discovery storage context changed.');
          }
          await environment.verifyLocation(request.directoryPath);
          await _processRecentFiles(request, start.replies);
        } catch (_) {
          start.replies.send(DiscoveryScanFailure(request));
        }
      }
      running = false;
    }

    commands.listen((message) {
      if (message is DiscoveryRequest) {
        pending = message;
        if (!running) {
          unawaited(drain());
        }
      }
    });
  }
}

// --- Isolate Logic ---

/// Extracts the folder/file name from a path, handling both Windows and Unix separators.
String _extractName(String path) {
  final pathParts = path.split(RegExp(r'[/\\]'));
  return pathParts.where((p) => p.isNotEmpty).last;
}

class _FileCandidate {
  final FileSystemEntity entity;
  final DateTime modified;
  final bool isFolder;

  _FileCandidate(this.entity, this.modified, {required this.isFolder});
}

Future<void> _processRecentFiles(
  DiscoveryRequest request,
  SendPort sendPort,
) async {
  final directory = Directory(request.directoryPath);
  if (!directory.existsSync()) {
    sendPort.send(DiscoverySnapshot(request, const [], isFinal: true));
    return;
  }

  final List<FileSystemEntity> entities = directory.listSync(
    followLinks: false,
  );
  final List<_FileCandidate> candidates = [];

  // 1. Collect candidates and get stats (fast)
  for (final entity in entities) {
    try {
      if (entity is File) {
        final fileName = _extractName(entity.path);
        if (fileName.startsWith('.')) continue; // Skip hidden
        if (fileName == 'settings.json') continue; // Skip settings file

        candidates.add(
          _FileCandidate(entity, entity.statSync().modified, isFolder: false),
        );
      } else if (entity is Directory) {
        final folderName = _extractName(entity.path);
        if (folderName.startsWith('note_')) {
          final noteId = folderName.replaceFirst('note_', '');
          final metaFile = File('${entity.path}/note_content_$noteId.enc');
          if (FileSystemEntity.typeSync(metaFile.path, followLinks: false) ==
              FileSystemEntityType.file) {
            candidates.add(
              _FileCandidate(
                metaFile, // Use the content file for processing
                metaFile.statSync().modified,
                isFolder: true,
              ),
            );
          }
        }
      }
    } catch (e) {
      // Ignore stat errors
    }
  }

  // 2. Sort by modified desc (Newest first)
  candidates.sort((a, b) => b.modified.compareTo(a.modified));

  // A small initial batch and one final snapshot, never cumulative repeats.
  final List<RecentFile> loadedFiles = [];
  int processedCount = 0;
  bool initialSent = false;

  for (final candidate in candidates) {
    try {
      final parsed = await readRecentNote(
        candidate.entity as File,
        overridePath: candidate.isFolder
            ? _extractName(candidate.entity.parent.path)
            : null,
      );

      if (parsed != null) {
        loadedFiles.add(parsed);
      }
    } catch (e) {
      // Skip error
    }

    processedCount++;

    if (!initialSent &&
        loadedFiles.length == 10 &&
        processedCount < candidates.length) {
      initialSent = true;
      sendPort.send(DiscoverySnapshot(request, loadedFiles, isFinal: false));
    }
  }

  // Final update
  sendPort.send(DiscoverySnapshot(request, loadedFiles, isFinal: true));
}

/// Parses a file and returns a RecentFile if it's a valid app note.
/// Returns null if the file is not a recognized note format.
Future<RecentFile?> readRecentNote(File file, {String? overridePath}) async {
  try {
    final stat = await file.stat();
    final decoded = NoteCodec.decodeSync(
      await file.readAsString(),
      decryptApp: EncryptionService.decryptAppResultSync,
    );
    final note = decoded.note;
    final effectivePath = overridePath ?? _extractName(file.path);
    DateTime? retainedDate;
    try {
      retainedDate = DateTime.fromMillisecondsSinceEpoch(note.timestamp);
    } on RangeError {
      // The stored integer remains intact; an undisplayable date must not hide
      // an otherwise valid note from the shared inventory.
    }
    return RecentFile(
      path: effectivePath,
      fullPath: file.path,
      title: note.title.isEmpty ? effectivePath : note.title,
      noteId: note.id,
      isLocked: note.isLocked,
      created: retainedDate,
      modified: stat.modified,
      sizeBytes: stat.size,
    );
  } catch (_) {
    return null; // Invalid/unreadable objects never become editor candidates.
  }
}
