import 'dart:io';
import 'dart:ui';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'attachment_batch_export.dart';

/// Exports stream into a new private candidate, then enter the native share/
/// Save-to-Files flow. No entire package is passed through a platform message.
class MobileExport {
  static final _owned = <String>{};
  static const _files = MethodChannel('future_notes/files');
  static bool _saving = false;
  static final _initializations = <String, Future<void>>{};

  static Future<Directory> _androidExportRoot() async {
    final path = await _files.invokeMethod<String>('exportRoot');
    if (path == null || !p.isAbsolute(path) || p.normalize(path) != path) {
      throw StateError('Private export storage is unavailable.');
    }
    return Directory(path);
  }

  static Future<void> _initializeRoot(Directory root) async {
    if (await root.resolveSymbolicLinks() != root.path) {
      throw StateError('Export storage escaped its private root.');
    }
    await _initializations.putIfAbsent(root.path, () => _removeOrphans(root));
  }

  /// Retained Android files need process-start cleanup even when the user does
  /// not start another export. Repeated app initialization shares the same pass.
  static Future<void> initialize({String? operatingSystem}) async {
    if ((operatingSystem ?? Platform.operatingSystem) != 'android') return;
    await _initializeRoot(await _androidExportRoot());
  }

  static Future<void> _removeOrphans(Directory root) async {
    await for (final item in root.list(followLinks: false)) {
      if (item is Directory &&
          p.basename(item.path).startsWith('future-notes-export-') &&
          await item.resolveSymbolicLinks() == item.path &&
          !_owned.any((path) => p.isWithin(item.path, path))) {
        await item.delete(recursive: true);
      }
    }
  }

  /// Native create-document/Files picker; bytes stay out of platform messages.
  static Future<bool> save(
    String path, {
    void Function(int, int)? onProgress,
  }) async {
    if (!_owned.contains(path) || _saving) {
      throw StateError('Export unavailable.');
    }
    _saving = true;
    _files.setMethodCallHandler((call) async {
      if (call.method == 'exportSaveProgress') {
        final args = call.arguments as Map;
        onProgress?.call(args['bytes'] as int, args['total'] as int);
      }
    });
    try {
      return await _files.invokeMethod<bool>('saveExport', {'path': path}) ??
          false;
    } finally {
      _files.setMethodCallHandler(null);
      _saving = false;
    }
  }

  static Future<bool> sharePrepared(String path) async {
    if (!_owned.contains(path)) throw StateError('Export unavailable.');
    return await _files.invokeMethod<bool>('shareExport', {'path': path}) ??
        false;
  }

  static Future<String> destination(
    String fileName, {
    String? operatingSystem,
  }) async {
    final Directory root;
    if ((operatingSystem ?? Platform.operatingSystem) == 'android') {
      // Active writes and ready exports must survive OS cache reclamation.
      // Native ownership, sharing scope and backup exclusions cover this root.
      root = await _androidExportRoot();
    } else {
      final temporary = await getTemporaryDirectory();
      // Keep the accepted iOS and desktop-test cache behavior independent.
      final cache = Directory(await temporary.resolveSymbolicLinks());
      await _initializations.putIfAbsent(
        cache.path,
        () => _removeOrphans(cache),
      );
      root = await Directory(p.join(cache.path, 'prepared-exports')).create();
    }
    await _initializeRoot(root);
    final directory = await root.createTemp('future-notes-export-');
    final name = p
        .basename(fileName)
        .replaceAll(RegExp(r'[\x00-\x1f/\\]'), '_');
    final baseName = name.isEmpty ? 'attachment' : name;
    // share_plus copies every file into one flat Android cache directory.
    // Separate source directories alone cannot protect duplicate filenames.
    final reserved = _owned
        .map((path) => p.basename(path).toLowerCase())
        .toSet();
    var uniqueName = baseName;
    for (
      var suffix = 2;
      reserved.contains(uniqueName.toLowerCase());
      suffix++
    ) {
      uniqueName =
          '${p.basenameWithoutExtension(baseName)} ($suffix)${p.extension(baseName)}';
    }
    final path = p.join(directory.path, uniqueName);
    _owned.add(path);
    return path;
  }

  static Future<void> share(String path) async {
    if (!_owned.contains(path)) throw StateError('Unowned mobile export.');
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(path)],
          sharePositionOrigin: const Rect.fromLTWH(1, 1, 1, 1),
        ),
      );
    } finally {
      _owned.remove(path);
      final file = File(path);
      if (await file.exists()) await file.delete();
      final parent = file.parent;
      if (await parent.exists() && await parent.list().isEmpty)
        await parent.delete();
    }
  }

  static Future<bool> shareAll(List<String> paths) async {
    if (paths.isEmpty ||
        paths.toSet().length != paths.length ||
        paths.any((path) => !_owned.contains(path))) {
      throw StateError('Unowned mobile export selection.');
    }
    final result = await SharePlus.instance.share(
      ShareParams(
        files: paths.map(XFile.new).toList(),
        sharePositionOrigin: const Rect.fromLTWH(1, 1, 1, 1),
      ),
    );
    return result.status != ShareResultStatus.dismissed;
  }

  static Future<void> discardAll(Iterable<String> paths) async {
    for (final path in paths.toSet()) {
      if (!_owned.contains(path)) continue;
      final file = File(path);
      if (await file.exists()) await file.delete();
      final parent = file.parent;
      if (await parent.exists() && await parent.list().isEmpty)
        await parent.delete();
      _owned.remove(path);
    }
  }
}

class MobileAttachmentBatchExport implements AttachmentBatchExport {
  const MobileAttachmentBatchExport();
  @override
  Future<String> destination(String name) => MobileExport.destination(name);
  @override
  Future<bool> publish(List<String> paths) => MobileExport.shareAll(paths);
  @override
  Future<void> cleanup(Iterable<String> paths) =>
      MobileExport.discardAll(paths);
}
