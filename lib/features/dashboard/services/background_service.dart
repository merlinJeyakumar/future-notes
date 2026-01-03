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

Future<List<RecentFile>> _processRecentFiles(
  String directoryPath,
  EncryptionService encryptionService,
) async {
  final directory = Directory(directoryPath);
  if (!directory.existsSync()) return [];

  final List<FileSystemEntity> entities = directory.listSync();
  final fileFiles = entities
      .whereType<File>()
      .where((e) => e.path.endsWith('.enc'))
      .toList();

  List<RecentFile> loadedFiles = [];

  for (final file in fileFiles) {
    String displayTitle = file.uri.pathSegments.last;
    bool isLocked = false;
    DateTime? created;
    DateTime? modified;
    int? sizeBytes;

    try {
      final stat = file.statSync();
      modified = stat.modified;
      sizeBytes = stat.size;

      final content = file.readAsStringSync();
      if (content.isNotEmpty) {
        final appDecrypted = encryptionService.decryptApp(content);
        if (appDecrypted.isNotEmpty) {
          try {
            final jsonMap = json.decode(appDecrypted);
            // We can use NoteModel.fromJson but we need to be careful about imports?
            // NoteModel is in note_model.dart which we imported.
            final note = NoteModel.fromJson(jsonMap);
            if (note.title.isNotEmpty) {
              displayTitle = note.title;
            }
            isLocked = note.isLocked;
            created = DateTime.fromMillisecondsSinceEpoch(note.timestamp);
          } catch (e) {
            // Json parse error
          }
        }
      }
    } catch (e) {
      // File read error
    }

    loadedFiles.add(
      RecentFile(
        path: file.uri.pathSegments.last,
        fullPath: file.path,
        title: displayTitle,
        isLocked: isLocked,
        created: created,
        modified: modified,
        sizeBytes: sizeBytes,
      ),
    );
  }

  // Sort by modified desc
  loadedFiles.sort((a, b) {
    if (a.modified == null && b.modified == null) return 0;
    if (a.modified == null) return 1;
    if (b.modified == null) return -1;
    return b.modified!.compareTo(a.modified!);
  });

  return loadedFiles;
}

class _LoadRecentFilesCommand {
  final String directoryPath;
  _LoadRecentFilesCommand(this.directoryPath);
}
