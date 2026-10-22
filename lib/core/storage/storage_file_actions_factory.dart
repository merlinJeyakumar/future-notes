import 'dart:io';
import 'desktop_posix_file_actions.dart';
import 'posix_file_actions.dart';
import 'storage_environment.dart';
import 'windows_file_actions.dart';

StorageFileActions storageFileActions({
  required String root,
  required StorageEnvironment environment,
}) {
  if (Platform.isWindows)
    return WindowsFileActions(root: root, environment: environment);
  if (Platform.isMacOS || Platform.isLinux)
    return DesktopPosixFileActions(root: root, environment: environment);
  if (Platform.isAndroid || Platform.isIOS) return PosixFileActions(root);
  throw UnsupportedError('Native publication is unavailable on this host.');
}
