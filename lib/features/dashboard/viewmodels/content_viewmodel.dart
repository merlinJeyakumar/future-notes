import 'dart:async';
import 'package:flutter/foundation.dart';
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
import 'package:flutter_image_compress/flutter_image_compress.dart';
import '../services/settings_service.dart';

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
  Timer? _searchDebounceTimer;
  StreamSubscription? _fileWatcherSubscription;
  final BackgroundService _backgroundService = BackgroundService();
  List<RecentFile> _recentFiles = [];
  List<RecentFile> _filteredFiles = [];
  List<AttachmentModel> _attachments = [];

  final Map<String, String> _sessionPasswords = {};
  bool _isLocked = false;

  bool get isLocked => _isLocked;

  String _searchQuery = "";

  List<RecentFile> get recentFiles =>
      _searchQuery.isEmpty ? _recentFiles : _filteredFiles;
  List<AttachmentModel> get attachments => _attachments;
  bool get isPasswordSet => _currentPassword != null;
  String? get currentFileName => _currentFileName;

  late final CodeController htmlController;
  bool _isHtmlMode = false;
  bool get isHtmlMode => _isHtmlMode;

  Future<void> pickAttachment() async {
    final result = await _fileService.pickFile(allowedExtensions: null);

    if (result != null && result.files.single.path != null) {
      // Don't block UI with setBusy

      final path = result.files.single.path!;
      final originalFile = File(path);
      final fileName = result.files.single.name;
      final tempId = const Uuid().v4();
      final ext = fileName.split('.').last.toLowerCase();

      // 1. Add Placeholder
      final placeholder = AttachmentModel(
        id: tempId,
        fileName: fileName,
        size: 0,
        mimeType: 'application/octet-stream', // Unknown pending
        isLoading: true,
      );
      _attachments.add(placeholder);
      notifyListeners();

      // Prepare Note ID
      String noteId;
      if (_currentFileName != null) {
        if (_currentFileName!.startsWith('note_')) {
          noteId = _currentFileName!.replaceFirst('note_', '');
        } else {
          noteId = const Uuid().v4();
          _currentFileName = "note_$noteId";
        }
      } else {
        noteId = const Uuid().v4();
        _currentFileName = "note_$noteId";
      }

      try {
        // 2. Check Size
        int size = await originalFile.length();
        if (size > 10 * 1024 * 1024 * 1024) {
          _attachments.removeWhere((a) => a.id == tempId);
          notifyListeners();
          print("File too large > 10GB");
          return;
        }

        // 3. Compress
        Uint8List bytes;
        final settings = SettingsService();
        final isImage = ['jpg', 'jpeg', 'png', 'webp', 'heic'].contains(ext);

        if (isImage && settings.compressionLevel != CompressionLevel.none) {
          int quality = 85;
          int minWidth = 1920;
          int minHeight = 1080;
          if (settings.compressionLevel == CompressionLevel.high) {
            quality = 50;
            minWidth = 1024;
            minHeight = 768;
          } else if (settings.compressionLevel == CompressionLevel.medium) {
            quality = 70;
            minWidth = 1280;
            minHeight = 720;
          }
          final compressed = await FlutterImageCompress.compressWithFile(
            path,
            quality: quality,
            minWidth: minWidth,
            minHeight: minHeight,
          );
          if (compressed != null) {
            bytes = compressed;
            size = bytes.length;
          } else {
            bytes = await originalFile.readAsBytes();
          }
        } else {
          bytes = await originalFile.readAsBytes();
        }

        // 4. Encrypt (Background via Service)
        final encryptedBytes = await _encryptionService.encryptBinary(
          bytes,
          password: _currentPassword,
        );

        // 5. Save
        final attachmentId = await _fileService.saveAttachment(
          encryptedBytes,
          noteId,
        );

        // 6. Update List (Replace placeholder)
        final index = _attachments.indexWhere((a) => a.id == tempId);
        if (index != -1) {
          _attachments[index] = AttachmentModel(
            id: attachmentId,
            fileName: fileName,
            size: size,
            mimeType: isImage ? 'image/$ext' : 'application/octet-stream',
            isLoading: false,
          );
          notifyListeners();
        }

        _scheduleAutoSave();
      } catch (e) {
        print("Error adding attachment: $e");
        // Remove placeholder on error
        _attachments.removeWhere((a) => a.id == tempId);
        notifyListeners();
      }
    }
  }

  Future<void> exportAttachment(AttachmentModel attachment) async {
    // 1. Pick location first
    final String? outputFile = await FilePicker.platform.saveFile(
      dialogTitle: 'Save Attachment',
      fileName: attachment.fileName,
      lockParentWindow: true,
    );

    if (outputFile == null) return;

    // 2. Process and Save
    setBusy(true);
    try {
      final data = await readAttachment(attachment.id);
      if (data != null) {
        final file = File(outputFile);
        await file.writeAsBytes(data);
      }
    } catch (e) {
      print("Error saving attachment: $e");
    } finally {
      setBusy(false);
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

    // Ensure settings are loaded before loading files
    _initAsync();
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

  Future<void> _initAsync() async {
    // Wait for settings to load so custom data path is available
    await SettingsService().init();
    loadRecentFiles();
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
        final appDecrypted = await _encryptionService.decryptApp(content);

        if (appDecrypted.isNotEmpty) {
          final jsonMap = json.decode(appDecrypted);
          final note = NoteModel.fromJson(jsonMap);
          await _applyNoteModel(note, fileName);
          loaded = true;
        }
      } catch (e) {
        print("App decryption failed: $e");
      }

      // 2. Try Legacy JSON (Unencrypted old notes)
      if (!loaded) {
        try {
          final jsonMap = json.decode(content);
          // Simple validation
          if (jsonMap is Map<String, dynamic> &&
              (jsonMap.containsKey('title') ||
                  jsonMap.containsKey('content'))) {
            final note = NoteModel.fromJson(jsonMap);
            await _applyNoteModel(note, fileName);
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

  Future<void> _applyNoteModel(NoteModel note, String fileName) async {
    _isLocked = note.isLocked;
    _attachments = List.from(note.attachments);

    if (note.isLocked) {
      // Check if we have a session password
      final sessionPass = _sessionPasswords[fileName];
      if (sessionPass != null) {
        // Unlock automatically
        await _unlockContent(note.content, sessionPass);
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
    _scheduleAutoSave();
  }

  Future<bool> unlockNote(String password) async {
    if (_currentFileName == null) return false;

    try {
      final jsonString = await _fileService.readFile(_currentFileName!);
      if (jsonString == null) return false;

      // 1. App Decrypt
      final appDecrypted = await _encryptionService.decryptApp(jsonString);
      final jsonMap = json.decode(appDecrypted);
      final note = NoteModel.fromJson(jsonMap);

      // 2. User Decrypt
      final decryptedContent = await _encryptionService.decrypt(
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

  Future<void> _unlockContent(String encryptedContent, String password) async {
    final decrypted = await _encryptionService.decrypt(
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

  Future<int> changePassword(String newPassword) async {
    final oldPassword = _currentPassword;
    if (oldPassword == null) return 0;

    setBusy(true);
    int count = 0;
    try {
      final files = await _fileService.getRecentFiles();
      for (final fileName in files) {
        try {
          // Read file
          final content = await _fileService.readFile(fileName);
          if (content == null) continue;

          // Decrypt App Layer
          final appDecrypted = await _encryptionService.decryptApp(content);
          if (appDecrypted.isEmpty) continue; // Not app encrypted or fail

          // Parse
          final jsonMap = json.decode(appDecrypted);
          final note = NoteModel.fromJson(jsonMap);

          // Check if locked
          if (note.isLocked) {
            // Try decrypt content
            final decrypted = await _encryptionService.decrypt(
              note.content,
              password: oldPassword,
            );
            if (decrypted.startsWith("Error decrypting")) {
              print("Skipping $fileName: Decryption failed with old password");
              continue;
            }

            // Re-encrypt content
            final newEncrypted = await _encryptionService.encrypt(
              decrypted,
              password: newPassword,
            );

            // Re-encrypt attachments
            final List<AttachmentModel> newAttachments = [];

            for (final attachment in note.attachments) {
              final oldData = await _fileService.readAttachment(
                note.id,
                attachment.id,
              );
              if (oldData != null) {
                final decryptedData = await _encryptionService.decryptBinary(
                  oldData,
                  password: oldPassword,
                );
                if (decryptedData.isNotEmpty) {
                  final newData = await _encryptionService.encryptBinary(
                    decryptedData,
                    password: newPassword,
                  );
                  // Generate new ID for re-encrypted attachment
                  final newId = await _fileService.saveAttachment(
                    newData,
                    note.id,
                  );

                  newAttachments.add(
                    AttachmentModel(
                      id: newId,
                      fileName: attachment.fileName,
                      size: attachment.size,
                      mimeType: attachment.mimeType,
                      isLoading: false,
                    ),
                  );
                } else {
                  newAttachments.add(attachment);
                }
              } else {
                newAttachments.add(attachment);
              }
            }

            // Update Note
            final newNote = NoteModel(
              id: note.id,
              title: note.title,
              content: newEncrypted,
              isLocked: true, // Remains locked
              timestamp: note.timestamp,
              attachments: newAttachments,
            );

            // Encrypt App Layer
            final newJson = json.encode(newNote.toJson());
            final newAppEncrypted = await _encryptionService.encryptApp(
              newJson,
            );

            // Save
            if (fileName.startsWith('note_')) {
              await _fileService.saveNoteContent(note.id, newAppEncrypted);
            } else {
              await _fileService.saveFile(newAppEncrypted, fileName);
            }

            count++;

            // If this is the current file, update session
            if (_currentFileName == fileName) {
              _currentPassword = newPassword;
              _sessionPasswords[fileName] = newPassword;
            }
          }
        } catch (e) {
          print("Error processing $fileName: $e");
        }
      }
    } finally {
      setBusy(false);
    }
    return count;
  }

  void setSearchQuery(String query) {
    _searchQuery = query;

    if (_searchDebounceTimer?.isActive ?? false) _searchDebounceTimer!.cancel();

    if (query.isEmpty) {
      _filteredFiles = [];
      notifyListeners();
      return;
    }

    _searchDebounceTimer = Timer(const Duration(milliseconds: 300), () async {
      final results = await compute(_filterFiles, {
        'files': _recentFiles,
        'query': query,
      });
      _filteredFiles = results;
      notifyListeners();
    });
  }

  static List<RecentFile> _filterFiles(Map<String, dynamic> params) {
    final List<RecentFile> files = params['files'];
    final String query = params['query'].toString().toLowerCase();

    return files.where((file) {
      final title = file.title.toLowerCase();
      return title.contains(query);
    }).toList();
  }

  // endregion

  // region Saving
  Future<void> saveNote({bool isAutoSave = false}) async {
    if (!isAutoSave) setBusy(true);

    if (!isAutoSave) await Future.delayed(const Duration(seconds: 1));

    String? noteId;
    bool isLegacy = false;

    if (_currentFileName != null) {
      if (_currentFileName!.startsWith('note_')) {
        noteId = _currentFileName!.replaceFirst('note_', '');
      } else {
        isLegacy = true;
        noteId = const Uuid().v4();
      }
    } else {
      noteId = const Uuid().v4();
    }

    String contentToSave = "";
    bool locked = false;

    if (_isHtmlMode) {
      contentToSave = htmlController.text;
    } else {
      final delta = quillController.document.toDelta();
      contentToSave = jsonEncode(delta.toJson());
    }

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

    String encryptedContent = "";
    if (_currentPassword != null) {
      encryptedContent = await _encryptionService.encrypt(
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

    final jsonString = json.encode(note.toJson());
    final appEncrypted = await _encryptionService.encryptApp(jsonString);

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
          final appDecrypted = await _encryptionService.decryptApp(content);
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
    _titleUpdateTimer?.cancel();
    _titleUpdateTimer = Timer(const Duration(milliseconds: 800), () {
      try {
        String text = quillController.document.toPlainText();
        if (titleController.text.trim().length < 40 ||
            titleController.text == "New Note") {
          final generatedTitle = _generateTitleFromContent(text);
          if (generatedTitle != "New Note" &&
              generatedTitle != titleController.text) {
            titleController.text = generatedTitle;
          }
        }
      } catch (e) {
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
    line = line.replaceAll(RegExp(r'^[\s#\*\->]+'), '');
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

    return await _encryptionService.decryptBinary(
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
