import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';

import 'i_rich_text_editor.dart';
import '../services/super_editor_html_service.dart';

/// Super Editor implementation of [IRichTextEditor].
///
/// This adapter wraps Super Editor's document model and provides a unified
/// interface for the ViewModel and UI.
class SuperEditorAdapter implements IRichTextEditor {
  SuperEditorAdapter() {
    _initDocument();
  }

  late MutableDocument _document;
  late MutableDocumentComposer _composer;
  late Editor _editor;
  final SuperEditorHtmlService _htmlService = SuperEditorHtmlService();
  final List<VoidCallback> _changeListeners = [];

  /// Access to the underlying document (for advanced use cases)
  MutableDocument get document => _document;
  MutableDocumentComposer get composer => _composer;
  Editor get editor => _editor;

  void _initDocument() {
    _document = MutableDocument(
      nodes: [
        ParagraphNode(id: Editor.createNodeId(), text: AttributedText('')),
      ],
    );
    _composer = MutableDocumentComposer();
    _editor = createDefaultDocumentEditor(
      document: _document,
      composer: _composer,
    );
  }

  @override
  String getHtml() {
    return _htmlService.documentToHtml(_document);
  }

  @override
  void setHtml(String html) {
    try {
      _document = _htmlService.htmlToDocument(html);
      _composer = MutableDocumentComposer();
      _editor = createDefaultDocumentEditor(
        document: _document,
        composer: _composer,
      );
      _notifyListeners();
    } catch (e) {
      debugPrint('Error setting HTML: $e');
    }
  }

  @override
  bool get hasContent {
    if (_document.nodeCount == 0) return false;
    if (_document.nodeCount == 1) {
      final node = _document.getNodeAt(0);
      if (node is ParagraphNode) {
        return node.text.text.isNotEmpty;
      }
    }
    return true;
  }

  @override
  Widget buildEditor({
    required bool readOnly,
    FocusNode? focusNode,
    ScrollController? scrollController,
  }) {
    return SuperEditor(
      document: _document,
      composer: _composer,
      editor: _editor,
      focusNode: focusNode,
      scrollController: scrollController,
      stylesheet: defaultStylesheet.copyWith(
        addRulesAfter: [
          StyleRule(
            BlockSelector.all,
            (doc, docNode) => {Styles.padding: const CascadingPadding.all(16)},
          ),
        ],
      ),
    );
  }

  @override
  Widget buildToolbar({required bool enabled}) {
    return _SuperEditorToolbar(adapter: this, enabled: enabled);
  }

  @override
  void dispose() {
    _changeListeners.clear();
  }

  @override
  void addChangeListener(VoidCallback listener) {
    _changeListeners.add(listener);
  }

  @override
  void removeChangeListener(VoidCallback listener) {
    _changeListeners.remove(listener);
  }

  void _notifyListeners() {
    for (final listener in _changeListeners) {
      listener();
    }
  }

  @override
  void undo() {
    // Super Editor handles undo internally via commands
    // This is a placeholder for future implementation
  }

  @override
  void redo() {
    // Super Editor handles redo internally via commands
    // This is a placeholder for future implementation
  }

  @override
  bool get canUndo => false; // Placeholder

  @override
  bool get canRedo => false; // Placeholder

  // Helper methods for toolbar actions
  void toggleAttribution(Attribution attribution) {
    final selection = _composer.selection;
    if (selection == null) return;

    _editor.execute([
      ToggleTextAttributionsRequest(
        documentRange: selection,
        attributions: {attribution},
      ),
    ]);
  }

  void toggleBlockType(Attribution blockType) {
    final selection = _composer.selection;
    if (selection == null) return;

    final selectedNode = _document.getNodeById(selection.extent.nodeId);
    if (selectedNode is! ParagraphNode) return;

    final currentBlockType = selectedNode.metadata['blockType'];
    final newBlockType = currentBlockType == blockType ? null : blockType;

    _editor.execute([
      ChangeParagraphBlockTypeRequest(
        nodeId: selectedNode.id,
        blockType: newBlockType,
      ),
    ]);
  }

