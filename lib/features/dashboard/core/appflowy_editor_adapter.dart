import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'i_rich_text_editor.dart';

/// AppFlowy Editor implementation of [IRichTextEditor].
class AppFlowyEditorAdapter implements IRichTextEditor {
  late EditorState _editorState;
  final List<VoidCallback> _listeners = [];

  AppFlowyEditorAdapter() {
    _editorState = EditorState.blank();
  }

  // Helper for ViewModel/UI to access state directly if needed
  EditorState get editorState => _editorState;

  @override
  String getDocumentJson() {
    final json = _editorState.document.toJson();
    return jsonEncode(json);
  }

  @override
  bool setDocumentJson(String jsonStr) {
    if (jsonStr.trim().isEmpty) return false;
    try {
      final json = jsonDecode(jsonStr);
      if (json is Map<String, dynamic>) {
        final document = Document.fromJson(json);
        _editorState = EditorState(document: document);
        return true;
      }
    } catch (e) {
      debugPrint('Error parsing document JSON: $e');
    }
    return false;
  }

  @override
  String getPlainText() {
    final buffer = StringBuffer();
    for (final node in _editorState.document.root.children) {
      final delta = node.delta;
      if (delta != null) {
        buffer.writeln(delta.toPlainText());
      }
    }
    return buffer.toString().trim();
  }

  @override
  bool get hasContent => !_editorState.document.isEmpty;

  @override
  Widget buildEditor({
    required BuildContext context,
    required bool readOnly,
    FocusNode? focusNode,
    ScrollController? scrollController,
  }) {
    final theme = Theme.of(context);
    final textColor = theme.textTheme.bodyLarge?.color ?? Colors.black;

    return AppFlowyEditor(
      editorState: _editorState,
      editable: !readOnly,
      focusNode: focusNode,
      editorStyle: EditorStyle(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        cursorColor: theme.colorScheme.primary,
        selectionColor: theme.colorScheme.primary.withAlpha(80),
        dragHandleColor: theme.colorScheme.primary,
        textStyleConfiguration: TextStyleConfiguration(
          text: TextStyle(fontSize: 16, color: textColor),
        ),
        // Custom text span decorator for code styling
        textSpanDecorator: (context, node, index, text, before, after) {
          // Check if this text has the code attribute
          if (text.attributes?[AppFlowyRichTextKeys.code] == true) {
            // Organic code block style: dark background, light text, Consolas
            return TextSpan(
              text: text.text,
              style: const TextStyle(
                fontFamily: 'Consolas',
                fontSize: 14,
                color: Color(0xFFE0E0E0), // Light gray text
                backgroundColor: Color(0xFF2D2D2D), // Dark background
                letterSpacing: 0.5,
              ),
            );
          }
          // For all other text, use default decoration
          return after;
        },
      ),
    );
  }

  /// Toggles a text formatting attribute (bold, italic, etc.) on the current selection.
  void _toggleTextAttribute(String attributeKey) {
    final selection = _editorState.selection;
    if (selection == null || selection.isCollapsed) return;

    final nodes = _editorState.getNodesInSelection(selection);
    if (nodes.isEmpty) return;

    // Check if attribute is already applied anywhere in selection
    bool hasAttribute = false;
    for (final node in nodes) {
      if (node.delta != null) {
        final delta = node.delta!;
        // Check attributes in the selection range
        for (final op in delta.toList()) {
          if (op.attributes != null && op.attributes![attributeKey] == true) {
            hasAttribute = true;
            break;
          }
        }
      }
      if (hasAttribute) break;
    }

    // Apply or remove the attribute, preserving selection
    final transaction = _editorState.transaction;
    transaction.formatText(
      nodes.first,
      selection.startIndex,
      selection.length,
      {attributeKey: hasAttribute ? null : true},
    );
    transaction.afterSelection = selection; // Preserve selection
    _editorState.apply(transaction);
  }

  @override
  Widget buildToolbar({required bool enabled}) {
    if (!enabled) return const SizedBox();
    return _EditorToolbar(adapter: this);
  }

