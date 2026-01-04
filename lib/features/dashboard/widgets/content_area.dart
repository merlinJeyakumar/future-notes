import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import '../viewmodels/content_viewmodel.dart';
import 'password_dialog.dart';
import 'editor_toolbar.dart';

class ContentArea extends StatelessWidget {
  final ContentViewModel viewModel;

  const ContentArea({super.key, required this.viewModel});

  @override
  Widget build(BuildContext context) {
    // Determine screen width to decide layout
    final isDesktop = MediaQuery.of(context).size.width > 900;

    // ListenableBuilder might be redundant if parent rebuilds, but safe to keep or remove if parent ensures rebuild.
    // Given DashboardScreen uses ListenableBuilder, this widget will be rebuilt with new state.
    // However, to be cleaner let's just use the vm directly.
    // Actually, if DashboardScreen rebuilds, this widget constructor is called again.

    return Container(
      color: const Color(0xFF1B2535),
      child: Column(
        children: [
          // Toolbar - Row 1: Title & Primary Action
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: const Color(0xFF1B2535),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: viewModel.titleController,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                    decoration: const InputDecoration(
                      hintText: 'Enter Message Title',
                      hintStyle: TextStyle(color: Colors.white30),
                      border: InputBorder.none,
                      prefixText: 'Editing: ',
                      prefixStyle: TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                if (viewModel.isPasswordSet) ...[
                  OutlinedButton.icon(
                    onPressed: () => viewModel.manualLock(),
                    icon: const Icon(
                      Icons.lock,
                      size: 16,
                      color: Colors.blueAccent,
                    ),
                    label: const Text(
                      "Lock",
                      style: TextStyle(color: Colors.blueAccent),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.blueAccent),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                ElevatedButton(
                  onPressed: viewModel.isBusy
                      ? null
                      : () => viewModel.saveNote(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    elevation: 0,
                  ),
                  child: viewModel.isBusy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Save Note',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                ),
              ],
            ),
          ),

          // Toolbar - Row 2: Custom Tools
          EditorToolbar(
            isLocked: viewModel.isLocked,
            isPasswordSet: viewModel.isPasswordSet,
            onPickFile: viewModel.pickFile,
            onLockPressed: () => _handleLockAction(context),
            onTerminalPressed: () {},
            onSettingsPressed: () {},
          ),

          // Toolbar - Row 3: HTML Formatting Bar (Quill)
          if (!viewModel.isLocked)
            Container(
              color: const Color(0xFF0F172A),
              child: QuillSimpleToolbar(
                controller: viewModel.quillController,
                config: const QuillSimpleToolbarConfig(
                  showFontFamily: false,
                  showFontSize: true,
                  showBoldButton: true,
                  showItalicButton: true,
                  showUnderLineButton: true,
                  showStrikeThrough: true,
                  showInlineCode: true,
                  showColorButton: true,
                  showBackgroundColorButton: true,
                  showClearFormat: true,
                  showAlignmentButtons: true,
                  showLeftAlignment: true,
                  showCenterAlignment: true,
                  showRightAlignment: true,
                  showJustifyAlignment: true,
                  showHeaderStyle: true,
                  showListNumbers: true,
                  showListBullets: true,
                  showListCheck: true,
                  showCodeBlock: true,
                  showQuote: true,
                  showIndent: true,
                  showLink: true,
                  showUndo: true,
                  showRedo: true,
                  showDirection: false,
                  showSearchButton: false,
                  toolbarIconAlignment: WrapAlignment.start,
                  toolbarSectionSpacing: 4,
                ),
              ),
            ),

          // Editor Area
          Expanded(child: _buildInputArea(context)),
        ],
      ),
    );
  }

  void _handleLockAction(BuildContext context) {
    if (viewModel.isLocked) {
      _showPasswordDialog(context, isUnlock: true);
    } else if (viewModel.isPasswordSet) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          title: const Text(
            'Remove Password?',
            style: TextStyle(color: Colors.white),
          ),
          content: const Text(
            'Are you sure you want to remove the password protection?',
            style: TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                viewModel.clearPassword();
                Navigator.pop(context);
              },
              child: const Text(
                'Remove',
                style: TextStyle(color: Colors.redAccent),
              ),
            ),
          ],
        ),
      );
    } else {
      _showPasswordDialog(context);
    }
  }

  Future<void> _showPasswordDialog(
    BuildContext context, {
    bool isUnlock = false,
  }) async {
    await showDialog(
      context: context,
      builder: (context) {
        return PasswordDialog(
          isUnlock: isUnlock,
          onConfirm: (password) {
            if (isUnlock) {
              viewModel.unlockNote(password);
            } else {
              viewModel.setPassword(password);
            }
          },
        );
      },
    );
  }

  Widget _buildInputArea(BuildContext context) {
    if (viewModel.isLocked) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              "This note is locked.",
              style: TextStyle(color: Colors.grey, fontSize: 18),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => _showPasswordDialog(context, isUnlock: true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                foregroundColor: Colors.white,
              ),
              child: const Text("Unlock"),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: QuillEditor.basic(
        controller: viewModel.quillController,
        config: QuillEditorConfig(
          autoFocus: false,
          scrollable: true,
          expands: false,
          padding: EdgeInsets.zero,
          keyboardAppearance: Brightness.dark,
        ),
        focusNode: viewModel.focusNode, // Check if this is valid here
        scrollController:
            viewModel.scrollController, // Check if this is valid here
      ),
    );
  }
}
