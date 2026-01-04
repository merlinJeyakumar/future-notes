import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import '../viewmodels/content_viewmodel.dart';
import 'password_dialog.dart';

// Anti-Gravity Design System Colors
class _DesignColors {
  static const background = Color(0xFF1A202C); // Deep Charcoal
  static const toolbarIsland = Color(0xFF2D3748); // Slate
  static const accent = Color(0xFF4299E1); // Electric Blue
  static const saveButton = Color(0xFF48BB78); // Modern Green
  static const subtleGray = Color(0xFF718096);
  static const divider = Color(0xFF4A5568);
  static const textPrimary = Color(0xFFE2E8F0);
  static const textSecondary = Color(0xFFA0AEC0);
}

class ContentArea extends StatelessWidget {
  final ContentViewModel viewModel;

  const ContentArea({super.key, required this.viewModel});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _DesignColors.background,
      child: Column(
        children: [
          // Top Strip - Clean breadcrumb + secondary actions
          _buildTopStrip(context),

          // Floating Toolbar Island (only when not locked)
          if (!viewModel.isLocked) _buildFloatingToolbar(),

          // Spacious Editor Area
          Expanded(child: _buildInputArea(context)),
        ],
      ),
    );
  }

  /// Clean, minimal top strip with breadcrumb and secondary actions
  Widget _buildTopStrip(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          // Breadcrumb-style indicator
          _buildBreadcrumb(),

          const Spacer(),

          // Secondary actions (right side)
          _buildSecondaryActions(context),

          const SizedBox(width: 16),

          // Save Button - Prominent pill style
          _buildSaveButton(),
        ],
      ),
    );
  }

  /// Breadcrumb indicator: "Editing > [title]"
  Widget _buildBreadcrumb() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.edit_note_rounded, size: 18, color: _DesignColors.accent),
        const SizedBox(width: 8),
        const Text(
          'Editing',
          style: TextStyle(
            color: _DesignColors.subtleGray,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(width: 6),
        Icon(
          Icons.chevron_right_rounded,
          size: 16,
          color: _DesignColors.subtleGray.withOpacity(0.6),
        ),
        const SizedBox(width: 6),
        // Editable title
        SizedBox(
          width: 200,
          child: TextField(
            controller: viewModel.titleController,
            style: const TextStyle(
              color: _DesignColors.textPrimary,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
            decoration: const InputDecoration(
              hintText: 'Untitled note',
              hintStyle: TextStyle(
                color: _DesignColors.subtleGray,
                fontWeight: FontWeight.w400,
              ),
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ),
      ],
    );
  }

  /// Secondary action icons (link, lock, settings)
  Widget _buildSecondaryActions(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!viewModel.isLocked)
          _buildSubtleIconButton(
            Icons.attach_file_rounded,
            'Attach file',
            onPressed: viewModel.pickFile,
          ),
        _buildSubtleIconButton(
          viewModel.isLocked
              ? Icons.lock_rounded
              : (viewModel.isPasswordSet
                    ? Icons.lock_rounded
                    : Icons.lock_open_rounded),
          viewModel.isLocked
              ? 'Unlock'
              : (viewModel.isPasswordSet ? 'Locked' : 'Set password'),
          onPressed: () => _handleLockAction(context),
          isActive: viewModel.isLocked || viewModel.isPasswordSet,
        ),
        _buildSubtleIconButton(
          Icons.settings_outlined,
          'Settings',
          onPressed: () {},
        ),
      ],
    );
  }

  /// Subtle icon button for secondary actions
  Widget _buildSubtleIconButton(
    IconData icon,
    String tooltip, {
    required VoidCallback onPressed,
    bool isActive = false,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.all(8),
            child: Icon(
              icon,
              size: 18,
              color: isActive ? _DesignColors.accent : _DesignColors.subtleGray,
            ),
          ),
        ),
      ),
    );
  }

  /// Prominent pill-shaped Save button
  Widget _buildSaveButton() {
    return ElevatedButton(
      onPressed: viewModel.isBusy ? null : () => viewModel.saveNote(),
      style: ElevatedButton.styleFrom(
        backgroundColor: _DesignColors.saveButton,
        foregroundColor: Colors.white,
        disabledBackgroundColor: _DesignColors.saveButton.withOpacity(0.5),
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        elevation: 0,
      ),
      child: viewModel.isBusy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : const Text(
              'Save Note',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
    );
  }

  /// Floating toolbar "island" with grouped formatting tools
  Widget _buildFloatingToolbar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: BoxDecoration(
        color: _DesignColors.toolbarIsland,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _DesignColors.divider.withOpacity(0.3),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: QuillSimpleToolbar(
          controller: viewModel.quillController,
          config: QuillSimpleToolbarConfig(
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
            toolbarIconAlignment: WrapAlignment.center,
            toolbarSectionSpacing: 8,
            sectionDividerColor: _DesignColors.divider.withOpacity(0.4),
            buttonOptions: QuillSimpleToolbarButtonOptions(
              base: QuillToolbarBaseButtonOptions(
                iconTheme: QuillIconTheme(
                  iconButtonUnselectedData: IconButtonData(
                    color: _DesignColors.textSecondary,
                  ),
                  iconButtonSelectedData: IconButtonData(
                    color: _DesignColors.accent,
                  ),
                ),
              ),
            ),
          ),
        ),
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
          backgroundColor: _DesignColors.toolbarIsland,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text(
            'Remove Password?',
            style: TextStyle(color: _DesignColors.textPrimary),
          ),
          content: const Text(
            'Are you sure you want to remove the password protection?',
            style: TextStyle(color: _DesignColors.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'Cancel',
                style: TextStyle(color: _DesignColors.subtleGray),
              ),
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
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: _DesignColors.toolbarIsland.withOpacity(0.5),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.lock_rounded,
                size: 48,
                color: _DesignColors.subtleGray,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'This note is locked',
              style: TextStyle(
                color: _DesignColors.textSecondary,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => _showPasswordDialog(context, isUnlock: true),
              style: ElevatedButton.styleFrom(
                backgroundColor: _DesignColors.accent,
                foregroundColor: Colors.white,
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 14,
                ),
              ),
              child: const Text(
                'Unlock',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );
    }

    // Spacious editor with increased padding
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: QuillEditor.basic(
        controller: viewModel.quillController,
        config: QuillEditorConfig(
          autoFocus: false,
          scrollable: true,
          expands: false,
          padding: const EdgeInsets.all(8),
          keyboardAppearance: Brightness.dark,
        ),
        focusNode: viewModel.focusNode,
        scrollController: viewModel.scrollController,
      ),
    );
  }
}