  void _formatBlock(String type, [Map<String, dynamic>? attributes]) {
    final selection = _editorState.selection;
    if (selection == null) return;

    final nodes = _editorState.getNodesInSelection(selection);
    if (nodes.isEmpty) return;

    final transaction = _editorState.transaction;

    for (final node in nodes) {
      // Skip non-block nodes (we only want to format block-level nodes)
      if (node.delta == null) continue;

      // Determine new type - toggle off if same type
      final newType = (node.type == type) ? ParagraphBlockKeys.type : type;
      final newAttributes = (node.type == type)
          ? <String, dynamic>{}
          : (attributes ?? {});

      // Get the path and delta content of the current node
      final path = node.path;
      final delta = node.delta;

      // Create a new node with the desired type, preserving the delta content
      final newNode = Node(
        type: newType,
        attributes: {
          ...newAttributes,
          if (delta != null) 'delta': delta.toJson(),
        },
      );

      // Insert the new node first at path+1, then delete the old node at path
      // This prevents path shift issues when deleting first
      transaction.insertNode(path.next, newNode);
      transaction.deleteNode(node);
    }

    // Preserve selection after block formatting
    transaction.afterSelection = selection;
    _editorState.apply(transaction);
  }

  void _applyTextColor(Color? color) {
    final selection = _editorState.selection;
    if (selection == null || selection.isCollapsed) return;

    final nodes = _editorState.getNodesInSelection(selection);
    if (nodes.isEmpty) return;

    // Convert color to hex string using modern API (avoid deprecated .value)
    final hex = color == null
        ? null
        : '#${color.toARGB32().toRadixString(16).substring(2)}';

    final transaction = _editorState.transaction;
    transaction.formatText(
      nodes.first,
      selection.startIndex,
      selection.length,
      {AppFlowyRichTextKeys.textColor: hex},
    );
    transaction.afterSelection = selection; // Preserve selection
    _editorState.apply(transaction);
  }

  void _applyHighlightColor(Color? color) {
    final selection = _editorState.selection;
    if (selection == null || selection.isCollapsed) return;

    final nodes = _editorState.getNodesInSelection(selection);
    if (nodes.isEmpty) return;

    // Convert color to hex string
    final hex = color == null
        ? null
        : '#${color.toARGB32().toRadixString(16).substring(2)}';

    final transaction = _editorState.transaction;
    transaction.formatText(
      nodes.first,
      selection.startIndex,
      selection.length,
      {AppFlowyRichTextKeys.backgroundColor: hex},
    );
    transaction.afterSelection = selection; // Preserve selection
    _editorState.apply(transaction);
  }

  void _applyFontSize(int? fontSize) {
    final selection = _editorState.selection;
    if (selection == null || selection.isCollapsed) return;

    final nodes = _editorState.getNodesInSelection(selection);
    if (nodes.isEmpty) return;

    final transaction = _editorState.transaction;
    transaction.formatText(
      nodes.first,
      selection.startIndex,
      selection.length,
      {AppFlowyRichTextKeys.fontSize: fontSize?.toDouble()},
    );
    transaction.afterSelection = selection; // Preserve selection
    _editorState.apply(transaction);
  }

  @override
  void dispose() {
    _listeners.clear();
  }

  @override
  void addChangeListener(VoidCallback listener) {
    _listeners.add(listener);
    _editorState.transactionStream.listen((_) => _notifyListeners());
  }

  @override
  void removeChangeListener(VoidCallback listener) {
    _listeners.remove(listener);
  }

  void _notifyListeners() {
    for (final listener in _listeners) {
      listener();
    }
  }

  @override
  void undo() => undoCommand.execute(_editorState);

  @override
  void redo() => redoCommand.execute(_editorState);

  @override
  bool get canUndo => true;

  @override
  bool get canRedo => true;
}

/// Stateful toolbar widget that doesn't steal focus from the editor
class _EditorToolbar extends StatelessWidget {
  final AppFlowyEditorAdapter adapter;

  const _EditorToolbar({required this.adapter});

