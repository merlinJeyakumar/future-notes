import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/viewmodels/base_viewmodel.dart';
import '../services/file_service.dart';
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

  String _lastText = "";
  final List<TextRange> _checkboxRanges = [];
  String? _currentPassword;
  String? _currentFileName;
  Timer? _autoSaveTimer;
  Timer? _debounceTimer; // For file watching
  StreamSubscription? _fileWatcherSubscription;
  List<RecentFile> _recentFiles = [];

  final Map<String, String> _sessionPasswords = {};
  bool _isLocked = false;

  bool get isLocked => _isLocked;

  // Expose for UI if needed, but logic should mainly happen here

  // Expose for UI if needed, but logic should mainly happen here
  // List<TextRange> get checkboxRanges => _checkboxRanges;
  List<RecentFile> get recentFiles => _recentFiles;

  bool get isPasswordSet => _currentPassword != null;

  ContentViewModel({
    required IFileService fileService,
    required IEncryptionService encryptionService,
  }) : _fileService = fileService,
       _encryptionService = encryptionService {
    _lastText = textController.text;
    parseCheckboxes(textController.text);
    loadRecentFiles();
    _initFileWatcher();
  }

  void _initFileWatcher() {
    _fileWatcherSubscription = _fileService.watchRecentFiles().listen((_) {
      // Debounce reload
      if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
      _debounceTimer = Timer(const Duration(seconds: 2), () {
        loadRecentFiles();
      });
    });
  }

  Future<void> loadRecentFiles() async {
    final files = await _fileService.getRecentFiles();
    List<RecentFile> loadedFiles = [];

    for (final file in files) {
      String displayTitle = file;
      try {
        final content = await _fileService.readFile(file);
        if (content != null) {
          final appDecrypted = _encryptionService.decryptApp(content);
          if (appDecrypted.isNotEmpty) {
            final jsonMap = json.decode(appDecrypted);
            final note = NoteModel.fromJson(jsonMap);
            // Use the title from the note if available and not default "New Note" (unless that's what user wants)
            if (note.title.isNotEmpty) {
              displayTitle = note.title;
            }
          }
        }
      } catch (e) {
        print("Error reading title for $file: $e");
      }
      loadedFiles.add(RecentFile(path: file, title: displayTitle));
    }
    _recentFiles = loadedFiles;
    notifyListeners();
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

      _lastText = textController.text;
      parseCheckboxes(textController.text);
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
    _checkboxRanges.clear();
    _lastText = "";
    notifyListeners();
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    _debounceTimer?.cancel();
    _fileWatcherSubscription?.cancel();
    textController.dispose();
    titleController.dispose();
    super.dispose();
  }

  void onTextChanged(String text) {
    handleAutoList(text);
    _lastText = text;

    if (titleController.text.trim().length < 40) {
      final generatedTitle = _generateTitleFromContent(text);
      if (generatedTitle != "New Note") {
        titleController.text = generatedTitle;
      }
    }

    parseCheckboxes(text);
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

  void parseCheckboxes(String text) {
    _checkboxRanges.clear();

    // 1. Identify ranges to exclude (code blocks)
    final List<TextRange> exclusions = [];
    final codeBlockRegex = RegExp(r'```[\s\S]*?```');
    for (final match in codeBlockRegex.allMatches(text)) {
      exclusions.add(TextRange(start: match.start, end: match.end));
    }

    // 2. Find all potential checkboxes
    final RegExp regex = RegExp(r'^\s*[-*+]\s+(\[[ xX]\])', multiLine: true);

    for (final match in regex.allMatches(text)) {
      if (match.groupCount >= 1) {
        final start =
            match.start + (match.group(0)!.lastIndexOf(match.group(1)!));
        final end = start + match.group(1)!.length;

        // 3. Check if this checkbox is inside a code block
        bool isExcluded = false;
        for (final exclusion in exclusions) {
          if (start >= exclusion.start && end <= exclusion.end) {
            isExcluded = true;
            break;
          }
        }

        if (!isExcluded) {
          _checkboxRanges.add(TextRange(start: start, end: end));
        }
      }
    }
  }

  void toggleCheckbox(int index) {
    if (index < 0 || index >= _checkboxRanges.length) return;

    final range = _checkboxRanges[index];
    final currentText = textController.text;

    // Safety check ensuring range is still valid
    if (range.end > currentText.length) return;

    final currentCheckbox = currentText.substring(range.start, range.end);
    final isChecked = currentCheckbox.toLowerCase().contains('x');
    final newCheckbox = isChecked ? '[ ]' : '[x]';

    final newText = currentText.replaceRange(
      range.start,
      range.end,
      newCheckbox,
    );

    // Update controller without losing selection if possible
    textController.value = TextEditingValue(
      text: newText,
      selection: textController.selection,
    );

    // Re-parse immediately
    parseCheckboxes(newText);
    notifyListeners();
    _scheduleAutoSave();
  }

  /// Handles auto-formatting list items (bullets/numbers) when Enter is pressed
  void handleAutoList(String newText) {
    if (newText.length != _lastText.length + 1) return;

    final selection = textController.selection;
    if (!selection.isValid || selection.start == 0) return;

    // Check if the character before the cursor is a newline
    if (newText[selection.start - 1] == '\n') {
      final currentPos = selection.start;
      final previousNewlinePos = newText.lastIndexOf('\n', currentPos - 2);
      final lineStart = previousNewlinePos == -1 ? 0 : previousNewlinePos + 1;

      final previousLine = newText.substring(lineStart, currentPos - 1);

      // Regex for Bullet: ^(\s*)([*+-])\s
      final bulletMatch = RegExp(r'^(\s*)([*+-])\s').firstMatch(previousLine);
      if (bulletMatch != null) {
        final indent = bulletMatch.group(1) ?? "";
        final bullet = bulletMatch.group(2) ?? "";
        _insertText('$indent$bullet ');
        return;
      }

      // Regex for Number: ^(\s*)(\d+)\.\s
      final numberMatch = RegExp(r'^(\s*)(\d+)\.\s').firstMatch(previousLine);
      if (numberMatch != null) {
        final indent = numberMatch.group(1) ?? "";
        final numberStr = numberMatch.group(2) ?? "0";
        final number = int.tryParse(numberStr) ?? 0;
        _insertText('$indent${number + 1}. ');
        return;
      }
    }
  }

  Future<void> pickFile() async {
    final result = await _fileService.pickFile();
    if (result != null) {
      final fileName = result.files.single.name;
      final textToAdd = '\n\n![Attachment: $fileName]($fileName)';
      _insertText(textToAdd);
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
    parseCheckboxes(textController.text);
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
    // Remove leading markdown symbols (e.g., #, -, *, >)
    line = line.replaceAll(RegExp(r'^[\s#\*\->]+'), '');
    // Remove leading numbering (e.g., 1., 2.)
    line = line.replaceAll(RegExp(r'^\s*\d+\.\s*'), '');
    return line.trim();
  }
}
