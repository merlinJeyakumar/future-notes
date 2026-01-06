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

  Future<void> init() async {
    await _loadSettings();
  }

  Future<void> setCompressionLevel(CompressionLevel level) async {
    _compressionLevel = level;
    await _saveSettings();
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

      final json = {'compressionLevel': _compressionLevel.index};

      await file.writeAsString(jsonEncode(json));
    } catch (e) {
      print("Error saving settings: $e");
    }
  }
}
