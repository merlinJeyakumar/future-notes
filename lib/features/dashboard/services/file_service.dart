import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:universal_html/html.dart' as html;
import 'package:uuid/uuid.dart';
import 'settings_service.dart';

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
  final SettingsService _settings = SettingsService();

  @override
  Future<FilePickerResult?> pickFile({List<String>? allowedExtensions}) async {
    return await FilePicker.platform.pickFiles(
      type: allowedExtensions != null ? FileType.custom : FileType.any,
      allowedExtensions: allowedExtensions,
    );
  }

  @override
  Future<String> saveAttachment(Uint8List data, String noteId) async {
    if (kIsWeb) return "";

    final attachmentsFolderPath = await _settings.getAttachmentsFolderPath(
      noteId,
    );
    final attachmentsDir = Directory(attachmentsFolderPath);
    if (!await attachmentsDir.exists()) {
      await attachmentsDir.create(recursive: true);
    }

    final attachmentId = const Uuid().v4();
    final filePath = await _settings.getAttachmentFilePath(
      noteId,
      attachmentId,
    );
    final file = File(filePath);
    await file.writeAsBytes(data);

    return attachmentId;
  }

  @override
  Future<Uint8List?> readAttachment(String noteId, String attachmentId) async {
    if (kIsWeb) return null;
    try {
      final filePath = await _settings.getAttachmentFilePath(
        noteId,
        attachmentId,
      );
      final file = File(filePath);

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
      final userDataPath = await _settings.getUserDataPath();
      final userDataDir = Directory(userDataPath);
      if (!await userDataDir.exists()) {
        await userDataDir.create(recursive: true);
      }

      final file = File('$userDataPath/$fileName');
      await file.writeAsString(content);
    }
  }

  @override
  Future<void> saveNoteContent(String noteId, String content) async {
    if (kIsWeb) return;

    final noteFolderPath = await _settings.getNoteFolderPath(noteId);
    final noteDir = Directory(noteFolderPath);
    if (!await noteDir.exists()) {
      await noteDir.create(recursive: true);
    }

    final noteFilePath = await _settings.getNoteFilePath(noteId);
    final file = File(noteFilePath);
    await file.writeAsString(content);
    print('Saved note to: ${file.path}');
  }

  @override
  Stream<void> watchRecentFiles() async* {
    if (kIsWeb) return;
    final userDataPath = await _settings.getUserDataPath();
    final userDataDir = Directory(userDataPath);

    if (await userDataDir.exists()) {
      yield* userDataDir.watch(events: FileSystemEvent.all);
    }
  }

  @override
  Future<List<String>> getRecentFiles() async {
    if (kIsWeb) return [];

    final userDataPath = await _settings.getUserDataPath();
    final userDataDir = Directory(userDataPath);
    final List<String> files = [];

    if (await userDataDir.exists()) {
      final entities = userDataDir.listSync();

      // Files directly in folder
      files.addAll(
        entities.whereType<File>().map((e) => e.uri.pathSegments.last),
      );

      // note_ folders directly in folder
      files.addAll(
        entities
            .whereType<Directory>()
            .where((d) => d.uri.pathSegments.last.startsWith('note_'))
            .map((e) => e.uri.pathSegments.last),
      );
    }
    return files;
  }

  @override
  Future<String?> readFile(String fileName) async {
    if (kIsWeb) return null;
    try {
      final basePath = await _settings.getUserDataPath();

      // Check if it's a note folder
      if (fileName.startsWith('note_')) {
        final noteId = fileName.replaceFirst('note_', '');
        final noteFilePath = await _settings.getNoteFilePath(noteId);
        final noteFile = File(noteFilePath);
        if (await noteFile.exists()) {
          return await noteFile.readAsString();
        }
      }

      // Fallback to legacy file directly in folder
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
      final basePath = await _settings.getUserDataPath();

      if (fileName.startsWith('note_')) {
        final noteId = fileName.replaceFirst('note_', '');
        final noteFolderPath = await _settings.getNoteFolderPath(noteId);
        final noteDir = Directory(noteFolderPath);
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
      final basePath = await _settings.getUserDataPath();

      if (fileName.startsWith('note_')) {
        final noteId = fileName.replaceFirst('note_', '');
        final noteFilePath = await _settings.getNoteFilePath(noteId);
        final noteFile = File(noteFilePath);
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
      if (fileName.startsWith('note_')) {
        final noteId = fileName.replaceFirst('note_', '');
        return await _settings.getNoteFolderPath(noteId);
      }
      final basePath = await _settings.getUserDataPath();
      return '$basePath/$fileName';
    } catch (e) {
      return fileName;
    }
  }

  @override
  Future<String?> importFile(PlatformFile file) async {
    if (kIsWeb) return null;
    try {
      final userDataPath = await _settings.getUserDataPath();
      final userDataDir = Directory(userDataPath);
      if (!await userDataDir.exists()) {
        await userDataDir.create(recursive: true);
      }

      final String fileName = file.name;
      final String destinationPath = '$userDataPath/$fileName';

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
      final userDataPath = await _settings.getUserDataPath();
      final userDataDir = Directory(userDataPath);
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
