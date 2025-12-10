import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:file_picker/file_picker.dart';

class ContentArea extends StatefulWidget {
  const ContentArea({super.key});

  @override
  State<ContentArea> createState() => _ContentAreaState();
}

class _ContentAreaState extends State<ContentArea> {
  final TextEditingController _controller = TextEditingController(
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

  // Stores the text range of the "[ ]" or "[x]" for each checkbox found.
  List<TextRange> _checkboxRanges = [];

  @override
  void initState() {
    super.initState();
    _lastText = _controller.text;
    _parseCheckboxes(_controller.text);
  }

  void _parseCheckboxes(String text) {
    _checkboxRanges.clear();

    // 1. Identify ranges to exclude (code blocks)
    final List<TextRange> exclusions = [];
    final codeBlockRegex = RegExp(r'```[\s\S]*?```');
    for (final match in codeBlockRegex.allMatches(text)) {
      exclusions.add(TextRange(start: match.start, end: match.end));
    }

    // 2. Find all potential checkboxes
    // Regex to match GFM task list items:
    // ^ (start of line)
    // \s* (optional indentation)
    // [-*+] (list marker)
    // \s+ (space)
    // (\[[ xX]\]) (capture group 1: the checkbox itself)
    final RegExp regex = RegExp(r'^\s*[-*+]\s+(\[[ xX]\])', multiLine: true);

    for (final match in regex.allMatches(text)) {
      if (match.groupCount >= 1) {
        // We want the range of the brackets e.g. "[ ]" or "[x]"
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

  void _toggleCheckbox(int index) {
    if (index < 0 || index >= _checkboxRanges.length) return;

    final range = _checkboxRanges[index];
    final currentText = _controller.text;

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

    // Update controller without losing selection if possible, though user is clicking preview
    _controller.value = TextEditingValue(
      text: newText,
      selection: _controller.selection,
    );

    // Re-parse immediately
    _parseCheckboxes(newText);
    setState(() {});
  }

  void _handleAutoList(String newText) {
    // Only trigger if we added exactly one character (the newline)
    // and that character is indeed a newline at the current cursor position.
    if (newText.length != _lastText.length + 1) return;

    final selection = _controller.selection;
    if (!selection.isValid || selection.start == 0) return;

    // Check if the character before the cursor is a newline
    if (newText[selection.start - 1] == '\n') {
      // Find the start of the previous line
      final currentPos = selection.start;
      final previousNewlinePos = newText.lastIndexOf('\n', currentPos - 2);
      final lineStart = previousNewlinePos == -1 ? 0 : previousNewlinePos + 1;

      // Extract the previous line content
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

  Future<void> _pickFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles();

    if (result != null) {
      final fileName = result.files.single.name;
      // In a real app, you would upload this file and get a URL.
      // Here we just insert a placeholder link.
      final textToAdd = '\n\n![Attachment: $fileName]($fileName)';
      _insertText(textToAdd);
    }
  }

  void _insertText(String text) {
    final textSelection = _controller.selection;
    if (textSelection.isValid) {
      final newText = _controller.text.replaceRange(
        textSelection.start,
        textSelection.end,
        text,
      );
      final newSelection = textSelection.copyWith(
        baseOffset: textSelection.start + text.length,
        extentOffset: textSelection.start + text.length,
      );
      _controller.value = TextEditingValue(
        text: newText,
        selection: newSelection,
      );
    } else {
      _controller.text += text;
    }
    _parseCheckboxes(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    // Determine screen width to decide layout
    final isDesktop = MediaQuery.of(context).size.width > 900;

    return Container(
      color: const Color(0xFF1B2535),
      child: Column(
        children: [
          // Toolbar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFF334155))),
            ),
            child: Row(
              children: [
                const Text(
                  'Editing: Deployment Plan',
                  style: TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                ElevatedButton(
                  onPressed: () {},
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Save Note',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 16),
                _buildToolbarIcon(
                  Icons.attach_file,
                  'Attach File',
                  onPressed: _pickFile,
                ),
                const SizedBox(width: 8),
                _buildToolbarIcon(
                  Icons.lock_outline,
                  'Password',
                  onPressed: () {},
                ),
                _buildToolbarIcon(Icons.terminal, 'Terminal', onPressed: () {}),
                const SizedBox(width: 8),
                _buildToolbarIcon(
                  Icons.settings_outlined,
                  'Settings',
                  onPressed: () {},
                ),
              ],
            ),
          ),

          // Editor Area
          Expanded(
            child: isDesktop
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: _buildInputArea()),
                      const VerticalDivider(width: 1, color: Color(0xFF334155)),
                      Expanded(child: _buildPreviewArea()),
                    ],
                  )
                : DefaultTabController(
                    length: 2,
                    child: Column(
                      children: [
                        const TabBar(
                          tabs: [
                            Tab(text: 'Edit'),
                            Tab(text: 'Preview'),
                          ],
                          labelColor: Colors.blueAccent,
                          unselectedLabelColor: Colors.grey,
                          indicatorColor: Colors.blueAccent,
                        ),
                        Expanded(
                          child: TabBarView(
                            children: [_buildInputArea(), _buildPreviewArea()],
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbarIcon(
    IconData icon,
    String tooltip, {
    required VoidCallback onPressed,
  }) {
    return IconButton(
      onPressed: onPressed,
      icon: Icon(icon, color: Colors.grey, size: 20),
      tooltip: tooltip,
      constraints: const BoxConstraints(), // Compact constraints
      padding: const EdgeInsets.all(8), // Consistent padding
      splashRadius: 20,
    );
  }

  Widget _buildInputArea() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: TextField(
        controller: _controller,
        maxLines: null,
        expands: true,
        style: const TextStyle(
          color: Colors.white,
          fontFamily: 'monospace',
          fontSize: 14,
        ),
        decoration: const InputDecoration(
          border: InputBorder.none,
          hintText: 'Type markdown here...',
          hintStyle: TextStyle(color: Colors.grey),
        ),
        onChanged: (text) {
          _handleAutoList(text);
          _lastText = text;
          _parseCheckboxes(text);
          setState(() {}); // Rebuild to update preview
        },
      ),
    );
  }

  Widget _buildPreviewArea() {
    // We rely on the fact that flutter_markdown builds widgets specifically in order.
    // So we can maintain an index that increments each time the builder is called.
    int checkboxIndex = 0;

    return Container(
      color: const Color(0xFF0F172A), // Slightly darker for preview
      child: Markdown(
        data: _controller.text,
        selectable: true,
        styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
          p: const TextStyle(color: Colors.white70, fontSize: 16),
          h1: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 32,
          ),
          h2: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 24,
          ),
          code: const TextStyle(
            backgroundColor: Color(0xFF1E293B),
            color: Colors.greenAccent,
            fontFamily: 'monospace',
          ),
          codeblockDecoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(8),
          ),
          checkbox: const TextStyle(color: Colors.blueAccent),
        ),
        checkboxBuilder: (bool value) {
          final currentIndex = checkboxIndex++;
          return GestureDetector(
            onTap: () {
              // Toggle logic
              _toggleCheckbox(currentIndex);
            },
            child: Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: Icon(
                value ? Icons.check_box : Icons.check_box_outline_blank,
                color: value ? Colors.blueAccent : Colors.grey,
                size: 20,
              ),
            ),
          );
        },
      ),
    );
  }
}
