import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
// import 'dart:io'; // duplicate removed
import 'package:file_picker/file_picker.dart';
import '../../../core/viewmodels/base_viewmodel.dart';
import '../services/file_service.dart';
import '../services/background_service.dart';
import '../services/encryption_service.dart';
import '../models/note_model.dart';
import 'dart:convert';
import 'package:flutter_quill/flutter_quill.dart';
// Removed invalid quill_delta import
import '../services/semantic_html_converter_service.dart';
import 'package:flutter_quill_delta_from_html/flutter_quill_delta_from_html.dart';
import 'package:uuid/uuid.dart';
import 'package:code_text_field/code_text_field.dart';
import 'package:highlight/languages/xml.dart'; // XML handles HTML highlighting
import 'dart:typed_data';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import '../services/settings_service.dart';
import '../services/pack_service.dart';

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
  Timer? _searchDebounceTimer;
  Timer? _autoSaveDebounceTimer; // Minimal debounce for auto-save
  Timer? _htmlSyncTimer; // For live HTML sync from Delta
  StreamSubscription? _fileWatcherSubscription;
  final BackgroundService _backgroundService = BackgroundService();
  List<RecentFile> _recentFiles = [];
  List<RecentFile> _filteredFiles = [];
  List<AttachmentModel> _attachments = [];

  final ValueNotifier<List<AttachmentModel>> attachmentsNotifier =
      ValueNotifier([]);
  final ValueNotifier<bool> isLockedNotifier = ValueNotifier(false);
  final ValueNotifier<bool> isAutoSavingNotifier = ValueNotifier(false);

  /// Progress notifier for long-running operations like password change/removal.
  /// Format: "status message" or null when not in progress
  final ValueNotifier<String?> progressNotifier = ValueNotifier(null);

  final Map<String, String> _sessionPasswords = {};
  final Map<String, Uint8List> _attachmentCache = {};
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
      attachmentsNotifier.value = List.from(_attachments);
      // notifyListeners(); // Removed to reduce rebuilds

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
          attachmentsNotifier.value = List.from(_attachments);
          // notifyListeners();
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
          attachmentsNotifier.value = List.from(_attachments);
          // notifyListeners();
        }

        _scheduleAutoSave();
      } catch (e) {
        print("Error adding attachment: $e");
        // Remove placeholder on error
        _attachments.removeWhere((a) => a.id == tempId);
        attachmentsNotifier.value = List.from(_attachments);
        // notifyListeners();
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
    attachmentsNotifier.value = List.from(_attachments);
    _attachmentCache.remove(attachmentId);
    // notifyListeners();
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

    // Listen to changes for auto-save (minimal debounce to reduce timer churn)
    quillController.document.changes.listen((change) {
      if (!_isHtmlMode) {
        _autoSaveDebounceTimer?.cancel();
        _autoSaveDebounceTimer = Timer(const Duration(milliseconds: 50), () {
          onTextChanged();
        });

        // Live sync to HTML with debouncing
        _syncDeltaToHtml();
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

  /// Sync Delta to HTML asynchronously with debouncing.
  void _syncDeltaToHtml() {
    _htmlSyncTimer?.cancel();
    _htmlSyncTimer = Timer(const Duration(milliseconds: 300), () async {
      try {
        final delta = quillController.document.toDelta();
        final html = await compute(_deltaToHtmlTask, delta.toJson());

        // Only update if still in rich text mode (user didn't switch)
        if (!_isHtmlMode) {
          htmlController.text = html;
        }
      } catch (e) {
        debugPrint('Error syncing Delta to HTML: $e');
      }
    });
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

  Future<void> toggleEditorMode() async {
    setBusy(true);
    if (_isHtmlMode) {
      // Switch to Rich Text
      // Convert HTML string to Delta
      try {
        final html = htmlController.text;
        // Offload to background
        final deltaList = await compute(_htmlToDeltaTask, html);
        quillController.document = Document.fromJson(deltaList);
        // Move cursor to end to avoid issues
        quillController.moveCursorToPosition(quillController.document.length);
      } catch (e) {
        print("Error converting HTML to Delta: $e");
      }
      _isHtmlMode = false;
    } else {
      // Switch to HTML Editor
      // Convert Delta to HTML string
      final delta = quillController.document.toDelta();
      // Offload to background
      final html = await compute(_deltaToHtmlTask, delta.toJson());

      htmlController.text = html;
      _isHtmlMode = true;
    }
    notifyListeners();
    setBusy(false);
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
    _attachmentCache.clear();

    // Reset mode to Rich Text on new load for consistency
    _isHtmlMode = false;

    final content = await _fileService.readFile(fileName);
    if (content != null) {
      // Offload heavy parsing (Decryption + JSON Decode) to isolate
      final note = await compute(_parseNoteIsolate, content);

      if (note != null) {
        await _applyNoteModel(note, fileName);
      } else {
        // 3. Fallback to Plain Text
        print("Loading as plain text");
        _loadContentToQuill(content);
        titleController.text = _generateTitleFromContent(content);
        _isLocked = false;
        isLockedNotifier.value = false;
        _currentPassword = null;
      }

      notifyListeners(); // Keep this for now as it's a full load
    }
    setBusy(false);
  }

  Future<void> _applyNoteModel(NoteModel note, String fileName) async {
    _isLocked = note.isLocked;
    isLockedNotifier.value = _isLocked;
    _attachments = List.from(note.attachments);
    attachmentsNotifier.value = List.from(_attachments);

    if (note.isLocked) {
      // Check if we have a session password
      final sessionPass = _sessionPasswords[fileName];
      if (sessionPass != null) {
        // Unlock automatically
        await _unlockContent(note.content, sessionPass);
        _currentPassword = sessionPass;
      } else {
        // Locked state - clear editor
        _isLocked = true;
        isLockedNotifier.value = true;
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

  /// Removes password protection from the current note.
  /// Decrypts all attachments and saves the note without encryption.
  /// If [password] is provided, it will be used instead of the stored password.
  Future<bool> removePassword({String? password}) async {
    final effectivePassword = password ?? _currentPassword;
    if (effectivePassword == null || _currentFileName == null) return false;

    // Extract noteId from _currentFileName
    String noteId;
    if (_currentFileName!.startsWith('note_')) {
      noteId = _currentFileName!.replaceFirst('note_', '');
      if (noteId.contains('.')) {
        noteId = noteId.split('.').first;
      }
    } else {
      noteId = const Uuid().v4();
    }

    setBusy(true);
    try {
      final totalSteps =
          _attachments.length + 2; // content + attachments + saving
      int currentStep = 0;

      // Report starting
      progressNotifier.value = 'Decrypting content...';
      currentStep++;

      // 1. Decrypt all attachments and save them unencrypted
      final List<AttachmentModel> newAttachments = [];
      for (int i = 0; i < _attachments.length; i++) {
        final attachment = _attachments[i];
        final percent = ((currentStep / totalSteps) * 100).round();
        progressNotifier.value =
            'Decrypting $percent% (${attachment.fileName})';

        // Yield to event loop to keep UI responsive
        await Future.delayed(Duration.zero);

        final encryptedData = await _fileService.readAttachment(
          noteId,
          attachment.id,
        );
        if (encryptedData != null) {
          final decryptedData = await _encryptionService.decryptBinary(
            encryptedData,
            password: effectivePassword,
          );
          if (decryptedData.isNotEmpty) {
            // Re-encrypt with app key (no user password) and save with new ID
            final reEncryptedData = await _encryptionService.encryptBinary(
              decryptedData,
              password: null, // App key only, no user password
            );
            final newId = await _fileService.saveAttachment(
              reEncryptedData,
              noteId,
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
            // Decryption failed, keep original
            newAttachments.add(attachment);
          }
        } else {
          // No data found, keep original
          newAttachments.add(attachment);
        }
        currentStep++;
      }

      // 2. Update attachments list
      _attachments = newAttachments;
      attachmentsNotifier.value = List.from(_attachments);

      // 3. Clear password (content is already in memory unencrypted)
      _currentPassword = null;
      _sessionPasswords.remove(_currentFileName!);

      // 4. Save the note (will save without encryption since password is null)
      progressNotifier.value = 'Saving note...';
      await saveNote();

      progressNotifier.value = null; // Clear progress
      notifyListeners();
      return true;
    } catch (e) {
      print("Error removing password: $e");
      progressNotifier.value = null;
      return false;
    } finally {
      setBusy(false);
      progressNotifier.value = null;
    }
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
      isLockedNotifier.value = false;
      notifyListeners(); // Keep for unlock transition
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
      isLockedNotifier.value = true;
    } else {
      _loadContentToQuill(decrypted);
      _isLocked = false;
      isLockedNotifier.value = false;
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
      isLockedNotifier.value = true;
      quillController.document = Document();
      htmlController.clear();
      _attachmentCache.clear();
      notifyListeners();
    }
  }

  /// Changes the password for the current note only.
  /// If [oldPassword] is provided, it will be used instead of the stored password.
  Future<String> changePassword(
    String newPassword, {
    String? oldPassword,
  }) async {
    final effectiveOldPassword = oldPassword ?? _currentPassword;
    if (effectiveOldPassword == null) return "Error: No active password";
    if (_currentFileName == null) return "Error: No file selected";

    // Extract noteId from currentFileName
    String noteId;
    if (_currentFileName!.startsWith('note_')) {
      noteId = _currentFileName!.replaceFirst('note_', '');
      if (noteId.contains('.')) {
        noteId = noteId.split('.').first;
      }
    } else {
      noteId = const Uuid().v4();
    }

    setBusy(true);
    try {
      // 1. Get content from editor (already decrypted in memory)
      progressNotifier.value = 'Re-encrypting content...';
      await Future.delayed(Duration.zero);

      String contentToSave = "";
      if (_isHtmlMode) {
        contentToSave = htmlController.text;
      } else {
        final delta = quillController.document.toDelta();
        contentToSave = jsonEncode(delta.toJson());
      }

      // Re-encrypt content with new password
      final newEncryptedContent = await _encryptionService.encrypt(
        contentToSave,
        password: newPassword,
      );

      // 2. Re-encrypt all attachments
      final List<AttachmentModel> newAttachments = [];
      final totalAttach = _attachments.length;

      for (int i = 0; i < _attachments.length; i++) {
        final attachment = _attachments[i];
        progressNotifier.value =
            'Re-encrypting attachment ${i + 1}/$totalAttach...';
        await Future.delayed(Duration.zero);

        final encryptedData = await _fileService.readAttachment(
          noteId,
          attachment.id,
        );
        if (encryptedData != null) {
          final decryptedData = await _encryptionService.decryptBinary(
            encryptedData,
            password: effectiveOldPassword,
          );
          if (decryptedData.isNotEmpty) {
            final newEncryptedData = await _encryptionService.encryptBinary(
              decryptedData,
              password: newPassword,
            );
            final newId = await _fileService.saveAttachment(
              newEncryptedData,
              noteId,
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

      // 3. Update internal state
      _attachments = newAttachments;
      attachmentsNotifier.value = List.from(_attachments);
      _currentPassword = newPassword;
      _sessionPasswords[_currentFileName!] = newPassword;

      // 4. Build and save the note
      progressNotifier.value = 'Saving...';
      final note = NoteModel(
        id: noteId,
        title: titleController.text,
        content: newEncryptedContent,
        isLocked: true,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        attachments: newAttachments,
      );

      final jsonString = json.encode(note.toJson());
      final appEncrypted = await _encryptionService.encryptApp(jsonString);

      if (_currentFileName!.startsWith('note_')) {
        await _fileService.saveNoteContent(noteId, appEncrypted);
      } else {
        await _fileService.saveFile(appEncrypted, _currentFileName!);
      }

      print("Password changed for: $_currentFileName");
      return "Password changed successfully";
    } catch (e) {
      print("Error changing password: $e");
      return "Error: $e";
    } finally {
      setBusy(false);
      progressNotifier.value = null;
    }
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
        // Strip any file extension (e.g., .enc) from the noteId
        if (noteId.contains('.')) {
          noteId = noteId.split('.').first;
        }
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
      final ext = file.name.split('.').last.toLowerCase();

      // Handle pack files (binary data)
      if (ext == 'fnote' || ext == 'zip') {
        final data = await fileObj.readAsBytes();
        final packService = PackService(_encryptionService);

        if (ext == 'fnote') {
          if (packService.isPack(data)) {
            final isEncrypted = packService.isEncrypted(data);
            return ImportVerificationResult(
              isValid: true,
              message: "Note Pack File",
              previewInfo:
                  "Format: Binary Pack (.fnote)\nEncrypted: ${isEncrypted ? 'Yes (password required)' : 'No'}",
              isPack: true,
              isPackEncrypted: isEncrypted,
            );
          } else {
            return ImportVerificationResult(
              isValid: false,
              message: "Invalid pack file format",
            );
          }
        } else if (ext == 'zip') {
          if (packService.isZip(data)) {
            return ImportVerificationResult(
              isValid: true,
              message: "ZIP Archive",
              previewInfo: "Format: ZIP Archive\nSize: ${data.length} bytes",
              isPack: true,
              isPackEncrypted: false, // We can't easily detect this for ZIP
            );
          } else {
            return ImportVerificationResult(
              isValid: false,
              message: "Invalid ZIP file",
            );
          }
        }
      }

      // Handle text-based files
      final content = await fileObj.readAsString();

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

  /// Export the current note as a pack file (binary or zip) with optional archive password
  /// Note: Content is packed as-is (preserving original encryption), archive password is separate
  Future<void> exportNotePack({
    required ExportFormat format,
    String? password,
  }) async {
    if (_currentFileName == null) return;

    setBusy(true);
    try {
      // 1. Get current note data (encrypted)
      final content = await _fileService.readFile(_currentFileName!);
      if (content == null) {
        setBusy(false);
        return;
      }

      // Parse to get note metadata (but keep original encrypted content in file)
      NoteModel? note;
      try {
        final appDecrypted = await _encryptionService.decryptApp(content);
        if (appDecrypted.isNotEmpty) {
          final jsonMap = json.decode(appDecrypted);
          note = NoteModel.fromJson(jsonMap);
        }
      } catch (e) {
        print('Error parsing note for export: $e');
      }

      if (note == null) {
        setBusy(false);
        return;
      }

      // 2. Keep the note content as-is (don't decrypt file password protected content)
      // The note.isLocked flag indicates if the CONTENT is password protected
      final exportNote = NoteModel(
        id: note.id,
        title: note.title,
        content: note.content, // Keep encrypted content as-is
        isLocked: note.isLocked, // Preserve lock status
        timestamp: note.timestamp,
        attachments: note.attachments,
      );

      // 3. Gather all attachment data AS-IS (encrypted)
      final attachmentData = <String, Uint8List>{};
      String noteId = note.id;

      for (final attachment in note.attachments) {
        final encryptedBytes = await _fileService.readAttachment(
          noteId,
          attachment.id,
        );
        if (encryptedBytes != null) {
          // Keep attachments encrypted as-is
          attachmentData[attachment.id] = encryptedBytes;
        }
      }

      // 4. Create pack (archive password is separate from file password)
      final packService = PackService(_encryptionService);
      Uint8List packData;
      String extension;

      if (format == ExportFormat.zip) {
        packData = await packService.createZipPack(
          exportNote,
          attachmentData,
          password: password, // This is ARCHIVE password
        );
        extension = 'zip';
      } else {
        packData = await packService.createPack(
          exportNote,
          attachmentData,
          password: password, // This is ARCHIVE password
        );
        extension = 'fnote';
      }

      // 5. Save or share based on platform
      final safeTitle = note.title.replaceAll(RegExp(r'[^\w\s-]'), '').trim();
      final fileName = '${safeTitle.isEmpty ? "note" : safeTitle}.$extension';

      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        // Desktop: use file picker to save
        final outputPath = await FilePicker.platform.saveFile(
          dialogTitle: 'Save Note Package',
          fileName: fileName,
          type: FileType.custom,
          allowedExtensions: [extension],
        );

        if (outputPath != null) {
          final file = File(outputPath);
          await file.writeAsBytes(packData);
        }
      } else {
        // Mobile: use share sheet
        final tempDir = await getTemporaryDirectory();
        final tempFile = File('${tempDir.path}/$fileName');
        await tempFile.writeAsBytes(packData);
        await Share.shareXFiles([XFile(tempFile.path)], text: note.title);
      }
    } catch (e) {
      print('Error exporting note pack: $e');
    } finally {
      setBusy(false);
    }
  }

  /// Import a note pack file (.fnote or .zip)
  /// Returns the noteId on success, null on failure
  /// archivePassword: password to decrypt the archive itself
  /// Content inside is preserved as-is (with original file password encryption if any)
  Future<String?> importNotePack(
    String filePath, {
    String? archivePassword,
  }) async {
    setBusy(true);
    try {
      final file = File(filePath);
      final data = await file.readAsBytes();

      final packService = PackService(_encryptionService);
      PackResult? result;

      if (packService.isPack(data)) {
        // Binary pack - use archive password to decrypt the pack
        result = await packService.extractPack(data, password: archivePassword);
      } else if (packService.isZip(data)) {
        // ZIP pack - use archive password to decrypt the pack
        result = await packService.extractZipPack(
          data,
          password: archivePassword,
        );
      }

      if (result == null) {
        setBusy(false);
        return null;
      }

      // Save the imported note
      final noteId = const Uuid().v4();

      // Save attachments AS-IS (they're already encrypted with file password)
      final newAttachments = <AttachmentModel>[];
      for (final entry in result.attachments.entries) {
        // Save the encrypted attachment data directly (no re-encryption)
        final attachmentId = await _fileService.saveAttachment(
          entry.value, // Already encrypted with file password
          noteId,
        );

        // Find original attachment model for metadata
        final original = result.note.attachments.firstWhere(
          (a) => a.id == entry.key,
          orElse: () => AttachmentModel(id: entry.key, fileName: 'attachment'),
        );

        newAttachments.add(
          AttachmentModel(
            id: attachmentId,
            fileName: original.fileName,
            size: entry.value.length,
            mimeType: original.mimeType,
          ),
        );
      }

      // Create the imported note with original content (encrypted with file password if any)
      final importedNote = NoteModel(
        id: noteId,
        title: result.note.title,
        content: result
            .note
            .content, // Keep content as-is (may be encrypted with file password)
        isLocked: result.note.isLocked, // Preserve original lock status
        timestamp: DateTime.now().millisecondsSinceEpoch,
        attachments: newAttachments,
      );

      final jsonString = json.encode(importedNote.toJson());
      final appEncrypted = await _encryptionService.encryptApp(jsonString);
      await _fileService.saveNoteContent(noteId, appEncrypted);

      await loadRecentFiles();
      setBusy(false);
      return "note_$noteId";
    } catch (e) {
      print('Error importing note pack: $e');
      setBusy(false);
      return null;
    }
  }

  /// Check if a file is an encrypted pack (needs password)
  Future<bool> isPackEncrypted(String filePath) async {
    try {
      final file = File(filePath);
      final data = await file.readAsBytes();
      final packService = PackService(_encryptionService);

      if (packService.isPack(data)) {
        return packService.isEncrypted(data);
      }
      // For ZIP, we try to extract without password first
      // If it fails, it might be encrypted
      return false;
    } catch (e) {
      return false;
    }
  }

  /// Pick a pack file for import
  Future<PlatformFile?> pickImportPackFile() async {
    final result = await _fileService.pickFile(
      allowedExtensions: ['txt', 'enc', 'fnote', 'zip'],
    );
    return result?.files.single;
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
    _attachmentCache.clear();
    notifyListeners();
  }

  // region Lifecycle
  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    _debounceTimer?.cancel();
    _autoSaveDebounceTimer?.cancel();
    _searchDebounceTimer?.cancel();
    _htmlSyncTimer?.cancel();
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
    _scheduleAutoSave();
  }

  // Title generation removed - was causing performance issues
  // Title now updates only on save

  // Background isolate for auto-saving note content
  static Future<void> _autoSaveIsolate(Map<String, dynamic> args) async {
    final fileName = args['fileName'] as String?;
    final plainText = args['plainText'] as String?;
    final isPasswordSet = args['isPasswordSet'] as bool;
    final password = args['password'] as String?;

    if (fileName == null || plainText == null) return;
    try {
      String dataToSave = plainText;
      if (isPasswordSet && password != null) {
        // Use async encryption within isolate
        dataToSave = await EncryptionService().encryptApp(plainText);
      }
      final file = File('${Directory.current.path}/$fileName');
      await file.writeAsString(dataToSave);
    } catch (e) {
      // Silently ignore errors in background save
    }
  }

  static Future<NoteModel?> _parseNoteIsolate(String content) async {
    // 1. Try App Decryption
    try {
      final appDecrypted = EncryptionService.decryptAppSync(content);
      if (appDecrypted.isNotEmpty) {
        final jsonMap = json.decode(appDecrypted);
        if (jsonMap is Map<String, dynamic>) {
          return NoteModel.fromJson(jsonMap);
        }
      }
    } catch (e) {
      // Decryption failed
    }

    // 2. Try Legacy JSON
    try {
      final jsonMap = json.decode(content);
      if (jsonMap is Map<String, dynamic> &&
          (jsonMap.containsKey('title') || jsonMap.containsKey('content'))) {
        return NoteModel.fromJson(jsonMap);
      }
    } catch (e) {
      // Not JSON
    }

    return null;
  }

  void _scheduleAutoSave() {
    if (_currentFileName != null || isPasswordSet) {
      _autoSaveTimer?.cancel();
      _autoSaveTimer = Timer(const Duration(seconds: 2), () async {
        // Offload save to background isolate to avoid UI thread blocking
        final plainText = quillController.document.toPlainText();
        await compute(_autoSaveIsolate, {
          'fileName': _currentFileName,
          'plainText': plainText,
          'isPasswordSet': isPasswordSet,
          'password': _currentPassword,
        });
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

    if (_attachmentCache.containsKey(attachmentId)) {
      return _attachmentCache[attachmentId];
    }

    final encryptedBytes = await _fileService.readAttachment(
      noteId,
      attachmentId,
    );
    if (encryptedBytes == null) return null;

    final decrypted = await _encryptionService.decryptBinary(
      encryptedBytes,
      password: _currentPassword,
    );
    _attachmentCache[attachmentId] = decrypted;
    return decrypted;
  }

  // endregion
}

class ImportVerificationResult {
  final bool isValid;
  final String message;
  final String? previewInfo;
  final bool isPack;
  final bool isPackEncrypted;

  ImportVerificationResult({
    required this.isValid,
    required this.message,
    this.previewInfo,
    this.isPack = false,
    this.isPackEncrypted = false,
  });
}

/// Synchronous task for compute() - converts HTML to Quill Delta JSON.
/// Must be synchronous for compute() to work correctly.
List<dynamic> _htmlToDeltaTask(String html) {
  final delta = HtmlToDelta().convert(html);
  return delta.toJson();
}

/// Synchronous task for compute() - converts Quill Delta JSON to semantic HTML.
/// Must be synchronous for compute() to work correctly.
String _deltaToHtmlTask(List<dynamic> deltaJson) {
  return SemanticHtmlConverterService().convert(deltaJson);
}
