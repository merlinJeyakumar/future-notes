import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';
import 'package:universal_html/html.dart' as html;

abstract class IFileService {
  Future<FilePickerResult?> pickFile({List<String>? allowedExtensions});
  Future<void> saveFile(String content, String fileName);
  Future<List<String>> getRecentFiles();
  Future<String?> readFile(String fileName);
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
      if (!await userDataDir.exists()) {
        await userDataDir.create(recursive: true);
      }
      final file = File('${userDataDir.path}/$fileName');
      await file.writeAsString(content);
      print('Saved to: ${file.path}');
    }
  }

  @override
  Stream<void> watchRecentFiles() async* {
    if (kIsWeb) return;

    final directory = await getApplicationDocumentsDirectory();
    final userDataDir = Directory('${directory.path}/UserData');

    if (await userDataDir.exists()) {
      yield* userDataDir.watch(events: FileSystemEvent.all).where((event) {
        return event.path.endsWith('.enc');
      });
    }
  }

  @override
  Future<List<String>> getRecentFiles() async {
    if (kIsWeb) {
      // Web doesn't support directory listing like this easily without backend or specific API
      return [];
    } else {
      final directory = await getApplicationDocumentsDirectory();
      final userDataDir = Directory('${directory.path}/UserData');
      if (await userDataDir.exists()) {
        final List<FileSystemEntity> entities = userDataDir.listSync();
        return entities
            .whereType<File>()
            .map((e) => e.uri.pathSegments.last)
            .toList();
      }
      return [];
    }
  }

  @override
  Future<String?> readFile(String fileName) async {
    if (kIsWeb) {
      return null;
    } else {
      try {
        final directory = await getApplicationDocumentsDirectory();
        final file = File('${directory.path}/UserData/$fileName');
        if (await file.exists()) {
          return await file.readAsString();
        }
      } catch (e) {
        print("Error reading file: $e");
      }
      return null;
    }
  }

  @override
  Future<void> deleteFile(String fileName) async {
    if (kIsWeb) return; // Not supported directly
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/UserData/$fileName');
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
      final file = File('${directory.path}/UserData/$fileName');
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
      return '${directory.path}/UserData';
    } catch (e) {
      return '';
    }
  }
}
