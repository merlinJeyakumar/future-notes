import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/viewmodels/base_viewmodel.dart';
import '../services/file_service.dart';
import '../services/encryption_service.dart';

import 'package:uuid/uuid.dart';

class ContentViewModel extends BaseViewModel {
  final IFileService _fileService;
  final IEncryptionService _encryptionService;

  final TextEditingController textController = TextEditingController();
  final TextEditingController titleController = TextEditingController(
    text: "Deployment Plan",
  );

  String _lastText = "";
  final List<TextRange> _checkboxRanges = [];
  String? _currentPassword;
  String? _currentFileName;
  Timer? _autoSaveTimer;
  List<String> _recentFiles = [];

  // Expose for UI if needed, but logic should mainly happen here
  // List<TextRange> get checkboxRanges => _checkboxRanges;
  List<String> get recentFiles => _recentFiles;

  bool get isPasswordSet => _currentPassword != null;

  ContentViewModel({
    required IFileService fileService,
    required IEncryptionService encryptionService,
  }) : _fileService = fileService,
       _encryptionService = encryptionService {
    _lastText = textController.text;
    parseCheckboxes(textController.text);
    loadRecentFiles();
  }

  Future<void> loadRecentFiles() async {
    _recentFiles = await _fileService.getRecentFiles();
    notifyListeners();
  }

  Future<void> loadNote(String fileName) async {
    setBusy(true);
    final content = await _fileService.readFile(fileName);
    if (content != null) {
      // Attempt to decrypt if encrypted
      try {
        final decryptedText = _encryptionService.decrypt(
          content,
          password: _currentPassword,
        );
        // If decryption fails (returns error string usually in our service mock),
        // we might want to handle it.
        // Our service returns "Error decrypting: ..." on failure.
        // For now, checks if it looks like the error message or just show text.
        // Improve in future.
        if (decryptedText.startsWith("Error decrypting:")) {
          // If password was wrong or not set, maybe show raw or prompt?
          // For now, show result (which is error msg) or try with default?

          // Retry with default if password was null?
          if (_currentPassword == null) {
            final retry = _encryptionService.decrypt(content, password: null);
            if (!retry.startsWith("Error decrypting:")) {
              textController.text = retry;
            } else {
              textController.text = decryptedText;
            }
          } else {
            textController.text = decryptedText;
          }
        } else {
          textController.text = decryptedText;
        }
      } catch (e) {
        textController.text = content; // Fallback to raw content
      }

      _currentFileName = fileName;
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

    // Simulate Network/Disk delay only for manual saves or if critical
    // For auto-save we might want to be silent or faster?
    // Keeping delay for consistency but could be removed for isAutoSave.
    if (!isAutoSave) await Future.delayed(const Duration(seconds: 1));

    final passwordToUse = _currentPassword ?? "default";

    final encryptedText = _encryptionService.encrypt(
      textController.text,
      password: passwordToUse,
    );

    if (_currentFileName == null) {
      final uuid = const Uuid().v4();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      _currentFileName = 'note_${timestamp}_$uuid.enc';
    }

    await _fileService.saveFile(encryptedText, _currentFileName!);

    // For verification, we log it to the console and keep the editor text AS-IS.
    print(
      "SAVED FILE: $_currentFileName (Password: $passwordToUse, Auto: $isAutoSave)",
    );
    print("ENCRYPTED DATA: $encryptedText");

    print("ENCRYPTED DATA: $encryptedText");

    await loadRecentFiles();

    if (!isAutoSave) setBusy(false);
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    textController.dispose();
    titleController.dispose();
    super.dispose();
  }

  void onTextChanged(String text) {
    handleAutoList(text);
    _lastText = text;
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
}
