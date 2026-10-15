import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../../../core/storage/storage_environment.dart';
import '../../../core/storage/owned_settings_persistence.dart';
import '../../../core/storage/storage_owner_worker.dart';
import '../../../core/operations/operation_result.dart';

enum CompressionLevel {
  high, // significant compression
  medium, // ~half size
  none, // original
}

class SettingsService {
  static final SettingsService _instance = SettingsService._internal();

  factory SettingsService() => _instance;

  SettingsService._internal()
    : _storage = const StorageEnvironment.production(),
      _storageOwner = null,
      _documentsDirectoryResolver = getApplicationDocumentsDirectory;

  /// Independent instance for injected storage and tests. Does not replace the
  /// application singleton or resolve the production Documents directory.
  SettingsService.withStorage({
    required StorageEnvironment storage,
    StorageOwner? storageOwner,
    Future<Directory> Function()? documentsDirectoryResolver,
  }) : _storage = storage,
       _storageOwner = storageOwner,
       _documentsDirectoryResolver =
           documentsDirectoryResolver ?? getApplicationDocumentsDirectory;

  StorageEnvironment _storage;
  final StorageOwner? _storageOwner;
  OwnedSettingsPersistence? _ownedPersistence;
  Map<String, dynamic> _ownedMetadata = {};
  Future<void> _settingsTail = Future.value();
  bool _persistenceClosing = false;
  Future<void>? _persistenceClose;
  final Future<Directory> Function() _documentsDirectoryResolver;
  Future<void>? _initialization;

  bool get isValidationMode => _storage.isValidation;
  StorageEnvironment get storageEnvironment => _storage;
  bool get settingsCleanupPending => _ownedPersistence?.cleanupPending ?? false;
  bool get supportsRecoverableLibrarySwitch => _storageOwner != null;

  void configureStorage(StorageEnvironment storage) {
    if (_initialization != null) {
      throw StateError(
        'Storage must be configured before settings initialization.',
      );
    }
    _storage = storage;
  }

  CompressionLevel _compressionLevel = CompressionLevel.medium;

  CompressionLevel get compressionLevel => _compressionLevel;

  String? _customDataPath;

  String? get customDataPath => _customDataPath;

  // Theme mode with reactive notifier
  ThemeMode _themeMode = ThemeMode.dark;
  final ValueNotifier<ThemeMode> themeModeNotifier = ValueNotifier(
    ThemeMode.dark,
  );

  ThemeMode get themeMode => _themeMode;
  bool _minimizeToTrayOnClose = Platform.isWindows;
  bool get minimizeToTrayOnClose => _minimizeToTrayOnClose;
  Future<void> setMinimizeToTrayOnClose(bool enabled) async {
    if (_storageOwner != null) {
      return _queueOwnedSettings(
        () => _saveOwnedSettings(minimizeToTray: enabled),
      );
    }
    final previous = _minimizeToTrayOnClose;
    _minimizeToTrayOnClose = enabled;
    try {
      await _saveSettings();
    } catch (_) {
      _minimizeToTrayOnClose = previous;
      rethrow;
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_storageOwner != null) {
      return _queueOwnedSettings(() => _saveOwnedSettings(theme: mode));
    }
    _themeMode = mode;
    themeModeNotifier.value = mode;
    await _saveSettings();
  }

  Future<void> init() {
    if (_storageOwner != null &&
        _persistenceClosing &&
        _initialization == null) {
      return Future.error(
        const SettingsPersistenceFailure(OperationOutcome.rejectedInput),
      );
    }
    return _initialization ??= _initialize();
  }

