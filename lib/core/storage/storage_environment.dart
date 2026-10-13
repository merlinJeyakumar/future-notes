import 'dart:io';

import 'package:path/path.dart' as p;

/// Captured storage locations for native ownership and isolated validation.
///
/// Production keeps its existing Documents/UserData locations. Validation
/// configuration is checked before any settings or library I/O; an incomplete
/// configuration must never fall back to production storage.
class StorageEnvironment {
  const StorageEnvironment.production()
    : validationRoot = null,
      dataRoot = null,
      settingsFile = null;

  StorageEnvironment._recoverable({
    required this.dataRoot,
    required this.settingsFile,
  }) : validationRoot = null;

  /// Preview admission is explicit; never infer or relocate an existing library.
  /// Default builds retain the previous writer until rollout validation passes.
  factory StorageEnvironment.recoverable({
    required String dataRoot,
    required String settingsFile,
  }) {
    final library = _absolutePath(dataRoot);
    final settings = _absolutePath(settingsFile);
    final configuration = p.dirname(settings);
    if (p.equals(library, p.rootPrefix(library)) ||
        p.equals(configuration, p.rootPrefix(configuration)) ||
        p.equals(library, settings) ||
        p.basename(settings) != 'settings.json' ||
        p.split(library).any((part) => part.startsWith('.future-notes-'))) {
      throw ArgumentError(
        'Explicit library and settings locations are required.',
      );
    }
    // The original layout can put settings.json in the library itself. Separate
    // roots must be disjoint to avoid two leases covering overlapping trees.
    if (!p.equals(library, configuration) &&
        (p.isWithin(library, configuration) ||
            p.isWithin(configuration, library))) {
      throw ArgumentError('Storage roots must be identical or disjoint.');
    }
    return StorageEnvironment._recoverable(
      dataRoot: library,
      settingsFile: settings,
    );
  }

  StorageEnvironment._validation({
    required this.validationRoot,
    required this.dataRoot,
    required this.settingsFile,
  });

  factory StorageEnvironment.validation({
    required String validationRoot,
    required String dataRoot,
    required String settingsFile,
  }) {
    final root = _absolutePath(validationRoot);
    if (!p.basename(root).startsWith('future-notes-validation-') ||
        p.basename(root) == 'future-notes-validation-') {
      throw ArgumentError('Validation root must identify a disposable run.');
    }
    final library = _absolutePath(dataRoot);
    final settings = _absolutePath(settingsFile);
    if (!p.isWithin(root, library) || !p.isWithin(root, settings)) {
      throw ArgumentError('Validation locations must be inside the run root.');
    }
    if (p.equals(library, settings) || p.isWithin(library, settings)) {
      throw ArgumentError('Validation settings must be outside the library.');
    }
    return StorageEnvironment._validation(
      validationRoot: root,
      dataRoot: library,
      settingsFile: settings,
    );
  }

  factory StorageEnvironment.fromDefines() {
    return StorageEnvironment.fromValues(
      mode: const String.fromEnvironment('FN_VALIDATION_MODE'),
      recoverableMode: const String.fromEnvironment('FN_RECOVERABLE_STORAGE'),
      validationRoot: const String.fromEnvironment('FN_VALIDATION_ROOT'),
      dataRoot: const String.fromEnvironment('FN_DATA_ROOT'),
      settingsFile: const String.fromEnvironment('FN_SETTINGS_PATH'),
    );
  }

  factory StorageEnvironment.fromValues({
    String mode = '',
    String recoverableMode = '',
    String validationRoot = '',
    String dataRoot = '',
    String settingsFile = '',
  }) {
    if (recoverableMode != '' &&
        recoverableMode != 'false' &&
        recoverableMode != 'true') {
      throw ArgumentError('FN_RECOVERABLE_STORAGE must be true or false.');
    }
    if (recoverableMode == 'true') {
      if ((mode != '' && mode != 'false') || validationRoot.isNotEmpty) {
        throw ArgumentError(
          'Recovery preview cannot bypass validation isolation.',
        );
      }
      return StorageEnvironment.recoverable(
        dataRoot: dataRoot,
        settingsFile: settingsFile,
      );
    }
    if (mode == 'true') {
      return StorageEnvironment.validation(
        validationRoot: validationRoot,
        dataRoot: dataRoot,
        settingsFile: settingsFile,
      );
    }
    if (mode != '' && mode != 'false') {
      throw ArgumentError('FN_VALIDATION_MODE must be true or false.');
    }
    if (validationRoot.isNotEmpty ||
        dataRoot.isNotEmpty ||
        settingsFile.isNotEmpty) {
      throw ArgumentError(
        'Explicit validation locations require validation mode.',
      );
    }
    return const StorageEnvironment.production();
  }

