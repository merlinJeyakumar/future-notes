import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import 'desktop_posix_native.dart';
import 'desktop_posix_file_actions.dart';
import 'storage_environment.dart';

/// Disposable metadata-capability probe, never a payload verification pass.
/// Admission is per actual filesystem; unsupported moves/sync fail closed.
class DesktopStorageAdmission {
  static Future<bool> verify(
    String root,
    StorageEnvironment environment,
  ) async {
    if (!DesktopPosixNative.supportedHost) return !Platform.isWindows;
    if (Platform.isLinux) await _requireLocalLinuxMount(root);
    final native = DesktopPosixNative();
    final folder = Directory(
      p.join(root, '.future-notes-admission-${const Uuid().v4()}'),
    );
    await environment.verifyLocation(folder.path);
    await folder.create();
    final source = File(p.join(folder.path, 'source'));
    final occupied = File(p.join(folder.path, 'occupied'));
    final published = File(p.join(folder.path, 'published'));
    final lock = File(p.join(folder.path, '.future-notes-probe.lock'));
    DesktopPosixLease? lease;
    var caseSensitive = true;
    try {
      await source.writeAsBytes([70, 78, 1], flush: true);
      await occupied.writeAsBytes([2], flush: true);
      // A bounded alias observation identifies the actual volume, not a guess
      // based on OS. It does not change journal object names or payload bytes.
      caseSensitive =
          await FileSystemEntity.type(
            p.join(folder.path, 'OCCUPIED'),
            followLinks: false,
          ) ==
          FileSystemEntityType.notFound;
      final conflict = native.moveWithoutReplace(source.path, occupied.path);
      if (!DesktopPosixNative.isNameConflict(conflict) ||
          !await _containsExactly(source, [70, 78, 1]) ||
          !await _containsExactly(occupied, [2])) {
        throw const FileSystemException(
          'Exclusive publication is unsupported.',
        );
      }
      final moved = await DesktopPosixFileActions(
        root: root,
        environment: environment,
        operations: native,
      ).moveWithoutReplace(source.path, published.path);
      if (!moved.isSuccess || !await _containsExactly(published, [70, 78, 1])) {
        throw const FileSystemException(
          'Recoverable publication is unsupported.',
        );
      }
      await lock.create(exclusive: true);
      lease = native.lock(lock.path);
      DesktopPosixLease? second;
      try {
        second = native.lock(lock.path);
      } on FileSystemException catch (error) {
        if (!DesktopPosixNative.isLockBusy(error.osError?.errorCode)) rethrow;
      }
      if (second != null) {
        await second.close();
        throw const FileSystemException(
          'Exclusive writer ownership is unsupported.',
        );
      }
    } finally {
      await lease?.close();
      // Only these four paths were issued by this probe. Never recursively
      // delete an unexpected object someone else added to the directory.
      for (final file in [source, occupied, published, lock]) {
        if (await FileSystemEntity.type(file.path, followLinks: false) ==
            FileSystemEntityType.file)
          await file.delete();
      }
      await folder.delete();
      native.syncDirectory(root);
    }
    return caseSensitive;
  }

  static Future<bool> _containsExactly(File file, List<int> expected) async {
    final input = await file.open();
    try {
      final bytes = await input.read(expected.length + 1);
      return bytes.length == expected.length &&
          List.generate(
            expected.length,
            (i) => bytes[i] == expected[i],
          ).every((v) => v);
    } finally {
      await input.close();
    }
  }

  static Future<void> _requireLocalLinuxMount(String root) async {
    final input = await File('/proc/self/mountinfo').open();
    final bytes = <int>[];
    try {
      while (true) {
        final chunk = await input.read(8192);
        if (chunk.isEmpty) break;
        bytes.addAll(chunk);
        if (bytes.length > 1024 * 1024)
          throw const FileSystemException('Mount inventory exceeds its bound.');
      }
    } finally {
      await input.close();
    }
    String? filesystem;
    var longest = -1;
    for (final line in utf8.decode(bytes).split('\n')) {
      final parts = line.split(' - ');
      if (parts.length != 2) continue;
      final fields = parts.first.split(' ');
      if (fields.length < 5) continue;
      final mount = fields[4].replaceAllMapped(
        RegExp(r'\\([0-7]{3})'),
        (m) => String.fromCharCode(int.parse(m[1]!, radix: 8)),
      );
      if ((p.equals(root, mount) || p.isWithin(mount, root)) &&
          mount.length > longest) {
        longest = mount.length;
        filesystem = parts.last.split(' ').first;
      }
    }
    if (!{
      'ext2',
      'ext3',
      'ext4',
      'xfs',
      'btrfs',
      'f2fs',
      'tmpfs',
      'overlay',
    }.contains(filesystem)) {
      throw const FileSystemException(
        'Select a supported local Linux filesystem.',
      );
    }
  }
}
