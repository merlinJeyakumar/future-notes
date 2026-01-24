import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'i_rich_text_editor.dart';

/// Stub for Flutter Quill implementation of [IRichTextEditor].
///
/// This is a placeholder for future implementation. To use Quill:
/// 1. Add flutter_quill dependency to pubspec.yaml
/// 2. Implement this adapter with QuillController
/// 3. Inject this adapter instead of SuperEditorAdapter
class QuillEditorAdapter implements IRichTextEditor {
  QuillEditorAdapter() {
    throw UnimplementedError(
      'QuillEditorAdapter is not yet implemented. '
      'Use SuperEditorAdapter or implement this class.',
    );
  }

  @override
  String getHtml() => throw UnimplementedError();

  @override
  void setHtml(String html) => throw UnimplementedError();

  @override
  bool get hasContent => throw UnimplementedError();

  @override
  Widget buildEditor({
    required BuildContext context,
    required bool readOnly,
    FocusNode? focusNode,
    ScrollController? scrollController,
  }) => throw UnimplementedError();

  @override
  Widget buildToolbar({required bool enabled}) => throw UnimplementedError();

  @override
  void dispose() {}

  @override
  void addChangeListener(VoidCallback listener) {}

  @override
  void removeChangeListener(VoidCallback listener) {}

  @override
  void undo() {}

  @override
  void redo() {}

  @override
  bool get canUndo => false;

  @override
  bool get canRedo => false;
}
