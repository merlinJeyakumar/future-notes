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
import 'dart:typed_data';

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
  List<AttachmentModel> _attachments = [];

  final Map<String, String> _sessionPasswords = {};
  bool _isLocked = false;

  bool get isLocked => _isLocked;

  List<RecentFile> get recentFiles => _recentFiles;
  List<AttachmentModel> get attachments => _attachments;
  bool get isPasswordSet => _currentPassword != null;
  String? get currentFileName => _currentFileName;

  late final CodeController htmlController;
  bool _isHtmlMode = false;
  bool get isHtmlMode => _isHtmlMode;

  Future<void> pickImage() async {
    final result = await _fileService.pickFile(
      allowedExtensions: ['png', 'jpg', 'jpeg', 'webp'],
    );

    if (result != null && result.files.single.path != null) {
      setBusy(true);

      String noteId;
      if (_currentFileName != null) {
        if (_currentFileName!.startsWith('note_')) {
          noteId = _currentFileName!.replaceFirst('note_', '');
        } else {
          // Legacy or new without save -> Migrate/Commit to New Structure
          noteId = const Uuid().v4();
          // Force update filename to use new folder structure
          _currentFileName = "note_$noteId";
        }
      } else {
        // New Note
        noteId = const Uuid().v4();
        _currentFileName = "note_$noteId";
      }

      try {
        // 2. Read & Encrypt
        final path = result.files.single.path!;
        final originalFile = File(path);
        final bytes = await originalFile.readAsBytes();
        final fileName = result.files.single.name;
        final size = await originalFile.length();

        final encryptedBytes = _encryptionService.encryptBinary(
          bytes,
          password: _currentPassword,
        );

        // 3. Save Attachment
        final attachmentId = await _fileService.saveAttachment(
          encryptedBytes,
          noteId,
        );

        // 4. Add to List
        _attachments.add(
          AttachmentModel(
            id: attachmentId,
            fileName: fileName,
            size: size,
            mimeType: 'image/${fileName.split('.').last}', // Simple guess
          ),
        );
        notifyListeners();

        // 5. Auto Save
        _scheduleAutoSave();
      } catch (e) {
        print("Error adding attachment: $e");
      }

      setBusy(false);
    }
  }

  Future<void> exportAttachment(AttachmentModel attachment) async {
    final data = await readAttachment(attachment.id);
    if (data == null) return;

    final String? outputFile = await FilePicker.platform.saveFile(
      dialogTitle: 'Save Attachment',
      fileName: attachment.fileName,
      lockParentWindow: true,
    );

    if (outputFile != null) {
      try {
        final file = File(outputFile);
        await file.writeAsBytes(data);
      } catch (e) {
        print("Error saving attachment: $e");
      }
    }
  }

  void removeAttachment(String attachmentId) {
    _attachments.removeWhere((a) => a.id == attachmentId);
    notifyListeners();
    _scheduleAutoSave();
    // TODO: Physically delete the attachment file to clean up storage
  }

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
        _checkForMentionTrigger();
      }
    });

    htmlController.addListener(() {
      if (_isHtmlMode) {
        _scheduleAutoSave();
        // Optional: Title generation from HTML could go here,
        // but stripping tags might be expensive/complex to do continuously.
      }
    });

    // Listen to selection to help deciding when to check trigger?
    // Usually changes is enough.
  }

  final StreamController<void> _linkPickerRequest =
      StreamController<void>.broadcast();
  Stream<void> get linkPickerRequest => _linkPickerRequest.stream;

  void _checkForMentionTrigger() {
    final index = quillController.selection.baseOffset;
    if (index > 0) {
      // Check character before cursor
      // Note: toPlainText might be expensive on huge docs, but usually fine.
      // Optimization: access delta directly? Document has `collectStyle`, `queryChild`.
      // `getPlainText` with range.
      final text = quillController.document.getPlainText(index - 1, 1);
      if (text == '@') {
        // Trigger UI
        _linkPickerRequest.add(null);
      }
    }
  }

  void insertInternalLink(String title, String id) {
    final index = quillController.selection.baseOffset;
    // Replaces '@' if we want? Yes.
    // If we triggered on '@', cursor is AFTER '@'.
    // So delete 1 char back, then insert link.

    // But user might have moved cursor?
    // We assume immediate action.
    // Check if '@' is still there?

    final start = index > 0 ? index - 1 : index;
    final char = quillController.document.getPlainText(start, 1);

    if (char == '@') {
      quillController.document.replace(start, 1, title);
      quillController.formatText(
        start,
        title.length,
        LinkAttribute('note://$id'),
      );
      // Move cursor after link
      quillController.moveCursorToPosition(start + title.length);
      // Insert space
      quillController.document.insert(start + title.length, ' ');
      // Reset format?
      quillController.formatText(start + title.length, 1, LinkAttribute(null));
    } else {
      // Just insert
      quillController.document.insert(index, title);
      quillController.formatText(
        index,
        title.length,
        LinkAttribute('note://$id'),
      );
    }
  }

  Future<void> handleLinkClick(String url) async {
    if (url.startsWith('note://')) {
      final noteId = url.replaceFirst('note://', '');
      // Find file with this noteId
      // We need to match noteId to filename.
      // Current assumption: filename is "note_$noteId".

      // Check recent files for "note_$noteId"
      final targetName = "note_$noteId";
      await loadNote(targetName);
    } else {
      // Standard URL
      // Default launch?
      // We can use launchUrl from url_launcher
      // But user needs to import it?
      // For now print
      print("External Link Clicked: $url");
    }
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
    _attachments = List.from(note.attachments);

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

    // Determine ID and Mode (Legacy vs New)
    String? noteId;
    bool isLegacy = false;

    if (_currentFileName != null) {
      if (_currentFileName!.startsWith('note_')) {
        // New structure: note_<id>
        noteId = _currentFileName!.replaceFirst('note_', '');
      } else {
        // Legacy structure: specific filename
        isLegacy = true;
        // ID is technically not in filename for legacy files usually, but we need one for NoteModel
        // We'll generate one or reuse existing if possible (but we can't extract easily from "MyNote.enc")
        // We'll generate a transient one for the Model, but file path relies on _currentFileName
        noteId = const Uuid().v4();
      }
    } else {
      // New Note -> New Structure
      noteId = const Uuid().v4();
    }

    String contentToSave = "";
    bool locked = false;

    // Get the content to save
    if (_isHtmlMode) {
      contentToSave = htmlController.text;
    } else {
      // Save as pure Delta JSON for maximum fidelity
      final delta = quillController.document.toDelta();
      contentToSave = jsonEncode(delta.toJson());
    }

    // Check if content is empty (logic remains similar but extracting plaintext from Delta or HTML)
    String plainText = "";
    if (_isHtmlMode) {
      plainText = htmlController.text.replaceAll(RegExp(r'<[^>]*>'), '').trim();
    } else {
      plainText = quillController.document.toPlainText().trim();
    }

    if (_currentFileName == null &&
        plainText.isEmpty &&
        titleController.text == "New Note") {
      print("Skipping save of empty new note");
      if (!isAutoSave) setBusy(false);
      return;
    }

    // Encrypt
    String encryptedContent = "";
    if (_currentPassword != null) {
      encryptedContent = _encryptionService.encrypt(
        contentToSave,
        password: _currentPassword,
      );
      locked = true;
    } else {
      encryptedContent = contentToSave;
    }

    final note = NoteModel(
      id: noteId,
      title: (titleController.text.trim().length < 40)
          ? (_isHtmlMode
                ? titleController.text
                : _generateTitleFromContent(plainText))
          : titleController.text,
      content: encryptedContent,
      isLocked: locked,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      attachments: _attachments,
    );

    // ... saving logic ...
    final jsonString = json.encode(note.toJson());
    final appEncrypted = _encryptionService.encryptApp(jsonString);

    if (isLegacy) {
      await _fileService.saveFile(appEncrypted, _currentFileName!);
    } else {
      await _fileService.saveNoteContent(noteId, appEncrypted);
      _currentFileName = "note_$noteId";
    }

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
  // endregion

  // region Import & Export
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
              "Size: ${await fileObj.length()} bytes\nPreview: ${content.length > 50 ? content.substring(0, 50) + '...' : content}",
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
    try {
      content = content.trim();

      // 1. Try Delta JSON
      if (content.startsWith('[') || content.startsWith('{')) {
        try {
          final jsonContent = jsonDecode(content);
          if (jsonContent is List) {
            quillController.document = Document.fromJson(jsonContent);
            quillController.moveCursorToPosition(
              quillController.document.length,
            );
            return;
          }
        } catch (e) {
          // Not JSON or failed to parse, fall through
        }
      }

      // 2. Try HTML
      if (content.startsWith('<')) {
        final delta = HtmlToDelta().convert(content);
        quillController.document = Document.fromDelta(delta);
      } else {
        // 3. Plain text
        quillController.document = Document()..insert(0, content);
      }
    } catch (e) {
      // Fallback
      print("Error loading content: $e");
      quillController.document = Document()..insert(0, content);
    }

    // Move cursor to end
    quillController.moveCursorToPosition(quillController.document.length);
  }

  void reset() {
    _currentFileName = null;
    _currentPassword = null;
    _isLocked = false;
    _isHtmlMode = false;
    _attachments = [];
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

  Future<Uint8List?> readAttachment(String attachmentId) async {
    if (_currentFileName == null || !_currentFileName!.startsWith('note_'))
      return null;
    final noteId = _currentFileName!.replaceFirst('note_', '');

    final encryptedBytes = await _fileService.readAttachment(
      noteId,
      attachmentId,
    );
    if (encryptedBytes == null) return null;

    return _encryptionService.decryptBinary(
      encryptedBytes,
      password: _currentPassword,
    );
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
