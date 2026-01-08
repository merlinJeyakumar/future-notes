import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

enum CompressionLevel {
  high, // significant compression
  medium, // ~half size
  none, // original
}

class SettingsService {
  static final SettingsService _instance = SettingsService._internal();

  factory SettingsService() => _instance;

  SettingsService._internal();

  CompressionLevel _compressionLevel = CompressionLevel.medium;

  CompressionLevel get compressionLevel => _compressionLevel;

  String? _customDataPath;

  String? get customDataPath => _customDataPath;

  Future<void> init() async {
    await _loadSettings();
  }

  Future<void> setCompressionLevel(CompressionLevel level) async {
    _compressionLevel = level;
    await _saveSettings();
  }

  Future<void> setCustomDataPath(String? path) async {
    _customDataPath = path;
    await _saveSettings();
  }

  /// Returns the effective path for storing user data.
  /// If a custom path is set, returns that.
  /// Otherwise, returns '[Documents]/UserData'.
  Future<String> getUserDataPath() async {
    if (_customDataPath != null && _customDataPath!.isNotEmpty) {
      return _customDataPath!;
    }
    final directory = await getApplicationDocumentsDirectory();
    return '${directory.path}/UserData';
  }

  // ========== Centralized Path Helpers ==========

  /// Returns the folder path for a note: $basePath/note_$noteId
  Future<String> getNoteFolderPath(String noteId) async {
    final basePath = await getUserDataPath();
    return '$basePath/note_$noteId';
  }

  /// Returns the content file path for a note: $basePath/note_$noteId/note_content_$noteId.enc
  Future<String> getNoteFilePath(String noteId) async {
    final folderPath = await getNoteFolderPath(noteId);
    return '$folderPath/note_content_$noteId.enc';
  }

  /// Returns the attachments folder for a note: $basePath/note_$noteId/attachments
  Future<String> getAttachmentsFolderPath(String noteId) async {
    final folderPath = await getNoteFolderPath(noteId);
    return '$folderPath/attachments';
  }

  /// Returns the file path for an attachment: $basePath/note_$noteId/attachments/$attachmentId.med
  Future<String> getAttachmentFilePath(
    String noteId,
    String attachmentId,
  ) async {
    final attachmentsPath = await getAttachmentsFolderPath(noteId);
    return '$attachmentsPath/$attachmentId.med';
  }

  Future<void> _loadSettings() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/UserData/settings.json');
      if (await file.exists()) {
        final content = await file.readAsString();
        final Map<String, dynamic> json = jsonDecode(content);
        if (json.containsKey('compressionLevel')) {
          _compressionLevel = CompressionLevel.values[json['compressionLevel']];
        }
        if (json.containsKey('customDataPath')) {
          _customDataPath = json['customDataPath'];
        }
      }
    } catch (e) {
      print("Error loading settings: $e");
    }
  }

  Future<void> _saveSettings() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final folder = Directory('${directory.path}/UserData');
      if (!await folder.exists()) {
        await folder.create(recursive: true);
      }
      final file = File('${directory.path}/UserData/settings.json');

      final json = {
        'compressionLevel': _compressionLevel.index,
        'customDataPath': _customDataPath,
      };

      await file.writeAsString(jsonEncode(json));
    } catch (e) {
      print("Error saving settings: $e");
    }
  }
}
