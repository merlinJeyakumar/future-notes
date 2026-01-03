import 'dart:async';
import 'package:flutter/material.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import '../../../core/viewmodels/base_viewmodel.dart';
import '../services/file_service.dart';
import '../services/encryption_service.dart';
import '../models/note_model.dart';
import 'dart:convert';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:vsc_quill_delta_to_html/vsc_quill_delta_to_html.dart';

import 'package:uuid/uuid.dart';

class ContentViewModel extends BaseViewModel {
  final IFileService _fileService;
  final IEncryptionService _encryptionService;

  final TextEditingController textController = TextEditingController();
  final quill.QuillController quillController = quill.QuillController.basic();

  final TextEditingController titleController = TextEditingController(
    text: "New Note",
  );

  String _lastText = "";
  final List<TextRange> _checkboxRanges = [];
  String? _currentPassword;
  String? _currentFileName;
  Timer? _autoSaveTimer;
  Timer? _debounceTimer; // For file watching
  Timer? _htmlSyncDebounceTimer; // For syncing Quill -> HTML
  StreamSubscription? _fileWatcherSubscription;
  List<RecentFile> _recentFiles = [];

  final Map<String, String> _sessionPasswords = {};
  bool _isLocked = false;

  // Track active tab index (0: Rich Editor, 1: HTML)
  int _activeTabIndex = 0;
  int get activeTabIndex => _activeTabIndex;

  // Flag to prevent sync loops
  bool _isSyncingFromQuill = false;
  bool _isSyncingFromText = false;

  bool get isLocked => _isLocked;

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

