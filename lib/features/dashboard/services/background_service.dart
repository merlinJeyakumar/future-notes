import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import '../models/note_model.dart';
import 'encryption_service.dart';

class BackgroundService {
  Isolate? _isolate;
  SendPort? _sendPort;
  final ReceivePort _receivePort = ReceivePort();
  final _recentFilesController = StreamController<List<RecentFile>>.broadcast();

  Stream<List<RecentFile>> get recentFilesStream =>
      _recentFilesController.stream;

  Future<void> init() async {
    _isolate = await Isolate.spawn(_isolateEntryPoint, _receivePort.sendPort);

    // Listen for the SendPort from the isolate or results
    _receivePort.listen((message) {
      if (message is SendPort) {
        _sendPort = message;
      } else if (message is List<RecentFile>) {
        _recentFilesController.add(message);
      } else if (message is String) {
        // Error or log from isolate
        print("[BackgroundService] Isolate: $message");
      }
    });
  }

  void loadRecentFiles(String directoryPath) {
    _sendPort?.send(_LoadRecentFilesCommand(directoryPath));
  }

  void dispose() {
    _receivePort.close();
    _isolate?.kill();
    _recentFilesController.close();
  }
}

// --- Isolate Logic ---

void _isolateEntryPoint(SendPort sendPort) {
  final receivePort = ReceivePort();
  sendPort.send(receivePort.sendPort);

  // Initialize service inside Isolate
  final encryptionService = EncryptionService();

  receivePort.listen((message) async {
    if (message is _LoadRecentFilesCommand) {
      try {
        final files = await _processRecentFiles(
          message.directoryPath,
          encryptionService,
        );
        sendPort.send(files);
      } catch (e) {
        sendPort.send("Error processing files: $e");
      }
    }
  });
}

/// Extracts the folder/file name from a path, handling both Windows and Unix separators.
String _extractName(String path) {
  final pathParts = path.split(RegExp(r'[/\\]'));
  return pathParts.where((p) => p.isNotEmpty).last;
}

Future<List<RecentFile>> _processRecentFiles(
  String directoryPath,
  EncryptionService encryptionService,
) async {
  List<RecentFile> loadedFiles = [];

  // 1. Scan Legacy Files (Root UserData)
  final directory = Directory(directoryPath);
  if (directory.existsSync()) {
    final List<FileSystemEntity> entities = directory.listSync();
    final fileFiles = entities.whereType<File>().toList();

    for (final file in fileFiles) {
      final fileName = _extractName(file.path);
      if (fileName.startsWith('.')) continue; // Skip hidden
      loadedFiles.add(await _parseFile(file, encryptionService));
    }
  }

  // 2. Scan New Note Folders in UserData/notes/ subdirectory
  final notesDir = Directory('$directoryPath/notes');
  if (notesDir.existsSync()) {
    final List<FileSystemEntity> noteEntities = notesDir.listSync();
    final noteFolders = noteEntities.whereType<Directory>().toList();

    for (final folder in noteFolders) {
      final folderName = _extractName(folder.path);

      if (folderName.startsWith('note_')) {
        final noteId = folderName.replaceFirst('note_', '');
        // Check for note_content_<id>.enc
        final metaFile = File('${folder.path}/note_content_$noteId.enc');
        if (metaFile.existsSync()) {
          loadedFiles.add(
            await _parseFile(
              metaFile,
              encryptionService,
              overridePath: folderName,
            ),
          );
        }
      }
    }
  }

  // 3. Also scan root UserData for legacy note_ folders (backward compatibility)
  if (directory.existsSync()) {
    final List<FileSystemEntity> entities = directory.listSync();
    final folders = entities.whereType<Directory>().toList();

    for (final folder in folders) {
      final folderName = _extractName(folder.path);
      if (folderName.startsWith('note_')) {
        final noteId = folderName.replaceFirst('note_', '');
        // Check for note_content_<id>.enc
        final metaFile = File('${folder.path}/note_content_$noteId.enc');
        if (metaFile.existsSync()) {
          loadedFiles.add(
            await _parseFile(
              metaFile,
              encryptionService,
              overridePath: folderName,
            ),
          );
        }
      }
    }
  }

  // 4. Sort by modified desc
  loadedFiles.sort((a, b) {
    if (a.modified == null && b.modified == null) return 0;
    if (a.modified == null) return 1;
    if (b.modified == null) return -1;
    return b.modified!.compareTo(a.modified!);
  });

  return loadedFiles;
}

Future<RecentFile> _parseFile(
  File file,
  EncryptionService encryptionService, {
  String? overridePath,
}) async {
  String displayTitle = overridePath ?? _extractName(file.path);
  bool isLocked = false;
  DateTime? created;
  DateTime? modified;
  int? sizeBytes;

  final effectivePath = overridePath ?? _extractName(file.path);

  try {
    final stat = file.statSync();
    modified = stat.modified;
    sizeBytes = stat.size;

    final content = await file.readAsString();
    if (content.isNotEmpty) {
      // Try App Decryption first (New .enc format)
      try {
        final appDecrypted = await encryptionService.decryptApp(content);
        if (appDecrypted.isNotEmpty) {
          // It's a valid app-encrypted file
          try {
            final jsonMap = json.decode(appDecrypted);
            final note = NoteModel.fromJson(jsonMap);
            if (note.title.isNotEmpty) {
              displayTitle = note.title;
            }
            isLocked = note.isLocked;
            created = DateTime.fromMillisecondsSinceEpoch(note.timestamp);
          } catch (_) {
            // Valid app encryption but invalid JSON inside?
          }
        }
      } catch (e) {
        // Not app encrypted, maybe legacy JSON or Plain Text?
        // Fallback: Check if it's plaintext JSON
        try {
          final jsonMap = json.decode(content);
          if (jsonMap is Map<String, dynamic> &&
              (jsonMap.containsKey('title') ||
                  jsonMap.containsKey('content'))) {
            final note = NoteModel.fromJson(jsonMap);
            displayTitle = note.title;
            isLocked = note.isLocked;
            created = DateTime.fromMillisecondsSinceEpoch(note.timestamp);
          }
        } catch (_) {
          // Plain text file, use filename as title
        }
      }
    }
  } catch (e) {
    // Error parsing file - silently skip
  }

  return RecentFile(
    path: effectivePath,
    fullPath: file.path,
    title: displayTitle,
    isLocked: isLocked,
    created: created,
    modified: modified,
    sizeBytes: sizeBytes,
  );
}

class _LoadRecentFilesCommand {
  final String directoryPath;
  _LoadRecentFilesCommand(this.directoryPath);
}
