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
import 'package:flutter_quill/flutter_quill.dart';
import 'package:vsc_quill_delta_to_html/vsc_quill_delta_to_html.dart';
import 'package:flutter_quill_delta_from_html/flutter_quill_delta_from_html.dart';
import 'package:uuid/uuid.dart';
import 'package:code_text_field/code_text_field.dart';
import 'package:highlight/languages/xml.dart'; // XML handles HTML highlighting

class ContentViewModel extends BaseViewModel {
  final IFileService _fileService;
  final IEncryptionService _encryptionService;

  final QuillController quillController = QuillController.basic();
  final TextEditingController titleController = TextEditingController(
    text: "New Note",
  );
  final FocusNode focusNode = FocusNode();
  final ScrollController scrollController = ScrollController();

  String? _currentPassword;
  String? _currentFileName;
  Timer? _autoSaveTimer;
  Timer? _debounceTimer; // For file watching
  Timer? _titleUpdateTimer; // For optimizing typing performance
  StreamSubscription? _fileWatcherSubscription;
  final BackgroundService _backgroundService = BackgroundService();
  List<RecentFile> _recentFiles = [];

  final Map<String, String> _sessionPasswords = {};
  bool _isLocked = false;

  bool get isLocked => _isLocked;

  List<RecentFile> get recentFiles => _recentFiles;

  bool get isPasswordSet => _currentPassword != null;
  String? get currentFileName => _currentFileName;

  late final CodeController htmlController;
  bool _isHtmlMode = false;
  bool get isHtmlMode => _isHtmlMode;

  // region Initialization
  ContentViewModel({
    required IFileService fileService,
    required IEncryptionService encryptionService,
  }) : _fileService = fileService,
       _encryptionService = encryptionService {
    // Initialize CodeController with syntax highlighting
    htmlController = CodeController(
      language: xml, // Highlighting for XML/HTML
    );

    loadRecentFiles();
    _initFileWatcher();

    // Listen to changes for auto-save and title generation
    quillController.document.changes.listen((change) {
      if (!_isHtmlMode) {
        onTextChanged();
      }
    });

    htmlController.addListener(() {
      if (_isHtmlMode) {
        _scheduleAutoSave();
        // Optional: Title generation from HTML could go here,
        // but stripping tags might be expensive/complex to do continuously.
      }
    });
  }

  void toggleEditorMode() {
    if (_isHtmlMode) {
      // Switch to Rich Text
      // Convert HTML string to Delta
      try {
        final html = htmlController.text;
        final delta = HtmlToDelta().convert(html);
        quillController.document = Document.fromDelta(delta);

        // Move cursor to end to avoid issues
        quillController.moveCursorToPosition(quillController.document.length);
      } catch (e) {
        print("Error converting HTML to Delta: $e");
        // Fallback or show error? For now, we just switch and maybe get empty/broken state.
        // But HtmlToDelta is usually robust enough to giving *something*.
      }
      _isHtmlMode = false;
    } else {
      // Switch to HTML Editor
      // Convert Delta to HTML string
      final delta = quillController.document.toDelta();
      final converter = QuillDeltaToHtmlConverter(
        delta.toJson(),
        ConverterOptions.forEmail(),
      );
      final html = converter.convert();
      htmlController.text = html; // This triggers listener, schedules auto-save
      _isHtmlMode = true;
    }
    notifyListeners();
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
  // endregion

  // region File Loading
  Future<void> loadRecentFiles() async {
    final path = await _fileService.getUserDataPath();
    if (path.isNotEmpty) {
      _backgroundService.loadRecentFiles(path);
    }
  }

  Future<void> loadNote(String fileName) async {
    setBusy(true);
    _currentFileName = fileName;

    // Reset mode to Rich Text on new load for consistency
    _isHtmlMode = false;

    final content = await _fileService.readFile(fileName);
    if (content != null) {
      bool loaded = false;

      // 1. Try App Decryption (New format)
      try {
        final appDecrypted = _encryptionService.decryptApp(content);

        if (appDecrypted.isNotEmpty) {
          final jsonMap = json.decode(appDecrypted);
          final note = NoteModel.fromJson(jsonMap);
          _applyNoteModel(note, fileName);
          loaded = true;
        }
      } catch (e) {
        print("App decryption failed: $e");
      }

      // 2. Try Legacy JSON (Unencrypted old notes)
      if (!loaded) {
        try {
          final jsonMap = json.decode(content);
          // Simple validation to check if it's a note
          if (jsonMap is Map<String, dynamic> &&
              (jsonMap.containsKey('title') ||
                  jsonMap.containsKey('content'))) {
            final note = NoteModel.fromJson(jsonMap);
            _applyNoteModel(note, fileName);
            loaded = true;
          }
        } catch (e) {
          print("Legacy JSON failed: $e");
        }
      }

      // 3. Fallback to Plain Text
      if (!loaded) {
        print("Loading as plain text");
        _loadContentToQuill(content);
        titleController.text = _generateTitleFromContent(content);
        _isLocked = false;
        _currentPassword = null;
      }

      notifyListeners();
    }
    setBusy(false);
  }

  void _applyNoteModel(NoteModel note, String fileName) {
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
        quillController.document = Document();
        htmlController.clear();
        _currentPassword = null;
        notifyListeners();
      }
    } else {
      // Not locked
      _loadContentToQuill(note.content);
      _currentPassword = null;
    }

