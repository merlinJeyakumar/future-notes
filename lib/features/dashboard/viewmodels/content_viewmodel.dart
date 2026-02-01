import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:file_picker/file_picker.dart';
import '../../../core/viewmodels/base_viewmodel.dart';
import '../services/file_service.dart';
import '../services/background_service.dart';
import '../services/encryption_service.dart';
import '../models/note_model.dart';
import 'dart:convert';
import '../core/i_rich_text_editor.dart';
import '../core/appflowy_editor_adapter.dart';
import 'package:uuid/uuid.dart';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import '../services/settings_service.dart';
import '../services/pack_service.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:htmltopdfwidgets/htmltopdfwidgets.dart' as htpdf;

class ContentViewModel extends BaseViewModel {
  final IFileService _fileService;
  final IEncryptionService _encryptionService;

  // Rich text editor adapter - decoupled from specific implementation
  late IRichTextEditor _richTextEditor;

  // Public getter for UI to access editor interface
  IRichTextEditor get richTextEditor => _richTextEditor;

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

  /// Snackbar notifier for showing quick feedback messages
  final ValueNotifier<String?> snackbarNotifier = ValueNotifier(null);

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

  Future<void> pickAttachment() async {
    final result = await _fileService.pickFile(allowedExtensions: null);

    if (result != null && result.files.isNotEmpty) {
      // Immediate feedback to user
      final count = result.files.length;
      snackbarNotifier.value =
          'Processing $count file${count > 1 ? 's' : ''}...';

      // Process all selected files
      for (final platformFile in result.files) {
        if (platformFile.path == null) continue;

        final path = platformFile.path!;
        final originalFile = File(path);
        final fileName = platformFile.name;
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
            snackbarNotifier.value = 'File too large: $fileName';
            continue;
          }

          // 3. Compress
          Uint8List bytes;
          final settings = SettingsService();
          // PNG excluded from compression (lossless format, compression not effective)
          final isCompressible = ['jpg', 'jpeg', 'webp', 'heic'].contains(ext);

          if (isCompressible &&
              settings.compressionLevel != CompressionLevel.none) {
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
            try {
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
            } catch (e) {
              // Compression failed, use original file
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
              mimeType:
                  ['jpg', 'jpeg', 'png', 'webp', 'heic', 'gif'].contains(ext)
                  ? 'image/$ext'
                  : 'application/octet-stream',
              isLoading: false,
            );
            attachmentsNotifier.value = List.from(_attachments);
          }
        } catch (e) {
          print("Error adding attachment: $e");
          // Remove placeholder on error
          _attachments.removeWhere((a) => a.id == tempId);
          attachmentsNotifier.value = List.from(_attachments);
        }
      }