  Future<void> _initialize() async {
    await _storage.verifyConfiguredPaths();
    if (_storageOwner != null) {
      try {
        final persistence = OwnedSettingsPersistence(
          environment: _storage,
          owner: _storageOwner,
        );
        _ownedPersistence = persistence;
        final metadata = await persistence.read();
        final compression = metadata['compressionLevel'];
        final theme = metadata['themeMode'];
        final tray = metadata['minimizeToTrayOnClose'];
        if (metadata.containsKey('minimizeToTrayOnClose') && tray is! bool) {
          throw const SettingsPersistenceFailure(
            OperationOutcome.rejectedInput,
          );
        }
        _minimizeToTrayOnClose = tray as bool? ?? Platform.isWindows;
        if ((metadata.containsKey('compressionLevel') &&
                (compression is! int ||
                    compression < 0 ||
                    compression >= CompressionLevel.values.length)) ||
            (metadata.containsKey('themeMode') &&
                (theme is! int ||
                    theme < 0 ||
                    theme >= ThemeMode.values.length)) ||
            (metadata.containsKey('customDataPath') &&
                metadata['customDataPath'] != null &&
                metadata['customDataPath'] is! String)) {
          throw const SettingsPersistenceFailure(
            OperationOutcome.rejectedInput,
          );
        }
        _ownedMetadata = metadata;
        _compressionLevel = compression == null
            ? CompressionLevel.medium
            : CompressionLevel.values[compression as int];
        _themeMode = theme == null
            ? ThemeMode.dark
            : ThemeMode.values[theme as int];
        // Verified settings rollback can restore the previous selection after
        // bootstrap captured the interrupted replacement's new selection.
        // Ordinary JSON mismatches cannot broaden root capabilities.
        final storedPath = metadata['customDataPath'] as String?;
        if (_storage.isRecoverable) {
          final selected = storedPath == null || storedPath.isEmpty
              ? p.dirname(_storage.settingsFile!)
              : storedPath;
          if (!p.equals(selected, _storage.dataRoot!) &&
              persistence.settingsRestored) {
            if (_storageOwner is! LibraryStorageOwner)
              throw const SettingsPersistenceFailure(
                OperationOutcome.recoveryRequired,
              );
            final admitted = await (_storageOwner as LibraryStorageOwner)
                .admitSelectedLibrary(selected);
            if (!admitted.isSuccess)
              throw SettingsPersistenceFailure(admitted.outcome);
            await _storage.admitSelectedLibrary(selected);
          }
          _storage.validateLibraryPath(selected);
        }
        _customDataPath = _storage.isValidation ? null : storedPath;
        themeModeNotifier.value = _themeMode;
        return;
      } on SettingsPersistenceFailure {
        rethrow;
      } on ArgumentError {
        throw const SettingsPersistenceFailure(OperationOutcome.rejectedInput);
      } catch (_) {
        throw const SettingsPersistenceFailure(
          OperationOutcome.recoveryRequired,
        );
      }
    }
    await _loadSettings();
  }

  Future<void> setCompressionLevel(CompressionLevel level) async {
    if (_storageOwner != null) {
      return _queueOwnedSettings(() => _saveOwnedSettings(compression: level));
    }
    _compressionLevel = level;
    await _saveSettings();
  }

  Future<void> setCustomDataPath(String? path) async {
    if (_storageOwner != null) {
      return _queueOwnedSettings(() async {
        final candidate = path == null
            ? null
            : _storage.validateLibraryPath(path);
        if (candidate != null) {
          await _storage.verifyLocation(candidate);
        }
        await _saveOwnedSettings(path: candidate, changesPath: true);
      });
    }
    final candidate = path == null ? null : _storage.validateLibraryPath(path);
    if (candidate != null) await _storage.verifyLocation(candidate);
    _customDataPath = candidate;
    await _saveSettings();
  }

  /// The coordinator has prepared recovery and watching before entering here.
  /// Refuse the legacy direct writer; this path is not enabled on real storage.
  Future<void> commitLibraryPath(
    String path, {
    required String expectedRoot,
    required bool Function() canCommit,
  }) {
    if (!supportsRecoverableLibrarySwitch) {
      return Future.error(
        const SettingsPersistenceFailure(OperationOutcome.rejectedInput),
      );
    }
    return _queueOwnedSettings(() async {
      final candidate = _storage.validateLibraryPath(path);
      await _storage.verifyLocation(candidate);
      if (!p.equals(await getUserDataPath(), expectedRoot)) {
        throw const SettingsPersistenceFailure(OperationOutcome.conflict);
      }
      if (!canCommit()) {
        throw const SettingsPersistenceFailure(OperationOutcome.conflict);
      }
      await _saveOwnedSettings(path: candidate, changesPath: true);
    });
  }

