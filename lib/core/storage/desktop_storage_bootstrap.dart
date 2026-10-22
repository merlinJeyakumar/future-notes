import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';

import '../platform/macos_file_access.dart';
import 'storage_environment.dart';

class DesktopLibraryAccessRequired implements Exception {
  const DesktopLibraryAccessRequired(
    this.libraryRoot, {
    this.code = 'permission_required',
  });
  final String libraryRoot;
  final String code;
}

class DesktopStoragePlan {
  const DesktopStoragePlan(
    this.environment,
    this.libraryGrant, {
    this.changeSelection = false,
  });
  final StorageEnvironment environment;
  final MacosLibraryGrant? libraryGrant;
  final bool changeSelection;
}

/// Capture legacy locations without writing settings or inspecting note data.
/// Restoring sandbox authority never opens a consent panel automatically.
class DesktopStorageBootstrap {
  static Future<DesktopStoragePlan> resolve({
    StorageEnvironment? captured,
    Future<Directory> Function()? documentsDirectory,
    bool? requiresMacosGrant,
    MacosFileAccess access = const MacosFileAccess(),
    MacosLibraryGrant? selectedGrant,
  }) async {
    StorageEnvironment environment;
    if (captured?.hasOwnedStorage ?? false) {
      environment = captured!;
    } else {
      final documents =
          await (documentsDirectory ?? getApplicationDocumentsDirectory)();
      // Only the trusted OS documents location is canonicalized. A selected
      // folder's authority/identity must come from its native grant instead.
      final canonical = await _canonicalDocuments(documents.path);
      final settings = File(p.join(canonical, 'UserData', 'settings.json'));
      var cursor = settings.path;
      while (true) {
        if (await FileSystemEntity.type(cursor, followLinks: false) ==
            FileSystemEntityType.link) {
          throw const FormatException('Settings cannot traverse links.');
        }
        final parent = p.dirname(cursor);
        if (parent == cursor) break;
        cursor = parent;
      }
      final before = await settings.stat();
      // Read with a bound even if metadata changes while the dialog is open.
      final metadata = await _readSettings(settings);
      final after = await settings.stat();
      if (before.type != after.type ||
          before.size != after.size ||
          before.modified != after.modified ||
          before.changed != after.changed) {
        throw const FormatException('Settings changed during startup. Retry.');
      }
      final selected = metadata['customDataPath'];
      if (selected != null && selected is! String) {
        throw const FormatException('Invalid existing library selection.');
      }
      environment = StorageEnvironment.recoverable(
        dataRoot: selected is String && selected.isNotEmpty
            ? selected
            : settings.parent.path,
        settingsFile: settings.path,
      );
    }
    MacosLibraryGrant? grant;
    final mac = requiresMacosGrant ?? Platform.isMacOS;
    var changeSelection = false;
    if (mac && selectedGrant != null && !environment.isValidation) {
      // A chooser selection is explicit authority, including a folder the user
      // moved. Admit it before changing the persisted library pointer.
      changeSelection = !p.equals(selectedGrant.path, environment.dataRoot!);
      if (changeSelection) {
        environment = StorageEnvironment.recoverable(
          dataRoot: selectedGrant.path,
          settingsFile: environment.settingsFile!,
        );
      }
    }
    if (mac &&
        !environment.isValidation &&
        !p.equals(
          environment.dataRoot!,
          p.dirname(environment.settingsFile!),
        )) {
      try {
        grant =
            selectedGrant ??
            await access.restoreLibrary(expectedPath: environment.dataRoot);
        if (grant == null || !p.equals(grant.path, environment.dataRoot!)) {
          throw DesktopLibraryAccessRequired(environment.dataRoot!);
        }
      } catch (error) {
        if (grant != null && !identical(grant, selectedGrant))
          await grant.close();
        throw DesktopLibraryAccessRequired(
          environment.dataRoot!,
          code: error is PlatformException ? error.code : 'permission_required',
        );
      }
    }
    try {
      await environment.verifyConfiguredPaths();
    } catch (_) {
      if (grant != null && !identical(grant, selectedGrant))
        await grant.close();
      rethrow;
    }
    // A selected private Documents library can also carry an owner lease.
    grant ??= selectedGrant;
    return DesktopStoragePlan(
      environment,
      grant,
      changeSelection: changeSelection,
    );
  }

  static Future<String> _canonicalDocuments(String path) async {
    if (!p.isAbsolute(path) || p.split(path).contains('..'))
      throw ArgumentError('Invalid documents directory.');
    var ancestor = p.normalize(path);
    final missing = <String>[];
    while (await FileSystemEntity.type(ancestor, followLinks: false) ==
        FileSystemEntityType.notFound) {
      missing.add(p.basename(ancestor));
      final parent = p.dirname(ancestor);
      if (parent == ancestor)
        throw const FileSystemException('Documents location is unavailable.');
      ancestor = parent;
    }
    final root = await Directory(ancestor).resolveSymbolicLinks();
    return p.joinAll([root, ...missing.reversed]);
  }

  static Future<Map<String, dynamic>> _readSettings(File file) async {
    RandomAccessFile input;
    try {
      input = await file.open();
    } on FileSystemException catch (error) {
      if (error.osError?.errorCode == 2 ||
          (Platform.isWindows && error.osError?.errorCode == 3))
        return {};
      rethrow;
    }
    try {
      final bytes = await input.read(64 * 1024 + 1);
      if (bytes.length > 64 * 1024)
        throw const FormatException('Settings exceed their bound.');
      final value = jsonDecode(utf8.decode(bytes));
      if (value is! Map<String, dynamic>)
        throw const FormatException('Invalid settings.');
      return value;
    } finally {
      await input.close();
    }
  }
}
