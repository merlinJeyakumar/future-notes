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
        // Error or log
        print("[BackgroundService] Isolate Message: $message");
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

  final encryptionService = EncryptionService();

  receivePort.listen((message) async {
    if (message is _LoadRecentFilesCommand) {
      try {
        print(
          "[BackgroundService] Processing files in: ${message.directoryPath}",
        );
        final files = await _processRecentFiles(
          message.directoryPath,
          encryptionService,
        );
        print("[BackgroundService] Found ${files.length} files");
        sendPort.send(files);
      } catch (e) {
        sendPort.send("Error processing files: $e");
      }
    }
  });
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
      if (file.uri.pathSegments.last.startsWith('.')) continue; // Skip hidden

      // Skip "notes" folder if it's listed as file? No, listSync handles types.
      // But we should act defensively.

      loadedFiles.add(_parseFile(file, encryptionService));
    }
  }

  // 2. Scan New Note Folders (UserData/notes)
  final notesDir = Directory('$directoryPath/notes');
  if (notesDir.existsSync()) {
    final List<FileSystemEntity> entities = notesDir.listSync();
    final noteFolders = entities.whereType<Directory>().toList();

    for (final folder in noteFolders) {
      final folderName = folder.uri.pathSegments.last;
      if (!folderName.startsWith('note_'))
        continue; // Strict check for note folders

      final noteId = folderName.replaceFirst('note_', '');
      final metaFile = File('${folder.path}/note_content_$noteId.enc');
      if (metaFile.existsSync()) {
        // Create a RecentFile representing the folder.
        // We read the meta file for details.
        loadedFiles.add(
          _parseFile(metaFile, encryptionService, overridePath: folderName),
        );
      }
    }
  }

  // 3. Sort by modified desc
  loadedFiles.sort((a, b) {
    if (a.modified == null && b.modified == null) return 0;
    if (a.modified == null) return 1;
    if (b.modified == null) return -1;
    return b.modified!.compareTo(a.modified!);
  });

  return loadedFiles;
}

RecentFile _parseFile(
  File file,
  EncryptionService encryptionService, {
  String? overridePath,
}) {
  String displayTitle = overridePath ?? file.uri.pathSegments.last;
  bool isLocked = false;
  DateTime? created;
  DateTime? modified;
  int? sizeBytes;

  // Use overridePath (folder name) as identity if provided
  final effectivePath = overridePath ?? file.uri.pathSegments.last;

  try {
    final stat = file.statSync();
    modified = stat.modified;
    sizeBytes = stat.size;

    final content = file.readAsStringSync();
    if (content.isNotEmpty) {
      // Try App Decryption first (New .enc format)
      try {
        final appDecrypted = encryptionService.decryptApp(content);
        if (appDecrypted.isNotEmpty) {
          final jsonMap = json.decode(appDecrypted);
          final note = NoteModel.fromJson(jsonMap);
          if (note.title.isNotEmpty) {
            displayTitle = note.title;
          }
          isLocked = note.isLocked;
          created = DateTime.fromMillisecondsSinceEpoch(note.timestamp);
        }
      } catch (e) {
        // Not an encrypted app file
        // Try JSON (Legacy unencrypted)
        try {
          final jsonMap = json.decode(content);
          if (jsonMap is Map<String, dynamic> && jsonMap.containsKey('title')) {
            final note = NoteModel.fromJson(jsonMap);
            displayTitle = note.title;
            isLocked = note.isLocked;
            created = DateTime.fromMillisecondsSinceEpoch(note.timestamp);
          }
        } catch (e2) {
          // Plain text fallbacks
          final lines = content.split('\n');
          if (lines.isNotEmpty && lines.first.trim().isNotEmpty) {
            String safeTitle = lines.first.trim();
            if (safeTitle.length > 50) safeTitle = safeTitle.substring(0, 50);
            displayTitle = safeTitle;
          }
        }
      }
    }
  } catch (e) {
    // Read error
  }

  return RecentFile(
    path: effectivePath,
    fullPath: file.path, // Point to actual file read (meta or legacy)
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