  final String? validationRoot;
  final String? dataRoot;
  final String? settingsFile;

  bool get isValidation => validationRoot != null;
  bool get isRecoverable => !isValidation && dataRoot != null;
  bool get hasOwnedStorage => isValidation || isRecoverable;

  String get operationRoot => isValidation
      ? validationRoot!
      : p.join(p.dirname(settingsFile!), '.future-notes-storage', 'sources');

  /// Opening a new root is a capability decision, not just a containment check.
  bool permitsOwnerRoot(String value) {
    if (!hasOwnedStorage ||
        !p.isAbsolute(value) ||
        p.split(value).contains('..')) {
      return false;
    }
    final root = p.normalize(value);
    return isValidation
        ? p.isWithin(validationRoot!, root)
        : p.equals(root, dataRoot!) || p.equals(root, p.dirname(settingsFile!));
  }

  static String _absolutePath(String value) {
    if (value.isEmpty ||
        !p.isAbsolute(value) ||
        p.split(value).contains('..')) {
      throw ArgumentError(
        'An absolute location without parent traversal is required.',
      );
    }
    return p.normalize(value);
  }

  /// Checks a candidate library without creating or reading any note files.
  String validateLibraryPath(String value) {
    if (isRecoverable) {
      final candidate = _absolutePath(value);
      if (!p.equals(candidate, dataRoot!)) {
        throw ArgumentError(
          'Opening another library requires its own rollout review.',
        );
      }
      return candidate;
    }
    if (!isValidation) return value;
    final candidate = _absolutePath(value);
    if (!p.isWithin(validationRoot!, candidate) ||
        p.equals(candidate, settingsFile!) ||
        p.isWithin(candidate, settingsFile!)) {
      throw ArgumentError(
        'Validation library must remain inside the run root.',
      );
    }
    return candidate;
  }

  /// Resolves a library-relative path before native services access it.
  String libraryChild(String libraryRoot, String relativePath) {
    final target = p.normalize(p.join(libraryRoot, relativePath));
    if (hasOwnedStorage &&
        (p.isAbsolute(relativePath) ||
            p.split(relativePath).contains('..') ||
            !p.isWithin(libraryRoot, target))) {
      throw ArgumentError('Validation file must remain inside its library.');
    }
    return target;
  }

  Future<void> verifyConfiguredPaths() async {
    if (!hasOwnedStorage) return;
    if (isValidation) {
      await verifyLocation(validationRoot!, allowRunRoot: true);
    }
    await verifyLocation(dataRoot!);
    await verifyLocation(settingsFile!);
  }

  /// Refuse existing symlinks/junctions rather than following them outside an
  /// isolated run. This check is not a defense against hostile concurrent
  /// filesystem replacement; cooperating writer ownership is added separately.
  Future<void> verifyLocation(String value, {bool allowRunRoot = false}) async {
    if (!hasOwnedStorage) return;
    final target = _absolutePath(value);
    final permitted = isValidation
        ? (allowRunRoot && p.equals(validationRoot!, target)) ||
              p.isWithin(validationRoot!, target)
        : p.equals(dataRoot!, target) ||
              p.isWithin(dataRoot!, target) ||
              p.equals(p.dirname(settingsFile!), target) ||
              p.isWithin(p.dirname(settingsFile!), target);
    if (!permitted) {
      throw ArgumentError(
        'Storage access must remain inside its captured roots.',
      );
    }
    var cursor = target;
    while (true) {
      final type = await FileSystemEntity.type(cursor, followLinks: false);
      if (type == FileSystemEntityType.link) {
        throw StateError(
          'Validation locations cannot traverse filesystem links.',
        );
      }
      final parent = p.dirname(cursor);
      if (p.equals(parent, cursor)) break;
      cursor = parent;
    }
  }
}
