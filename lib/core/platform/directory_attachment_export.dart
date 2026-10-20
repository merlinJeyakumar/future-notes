import 'dart:io';
import 'package:path/path.dart' as p;
import 'attachment_batch_export.dart';

/// A fresh native export folder avoids replacing unrelated user files. Each
/// attachment is written once directly into this owned destination directory.
class DirectoryAttachmentExport implements AttachmentBatchExport {
  DirectoryAttachmentExport._(this.directory);
  final Directory directory;
  final _allocated = <String>{};
  final _names = <String>{};
  bool _published = false;

  static Future<DirectoryAttachmentExport> create(String parent) async {
    final root = Directory(await Directory(parent).resolveSymbolicLinks());
    return DirectoryAttachmentExport._(
      await root.createTemp('Future Notes attachments-'),
    );
  }

  @override
  Future<String> destination(String fileName) async {
    final safe = p
        .basename(fileName.replaceAll('\\', '/'))
        .replaceAll(RegExp(r'[\x00-\x1f<>:"/\\|?*]'), '_')
        .replaceAll(RegExp(r'[. ]+$'), '');
    var base = safe.isEmpty || safe == '.' || safe == '..'
        ? 'attachment'
        : safe;
    if (RegExp(
      r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)',
      caseSensitive: false,
    ).hasMatch(base))
      base = 'Attachment - $base';
    final stem = p.basenameWithoutExtension(base);
    final extension = p.extension(base);
    var name = base;
    for (var i = 2; !_names.add(name.toLowerCase()); i++) {
      name = '$stem ($i)$extension';
    }
    final target = p.join(directory.path, name);
    if (await FileSystemEntity.type(target, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw const FileSystemException('Export destination already exists.');
    }
    _allocated.add(target);
    return target;
  }

  @override
  Future<bool> publish(List<String> paths) async {
    if (paths.length != _allocated.length || !paths.every(_allocated.contains))
      return false;
    _published = true;
    return true;
  }

  @override
  Future<void> cleanup(Iterable<String> paths) async {
    if (_published) return;
    // Never recurse through an external destination or delete unrelated files.
    for (final path in paths.where(_allocated.contains)) {
      if (p.equals(p.dirname(path), directory.path) &&
          await FileSystemEntity.type(path, followLinks: false) ==
              FileSystemEntityType.file) {
        await File(path).delete();
      }
    }
    if (await directory.exists() && await directory.list().isEmpty) {
      await directory.delete();
    }
  }
}
