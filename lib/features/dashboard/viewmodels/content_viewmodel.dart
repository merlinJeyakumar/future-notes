import 'package:flutter/material.dart';
import '../../../core/viewmodels/base_viewmodel.dart';
import '../services/file_service.dart';

class ContentViewModel extends BaseViewModel {
  final IFileService _fileService;
  final TextEditingController textController = TextEditingController(
    text: """
# Deployment Plan

We need to update the `nginx.conf` before pushing to prod.

## Tasks

- [x] Backup DB
- [ ] Run migration

```
sudo systemctl restart nginx
```
""",
  );

  String _lastText = "";
  List<TextRange> _checkboxRanges = [];

  // Expose for UI if needed, but logic should mainly happen here
  // List<TextRange> get checkboxRanges => _checkboxRanges;

  ContentViewModel({required IFileService fileService})
    : _fileService = fileService {
    _lastText = textController.text;
    parseCheckboxes(textController.text);
  }

  @override
  void dispose() {
    textController.dispose();
    super.dispose();
  }

  void onTextChanged(String text) {
    handleAutoList(text);
    _lastText = text;
    parseCheckboxes(text);
    notifyListeners();
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
    final fileName = await _fileService.pickFileName();
    if (fileName != null) {
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
  }
}
