import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import '../viewmodels/content_viewmodel.dart';
import 'password_dialog.dart';

import 'package:code_text_field/code_text_field.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';

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
    return LayoutBuilder(
      builder: (context, constraints) {
        // Use a higher breakpoint to trigger "Mobile/Compact" mode earlier,
        // preventing overflow on smaller tablets or when Sidebar is open on desktop.
        final isMobile = constraints.maxWidth < 900;

        return Container(
          color: _DesignColors.background,
          child: SafeArea(
            // Ensure status bar doesn't overlap
            child: Column(
              children: [
                // Top Strip - Clean breadcrumb + secondary actions
                _buildTopStrip(context, isMobile),

                // Floating Toolbar Island (only when not locked)
                if (!viewModel.isLocked) _buildFloatingToolbar(isMobile),

                // Spacious Editor Area
                Expanded(child: _buildInputArea(context)),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Clean, minimal top strip with breadcrumb and secondary actions
  Widget _buildTopStrip(BuildContext context, bool isMobile) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 12 : 20,
        vertical: 12,
      ),
      // Clip hard edge to prevent pixel overflow if content is slightly too wide
      clipBehavior: Clip.hardEdge,
      decoration: const BoxDecoration(),
      child: Row(
        children: [
          // Breadcrumb-style indicator
          Expanded(child: _buildBreadcrumb(isMobile)),

          if (!isMobile) const Spacer(),

          // Secondary actions (right side)
          _buildSecondaryActions(context),

          SizedBox(width: isMobile ? 8 : 16),

          // Save Button - Prominent pill style
          _buildSaveButton(isMobile),
        ],
      ),
    );
  }

  /// Breadcrumb indicator: "Editing > [title]"
  Widget _buildBreadcrumb(bool isMobile) {
    return Row(
      // mainAxisSize.min removed to allow Expanded child to work naturally
      children: [
        Icon(Icons.edit_note_rounded, size: 18, color: _DesignColors.accent),
        const SizedBox(width: 8),
        if (!isMobile) ...[
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
        ],
        // Editable title
        Expanded(
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
          onPressed: () => _showSettingsMenu(context),
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
  Widget _buildSaveButton(bool isMobile) {
    return ElevatedButton(
      onPressed: viewModel.isBusy ? null : () => viewModel.saveNote(),
      style: ElevatedButton.styleFrom(
        backgroundColor: _DesignColors.saveButton,
        foregroundColor: Colors.white,
        disabledBackgroundColor: _DesignColors.saveButton.withOpacity(0.5),
        shape: isMobile ? const CircleBorder() : const StadiumBorder(),
        padding: isMobile
            ? const EdgeInsets.all(12)
            : const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
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
          : (isMobile
                ? const Icon(Icons.save_rounded, size: 18)
                : const Text(
                    'Save Note',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  )),
    );
  }

  /// Floating toolbar "island" with grouped formatting tools
  Widget _buildFloatingToolbar(bool isMobile) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 20, vertical: 8),
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
      // Always allow horizontal scroll to prevent overflow, even on larger screens if constrained
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: isMobile
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildToolbarRow1(),
                          _buildVerticalDivider(),
                          _buildToolbarRow2(),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildToolbarRow1(),
                          Divider(
                            color: _DesignColors.divider.withOpacity(0.3),
                            height: 1,
                          ),
                          _buildToolbarRow2(),
                        ],
                      ),
              ),
            ),
          ),

          // Fixed Toggle Button
          Padding(
            padding: const EdgeInsets.only(right: 8, left: 4),
            child: _buildModeToggleButton(),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbarRow1() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Undo/Redo
          QuillToolbarHistoryButton(
            controller: viewModel.quillController,
            isUndo: true,
            options: QuillToolbarHistoryButtonOptions(
              iconTheme: _getIconTheme(),
            ),
          ),
          QuillToolbarHistoryButton(
            controller: viewModel.quillController,
            isUndo: false,
            options: QuillToolbarHistoryButtonOptions(
              iconTheme: _getIconTheme(),
            ),
          ),
          _buildVerticalDivider(),

          // Font Size dropdown
          QuillToolbarFontSizeButton(
            controller: viewModel.quillController,
            options: QuillToolbarFontSizeButtonOptions(
              style: TextStyle(
                color: _DesignColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ),
          _buildVerticalDivider(),

          // Text Styling: Bold, Italic, Underline, Strike, Inline Code
          QuillToolbarToggleStyleButton(
            controller: viewModel.quillController,
            attribute: Attribute.bold,
            options: _getButtonOptions(),
          ),
          QuillToolbarToggleStyleButton(
            controller: viewModel.quillController,
            attribute: Attribute.italic,
            options: _getButtonOptions(),
          ),
          QuillToolbarToggleStyleButton(
            controller: viewModel.quillController,
            attribute: Attribute.underline,
            options: _getButtonOptions(),
          ),
          QuillToolbarToggleStyleButton(
            controller: viewModel.quillController,
            attribute: Attribute.strikeThrough,
            options: _getButtonOptions(),
          ),
          QuillToolbarToggleStyleButton(
            controller: viewModel.quillController,
            attribute: Attribute.inlineCode,
            options: _getButtonOptions(),
          ),
          _buildVerticalDivider(),

          // Subscript, Superscript
          QuillToolbarToggleStyleButton(
            controller: viewModel.quillController,
            attribute: Attribute.subscript,
            options: _getButtonOptions(),
          ),
          QuillToolbarToggleStyleButton(
            controller: viewModel.quillController,
            attribute: Attribute.superscript,
            options: _getButtonOptions(),
          ),
          _buildVerticalDivider(),

          // Color buttons
          QuillToolbarColorButton(
            controller: viewModel.quillController,
            isBackground: false,
            options: _getColorButtonOptions(),
          ),
          QuillToolbarColorButton(
            controller: viewModel.quillController,
            isBackground: true,
            options: _getColorButtonOptions(),
          ),
          QuillToolbarClearFormatButton(
            controller: viewModel.quillController,
            options: QuillToolbarClearFormatButtonOptions(
              iconTheme: _getIconTheme(),
            ),
          ),
          _buildVerticalDivider(),

          // Alignment
          QuillToolbarToggleStyleButton(
            controller: viewModel.quillController,
            attribute: Attribute.leftAlignment,
            options: _getButtonOptions(),
          ),
          QuillToolbarToggleStyleButton(
            controller: viewModel.quillController,
            attribute: Attribute.centerAlignment,
            options: _getButtonOptions(),
          ),
          QuillToolbarToggleStyleButton(
            controller: viewModel.quillController,
            attribute: Attribute.rightAlignment,
            options: _getButtonOptions(),
          ),
          QuillToolbarToggleStyleButton(
            controller: viewModel.quillController,
            attribute: Attribute.justifyAlignment,
            options: _getButtonOptions(),
          ),
          _buildVerticalDivider(),

          // Header dropdown
          QuillToolbarSelectHeaderStyleDropdownButton(
            controller: viewModel.quillController,
            options: QuillToolbarSelectHeaderStyleDropdownButtonOptions(
              textStyle: TextStyle(color: _DesignColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbarRow2() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Ordered list, Bullet list, Checkbox
          QuillToolbarToggleStyleButton(
            controller: viewModel.quillController,
            attribute: Attribute.ol,
            options: _getButtonOptions(),
          ),
          QuillToolbarToggleStyleButton(
            controller: viewModel.quillController,
            attribute: Attribute.ul,
            options: _getButtonOptions(),
          ),
          QuillToolbarToggleCheckListButton(
            controller: viewModel.quillController,
            options: QuillToolbarToggleCheckListButtonOptions(
              iconTheme: _getIconTheme(),
            ),
          ),
          _buildVerticalDivider(),

          // Code Block
          QuillToolbarToggleStyleButton(
            controller: viewModel.quillController,
            attribute: Attribute.codeBlock,
            options: _getButtonOptions(),
          ),
          _buildVerticalDivider(),

          // Quote
          QuillToolbarToggleStyleButton(
            controller: viewModel.quillController,
            attribute: Attribute.blockQuote,
            options: _getButtonOptions(),
          ),
          _buildVerticalDivider(),

          // Indent buttons
          QuillToolbarIndentButton(
            controller: viewModel.quillController,
            isIncrease: true,
            options: QuillToolbarIndentButtonOptions(
              iconTheme: _getIconTheme(),
            ),
          ),
          QuillToolbarIndentButton(
            controller: viewModel.quillController,
            isIncrease: false,
            options: QuillToolbarIndentButtonOptions(
              iconTheme: _getIconTheme(),
            ),
          ),
          _buildVerticalDivider(),

          // Link
          QuillToolbarLinkStyleButton(
            controller: viewModel.quillController,
            options: QuillToolbarLinkStyleButtonOptions(
              iconTheme: _getIconTheme(),
            ),
          ),
        ],
      ),
    );
  }

  /// Toggle button for Rich Text / HTML
  Widget _buildModeToggleButton() {
    final isHtml = viewModel.isHtmlMode;
    return Container(
      decoration: BoxDecoration(
        color: _DesignColors.accent.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _DesignColors.accent.withOpacity(0.5)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            viewModel.toggleEditorMode();
          },
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isHtml ? Icons.auto_awesome_rounded : Icons.code_rounded,
                  size: 14,
                  color: _DesignColors.accent,
                ),
                const SizedBox(width: 6),
                Text(
                  isHtml ? 'Rich Text' : 'HTML',
                  style: const TextStyle(
                    color: _DesignColors.accent,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVerticalDivider() {
    return Container(
      height: 20,
      width: 1,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: _DesignColors.divider.withOpacity(0.4),
    );
  }

  QuillToolbarToggleStyleButtonOptions _getButtonOptions() {
    return QuillToolbarToggleStyleButtonOptions(iconTheme: _getIconTheme());
  }

  QuillToolbarColorButtonOptions _getColorButtonOptions() {
    return QuillToolbarColorButtonOptions(iconTheme: _getIconTheme());
  }

  QuillIconTheme _getIconTheme() {
    return QuillIconTheme(
      iconButtonUnselectedData: IconButtonData(
        color: _DesignColors.textSecondary,
        iconSize: 18,
      ),
      iconButtonSelectedData: IconButtonData(
        color: _DesignColors.accent,
        iconSize: 18,
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.all(
            _DesignColors.accent.withOpacity(0.15),
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
      child: viewModel.isHtmlMode
          ? CodeTheme(
              data: CodeThemeData(styles: atomOneDarkTheme),
              child: CodeField(
                controller: viewModel.htmlController,
                textStyle: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 14,
                ),
                expands: true,
                decoration: const BoxDecoration(), // Remove default border
              ),
            )
          : QuillEditor.basic(
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

  void _showSettingsMenu(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _DesignColors.toolbarIsland,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'File Settings',
              style: TextStyle(color: _DesignColors.textPrimary, fontSize: 18),
            ),
            if (viewModel.currentFileName != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  viewModel.currentFileName!,
                  style: const TextStyle(
                    color: _DesignColors.textSecondary,
                    fontSize: 12,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            const Divider(color: _DesignColors.divider),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Change/Set Password
            _buildSettingsTile(
              icon: viewModel.isPasswordSet
                  ? Icons.lock_reset_rounded
                  : Icons.lock_outline_rounded,
              title: viewModel.isPasswordSet
                  ? 'Change Password'
                  : 'Set Password',
              onTap: () {
                Navigator.pop(context);
                // If set, we might want to ask for old password first?
                // For simplicity now, we just open the set password dialog which overwrites.
                // Or if we want "Change", we reuse the set password flow.
                _showPasswordDialog(context, isUnlock: false);
              },
            ),

            // Remove Password (only if set)
            if (viewModel.isPasswordSet)
              _buildSettingsTile(
                icon: Icons.lock_open_rounded,
                title: 'Remove Password',
                textColor: Colors.orangeAccent,
                iconColor: Colors.orangeAccent,
                onTap: () {
                  Navigator.pop(context); // Close settings
                  _handleLockAction(
                    context,
                  ); // This handles the remove logic/dialog
                },
              ),

            // Delete File
            _buildSettingsTile(
              icon: Icons.delete_outline_rounded,
              title: 'Delete File',
              textColor: Colors.redAccent,
              iconColor: Colors.redAccent,
              onTap: () {
                Navigator.pop(context);
                _confirmDelete(context);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Close',
              style: TextStyle(color: _DesignColors.subtleGray),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsTile({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    Color textColor = _DesignColors.textPrimary,
    Color iconColor = _DesignColors.textPrimary,
  }) {
    return ListTile(
      leading: Icon(icon, color: iconColor, size: 20),
      title: Text(title, style: TextStyle(color: textColor, fontSize: 14)),
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      onTap: onTap,
      hoverColor: _DesignColors.divider.withOpacity(0.2),
    );
  }

  void _confirmDelete(BuildContext context) {
    if (viewModel.currentFileName == null) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _DesignColors.toolbarIsland,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Delete Note?',
          style: TextStyle(color: _DesignColors.textPrimary),
        ),
        content: const Text(
          'This action cannot be undone. Are you sure you want to delete this file?',
          style: TextStyle(color: _DesignColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Cancel',
              style: TextStyle(color: _DesignColors.subtleGray),
            ),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await viewModel.deleteNote(viewModel.currentFileName!);
            },
            child: const Text(
              'Delete',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
  }
}