  void toggleListType(ListItemType type) {
    final selection = _composer.selection;
    if (selection == null) return;

    final selectedNode = _document.getNodeById(selection.extent.nodeId);
    if (selectedNode == null) return;

    _editor.execute([
      InsertNodeAfterNodeRequest(
        existingNodeId: selectedNode.id,
        newNode: ListItemNode(
          id: Editor.createNodeId(),
          itemType: type,
          text: AttributedText(''),
        ),
      ),
    ]);
  }

  void clearFormatting() {
    final selection = _composer.selection;
    if (selection == null) return;

    _editor.execute([
      RemoveTextAttributionsRequest(
        documentRange: selection,
        attributions: {
          boldAttribution,
          italicsAttribution,
          underlineAttribution,
          strikethroughAttribution,
        },
      ),
    ]);
  }
}

/// Internal toolbar widget for SuperEditorAdapter
class _SuperEditorToolbar extends StatelessWidget {
  const _SuperEditorToolbar({required this.adapter, required this.enabled});

  final SuperEditorAdapter adapter;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final iconColor = isDark ? Colors.grey[400] : Colors.grey[700];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [_buildRow1(iconColor), _buildRow2(iconColor)],
    );
  }

  Widget _buildRow1(Color? iconColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildButton(Icons.format_bold, 'Bold', iconColor, () {
            adapter.toggleAttribution(boldAttribution);
          }),
          _buildButton(Icons.format_italic, 'Italic', iconColor, () {
            adapter.toggleAttribution(italicsAttribution);
          }),
          _buildButton(Icons.format_underlined, 'Underline', iconColor, () {
            adapter.toggleAttribution(underlineAttribution);
          }),
          _buildButton(Icons.strikethrough_s, 'Strikethrough', iconColor, () {
            adapter.toggleAttribution(strikethroughAttribution);
          }),
          _buildDivider(),
          _buildButton(Icons.title, 'Header 1', iconColor, () {
            adapter.toggleBlockType(header1Attribution);
          }),
          _buildButton(Icons.text_fields, 'Header 2', iconColor, () {
            adapter.toggleBlockType(header2Attribution);
          }),
          _buildDivider(),
          _buildButton(
            Icons.format_list_bulleted,
            'Bullet List',
            iconColor,
            () {
              adapter.toggleListType(ListItemType.unordered);
            },
          ),
          _buildButton(
            Icons.format_list_numbered,
            'Numbered List',
            iconColor,
            () {
              adapter.toggleListType(ListItemType.ordered);
            },
          ),
          _buildDivider(),
          _buildButton(Icons.format_quote, 'Quote', iconColor, () {
            adapter.toggleBlockType(blockquoteAttribution);
          }),
          _buildButton(Icons.code, 'Code Block', iconColor, () {
            adapter.toggleBlockType(codeAttribution);
          }),
        ],
      ),
    );
  }

  Widget _buildRow2(Color? iconColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildButton(Icons.format_indent_increase, 'Indent', iconColor, () {
            // Indent - simplified
          }),
          _buildButton(Icons.format_indent_decrease, 'Outdent', iconColor, () {
            // Outdent - simplified
          }),
          _buildDivider(),
          _buildButton(Icons.link, 'Add Link', iconColor, () {
            // Link - simplified
          }),
          _buildDivider(),
          _buildButton(Icons.format_clear, 'Clear Format', iconColor, () {
            adapter.clearFormatting();
          }),
        ],
      ),
    );
  }

  Widget _buildButton(
    IconData icon,
    String tooltip,
    Color? iconColor,
    VoidCallback onPressed,
  ) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        icon: Icon(icon, size: 20, color: enabled ? iconColor : Colors.grey),
        onPressed: enabled ? onPressed : null,
        padding: const EdgeInsets.all(8),
        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
        splashRadius: 18,
      ),
    );
  }

  Widget _buildDivider() {
    return Container(
      width: 1,
      height: 24,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: Colors.grey.withOpacity(0.3),
    );
  }
}
