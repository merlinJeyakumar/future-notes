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
        await _processRecentFiles(
          message.directoryPath,
          encryptionService,
          sendPort,
        );
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

class _FileCandidate {
  final FileSystemEntity entity;
  final DateTime modified;
  final bool isFolder;

  _FileCandidate(this.entity, this.modified, {required this.isFolder});
}

Future<void> _processRecentFiles(
  String directoryPath,
  EncryptionService encryptionService,
  SendPort sendPort,
) async {
  final directory = Directory(directoryPath);
  if (!directory.existsSync()) {
    sendPort.send(<RecentFile>[]);
    return;
  }

  final List<FileSystemEntity> entities = directory.listSync();
  final List<_FileCandidate> candidates = [];

  // 1. Collect candidates and get stats (fast)
  for (final entity in entities) {
    try {
      if (entity is File) {
        final fileName = _extractName(entity.path);
        if (fileName.startsWith('.')) continue; // Skip hidden
        if (fileName == 'settings.json') continue; // Skip settings file

        candidates.add(
          _FileCandidate(entity, entity.statSync().modified, isFolder: false),
        );
      } else if (entity is Directory) {
        final folderName = _extractName(entity.path);
        if (folderName.startsWith('note_')) {
          final noteId = folderName.replaceFirst('note_', '');
          final metaFile = File('${entity.path}/note_content_$noteId.enc');
          if (metaFile.existsSync()) {
            candidates.add(
              _FileCandidate(
                metaFile, // Use the content file for processing
                metaFile.statSync().modified,
                isFolder: true,
              ),
            );
          }
        }
      }
    } catch (e) {
      // Ignore stat errors
    }
  }

  // 2. Sort by modified desc (Newest first)
  candidates.sort((a, b) => b.modified.compareTo(a.modified));

  // 3. Process and stream
  List<RecentFile> loadedFiles = [];
  int processedCount = 0;

  // Batches: Send first 10, then next 40, then remainder
  final batchSizes = [10, 40];
  int currentBatchIndex = 0;
  int nextUpdateAt = batchSizes[0];

  for (final candidate in candidates) {
    try {
      final parsed = await _parseFile(
        candidate.entity as File,
        encryptionService,
        overridePath: candidate.isFolder
            ? _extractName(candidate.entity.parent.path)
            : null,
      );

      if (parsed != null) {
        loadedFiles.add(parsed);
      }
    } catch (e) {
      // Skip error
    }

    processedCount++;

    // Send update if we hit a batch boundary
    if (processedCount >= nextUpdateAt) {
      sendPort.send(List<RecentFile>.from(loadedFiles));

      currentBatchIndex++;
      if (currentBatchIndex < batchSizes.length) {
        nextUpdateAt += batchSizes[currentBatchIndex];
      } else {
        // Update every 50 sorted files thereafter
        nextUpdateAt += 50;
      }
    }
  }

  // Final update
  sendPort.send(loadedFiles);
}

/// Parses a file and returns a RecentFile if it's a valid app note.
/// Returns null if the file is not a recognized note format.
Future<RecentFile?> _parseFile(
  File file,
  EncryptionService encryptionService, {
  String? overridePath,
}) async {
  String displayTitle = overridePath ?? _extractName(file.path);
  bool isLocked = false;
  DateTime? created;
  DateTime? modified;
  int? sizeBytes;
  bool isValidNote = false;

  final effectivePath = overridePath ?? _extractName(file.path);

  try {
    final stat = file.statSync();
    modified = stat.modified;
    sizeBytes = stat.size;

    final content = await file.readAsString();
    if (content.isNotEmpty) {
      // Try App Decryption first (New .enc format)
      try {
        // Use sync version since we're already in an isolate (compute doesn't work inside isolates)
        final appDecrypted = EncryptionService.decryptAppSync(content);
        if (appDecrypted.isNotEmpty) {
          // It's a valid app-encrypted file
          try {
            final jsonMap = json.decode(appDecrypted);
            if (jsonMap is Map<String, dynamic> &&
                jsonMap.containsKey('title') &&
                jsonMap.containsKey('content') &&
                jsonMap.containsKey('timestamp')) {
              final note = NoteModel.fromJson(jsonMap);
              if (note.title.isNotEmpty) {
                displayTitle = note.title;
              }
              isLocked = note.isLocked;
              created = DateTime.fromMillisecondsSinceEpoch(note.timestamp);
              isValidNote = true;
            }
          } catch (_) {
            // Valid app encryption but invalid JSON inside
          }
        }
      } catch (e) {
        // Not app encrypted, maybe legacy JSON?
        // Fallback: Check if it's plaintext JSON with note structure
        try {
          final jsonMap = json.decode(content);
          if (jsonMap is Map<String, dynamic> &&
              jsonMap.containsKey('title') &&
              jsonMap.containsKey('content') &&
              jsonMap.containsKey('timestamp')) {
            final note = NoteModel.fromJson(jsonMap);
            displayTitle = note.title;
            isLocked = note.isLocked;
            created = DateTime.fromMillisecondsSinceEpoch(note.timestamp);
            isValidNote = true;
          }
        } catch (_) {
          // Not a valid note file
        }
      }
    }
  } catch (e) {
    // Error parsing file - not a valid note
  }

  // Only return if this is a confirmed valid note
  if (!isValidNote) {
    return null;
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
