import 'dart:async';
import 'package:flutter/material.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import '../../../core/viewmodels/base_viewmodel.dart';
import '../services/file_service.dart';
import '../services/background_service.dart';
import '../services/encryption_service.dart';
import '../models/note_model.dart';
import 'dart:convert';

import 'package:uuid/uuid.dart';

class ContentViewModel extends BaseViewModel {
  final IFileService _fileService;
  final IEncryptionService _encryptionService;

  final TextEditingController textController = TextEditingController();
  final TextEditingController titleController = TextEditingController(
    text: "New Note",
  );

  String? _currentPassword;
  String? _currentFileName;
  Timer? _autoSaveTimer;
  Timer? _debounceTimer; // For file watching
  StreamSubscription? _fileWatcherSubscription;
  final BackgroundService _backgroundService = BackgroundService();
  List<RecentFile> _recentFiles = [];

  final Map<String, String> _sessionPasswords = {};
  bool _isLocked = false;

  bool get isLocked => _isLocked;

  List<RecentFile> get recentFiles => _recentFiles;

  bool get isPasswordSet => _currentPassword != null;

  ContentViewModel({
    required IFileService fileService,
    required IEncryptionService encryptionService,
  }) : _fileService = fileService,
       _encryptionService = encryptionService {
    loadRecentFiles();
    _initFileWatcher();
  }

  void _initFileWatcher() {
    _backgroundService.init();
    _backgroundService.recentFilesStream.listen((files) {
      _recentFiles = files;
      notifyListeners();
      setBusy(false);
    });

    _fileWatcherSubscription = _fileService.watchRecentFiles().listen((_) {
      // Debounce reload
      if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
      _debounceTimer = Timer(const Duration(seconds: 2), () {
        loadRecentFiles();
      });
    });
  }

  Future<void> loadRecentFiles() async {
    final path = await _fileService.getUserDataPath();
    if (path.isNotEmpty) {
      _backgroundService.loadRecentFiles(path);
    }
  }

  Future<void> loadNote(String fileName) async {
    setBusy(true);
    _currentFileName = fileName;

    final content = await _fileService.readFile(fileName);
    if (content != null) {
      try {
        // 1. Decrypt with APP SECRET KEY
        final appDecrypted = _encryptionService.decryptApp(content);

        if (appDecrypted.isNotEmpty) {
          // It's a valid JSON note
          final jsonMap = json.decode(appDecrypted);
          final note = NoteModel.fromJson(jsonMap);

          _isLocked = note.isLocked;

          if (note.isLocked) {
            // Check if we have a session password
            final sessionPass = _sessionPasswords[fileName];
            if (sessionPass != null) {
              // Unlock automatically
              _unlockContent(note.content, sessionPass);
              _currentPassword = sessionPass;
            } else {
              // Locked state - clear editor
              textController.text = "";
              _currentPassword = null;
              notifyListeners();
            }
          } else {
            // Not locked, content is plain
            textController.text = note.content;
            _currentPassword = null;
          }

          titleController.text = note.title;
        } else {
          // Legacy file or bad key
          print("App decryption failed, trying legacy...");
          textController.text = "Error: Invalid file format.";
        }
      } catch (e) {
        print("Error loading note: $e");
        textController.text = "Error loading file.";
      }
      notifyListeners();
    }
    setBusy(false);
  }

  void setPassword(String password) {
    _currentPassword = password;
    notifyListeners();
    _scheduleAutoSave();
  }

  void clearPassword() {
    _currentPassword = null;
    notifyListeners();
    // Decide if valid strategy: keep auto-saving if file exists?
    // Request says: "once saved it will auto save".
    // If file exists, we continue auto-saving even if password cleared.
    _scheduleAutoSave();
  }