    titleController.text = note.title;
  }
  // endregion

  // region Password & Locking
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

  Future<bool> unlockNote(String password) async {
    if (_currentFileName == null) return false;

    try {
      final jsonString = await _fileService.readFile(_currentFileName!);
      if (jsonString == null) return false;

      // 1. App Decrypt
      final appDecrypted = _encryptionService.decryptApp(jsonString);
      final jsonMap = json.decode(appDecrypted);
      final note = NoteModel.fromJson(jsonMap);

      // 2. User Decrypt
      final decryptedContent = _encryptionService.decrypt(
        note.content,
        password: password,
      );

      if (decryptedContent.startsWith("Error decrypting:")) {
        return false;
      }

      // Success
      _currentPassword = password;
      _sessionPasswords[_currentFileName!] = password;
      _loadContentToQuill(decryptedContent);
      _isLocked = false;
      notifyListeners();
      return true;
    } catch (e) {
      print("Unlock failed: $e");
      return false;
    }
  }

  void _unlockContent(String encryptedContent, String password) {
    final decrypted = _encryptionService.decrypt(
      encryptedContent,
      password: password,
    );
    if (decrypted.startsWith("Error decrypting:")) {
      quillController.document = Document()..insert(0, "Incorrect Password");
      _sessionPasswords.remove(_currentFileName); // Invalid pass
      _isLocked = true;
    } else {
      _loadContentToQuill(decrypted);
      _isLocked = false;
    }
  }

  bool verifyPassword(String password) {
    return _currentPassword == password;
  }

  void manualLock() {
    if (_currentFileName != null) {
      _sessionPasswords.remove(_currentFileName);
      _currentPassword = null;
      _isLocked = true;
      quillController.document = Document();
      htmlController.clear();
      notifyListeners();
    }
  }
  // endregion

  // region Saving
  Future<void> saveNote({bool isAutoSave = false}) async {
    if (!isAutoSave) setBusy(true);

    if (!isAutoSave) await Future.delayed(const Duration(seconds: 1));

    // Determine current ID (if new file, ID is UUID)
    final uuid = _currentFileName != null
        ? _currentFileName!
              .replaceAll('.enc', '')
              .replaceAll(RegExp(r'note_\d+_'), '')
        : const Uuid().v4();

    String contentToSave = "";
    bool locked = false;

    // Get the HTML content, either from HtmlController (if editing HTML)
    // or by converting Quill Delta
    String htmlContent;
    if (_isHtmlMode) {
      htmlContent = htmlController.text;
    } else {
      final delta = quillController.document.toDelta();
      final converter = QuillDeltaToHtmlConverter(
        delta.toJson(),
        ConverterOptions.forEmail(),
      );
      htmlContent = converter.convert();
    }

    // Check if content is empty (strip HTML tags if needed, or just check length basics)
    // For a robust check, we look at plain text equivalent.
    final plainText = _isHtmlMode
        ? htmlController.text.replaceAll(RegExp(r'<[^>]*>'), '').trim()
        : quillController.document.toPlainText().trim();

    // If new file and empty content, do not save
    if (_currentFileName == null &&
        plainText.isEmpty &&
        titleController.text == "New Note") {
      print("Skipping save of empty new note");
      if (!isAutoSave) setBusy(false);
      return;
    }

    // If password set, encrypt content with USER PASSWORD
    if (_currentPassword != null) {
      // For encryption, we need to save the HTML string, then encrypt THAT string.
      // So 'contentToSave' will be the Encrypted(HTML).
      contentToSave = _encryptionService.encrypt(
        htmlContent,
        password: _currentPassword,
      );
      locked = true;
    } else {
      // Not locked, save raw HTML
      contentToSave = htmlContent;
    }

    // Create NoteModel
    final note = NoteModel(
      id: uuid,
      title: (titleController.text.trim().length < 40)
          ? (_isHtmlMode
                ? titleController
                      .text // Don't auto-generate from HTML yet to exist perf/complexity
                : _generateTitleFromContent(
                    quillController.document.toPlainText(),
                  ))
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
  // endregion

  // region Import & Export
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
  // endregion

  // region Helpers
  void _loadContentToQuill(String content) {
    // content is either HTML (if previously saved with new editor) or Plain Text (old notes)
    // Simple heuristic: check for HTML tags
    // Or just try to parse with HtmlToDelta

    try {
      if (content.trim().startsWith('<')) {
        final delta = HtmlToDelta().convert(content);
        quillController.document = Document.fromDelta(delta);
      } else {
        // Plain text
        quillController.document = Document()..insert(0, content);
      }
    } catch (e) {
      // Fallback
      quillController.document = Document()..insert(0, content);
    }

    // Move cursor to end
    quillController.moveCursorToPosition(quillController.document.length);
  }

  void _insertText(String text) {
    if (_isHtmlMode) {
      // Insert in HTML
      final textSelection = htmlController.selection;
      String newText = htmlController.text;
      if (textSelection.start >= 0) {
        newText = newText.replaceRange(
          textSelection.start,
          textSelection.end,
          text,
        );
        htmlController.text = newText;
      } else {
        htmlController.text += text;
      }
      return;
    }

    // We don't support simple insertText for attachments in Quill easily without Delta
    // But we can just insert text at selection
    final index = quillController.selection.baseOffset;
    final length = quillController.selection.extentOffset - index;
    // Replace logic?
    // Just insert
    if (index >= 0) {
      quillController.document.replace(index, length, text);
    } else {
      quillController.document.insert(
        quillController.document.length - 1,
        text,
      );
    }

    notifyListeners();
    _scheduleAutoSave();
  }

  void reset() {
    _currentFileName = null;
    _currentPassword = null;
    _isLocked = false;
    _isHtmlMode = false;
    quillController.document = Document();
    htmlController.clear();
    titleController.text = "New Note";
    notifyListeners();
  }

  // region Lifecycle
  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    _debounceTimer?.cancel();
    _titleUpdateTimer?.cancel();
    _fileWatcherSubscription?.cancel();
    quillController.dispose();
    titleController.dispose();
    htmlController.dispose();
    focusNode.dispose();
    scrollController.dispose();
    _backgroundService.dispose();
    super.dispose();
  }
  // endregion

  void onTextChanged() {
    // Optimization: Debounce title generation to avoid heavy toPlainText() calls on every keystroke
    _titleUpdateTimer?.cancel();
    _titleUpdateTimer = Timer(const Duration(milliseconds: 800), () {
      try {
        String text = quillController.document.toPlainText();
        // Only auto-update title if it's the default or short (likely same as default logic)
        // Adjust the condition to be less aggressive if needed
        if (titleController.text.trim().length < 40 ||
            titleController.text == "New Note") {
          final generatedTitle = _generateTitleFromContent(text);
          if (generatedTitle != "New Note" &&
              generatedTitle != titleController.text) {
            titleController.text = generatedTitle;
          }
        }
      } catch (e) {
        // Handle potential errors during text processing
        print("Error updating title: $e");
      }
    });

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

  // endregion
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
