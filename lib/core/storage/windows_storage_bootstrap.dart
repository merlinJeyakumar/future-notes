import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'native_storage_primitives.dart';
import 'storage_environment.dart';

/// Reads only the existing configuration to capture the normal library before
/// owned settings initialization. No migration, settings write, or note access.
class WindowsStorageBootstrap {
  static Future<StorageEnvironment> resolve({
    Future<Directory> Function()? documentsDirectory,
  }) async {
    final documents =
        await (documentsDirectory ?? getApplicationDocumentsDirectory)();
    final settings = File(p.join(documents.path, 'UserData', 'settings.json'));
    final primitives = NativeStoragePrimitives(
      const StorageEnvironment.production(),
    );
    final before = await primitives.captureRevision(settings.path);
    String? selected;
    if (before.exists) {
      if (before.length! > 256 * 1024) {
        throw const FormatException('Settings metadata exceeds its bound.');
      }
      final content = jsonDecode(await settings.readAsString());
      if (content is! Map<String, dynamic> ||
          (content['customDataPath'] != null &&
              content['customDataPath'] is! String)) {
        throw const FormatException('Invalid existing settings.');
      }
      selected = content['customDataPath'] as String?;
      if (!(await primitives.captureRevision(settings.path)).matches(before)) {
        throw const FormatException('Settings changed during startup.');
      }
    }
    final environment = StorageEnvironment.recoverable(
      dataRoot: selected == null || selected.isEmpty
          ? settings.parent.path
          : selected,
      settingsFile: settings.path,
    );
    await environment.verifyConfiguredPaths();
    return environment;
  }
}