      _scheduleAutoSave();
    }
  }

  /// Export the current note content as an HTML file.
  /// On mobile, opens system share sheet. On desktop, uses save dialog.
  Future<void> exportAsHtml() async {
    final title = titleController.text.trim();
    final suggestedName = title.isEmpty
        ? 'note'
        : title.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');

    setBusy(true);
    try {
      // Get HTML from editor's built-in conversion
      final htmlContent = _richTextEditor.getDocumentHtml();

      // Wrap in a complete HTML document with styling
      final fullHtml =
          '''<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>$title</title>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; line-height: 1.6; max-width: 800px; margin: 0 auto; padding: 20px; }
    h1, h2, h3 { margin-top: 1.5em; margin-bottom: 0.5em; }
    ul, ol { padding-left: 2em; }
    blockquote { border-left: 4px solid #ccc; margin: 1em 0; padding-left: 1em; color: #666; }
    code { background: #f4f4f4; padding: 0.2em 0.4em; border-radius: 3px; }
    pre { background: #f4f4f4; padding: 1em; overflow-x: auto; border-radius: 6px; }
    img { max-width: 100%; height: auto; }
  </style>
</head>
<body>
$htmlContent
</body>
</html>''';

      // Check if we're on mobile (Android/iOS)
      final isMobile =
          defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS;

      if (isMobile) {
        // Use system share sheet on mobile
        final tempDir = await getTemporaryDirectory();
        final tempFile = File('${tempDir.path}/$suggestedName.html');
        await tempFile.writeAsString(fullHtml);

        await Share.shareXFiles([
          XFile(tempFile.path),
        ], subject: title.isNotEmpty ? title : 'Note Export');
        snackbarNotifier.value = 'Shared HTML';
      } else {
        // Use file save dialog on desktop
        final String? outputFile = await FilePicker.platform.saveFile(
          dialogTitle: 'Export as HTML',
          fileName: '$suggestedName.html',
          lockParentWindow: true,
          type: FileType.custom,
          allowedExtensions: ['html'],
        );

        if (outputFile == null) {
          setBusy(false);
          return;
        }

        final file = File(outputFile);
        await file.writeAsString(fullHtml);
        snackbarNotifier.value = 'Exported to HTML';
      }
    } catch (e) {
      snackbarNotifier.value = 'Export failed: $e';
    } finally {
      setBusy(false);
    }
  }

  /// Export the current note content as a PDF file.
  /// On mobile, opens system share sheet. On desktop, uses save dialog.
  Future<void> exportAsPdf() async {
    final title = titleController.text.trim();
    final suggestedName = title.isEmpty
        ? 'note'
        : title.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');

    setBusy(true);
    try {
      // Get HTML from editor for conversion
      final htmlContent = _richTextEditor.getDocumentHtml();

      // Wrap in a complete HTML document for better styling
      final fullHtml =
          '''
<html>
<head>
  <style>
    body { font-family: Arial, sans-serif; line-height: 1.6; }
    h1 { font-size: 24px; font-weight: bold; margin-top: 16px; margin-bottom: 8px; }
    h2 { font-size: 20px; font-weight: bold; margin-top: 14px; margin-bottom: 6px; }
    h3 { font-size: 18px; font-weight: bold; margin-top: 12px; margin-bottom: 4px; }
    p { margin: 8px 0; }
    ul, ol { padding-left: 20px; }
    blockquote { border-left: 3px solid #ccc; margin: 10px 0; padding-left: 15px; color: #666; }
    code { background: #f4f4f4; padding: 2px 4px; }
  </style>
</head>
<body>
${title.isNotEmpty ? '<h1>$title</h1>' : ''}
$htmlContent
</body>
</html>
''';

      // Convert HTML to PDF widgets using htmltopdfwidgets
      final pdfWidgets = await htpdf.HTMLToPdf().convert(
        fullHtml,
        useNewEngine:
            true, // Use new browser rendering engine for better CSS support
      );

      final pdf = pw.Document();
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(40),
          maxPages: 100,
          build: (context) => pdfWidgets,
        ),
      );

      final bytes = await pdf.save();

      // Check if we're on mobile (Android/iOS)
      final isMobile =
          defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS;

      if (isMobile) {
        // Use system share sheet on mobile
        final tempDir = await getTemporaryDirectory();
        final tempFile = File('${tempDir.path}/$suggestedName.pdf');
        await tempFile.writeAsBytes(bytes);

        await Share.shareXFiles([
          XFile(tempFile.path),
        ], subject: title.isNotEmpty ? title : 'Note Export');
        snackbarNotifier.value = 'Shared PDF';
      } else {
        // Use file save dialog on desktop
        final String? outputFile = await FilePicker.platform.saveFile(
          dialogTitle: 'Export as PDF',
          fileName: '$suggestedName.pdf',
          lockParentWindow: true,
          type: FileType.custom,
          allowedExtensions: ['pdf'],
        );

        if (outputFile == null) {
          setBusy(false);
          return;
        }

        final file = File(outputFile);
        await file.writeAsBytes(bytes);
        snackbarNotifier.value = 'Exported to PDF';
      }
    } catch (e) {
      snackbarNotifier.value = 'Export failed: $e';
    } finally {
      setBusy(false);
    }
  }

  /// Build PDF content from document JSON structure.
  /// Parses the AppFlowy document format and creates styled PDF widgets.
  List<pw.Widget> _buildPdfContent() {
    final widgets = <pw.Widget>[];

    try {
      final jsonStr = _richTextEditor.getDocumentJson();
      final docData = jsonDecode(jsonStr) as Map<String, dynamic>;
      final document = docData['document'] as Map<String, dynamic>?;
      if (document == null) return widgets;

      final children = document['children'] as List<dynamic>? ?? [];

      for (final child in children) {
        final node = child as Map<String, dynamic>;
        final widget = _nodeToPdfWidget(node);
        if (widget != null) {
          widgets.add(widget);
        }
      }
    } catch (e) {
      // Fall back to plain text if JSON parsing fails
      final plainText = _richTextEditor.getPlainText();
      for (final line in plainText.split('\n')) {
        if (line.trim().isEmpty) {
          widgets.add(pw.SizedBox(height: 8));
        } else {
          widgets.add(pw.Paragraph(text: line));
        }
      }
    }

    return widgets;
  }

  /// Convert a document node to a PDF widget.
  pw.Widget? _nodeToPdfWidget(Map<String, dynamic> node) {
    final type = node['type'] as String?;
    final delta = node['delta'] as List<dynamic>?;
    final attrs = node['attributes'] as Map<String, dynamic>? ?? {};

    switch (type) {
      case 'heading':
        final level = attrs['level'] as int? ?? 1;
        final fontSize =
            {1: 28.0, 2: 24.0, 3: 20.0, 4: 18.0, 5: 16.0, 6: 14.0}[level] ??
            16.0;
        return pw.Container(
          margin: const pw.EdgeInsets.only(top: 16, bottom: 8),
          child: pw.RichText(
            text: _deltaToTextSpan(delta, baseFontSize: fontSize, bold: true),
          ),
        );

      case 'paragraph':
        if (delta == null || delta.isEmpty) {
          return pw.SizedBox(height: 8);
        }
        return pw.Container(
          margin: const pw.EdgeInsets.only(bottom: 8),
          child: pw.RichText(text: _deltaToTextSpan(delta)),
        );

      case 'bulleted_list':
        return pw.Container(
          margin: const pw.EdgeInsets.only(left: 20, bottom: 4),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('• ', style: const pw.TextStyle(fontSize: 14)),
              pw.Expanded(child: pw.RichText(text: _deltaToTextSpan(delta))),
            ],
          ),
        );

      case 'numbered_list':
        return pw.Container(
          margin: const pw.EdgeInsets.only(left: 20, bottom: 4),
          child: pw.RichText(text: _deltaToTextSpan(delta)),
        );

      case 'quote':
        return pw.Container(
          margin: const pw.EdgeInsets.symmetric(vertical: 8),
          padding: const pw.EdgeInsets.only(left: 12),
          decoration: const pw.BoxDecoration(
            border: pw.Border(
              left: pw.BorderSide(width: 3, color: PdfColors.grey400),
            ),
          ),
          child: pw.RichText(
            text: _deltaToTextSpan(
              delta,
              italic: true,
              color: PdfColors.grey700,
            ),
          ),
        );

      case 'code':
        final text =
            delta?.map((op) => op['insert'] as String? ?? '').join() ?? '';
        return pw.Container(
          margin: const pw.EdgeInsets.symmetric(vertical: 8),
          padding: const pw.EdgeInsets.all(12),
          decoration: pw.BoxDecoration(
            color: PdfColors.grey200,
            borderRadius: pw.BorderRadius.circular(4),
          ),
          child: pw.Text(
            text,
            style: pw.TextStyle(font: pw.Font.courier(), fontSize: 12),
          ),
        );

      case 'divider':
        return pw.Container(
          margin: const pw.EdgeInsets.symmetric(vertical: 12),
          child: pw.Divider(thickness: 1, color: PdfColors.grey400),
        );

      default:
        // Unknown type - try to extract text
        if (delta != null && delta.isNotEmpty) {
          return pw.Container(
            margin: const pw.EdgeInsets.only(bottom: 8),
            child: pw.RichText(text: _deltaToTextSpan(delta)),
          );
        }
        return null;
    }
  }

  /// Convert delta operations to PDF TextSpan with formatting.
  pw.TextSpan _deltaToTextSpan(
    List<dynamic>? delta, {
    double baseFontSize = 14,
    bool bold = false,
    bool italic = false,
    PdfColor color = PdfColors.black,
  }) {
    if (delta == null || delta.isEmpty) {
      return const pw.TextSpan(text: '');
    }

    final spans = <pw.TextSpan>[];

    for (final op in delta) {
      final insert = op['insert'] as String? ?? '';
      final attrs = op['attributes'] as Map<String, dynamic>? ?? {};

      // Build text style from attributes
      final isBold = bold || attrs['bold'] == true;
      final isItalic = italic || attrs['italic'] == true;
      final isUnderline = attrs['underline'] == true;
      final isStrikethrough = attrs['strikethrough'] == true;
      final fontSize = (attrs['fontSize'] as num?)?.toDouble() ?? baseFontSize;

      pw.TextDecoration? decoration;
      if (isUnderline && isStrikethrough) {
        decoration = pw.TextDecoration.combine([
          pw.TextDecoration.underline,
          pw.TextDecoration.lineThrough,
        ]);
      } else if (isUnderline) {
        decoration = pw.TextDecoration.underline;
      } else if (isStrikethrough) {
        decoration = pw.TextDecoration.lineThrough;
      }

      spans.add(
        pw.TextSpan(
          text: insert,
          style: pw.TextStyle(
            fontSize: fontSize,
            fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
            fontStyle: isItalic ? pw.FontStyle.italic : pw.FontStyle.normal,
            decoration: decoration,
            color: color,
          ),
        ),
      );
    }

    return pw.TextSpan(children: spans);
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
    // Initialize Super Editor document model
    _initDocument();

    // Ensure settings are loaded before loading files
    _initAsync();
    _initFileWatcher();
  }

  /// Initialize the rich text editor adapter
  void _initDocument() {
    _richTextEditor = AppFlowyEditorAdapter();
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

    final content = await _fileService.readFile(fileName);
    if (content != null) {
      // Offload heavy parsing (Decryption + JSON Decode) to isolate
      final note = await compute(_parseNoteIsolate, content);

      if (note != null) {
        await _applyNoteModel(note, fileName);
      } else {
        // 3. Fallback to Plain Text
        print("Loading as plain text");
        _loadContentToEditor(content);
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
        _initDocument();
        _currentPassword = null;
        notifyListeners();
      }
    } else {
      // Not locked
      _loadContentToEditor(note.content);
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
      _loadContentToEditor(decryptedContent);
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
      _initDocument();
      _createSimpleDocument("Incorrect Password");
      _sessionPasswords.remove(_currentFileName); // Invalid pass
      _isLocked = true;
      isLockedNotifier.value = true;
    } else {
      _loadContentToEditor(decrypted);
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
      _initDocument();
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
      progressNotifier.value = 'Re-encrypting content...';
      await Future.delayed(Duration.zero);

      String contentToSave = _richTextEditor.getDocumentJson();

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

    String contentToSave = _richTextEditor.getDocumentJson();
    bool locked = false;

    // Extract plain text from document
    String plainText = _richTextEditor.getPlainText();

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
          ? _generateTitleFromContent(plainText)
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

  /// Load content into the editor document
  void _loadContentToEditor(String content) {
    if (content.trim().isEmpty) return;

    try {
      content = content.trim();

      // 1. Try native AppFlowy JSON format (preferred)
      if (content.startsWith('{')) {
        final loaded = _richTextEditor.setDocumentJson(content);
        if (loaded) return;
      }

      // 2. Legacy Delta JSON - convert to plain text (backwards compatibility)
      if (content.startsWith('[')) {
        try {
          final jsonContent = jsonDecode(content);
          if (jsonContent is List) {
            final buffer = StringBuffer();
            for (final op in jsonContent) {
              if (op is Map && op['insert'] is String) {
                buffer.write(op['insert']);
              }
            }
            final plainText = buffer.toString().trim();
            _createSimpleDocument(plainText);
            return;
          }
        } catch (e) {
          // Not valid Delta JSON
        }
      }

      // 3. Legacy HTML - convert to plain text (backwards compatibility)
      if (content.startsWith('<')) {
        final plainText = content.replaceAll(RegExp(r'<[^>]*>'), '').trim();
        _createSimpleDocument(plainText);
        return;
      }

      // 4. Plain text fallback
      _createSimpleDocument(content);
    } catch (e) {
      debugPrint("Error loading content: $e");
      _createSimpleDocument(content);
    }
  }

  /// Create a simple document with plain text content
  void _createSimpleDocument(String text) {
    if (text.trim().isEmpty) return;
    // Create a minimal AppFlowy document structure
    final documentJson = {
      'document': {
        'type': 'page',
        'children': text
            .split('\n')
            .map(
              (line) => {
                'type': 'paragraph',
                'data': {
                  'delta': [
                    {'insert': line},
                  ],
                },
              },
            )
            .toList(),
      },
    };
    _richTextEditor.setDocumentJson(jsonEncode(documentJson));
  }

  void reset() {
    _currentFileName = null;
    _currentPassword = null;
    _isLocked = false;
    _attachments = [];
    _initDocument();
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
    _fileWatcherSubscription?.cancel();
    titleController.dispose();
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
    final content = args['content'] as String?;
    final isPasswordSet = args['isPasswordSet'] as bool;
    final password = args['password'] as String?;

    if (fileName == null || content == null) return;
    try {
      String dataToSave = content;
      if (isPasswordSet && password != null) {
        dataToSave = await EncryptionService().encryptApp(content);
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
        String contentToSave = _richTextEditor.getDocumentJson();

        await compute(_autoSaveIsolate, {
          'fileName': _currentFileName,
          'content': contentToSave,
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
    if (_currentFileName == null || !_currentFileName!.startsWith('note_')) {
      return null;
    }
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
