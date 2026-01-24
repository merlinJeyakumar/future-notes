import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Abstract interface for rich text editors.
///
/// This abstraction allows swapping between different editor implementations
/// (Super Editor, Flutter Quill, etc.) without changing ViewModel or UI code.
abstract class IRichTextEditor {
  /// Get current content as HTML string.
  String getHtml();

  /// Set content from HTML string.
  void setHtml(String html);

  /// Check if the editor has any content.
  bool get hasContent;

  /// Get the editor widget for display.
  ///
  /// [readOnly] - If true, the editor should be in read-only mode.
  Widget buildEditor({
    required bool readOnly,
    FocusNode? focusNode,
    ScrollController? scrollController,
  });

  /// Get the toolbar widget for formatting controls.
  Widget buildToolbar({required bool enabled});

  /// Dispose of any resources held by the editor.
  void dispose();

  /// Add a listener that will be called when content changes.
  void addChangeListener(VoidCallback listener);

  /// Remove a previously added change listener.
  void removeChangeListener(VoidCallback listener);

  /// Undo the last action.
  void undo();

  /// Redo the last undone action.
  void redo();

  /// Check if undo is available.
  bool get canUndo;

  /// Check if redo is available.
  bool get canRedo;
}
