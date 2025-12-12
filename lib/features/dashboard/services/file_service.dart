import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';
import 'package:universal_html/html.dart' as html;

abstract class IFileService {
  Future<FilePickerResult?> pickFile();
  Future<void> saveFile(String content, String fileName);
  Future<List<String>> getRecentFiles();
  Future<String?> readFile(String fileName);
}

class FileService implements IFileService {
  @override
  Future<FilePickerResult?> pickFile() async {
    return await FilePicker.platform.pickFiles();
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
}