  Future<void> saveNote({bool isAutoSave = false}) async {
    if (!isAutoSave) setBusy(true);

    if (!isAutoSave) await Future.delayed(const Duration(seconds: 1));

    // Determine current ID (if new file, ID is UUID)
    final uuid = _currentFileName != null
        ? _currentFileName!
              .replaceAll('.enc', '')
              .replaceAll(RegExp(r'note_\d+_'), '')
        : const Uuid().v4();

    String contentToSave = textController.text;
    bool locked = false;

    // If password set, encrypt content with USER PASSWORD
    if (_currentPassword != null) {
      contentToSave = _encryptionService.encrypt(
        textController.text,
        password: _currentPassword,
      );
      locked = true;
    }

    // Create NoteModel
    final note = NoteModel(
      id: uuid,
      title: (titleController.text.trim().length < 40)
          ? _generateTitleFromContent(textController.text)
          : titleController.text,
      content: contentToSave,
      isLocked: locked,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );

    // Convert to JSON
    final jsonString = json.encode(note.toJson());

    // Encrypt JSON with APP SECRET KEY
    final appEncrypted = _encryptionService.encryptApp(jsonString);

    if (_currentFileName == null) {
      final timestamp = note.timestamp;
      _currentFileName = 'note_${timestamp}_$uuid.enc';
    }

    await _fileService.saveFile(appEncrypted, _currentFileName!);

    // Update session password for this file if saving with a password
    if (_currentFileName != null && _currentPassword != null) {
      _sessionPasswords[_currentFileName!] = _currentPassword!;
    }

    // For verification
    print("SAVED FILE: $_currentFileName (Locked: $locked, Auto: $isAutoSave)");

    await loadRecentFiles();

    if (!isAutoSave) setBusy(false);
  }

  Future<void> deleteNote(String fileName) async {
    await _fileService.deleteFile(fileName);
    if (_currentFileName == fileName) {
      reset();
    }
    await loadRecentFiles();
  }

  void unlockNote(String password) {
    // Re-read logic or just store `_tempEncryptedContent`?
    // To be safe, we should reload/re-decrypt using the password.
    // However, we don't hold the encrypted content in memory here optimally.
    // Let's reload the file to be safe and clean.
    if (_currentFileName != null) {
      _sessionPasswords[_currentFileName!] = password;
      loadNote(_currentFileName!);
    }
  }

  void _unlockContent(String encryptedContent, String password) {
    final decrypted = _encryptionService.decrypt(
      encryptedContent,
      password: password,
    );
    if (decrypted.startsWith("Error decrypting:")) {
      textController.text = "Incorrect Password";
      _sessionPasswords.remove(_currentFileName); // Invalid pass
      _isLocked = true;
    } else {
      textController.text = decrypted;
      _isLocked = false;
    }
  }

  void manualLock() {
    if (_currentFileName != null) {
      _sessionPasswords.remove(_currentFileName);
      _currentPassword = null;
      _isLocked = true;
      textController.clear();
      notifyListeners();
    }
  }

  void reset() {
    _currentFileName = null;
    _currentPassword = null;
    _isLocked = false;
    textController.clear();
    titleController.text = "New Note";
    notifyListeners();
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    _debounceTimer?.cancel();
    _fileWatcherSubscription?.cancel();
    textController.dispose();
    titleController.dispose();
    _backgroundService.dispose();
    super.dispose();
  }

  void onTextChanged(String text) {
    if (titleController.text.trim().length < 40) {
      final generatedTitle = _generateTitleFromContent(text);
      if (generatedTitle != "New Note") {
        titleController.text = generatedTitle;
      }
    }

    notifyListeners();
    _scheduleAutoSave();
  }

  void _scheduleAutoSave() {
    if (_currentFileName != null || isPasswordSet) {
      _autoSaveTimer?.cancel();
      _autoSaveTimer = Timer(const Duration(seconds: 2), () {
        saveNote(isAutoSave: true);
      });
    }
  }

