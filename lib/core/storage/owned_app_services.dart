import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path/path.dart' as p;

import '../../features/dashboard/services/file_service.dart';
import '../../features/dashboard/services/settings_service.dart';
import '../operations/operation_result.dart';
import 'storage_environment.dart';
import 'storage_owner_worker.dart';
import 'desktop_storage_host.dart';

typedef StorageOwnerStarter =
    Future<OperationResult<StorageOwner>> Function(
      StorageEnvironment environment,
    );

/// Composition for explicitly admitted Windows storage roots.
/// Keep this object alive after failed startup/close so acquired handles remain
/// available for cleanup. Unconfigured production environments are refused.
class OwnedAppServices {
  OwnedAppServices({
    required this.environment,
    StorageOwnerStarter? startOwner,
    FileService Function(SettingsService, StorageOwner)? createFiles,
    this.selectedLibraryOverride,
    this.afterLibraryAdmission,
  }) : _startOwner = startOwner ?? _startWorker,
       _createFiles = createFiles {
    if (!environment.hasOwnedStorage || !isOwnedDesktopHost) {
      throw ArgumentError(
        'Owned services require explicitly bound desktop storage.',
      );
    }
    if (selectedLibraryOverride != null &&
        (!environment.isRecoverable ||
            !p.equals(selectedLibraryOverride!, environment.dataRoot!))) {
      throw ArgumentError(
        'The startup selection must be an explicitly captured library.',
      );
    }
  }

  final StorageEnvironment environment;
  final StorageOwnerStarter _startOwner;
  final FileService Function(SettingsService, StorageOwner)? _createFiles;
  final String? selectedLibraryOverride;
  final Future<void> Function()? afterLibraryAdmission;
  StorageOwner? _owner;
  SettingsService? _settings;
  FileService? _files;
  Future<OperationResult<void>>? _initialization;
  Future<OperationResult<void>>? _closing;
  bool _closed = false;
  bool _closeRequested = false;
  bool _ready = false;

  bool get isReady => _ready && !_closeRequested;
  SettingsService get settings {
    if (!isReady) {
      throw StateError('Storage services are unavailable.');
    }
    return _settings!;
  }

  FileService get files {
    if (!isReady) {
      throw StateError('Storage services are unavailable.');
    }
    return _files!;
  }

  static Future<OperationResult<StorageOwner>> _startWorker(
    StorageEnvironment environment,
  ) async {
    final started = await StorageOwnerWorker.start(environment: environment);
    if (!started.isSuccess) {
      return OperationResult.failure(started.outcome, started.message);
    }
    return OperationResult.success(started.value!);
  }

  Future<OperationResult<void>> initialize() {
    if (_closeRequested) {
      return Future.value(
        const OperationResult.failure(
          OperationOutcome.rejectedInput,
          'Storage services are closing.',
        ),
      );
    }
    return _initialization ??= _initialize();
  }

  Future<OperationResult<void>> _initialize() async {
    try {
      await environment.verifyConfiguredPaths();
      final started = await _startOwner(environment);
      if (!started.isSuccess) {
        return OperationResult.failure(
          started.outcome,
          'Owned storage startup failed.',
        );
      }
      _owner = started.value!;
      final settings = SettingsService.withStorage(
        storage: environment,
        storageOwner: _owner,
        bootstrapLibraryRoot: selectedLibraryOverride,
        documentsDirectoryResolver: () async =>
            throw StateError('Production storage is unavailable.'),
      );
      _settings = settings;
      await settings.init();
      final files =
          _createFiles?.call(settings, _owner!) ??
          FileService(settings: settings, storageOwner: _owner);
      _files = files;
      // Acquire leases and recover both roots before the UI can start scanning.
      await files.currentLibrary();
      await afterLibraryAdmission?.call();
      if (selectedLibraryOverride != null) {
        await settings.setCustomDataPath(selectedLibraryOverride);
      }
      _ready = true;
      return const OperationResult.success();
    } catch (_) {
      return const OperationResult.failure(
        OperationOutcome.recoveryRequired,
        'Owned storage could not be prepared.',
      );
    }
  }

  Future<OperationResult<void>> close() => _closing ??= _close();

  Future<OperationResult<void>> _close() async {
    _closeRequested = true;
    await _initialization;
    if (_closed) {
      return const OperationResult.success();
    }
    var failed = false;
    final elapsed = Stopwatch()..start();
    // Independent root releases must both be attempted. Do not stop the worker
    // after partial failure: its retained ownership is needed for retry.
    try {
      debugPrint(
        'Storage shutdown: note roots at ${elapsed.elapsedMilliseconds} ms',
      );
      await _files?.closePersistence();
    } catch (_) {
      failed = true;
    }
    try {
      debugPrint(
        'Storage shutdown: settings root at ${elapsed.elapsedMilliseconds} ms',
      );
      await _settings?.closePersistence();
    } catch (_) {
      failed = true;
    }
    if (!failed) {
      try {
        debugPrint(
          'Storage shutdown: worker at ${elapsed.elapsedMilliseconds} ms',
        );
        final closed = await _owner?.close();
        failed = closed != null && !closed.isSuccess;
      } catch (_) {
        failed = true;
      }
    }
    if (failed) {
      _closing = null;
      return const OperationResult.failure(
        OperationOutcome.recoveryRequired,
        'Owned storage cleanup requires retry.',
      );
    }
    _closed = true;
    return const OperationResult.success();
  }
}
