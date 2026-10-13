import 'dart:io';

import 'package:path/path.dart' as p;

/// Explicit storage locations for disposable native validation runs.
///
/// Production keeps its existing Documents/UserData locations. Validation
/// configuration is checked before any settings or library I/O; an incomplete
/// configuration must never fall back to production storage.
class StorageEnvironment {
  const StorageEnvironment.production()
    : validationRoot = null,
      dataRoot = null,
      settingsFile = null;

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
      validationRoot: const String.fromEnvironment('FN_VALIDATION_ROOT'),
      dataRoot: const String.fromEnvironment('FN_DATA_ROOT'),
      settingsFile: const String.fromEnvironment('FN_SETTINGS_PATH'),
    );
  }

  factory StorageEnvironment.fromValues({
    String mode = '',
    String validationRoot = '',
    String dataRoot = '',
    String settingsFile = '',
  }) {
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
    if (isValidation &&
        (p.isAbsolute(relativePath) ||
            p.split(relativePath).contains('..') ||
            !p.isWithin(libraryRoot, target))) {
      throw ArgumentError('Validation file must remain inside its library.');
    }
    return target;
  }

  Future<void> verifyConfiguredPaths() async {
    if (!isValidation) return;
    await verifyLocation(validationRoot!, allowRunRoot: true);
    await verifyLocation(dataRoot!);
    await verifyLocation(settingsFile!);
  }

  /// Refuse existing symlinks/junctions rather than following them outside an
  /// isolated run. This check is not a defense against hostile concurrent
  /// filesystem replacement; cooperating writer ownership is added separately.
  Future<void> verifyLocation(String value, {bool allowRunRoot = false}) async {
    if (!isValidation) return;
    final target = _absolutePath(value);
    if (!(allowRunRoot && p.equals(validationRoot!, target)) &&
        !p.isWithin(validationRoot!, target)) {
      throw ArgumentError('Validation access must remain inside the run root.');
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
