import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';
import 'package:universal_html/html.dart' as html;
import 'package:uuid/uuid.dart';

abstract class IFileService {
  Future<FilePickerResult?> pickFile({List<String>? allowedExtensions});
  Future<void> saveFile(String content, String fileName);
  Future<void> saveNoteContent(String noteId, String content);
  Future<String> saveAttachment(Uint8List data, String noteId);
  Future<List<String>> getRecentFiles();
  Future<String?> readFile(String fileName);
  Future<Uint8List?> readAttachment(String noteId, String attachmentId);
  Future<void> deleteFile(String fileName);
  Future<FileStat?> getFileStats(String fileName);
  Future<String> getFullPath(String fileName);
  Future<String?> importFile(PlatformFile file);
  Stream<void> watchRecentFiles();
  Future<String> getUserDataPath();
}

class FileService implements IFileService {
  @override
  Future<FilePickerResult?> pickFile({List<String>? allowedExtensions}) async {
    return await FilePicker.platform.pickFiles(
      type: allowedExtensions != null ? FileType.custom : FileType.any,
      allowedExtensions: allowedExtensions,
    );
  }

  @override
  Future<String> saveAttachment(Uint8List data, String noteId) async {
    if (kIsWeb) return ""; // Not supported

    final directory = await getApplicationDocumentsDirectory();
    final attachmentsDir = Directory(
      '${directory.path}/UserData/notes/note_$noteId/attachments',
    );
    if (!await attachmentsDir.exists()) {
      await attachmentsDir.create(recursive: true);
    }

    final attachmentId = const Uuid().v4();
    final file = File('${attachmentsDir.path}/$attachmentId.med');
    await file.writeAsBytes(data);

    return attachmentId;
  }