  // Common colors for the color picker
  static const List<Color> _colors = [
    Colors.black,
    Colors.white,
    Colors.red,
    Colors.pink,
    Colors.purple,
    Colors.deepPurple,
    Colors.indigo,
    Colors.blue,
    Colors.lightBlue,
    Colors.cyan,
    Colors.teal,
    Colors.green,
    Colors.lightGreen,
    Colors.lime,
    Colors.yellow,
    Colors.amber,
    Colors.orange,
    Colors.deepOrange,
    Colors.brown,
    Colors.grey,
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black26)],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Text Formatting
            _buildBarButton(
              Icons.format_bold,
              () => adapter._toggleTextAttribute(AppFlowyRichTextKeys.bold),
            ),
            _buildBarButton(
              Icons.format_italic,
              () => adapter._toggleTextAttribute(AppFlowyRichTextKeys.italic),
            ),
            _buildBarButton(
              Icons.format_underlined,
              () =>
                  adapter._toggleTextAttribute(AppFlowyRichTextKeys.underline),
            ),
            _buildBarButton(
              Icons.strikethrough_s,
              () => adapter._toggleTextAttribute(
                AppFlowyRichTextKeys.strikethrough,
              ),
            ),
            _buildBarButton(
              Icons.code,
              () => adapter._toggleTextAttribute(AppFlowyRichTextKeys.code),
            ),

            // Divider
            _buildDivider(),

            // Color Picker
            _buildColorPickerButton(context),
            _buildBarButton(
              Icons.format_color_reset,
              () => adapter._applyTextColor(null),
              tooltip: 'Reset Color',
            ),

            // Divider
            _buildDivider(),

            // Highlighter
            _buildHighlighterButton(context),
            _buildBarButton(
              Icons.highlight_remove,
              () => adapter._applyHighlightColor(null),
              tooltip: 'Remove Highlight',
            ),

            // Divider
            _buildDivider(),

            // Block Formatting - Text Size Dropdown
            _buildTextSizeDropdown(context),
            _buildBarButton(
              Icons.format_list_bulleted,
              () => adapter._formatBlock(BulletedListBlockKeys.type),
              tooltip: 'Bullet List',
            ),
            _buildBarButton(
              Icons.format_list_numbered,
              () => adapter._formatBlock(NumberedListBlockKeys.type),
              tooltip: 'Numbered List',
            ),
            _buildBarButton(
              Icons.check_box_outlined,
              () => adapter._formatBlock(TodoListBlockKeys.type, {
                'checked': false,
              }),
              tooltip: 'Checkbox',
            ),
            _buildBarButton(
              Icons.format_quote,
              () => adapter._formatBlock(QuoteBlockKeys.type),
              tooltip: 'Quote',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return Container(
      width: 1,
      height: 20,
      color: Colors.white24,
      margin: const EdgeInsets.symmetric(horizontal: 4),
    );
  }

  Widget _buildBarButton(
    IconData icon,
    VoidCallback onPressed, {
    String? tooltip,
  }) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) {
          // Execute immediately on tap down to prevent focus loss
          onPressed();
        },
        child: Tooltip(
          message: tooltip ?? '',
          child: Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            child: Icon(icon, color: Colors.white, size: 20),
          ),
        ),
      ),
    );
  }

  Widget _buildTextSizeDropdown(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _showFontSizeDialog(context),
        child: Tooltip(
          message: 'Font Size',
          child: Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            child: const Icon(Icons.format_size, color: Colors.white, size: 20),
          ),
        ),
      ),
    );
  }

  // Common font sizes in pixels
  static const List<int> _fontSizes = [
    8,
    10,
    12,
    14,
    16,
    18,
    20,
    22,
    24,
    26,
    28,
    30,
    32,
    36,
    40,
    44,
    48,
    54,
    60,
    66,
    72,
    80,
    88,
    96,
    104,
    110,
  ];

  void _showFontSizeDialog(BuildContext context) {
    // Store selection before showing dialog
    final selection = adapter._editorState.selection;

    // Get current font size from selection
    int? currentFontSize;
    if (selection != null && !selection.isCollapsed) {
      final nodes = adapter._editorState.getNodesInSelection(selection);
      if (nodes.isNotEmpty && nodes.first.delta != null) {
        final delta = nodes.first.delta!;
        // Check the first text operation for font size
        for (final op in delta.toList()) {
          if (op.attributes != null &&
              op.attributes![AppFlowyRichTextKeys.fontSize] != null) {
            final sizeValue = op.attributes![AppFlowyRichTextKeys.fontSize];
            if (sizeValue is num) {
              currentFontSize = sizeValue.toInt();
            }
            break;
          }
        }
      }
    }

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF2D2D2D),
          title: const Text('Font Size', style: TextStyle(color: Colors.white)),
          content: SizedBox(
            width: 300,
            height: 400,
            child: ListView(
              children: [
                // Default option
                ListTile(
                  selected: currentFontSize == null,
                  selectedTileColor: Colors.white.withAlpha(25),
                  leading: currentFontSize == null
                      ? const Icon(Icons.check, color: Colors.green, size: 18)
                      : const SizedBox(width: 18),
                  title: const Text(
                    'Default',
                    style: TextStyle(color: Colors.white),
                  ),
                  onTap: () {
                    Navigator.of(dialogContext).pop();
                    _applyFontSizeWithSelection(null, selection);
                  },
                ),
                const Divider(color: Colors.white24),
                // Pixel size options
                ..._fontSizes.map((size) {
                  final isSelected = currentFontSize == size;
                  return ListTile(
                    selected: isSelected,
                    selectedTileColor: Colors.white.withAlpha(25),
                    leading: isSelected
                        ? const Icon(Icons.check, color: Colors.green, size: 18)
                        : const SizedBox(width: 18),
                    title: Text(
                      '$size px',
                      style: TextStyle(
                        color: isSelected ? Colors.greenAccent : Colors.white,
                        fontSize: (size.clamp(12, 24)).toDouble(),
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                    trailing: Text(
                      'Aa',
                      style: TextStyle(
                        color: isSelected ? Colors.greenAccent : Colors.white54,
                        fontSize: (size.clamp(10, 28)).toDouble(),
                      ),
                    ),
                    onTap: () {
                      Navigator.of(dialogContext).pop();
                      _applyFontSizeWithSelection(size, selection);
                    },
                  );
                }),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

  void _applyFontSizeWithSelection(int? fontSize, Selection? selection) {
    if (selection != null) {
      adapter._editorState.updateSelectionWithReason(
        selection,
        reason: SelectionUpdateReason.uiEvent,
      );
    }
    Future.microtask(() => adapter._applyFontSize(fontSize));
  }

  Widget _buildColorPickerButton(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _showColorPicker(context),
        child: Tooltip(
          message: 'Text Color',
          child: Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            child: const Icon(
              Icons.format_color_text,
              color: Colors.white,
              size: 20,
            ),
          ),
        ),
      ),
    );
  }

  void _showColorPicker(BuildContext context) {
    // Store selection before showing dialog
    final selection = adapter._editorState.selection;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF2D2D2D),
          title: const Text(
            'Select Color',
            style: TextStyle(color: Colors.white),
          ),
          content: SizedBox(
            width: 280,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _colors.map((color) {
                return MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () {
                      Navigator.of(dialogContext).pop();
                      // Restore selection before applying color
                      if (selection != null) {
                        adapter._editorState.updateSelectionWithReason(
                          selection,
                          reason: SelectionUpdateReason.uiEvent,
                        );
                      }
                      // Apply color after a micro task to ensure selection is restored
                      Future.microtask(() => adapter._applyTextColor(color));
                    },
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: color,
                        border: Border.all(
                          color: color == Colors.white
                              ? Colors.grey
                              : Colors.white24,
                          width: 1,
                        ),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildHighlighterButton(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _showHighlightPicker(context),
        child: Tooltip(
          message: 'Highlight',
          child: Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            child: const Icon(
              Icons.format_color_fill,
              color: Colors.white,
              size: 20,
            ),
          ),
        ),
      ),
    );
  }

  void _showHighlightPicker(BuildContext context) {
    // Store selection before showing dialog
    final selection = adapter._editorState.selection;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF2D2D2D),
          title: const Text(
            'Highlight Color',
            style: TextStyle(color: Colors.white),
          ),
          content: SizedBox(
            width: 280,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _colors.map((color) {
                return MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () {
                      Navigator.of(dialogContext).pop();
                      // Restore selection before applying color
                      if (selection != null) {
                        adapter._editorState.updateSelectionWithReason(
                          selection,
                          reason: SelectionUpdateReason.uiEvent,
                        );
                      }
                      // Apply highlight color after a micro task
                      Future.microtask(
                        () => adapter._applyHighlightColor(color),
                      );
                    },
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: color,
                        border: Border.all(color: Colors.white24, width: 1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }
}
