import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'dart:typed_data';
import '../viewmodels/content_viewmodel.dart';
import '../models/note_model.dart';
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
    return LinkHandler(
      viewModel: viewModel,
      child: LayoutBuilder(
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

                  // Attachments Bar
                  // Attachments Bar
                  if (!viewModel.isLocked && viewModel.attachments.isNotEmpty)
                    AttachmentBar(viewModel: viewModel),
                ],
              ),
            ),
          );
        },
      ),
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

          // HTML/Rich Text Toggle Button
          if (!viewModel.isLocked) _buildModeToggleButton(),

          SizedBox(width: isMobile ? 8 : 12),

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
            onPressed: viewModel.pickAttachment,
          ),
        if (viewModel.isLocked || viewModel.isPasswordSet)
          _buildSubtleIconButton(
            viewModel.isLocked ? Icons.lock_rounded : Icons.lock_open_rounded,
            viewModel.isLocked ? 'Unlock' : 'Lock File',
            onPressed: () => _handleLockAction(context),
            isActive: true,
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
    Color? color,
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
              color:
                  color ??
                  (isActive ? _DesignColors.accent : _DesignColors.subtleGray),
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

  void _handleLockAction(BuildContext context) async {
    if (viewModel.isLocked) {
      final password = await _showPasswordDialog(
        context,
        mode: PasswordMode.unlock,
      );
      if (password != null && password.isNotEmpty) {
        viewModel.unlockNote(password);
      }
    } else if (viewModel.isPasswordSet) {
      // Lock the file manually as requested
      viewModel.manualLock();
    } else {
      final password = await _showPasswordDialog(
        context,
        mode: PasswordMode.set,
      );
      if (password != null && password.isNotEmpty) {
        viewModel.setPassword(password);
        _promptSave(context);
      }
    }
  }

  Future<String?> _showPasswordDialog(
    BuildContext context, {
    PasswordMode mode = PasswordMode.unlock,
  }) async {
    return showDialog<String>(
      context: context,
      builder: (context) {
        return PasswordDialog(
          mode: mode,
          onVerifyCurrent: (password) async {
            if (mode == PasswordMode.unlock) {
              return await viewModel.unlockNote(password);
            }
            return viewModel.verifyPassword(password);
          },
          onConfirm: (_) {}, // Handled by return value
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
              onPressed: () async {
                final password = await _showPasswordDialog(
                  context,
                  mode: PasswordMode.unlock,
                );
                if (password != null && password.isNotEmpty) {
                  viewModel.unlockNote(password);
                }
              },
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
          : GestureDetector(
              onTap: () {
                if (!viewModel.focusNode.hasFocus) {
                  viewModel.focusNode.requestFocus();
                }
              },
              behavior: HitTestBehavior.translucent,
              child: QuillEditor.basic(
                controller: viewModel.quillController,
                config: QuillEditorConfig(
                  autoFocus: false,
                  scrollable: true,
                  expands: true,
                  padding: const EdgeInsets.all(8),
                  keyboardAppearance: Brightness.dark,
                  embedBuilders: [AttachmentEmbedBuilder(viewModel)],
                  onLaunchUrl: (url) {
                    viewModel.handleLinkClick(url);
                  },
                ),
                focusNode: viewModel.focusNode,
                scrollController: viewModel.scrollController,
              ),
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
              onTap: () async {
                Navigator.pop(context);
                if (viewModel.isPasswordSet) {
                  final password = await _showPasswordDialog(
                    context,
                    mode: PasswordMode.update,
                  );
                  if (password != null && password.isNotEmpty) {
                    final count = await viewModel.changePassword(password);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Password updated. Re-encrypted $count notes.',
                          ),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  }
                } else {
                  final password = await _showPasswordDialog(
                    context,
                    mode: PasswordMode.set,
                  );
                  if (password != null && password.isNotEmpty) {
                    viewModel.setPassword(password);
                    _promptSave(context);
                  }
                }
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
    Color? textColor,
    Color? iconColor,
  }) {
    return ListTile(
      leading: Icon(icon, color: iconColor ?? _DesignColors.textPrimary),
      title: Text(
        title,
        style: TextStyle(color: textColor ?? _DesignColors.textPrimary),
      ),
      onTap: onTap,
    );
  }

  void _promptSave(BuildContext context) {
    viewModel.saveNote();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Note saved"),
        duration: Duration(seconds: 1),
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    if (viewModel.currentFileName == null) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _DesignColors.toolbarIsland,
        title: const Text(
          "Delete Note?",
          style: TextStyle(color: _DesignColors.textPrimary),
        ),
        content: const Text(
          "This action cannot be undone.",
          style: TextStyle(color: _DesignColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              viewModel.deleteNote(viewModel.currentFileName!);
            },
            child: const Text(
              "Delete",
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
  }
} // End of ContentArea

class AttachmentEmbedBuilder extends EmbedBuilder {
  final ContentViewModel viewModel;

  AttachmentEmbedBuilder(this.viewModel);

  @override
  String get key => BlockEmbed.imageType;

  @override
  bool get expanded => false;

  @override
  Widget build(BuildContext context, EmbedContext embedContext) {
    final node = embedContext.node;
    final String? imageUrl = node.value.data;

    if (imageUrl != null && imageUrl.startsWith('attach://')) {
      // Inline attachments are now displayed in the Attachment Bar.
      // We hide them from the editor viewport to avoid duplication and potential crashes.
      return const SizedBox.shrink();
    }

    if (imageUrl != null &&
        (imageUrl.startsWith('http') || imageUrl.startsWith('file'))) {
      return Image.network(imageUrl);
    }

    // Fallback for base64 or other formats if needed, or return nothing
    return const SizedBox();
  }
}

class LinkHandler extends StatefulWidget {
  final ContentViewModel viewModel;
  final Widget child;

  const LinkHandler({super.key, required this.viewModel, required this.child});

  @override
  State<LinkHandler> createState() => _LinkHandlerState();
}

class _LinkHandlerState extends State<LinkHandler> {
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    _sub = widget.viewModel.linkPickerRequest.listen((_) {
      _showLinkPicker();
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _showLinkPicker() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: const Color(0xFF2D3748), // _DesignColors.toolbarIsland
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          width: 400,
          constraints: const BoxConstraints(maxHeight: 500),
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  "Link to Note",
                  style: TextStyle(
                    color: Color(0xFFE2E8F0), // _DesignColors.textPrimary
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const Divider(
                color: Color(0xFF4A5568),
                height: 1,
              ), // _DesignColors.divider
              Expanded(
                child: widget.viewModel.recentFiles.isEmpty
                    ? const Center(
                        child: Text(
                          "No recent notes found",
                          style: TextStyle(color: Color(0xFF718096)),
                        ),
                      )
                    : ListView.separated(
                        itemCount: widget.viewModel.recentFiles.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1, color: Color(0xFF4A5568)),
                        itemBuilder: (context, index) {
                          final file = widget.viewModel.recentFiles[index];
                          // Skip current file? Maybe not.
                          // Extract ID if possible
                          String id = file.path;
                          if (file.path.startsWith('note_')) {
                            id = file.path.replaceFirst('note_', '');
                          }

                          return ListTile(
                            title: Text(
                              file.title.isEmpty ? "Untitled" : file.title,
                              style: const TextStyle(color: Color(0xFFE2E8F0)),
                            ),
                            subtitle: Text(
                              file.path,
                              style: const TextStyle(
                                color: Color(0xFF718096),
                                fontSize: 10,
                              ),
                            ),
                            onTap: () {
                              Navigator.pop(context);
                              widget.viewModel.insertInternalLink(
                                file.title.isEmpty ? "Note" : file.title,
                                id,
                              );
                            },
                          );
                        },
                      ),
              ),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Cancel"),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

class AttachmentBar extends StatefulWidget {
  final ContentViewModel viewModel;
  const AttachmentBar({super.key, required this.viewModel});

  @override
  State<AttachmentBar> createState() => _AttachmentBarState();
}

class _AttachmentBarState extends State<AttachmentBar> {
  bool _isExpanded = true;

  ContentViewModel get viewModel => widget.viewModel;

  @override
  Widget build(BuildContext context) {
    if (viewModel.attachments.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      decoration: BoxDecoration(
        color: _DesignColors.background,
        border: Border(
          top: BorderSide(color: _DesignColors.divider.withOpacity(0.3)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            behavior: HitTestBehavior.opaque,
            child: Row(
              children: [
                Icon(
                  _isExpanded
                      ? Icons.keyboard_arrow_down
                      : Icons.keyboard_arrow_right,
                  color: _DesignColors.textSecondary,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Text(
                  "Attachments (${viewModel.attachments.length})",
                  style: const TextStyle(
                    color: _DesignColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          if (_isExpanded) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 90,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: viewModel.attachments.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  return _buildAttachmentItem(
                    context,
                    viewModel.attachments[index],
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAttachmentItem(
    BuildContext context,
    AttachmentModel attachment,
  ) {
    // 1. Loading State
    if (attachment.isLoading) {
      return Container(
        width: 60,
        decoration: BoxDecoration(
          color: _DesignColors.toolbarIsland,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _DesignColors.divider.withOpacity(0.3)),
        ),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(height: 4),
              Text("Loading...", style: TextStyle(fontSize: 7)),
            ],
          ),
        ),
      );
    }

    final ext = attachment.fileName.split('.').last.toLowerCase();
    final isImg = ['jpg', 'jpeg', 'png', 'webp', 'heic'].contains(ext);

    return GestureDetector(
      onTap: () => _viewAttachment(context, attachment),
      onSecondaryTap: () => _showAttachmentMenu(context, attachment),
      onLongPress: () => _showAttachmentMenu(context, attachment),
      child: Column(
        children: [
          Expanded(
            child: Container(
              width: 60,
              decoration: BoxDecoration(
                color: _DesignColors.toolbarIsland,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _DesignColors.divider.withOpacity(0.3),
                ),
              ),
              child: isImg
                  ? FutureBuilder<Uint8List?>(
                      future: viewModel.readAttachment(attachment.id),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          );
                        }
                        if (snapshot.hasData && snapshot.data != null) {
                          return ClipRRect(
                            borderRadius: BorderRadius.circular(7),
                            child: Image.memory(
                              snapshot.data!,
                              fit: BoxFit.cover,
                              errorBuilder: (c, e, s) => const Icon(
                                Icons.broken_image,
                                color: _DesignColors.subtleGray,
                                size: 20,
                              ),
                            ),
                          );
                        }
                        return const Icon(
                          Icons.broken_image,
                          color: _DesignColors.subtleGray,
                          size: 20,
                        );
                      },
                    )
                  : const Center(
                      child: Icon(
                        Icons.insert_drive_file,
                        size: 24,
                        color: _DesignColors.accent,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: 60,
            child: Text(
              attachment.fileName,
              style: const TextStyle(
                color: _DesignColors.textSecondary,
                fontSize: 9,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  void _showAttachmentMenu(BuildContext context, AttachmentModel attachment) {
    showModalBottomSheet(
      context: context,
      backgroundColor: _DesignColors.toolbarIsland,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.visibility, color: _DesignColors.accent),
            title: const Text(
              "View",
              style: TextStyle(color: _DesignColors.textPrimary),
            ),
            onTap: () {
              Navigator.pop(context);
              _viewAttachment(context, attachment);
            },
          ),
          ListTile(
            leading: const Icon(
              Icons.save_alt,
              color: _DesignColors.saveButton,
            ),
            title: const Text(
              "Save As...",
              style: TextStyle(color: _DesignColors.textPrimary),
            ),
            onTap: () {
              Navigator.pop(context);
              viewModel.exportAttachment(attachment);
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete, color: Colors.redAccent),
            title: const Text(
              "Delete",
              style: TextStyle(color: Colors.redAccent),
            ),
            onTap: () {
              Navigator.pop(context);
              viewModel.removeAttachment(attachment.id);
            },
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  void _viewAttachment(BuildContext context, AttachmentModel attachment) {
    // Local helper to build consistent dialogs with integrated close button
    Widget buildDialogContent(BuildContext ctx, List<Widget> children) {
      return Container(
        padding: EdgeInsets.zero,
        decoration: BoxDecoration(
          color: _DesignColors.toolbarIsland,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
              child: Column(mainAxisSize: MainAxisSize.min, children: children),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: IconButton(
                icon: const Icon(
                  Icons.close,
                  color: _DesignColors.textSecondary,
                  size: 20,
                ),
                onPressed: () => Navigator.of(ctx).pop(),
                tooltip: 'Close',
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(),
                splashRadius: 20,
              ),
            ),
          ],
        ),
      );
    }

    showDialog(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        child: FutureBuilder<Uint8List?>(
          future: viewModel.readAttachment(attachment.id),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return buildDialogContent(dialogContext, [
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(height: 16),
                const Text(
                  "Decrypting...",
                  style: TextStyle(color: _DesignColors.textPrimary),
                ),
              ]);
            }

            final data = snapshot.data;
            if (data != null && data.isNotEmpty) {
              if (_isImage(attachment.fileName, data)) {
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    InteractiveViewer(
                      maxScale: 5.0,
                      child: Image.memory(
                        data,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) {
                          return const Icon(
                            Icons.broken_image,
                            color: Colors.white,
                            size: 64,
                          );
                        },
                      ),
                    ),
                    Positioned(
                      top: 0,
                      right: 0,
                      child: IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        tooltip: 'Close',
                      ),
                    ),
                  ],
                );
              } else {
                final sizeKb = (attachment.size / 1024).toStringAsFixed(1);
                return buildDialogContent(dialogContext, [
                  const Icon(
                    Icons.insert_drive_file,
                    size: 48,
                    color: _DesignColors.accent,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    attachment.fileName,
                    style: const TextStyle(
                      color: _DesignColors.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "$sizeKb KB",
                    style: const TextStyle(
                      color: _DesignColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    "No preview available",
                    style: TextStyle(
                      color: _DesignColors.subtleGray,
                      fontSize: 12,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ]);
              }
            } else {
              return buildDialogContent(dialogContext, [
                const Icon(
                  Icons.error_outline,
                  color: Colors.redAccent,
                  size: 40,
                ),
                const SizedBox(height: 16),
                const Text(
                  "Failed to load",
                  style: TextStyle(color: _DesignColors.textPrimary),
                ),
              ]);
            }
          },
        ),
      ),
    );
  }

  bool _isImage(String name, Uint8List? data) {
    final ext = name.split('.').last.toLowerCase();
    if (name.contains('.') &&
        ['png', 'jpg', 'jpeg', 'webp', 'gif'].contains(ext)) {
      return true;
    }
    if (data != null && data.length > 12) {
      if (data[0] == 0x89 &&
          data[1] == 0x50 &&
          data[2] == 0x4E &&
          data[3] == 0x47)
        return true;
      if (data[0] == 0xFF && data[1] == 0xD8 && data[2] == 0xFF) return true;
      if (data[0] == 0x47 &&
          data[1] == 0x49 &&
          data[2] == 0x46 &&
          data[3] == 0x38)
        return true;
      if (data[8] == 0x57 &&
          data[9] == 0x45 &&
          data[10] == 0x42 &&
          data[11] == 0x50)
        return true;
    }
    return false;
  }
}