    // Listen to changes in Quill and IMMEDIATELY sync to HTML
    // This ensures textController always has the latest HTML
    quillController.document.changes.listen((change) {
      _onQuillChanged();
    });
  }

  /// Called whenever Quill content changes - syncs to HTML immediately
  void _onQuillChanged() {
    if (_isSyncingFromText) return; // Prevent loop

    // Debounce to avoid excessive syncing during rapid typing
    _htmlSyncDebounceTimer?.cancel();
    _htmlSyncDebounceTimer = Timer(const Duration(milliseconds: 100), () {
      _syncQuillToHtml();

      // Generate title from plain text
      if (titleController.text.trim().length < 40) {
        final plainText = quillController.document.toPlainText();
        final generatedTitle = _generateTitleFromContent(plainText);
        if (generatedTitle != "New Note") {
          titleController.text = generatedTitle;
        }
      }

      notifyListeners();
      _scheduleAutoSave();
    });
  }

  /// Syncs QuillController content to textController as HTML
  void _syncQuillToHtml() {
    if (_isSyncingFromText) return;

    try {
      _isSyncingFromQuill = true;

      final delta = quillController.document.toDelta();
      final List<Map<String, dynamic>> ops = [];

      for (final op in delta.toList()) {
        final Map<String, dynamic> opMap = {};
        if (op.isInsert) {
          opMap['insert'] = op.data;
          if (op.attributes != null && op.attributes!.isNotEmpty) {
            opMap['attributes'] = op.attributes;
          }
        }
        if (opMap.isNotEmpty) {
          ops.add(opMap);
        }
      }

      final converter = QuillDeltaToHtmlConverter(ops);
      final html = converter.convert();

      // Only update if actually different to prevent cursor jumps
      if (textController.text != html) {
        textController.text = html;
      }
    } catch (e, stack) {
      print("Error syncing Quill to HTML: $e");
      print("Stack: $stack");
      // Fallback to plain text
      final plainText = quillController.document.toPlainText();
      if (textController.text != plainText) {
        textController.text = plainText;
      }
    } finally {
      _isSyncingFromQuill = false;
    }
  }

  /// Syncs textController (HTML) content back to QuillController
  void _syncHtmlToQuill() {
    if (_isSyncingFromQuill) return;

    try {
      _isSyncingFromText = true;

      // For HTML content, strip to plain text for Quill
      // (Full HTML to Delta conversion requires a more complex library)
      final plainText = _stripHtmlTags(textController.text);

      // Only update if actually different
      final currentPlain = quillController.document.toPlainText().trim();
      if (currentPlain != plainText.trim()) {
        quillController.clear();
        if (plainText.isNotEmpty) {
          quillController.document.insert(0, plainText);
        }
      }
    } catch (e) {
      print("Error syncing HTML to Quill: $e");
    } finally {
      _isSyncingFromText = false;
    }
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
      bool isLocked = false;
      DateTime? created;
      DateTime? modified;
      int? sizeBytes;

      try {
        final content = await _fileService.readFile(file);
        final stats = await _fileService.getFileStats(file);

        if (stats != null) {
          modified = stats.modified;
          sizeBytes = stats.size;
        }

        if (content != null) {
          final appDecrypted = _encryptionService.decryptApp(content);
          if (appDecrypted.isNotEmpty) {
            final jsonMap = json.decode(appDecrypted);
            final note = NoteModel.fromJson(jsonMap);
            if (note.title.isNotEmpty) {
              displayTitle = note.title;
            }
            isLocked = note.isLocked;
            created = DateTime.fromMillisecondsSinceEpoch(note.timestamp);
          }
        }
      } catch (e) {
        print("Error reading title for $file: $e");
      }
      final fullPath = await _fileService.getFullPath(file);

      loadedFiles.add(
        RecentFile(
          path: file,
          fullPath: fullPath,
          title: displayTitle,
          isLocked: isLocked,
          created: created,
          modified: modified,
          sizeBytes: sizeBytes,
        ),
      );
    }

    loadedFiles.sort((a, b) {
      if (a.modified == null && b.modified == null) return 0;
      if (a.modified == null) return 1;
      if (b.modified == null) return -1;
      return b.modified!.compareTo(a.modified!);
    });

    _recentFiles = loadedFiles;
    notifyListeners();
  }

  Future<void> loadNote(String fileName) async {
    setBusy(true);
    _currentFileName = fileName;

    final content = await _fileService.readFile(fileName);
    if (content != null) {
      try {
        final appDecrypted = _encryptionService.decryptApp(content);

        if (appDecrypted.isNotEmpty) {
          final jsonMap = json.decode(appDecrypted);
          final note = NoteModel.fromJson(jsonMap);

          _isLocked = note.isLocked;

          if (note.isLocked) {
            final sessionPass = _sessionPasswords[fileName];
            if (sessionPass != null) {
              _unlockContent(note.content, sessionPass);
              _currentPassword = sessionPass;
            } else {
              textController.text = "";
              quillController.clear();
              _currentPassword = null;
              notifyListeners();
            }
          } else {
            // Not locked - set content to both controllers
            _isSyncingFromText = true;
            textController.text = note.content;
            _isSyncingFromText = false;

            // Load into Quill (stripping HTML for now)
            final plainText = _stripHtmlTags(note.content);
            quillController.clear();
            if (plainText.isNotEmpty) {
              quillController.document.insert(0, plainText);
            }

            _currentPassword = null;
          }

          titleController.text = note.title;
        } else {
          print("App decryption failed, trying legacy...");
          textController.text = "Error: Invalid file format.";
          quillController.clear();
        }
      } catch (e) {
        print("Error loading note: $e");
        textController.text = "Error loading file.";
        quillController.clear();
      }

      _lastText = textController.text;
      parseCheckboxes(textController.text);
      notifyListeners();
    }
    setBusy(false);
  }

  String _stripHtmlTags(String html) {
    return html
        .replaceAll(RegExp(r'<br\s*/?>'), '\n')
        .replaceAll(RegExp(r'<p[^>]*>'), '')
        .replaceAll(RegExp(r'</p>'), '\n')
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .trim();
  }

  void setActiveTab(int index) {
    if (_activeTabIndex == index) return;

    // When switching TO editor from HTML, sync HTML back to Quill
    if (index == 0 && _activeTabIndex == 1) {
      _syncHtmlToQuill();
    }
    // When switching TO HTML from editor, sync is already done continuously
    // So nothing extra needed here

    _activeTabIndex = index;
    notifyListeners();
  }

  void setPassword(String password) {
    _currentPassword = password;
    notifyListeners();
    _scheduleAutoSave();
  }

  void clearPassword() {
    _currentPassword = null;
    notifyListeners();
    _scheduleAutoSave();
  }

  Future<void> saveNote({bool isAutoSave = false}) async {
    // textController should already have the latest HTML due to continuous sync
    // But just to be safe, do one more sync if we're in editor mode
    if (_activeTabIndex == 0) {
      _syncQuillToHtml();
    }

    if (!isAutoSave) setBusy(true);
    if (!isAutoSave) await Future.delayed(const Duration(seconds: 1));

    final uuid = _currentFileName != null
        ? _currentFileName!
              .replaceAll('.enc', '')
              .replaceAll(RegExp(r'note_\d+_'), '')
        : const Uuid().v4();

    String contentToSave = textController.text;
    bool locked = false;

    if (_currentPassword != null) {
      contentToSave = _encryptionService.encrypt(
        textController.text,
        password: _currentPassword,
      );
      locked = true;
    }

    final note = NoteModel(
      id: uuid,
      title: (titleController.text.trim().length < 40)
          ? _generateTitleFromContent(_stripHtmlTags(textController.text))
          : titleController.text,
      content: contentToSave,
      isLocked: locked,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );

    final jsonString = json.encode(note.toJson());
    final appEncrypted = _encryptionService.encryptApp(jsonString);

    if (_currentFileName == null) {
      final timestamp = note.timestamp;
      _currentFileName = 'note_${timestamp}_$uuid.enc';
    }

    await _fileService.saveFile(appEncrypted, _currentFileName!);

    if (_currentFileName != null && _currentPassword != null) {
      _sessionPasswords[_currentFileName!] = _currentPassword!;
    }

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
      _sessionPasswords.remove(_currentFileName);
      _isLocked = true;
    } else {
      _isSyncingFromText = true;
      textController.text = decrypted;
      _isSyncingFromText = false;

      final plainText = _stripHtmlTags(decrypted);
      quillController.clear();
      if (plainText.isNotEmpty) {
        quillController.document.insert(0, plainText);
      }

      _isLocked = false;
    }
  }

  void manualLock() {
    if (_currentFileName != null) {
      _sessionPasswords.remove(_currentFileName);
      _currentPassword = null;
      _isLocked = true;
      textController.clear();
      quillController.clear();
      notifyListeners();
    }
  }

  void reset() {
    _currentFileName = null;
    _currentPassword = null;
    _isLocked = false;
    _isSyncingFromQuill = true;
    _isSyncingFromText = true;
    textController.clear();
    quillController.clear();
    _isSyncingFromQuill = false;
    _isSyncingFromText = false;
    titleController.text = "New Note";
    _checkboxRanges.clear();
    _lastText = "";
    notifyListeners();
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    _debounceTimer?.cancel();
    _htmlSyncDebounceTimer?.cancel();
    _fileWatcherSubscription?.cancel();
    textController.dispose();
    quillController.dispose();
    titleController.dispose();
    super.dispose();
  }

  void onTextChanged(String text) {
    if (_isSyncingFromQuill) return; // Prevent loop

    handleAutoList(text);
    _lastText = text;

    if (titleController.text.trim().length < 40) {
      final generatedTitle = _generateTitleFromContent(_stripHtmlTags(text));
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

    final List<TextRange> exclusions = [];
    final codeBlockRegex = RegExp(r'```[\s\S]*?```');
    for (final match in codeBlockRegex.allMatches(text)) {
      exclusions.add(TextRange(start: match.start, end: match.end));
    }

    final RegExp regex = RegExp(r'^\s*[-*+]\s+(\[[ xX]\])', multiLine: true);

    for (final match in regex.allMatches(text)) {
      if (match.groupCount >= 1) {
        final start =
            match.start + (match.group(0)!.lastIndexOf(match.group(1)!));
        final end = start + match.group(1)!.length;

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

    if (range.end > currentText.length) return;

    final currentCheckbox = currentText.substring(range.start, range.end);
    final isChecked = currentCheckbox.toLowerCase().contains('x');
    final newCheckbox = isChecked ? '[ ]' : '[x]';

    final newText = currentText.replaceRange(
      range.start,
      range.end,
      newCheckbox,
    );

    textController.value = TextEditingValue(
      text: newText,
      selection: textController.selection,
    );

    parseCheckboxes(newText);
    notifyListeners();
    _scheduleAutoSave();
  }

  void handleAutoList(String newText) {
    if (newText.length != _lastText.length + 1) return;

    final selection = textController.selection;
    if (!selection.isValid || selection.start == 0) return;

    if (newText[selection.start - 1] == '\n') {
      final currentPos = selection.start;
      final previousNewlinePos = newText.lastIndexOf('\n', currentPos - 2);
      final lineStart = previousNewlinePos == -1 ? 0 : previousNewlinePos + 1;

      final previousLine = newText.substring(lineStart, currentPos - 1);

      final bulletMatch = RegExp(r'^(\s*)([*+-])\s').firstMatch(previousLine);
      if (bulletMatch != null) {
        final indent = bulletMatch.group(1) ?? "";
        final bullet = bulletMatch.group(2) ?? "";
        _insertText('$indent$bullet ');
        return;
      }

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
    line = line.replaceAll(RegExp(r'^[\s#\*\->]+'), '');
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