  @override
  Future<Uint8List?> readAttachment(String noteId, String attachmentId) async {
    if (kIsWeb) return null;
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File(
        '${directory.path}/UserData/notes/note_$noteId/attachments/$attachmentId.med',
      );

      if (await file.exists()) {
        return await file.readAsBytes();
      }
    } catch (e) {
      print("Error reading attachment: $e");
    }
    return null;
  }

  @override
  Future<void> saveFile(String content, String fileName) async {
    if (kIsWeb) {
      final bytes = utf8.encode(content);
      final blob = html.Blob([bytes]);
      final url = html.Url.createObjectUrlFromBlob(blob);
      html.AnchorElement(href: url)
        ..setAttribute("download", fileName)
        ..click();
      html.Url.revokeObjectUrl(url);
    } else {
      final directory = await getApplicationDocumentsDirectory();
      final userDataDir = Directory('${directory.path}/UserData');
      if (!await userDataDir.exists())
        await userDataDir.create(recursive: true);

      final file = File('${userDataDir.path}/$fileName');
      await file.writeAsString(content);
    }
  }

  Future<void> saveNoteContent(String noteId, String content) async {
    if (kIsWeb) return;
    final directory = await getApplicationDocumentsDirectory();
    final noteDir = Directory('${directory.path}/UserData/notes/note_$noteId');
    if (!await noteDir.exists()) {
      await noteDir.create(recursive: true);
    }
    // Encoded filename with ID
    final file = File('${noteDir.path}/note_content_$noteId.enc');
    await file.writeAsString(content);
    print('Saved note to: ${file.path}');
  }

  @override
  Stream<void> watchRecentFiles() async* {
    if (kIsWeb) return;
    final directory = await getApplicationDocumentsDirectory();
    final userDataDir = Directory('${directory.path}/UserData');

    // Watch root UserData for legacy files
    if (await userDataDir.exists()) {
      yield* userDataDir.watch(events: FileSystemEvent.all);
    }

    // Watch notes directory
    final notesDir = Directory('${userDataDir.path}/notes');
    if (await notesDir.exists()) {
      yield* notesDir.watch(events: FileSystemEvent.all);
    }
  }

  @override
  Future<List<String>> getRecentFiles() async {
    if (kIsWeb) return [];

    final directory = await getApplicationDocumentsDirectory();
    final userDataDir = Directory('${directory.path}/UserData');
    final List<String> files = [];

    if (await userDataDir.exists()) {
      // 1. Legacy Files
      final legacyEntities = userDataDir.listSync();
      files.addAll(
        legacyEntities.whereType<File>().map((e) => e.uri.pathSegments.last),
      );

      // 2. New Note Folders
      final notesDir = Directory('${userDataDir.path}/notes');
      if (await notesDir.exists()) {
        final noteFolders = notesDir.listSync();
        files.addAll(
          noteFolders.whereType<Directory>().map(
            (e) => e.uri.pathSegments.last,
          ),
        ); // e.g., "note_123"
      }
    }
    return files;
  }

  @override
  Future<String?> readFile(String fileName) async {
    if (kIsWeb) return null;
    try {
      final directory = await getApplicationDocumentsDirectory();
      final basePath = '${directory.path}/UserData';

      // Check if it's a new style note folder
      if (fileName.startsWith('note_')) {
        final noteId = fileName.replaceFirst('note_', '');
        final noteFile = File(
          '$basePath/notes/$fileName/note_content_$noteId.enc',
        );
        if (await noteFile.exists()) {
          return await noteFile.readAsString();
        }
      }

      // Fallback to legacy file
      final file = File('$basePath/$fileName');
      if (await file.exists()) {
        return await file.readAsString();
      }
    } catch (e) {
      print("Error reading file: $e");
    }
    return null;
  }

  @override
  Future<void> deleteFile(String fileName) async {
    if (kIsWeb) return;
    try {
      final directory = await getApplicationDocumentsDirectory();
      final basePath = '${directory.path}/UserData';

      if (fileName.startsWith('note_')) {
        final noteDir = Directory('$basePath/notes/$fileName');
        if (await noteDir.exists()) {
          await noteDir.delete(recursive: true);
          print("Deleted note folder: ${noteDir.path}");
          return;
        }
      }

      final file = File('$basePath/$fileName');
      if (await file.exists()) {
        await file.delete();
        print("Deleted file: ${file.path}");
      }
    } catch (e) {
      print("Error deleting file: $e");
    }
  }

  @override
  Future<FileStat?> getFileStats(String fileName) async {
    if (kIsWeb) return null;
    try {
      final directory = await getApplicationDocumentsDirectory();
      final basePath = '${directory.path}/UserData';

      if (fileName.startsWith('note_')) {
        final noteId = fileName.replaceFirst('note_', '');
        final noteFile = File(
          '$basePath/notes/$fileName/note_content_$noteId.enc',
        );
        if (await noteFile.exists()) return await noteFile.stat();
      }

      final file = File('$basePath/$fileName');
      if (await file.exists()) {
        return await file.stat();
      }
    } catch (e) {
      print("Error getting stats: $e");
    }
    return null;
  }

  @override
  Future<String> getFullPath(String fileName) async {
    if (kIsWeb) return fileName;
    try {
      final directory = await getApplicationDocumentsDirectory();
      if (fileName.startsWith('note_')) {
        // Return path to the folder or the meta file?
        // Sidebar uses this for "Show in folder".
        // For a bundle, usually showing the folder is better.
        return '${directory.path}/UserData/notes/$fileName';
      }
      return '${directory.path}/UserData/$fileName';
    } catch (e) {
      return fileName;
    }
  }

  @override
  Future<String?> importFile(PlatformFile file) async {
    if (kIsWeb) return null;
    try {
      final directory = await getApplicationDocumentsDirectory();
      final userDataDir = Directory('${directory.path}/UserData');
      if (!await userDataDir.exists()) {
        await userDataDir.create(recursive: true);
      }

      // Generate unique name if collision? For now overwrite or strict name?
      // User request: "move that file to the app storage"
      // Let's keep original name but sanitize?
      // Or just copy.
      final String fileName = file.name;
      final String destinationPath = '${userDataDir.path}/$fileName';

      // Copy source to destination
      // PlatformFile has 'path' on IO (except web which we handled)
      if (file.path != null) {
        await File(file.path!).copy(destinationPath);
        print("Imported file to: $destinationPath");
        return fileName;
      }
    } catch (e) {
      print("Error importing file: $e");
    }
    return null;
  }

  @override
  Future<String> getUserDataPath() async {
    if (kIsWeb) return '';
    try {
      final directory = await getApplicationDocumentsDirectory();
      final userDataDir = Directory('${directory.path}/UserData');
      if (!await userDataDir.exists()) {
        await userDataDir.create(recursive: true);
        print("Created UserData directory at: ${userDataDir.path}");
      }
      return userDataDir.path;
    } catch (e) {
      return '';
    }
  }
}
