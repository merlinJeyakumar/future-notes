import 'dart:io';
import 'dart:ui';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'attachment_batch_export.dart';

/// Exports stream into a new private candidate, then enter the native share/
/// Save-to-Files flow. No entire package is passed through a platform message.
class MobileExport {
  static final _owned = <String>{};
  static Future<String> destination(String fileName) async {
    final temporary = await getTemporaryDirectory();
    // Android/iOS may expose the app cache through an OS directory alias.
    // Resolve the trusted platform root before allocating children; downstream
    // revision/publication checks still reject links in export paths.
    final root = Directory(await temporary.resolveSymbolicLinks());
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