  Future<void> _queueOwnedSettings(Future<void> Function() action) {
    if (_persistenceClosing) {
      return Future.error(
        const SettingsPersistenceFailure(OperationOutcome.rejectedInput),
      );
    }
    final mutation = _settingsTail.then((_) async {
      // Accepted requests may initialize even if close was requested before
      // this queued action began. Close waits for this queue before releasing.
      await (_initialization ??= _initialize());
      try {
        await action();
      } on SettingsPersistenceFailure {
        rethrow;
      } on ArgumentError {
        throw const SettingsPersistenceFailure(OperationOutcome.rejectedInput);
      } catch (_) {
        throw const SettingsPersistenceFailure(OperationOutcome.ioFailure);
      }
    });
    _settingsTail = mutation.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {},
    );
    return mutation;
  }

  Future<void> _saveOwnedSettings({
    ThemeMode? theme,
    CompressionLevel? compression,
    String? path,
    bool changesPath = false,
    bool? minimizeToTray,
  }) async {
    final candidateTheme = theme ?? _themeMode;
    final candidateCompression = compression ?? _compressionLevel;
    final candidatePath = changesPath ? path : _customDataPath;
    final candidate = <String, dynamic>{
      ..._ownedMetadata,
      'compressionLevel': candidateCompression.index,
      'customDataPath': candidatePath,
      'themeMode': candidateTheme.index,
      'minimizeToTrayOnClose': minimizeToTray ?? _minimizeToTrayOnClose,
    };
    await _ownedPersistence!.write(candidate);
    _ownedMetadata = candidate;
    _compressionLevel = candidateCompression;
    _customDataPath = candidatePath;
    _themeMode = candidateTheme;
    _minimizeToTrayOnClose = minimizeToTray ?? _minimizeToTrayOnClose;
    themeModeNotifier.value = candidateTheme;
  }

  /// Release only this service's settings root after accepted mutations. The
  /// injected worker and theme notifier belong to their respective callers.
  Future<void> closePersistence() => _persistenceClose ??= _closePersistence();

  Future<void> _closePersistence() async {
    _persistenceClosing = true;
    await _settingsTail;
    try {
      await _initialization;
    } catch (_) {
      // A failed initialization can still have acquired a settings root.
    }
    try {
      await _ownedPersistence?.close();
    } catch (_) {
      _persistenceClose = null;
      rethrow;
    }
  }

  /// Returns the effective path for storing user data.
  /// If a custom path is set, returns that.
  /// Otherwise, returns '[Documents]/UserData'.
  Future<String> getUserDataPath() async {
    if (_storage.hasOwnedStorage) {
      final location = _customDataPath ?? _storage.dataRoot!;
      await _storage.verifyLocation(location);
      return location;
    }
    if (_customDataPath != null && _customDataPath!.isNotEmpty) {
      return _customDataPath!;
    }
    final directory = await _documentsDirectoryResolver();
    return '${directory.path}/UserData';
  }

  Future<String> getSettingsFilePath() async {
    if (_storage.hasOwnedStorage) {
      await _storage.verifyLocation(_storage.settingsFile!);
      return _storage.settingsFile!;
    }
    final directory = await _documentsDirectoryResolver();
    return p.join(directory.path, 'UserData', 'settings.json');
  }

  Future<String> getLibraryFilePath(String relativePath) async {
    final basePath = await getUserDataPath();
    final target = _storage.libraryChild(basePath, relativePath);
    await _storage.verifyLocation(target);
    return target;
  }

  /// Checks an already-captured location without resolving mutable settings.
  Future<void> verifyStoragePath(String path) => _storage.verifyLocation(path);

  // ========== Centralized Path Helpers ==========

  /// Returns the folder path for a note: $basePath/note_$noteId
  Future<String> getNoteFolderPath(String noteId) async {
    return getLibraryFilePath('note_$noteId');
  }

  /// Returns the content file path for a note: $basePath/note_$noteId/note_content_$noteId.enc
  Future<String> getNoteFilePath(String noteId) async {
    return getLibraryFilePath('note_$noteId/note_content_$noteId.enc');
  }

  /// Returns the attachments folder for a note: $basePath/note_$noteId/attachments
  Future<String> getAttachmentsFolderPath(String noteId) async {
    return getLibraryFilePath('note_$noteId/attachments');
  }

  /// Returns the file path for an attachment: $basePath/note_$noteId/attachments/$attachmentId.med
  Future<String> getAttachmentFilePath(
    String noteId,
    String attachmentId,
  ) async {
    return getLibraryFilePath('note_$noteId/attachments/$attachmentId.med');
  }

  Future<void> _loadSettings() async {
    try {
      final file = File(await getSettingsFilePath());
      if (await file.exists()) {
        final content = await file.readAsString();
        final Map<String, dynamic> json = jsonDecode(content);
        if (json.containsKey('compressionLevel')) {
          _compressionLevel = CompressionLevel.values[json['compressionLevel']];
        }
        // Explicit validation input takes precedence over a copied settings
        // file. Its stored custom path must not redirect this run.
        if (!_storage.isValidation && json.containsKey('customDataPath')) {
          _customDataPath = json['customDataPath'];
        }
        if (json.containsKey('themeMode')) {
          final index = json['themeMode'] as int;
          if (index >= 0 && index < ThemeMode.values.length) {
            _themeMode = ThemeMode.values[index];
            themeModeNotifier.value = _themeMode;
          }
        }
        if (json['minimizeToTrayOnClose'] is bool) {
          _minimizeToTrayOnClose = json['minimizeToTrayOnClose'] as bool;
        }
      }
    } catch (e) {
      debugPrint('Settings could not be loaded; defaults retained.');
    }
  }

  Future<void> _saveSettings() async {
    try {
      final file = File(await getSettingsFilePath());
      final folder = file.parent;
      if (!await folder.exists()) {
        await folder.create(recursive: true);
      }

      final json = {
        'compressionLevel': _compressionLevel.index,
        'customDataPath': _customDataPath,
        'themeMode': _themeMode.index,
        'minimizeToTrayOnClose': _minimizeToTrayOnClose,
      };

      await file.writeAsString(jsonEncode(json));
    } catch (e) {
      debugPrint('Settings could not be saved.');
    }
  }
}