  Future<void> pickFile() async {
    final result = await _fileService.pickFile();
    if (result != null) {
      final fileName = result.files.single.name;
      final textToAdd = '\n\n[Attachment: $fileName]';
      _insertText(textToAdd);
    }
  }

  Future<PlatformFile?> pickImportFile() async {
    final result = await _fileService.pickFile(
      allowedExtensions: ['txt', 'enc'],
    );
    return result?.files.single;
  }

  Future<ImportVerificationResult> verifyImportFile(PlatformFile file) async {
    if (file.path == null) {
      return ImportVerificationResult(
        isValid: false,
        message: "File path not found",
      );
    }

    try {
      final fileObj = File(file.path!);
      final content = await fileObj.readAsString();
      final ext = file.name.split('.').last.toLowerCase();

      if (ext == 'enc') {
        try {
          final appDecrypted = _encryptionService.decryptApp(content);
          if (appDecrypted.isNotEmpty) {
            final jsonMap = json.decode(appDecrypted);
            final note = NoteModel.fromJson(jsonMap);
            return ImportVerificationResult(
              isValid: true,
              message: "Valid Encrypted Note",
              previewInfo:
                  "Title: ${note.title}\nDate: ${DateTime.fromMillisecondsSinceEpoch(note.timestamp)}",
            );
          }
        } catch (e) {
          return ImportVerificationResult(
            isValid: false,
            message: "Invalid Encryption or Corrupt File",
          );
        }
      } else if (ext == 'txt') {
        // Valid text file
        return ImportVerificationResult(
          isValid: true,
          message: "Plain Text File",
          previewInfo:
              "Size: ${await fileObj.length()} bytes\nPreview: ${content.length > 50 ? content.substring(0, 50) + "..." : content}",
        );
      }

      return ImportVerificationResult(
        isValid: false,
        message: "Unsupported format",
      );
    } catch (e) {
      return ImportVerificationResult(
        isValid: false,
        message: "Error reading file: $e",
      );
    }
  }

  Future<void> performImport(PlatformFile file) async {
    final importedName = await _fileService.importFile(file);
    if (importedName != null) {
      await loadRecentFiles();
    }
  }

  void _insertText(String text) {
    final textSelection = textController.selection;
    if (textSelection.isValid) {
      final newText = textController.text.replaceRange(
        textSelection.start,
        textSelection.end,
        text,
      );
      final newSelection = textSelection.copyWith(
        baseOffset: textSelection.start + text.length,
        extentOffset: textSelection.start + text.length,
      );
      textController.value = TextEditingValue(
        text: newText,
        selection: newSelection,
      );
    } else {
      textController.text += text;
    }
    notifyListeners();
    _scheduleAutoSave();
  }

  String _generateTitleFromContent(String content) {
    if (content.trim().isEmpty) return "New Note";

    final lines = content.split('\n');
    final contentLines = lines.where((line) => line.trim().isNotEmpty).toList();

    if (contentLines.isEmpty) return "New Note";

    String title = "";

    for (var line in contentLines) {
      String cleaned = _cleanTitleLine(line);
      if (cleaned.isEmpty) continue;

      if (title.isNotEmpty) {
        title += " ";
      }
      title += cleaned;

      if (title.length >= 40) break;
    }

    if (title.length > 40) {
      title = title.substring(0, 40);
    }

    return title.isEmpty ? "New Note" : title;
  }

  String _cleanTitleLine(String line) {
    // Remove leading symbols (e.g., #, -, *, >)
    line = line.replaceAll(RegExp(r'^[\s#\*\->]+'), '');
    // Remove leading numbering (e.g., 1., 2.)
    line = line.replaceAll(RegExp(r'^\s*\d+\.\s*'), '');
    return line.trim();
  }
}

class ImportVerificationResult {
  final bool isValid;
  final String message;
  final String? previewInfo;

  ImportVerificationResult({
    required this.isValid,
    required this.message,
    this.previewInfo,
  });
}
