import 'dart:async';
import 'dart:io';
import 'package:flutter/scheduler.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'dart:typed_data';
import '../viewmodels/content_viewmodel.dart';
import '../models/note_model.dart';
import 'password_dialog.dart';
import '../../../core/theme/app_theme.dart';

import 'package:code_text_field/code_text_field.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:pdfx/pdfx.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:path_provider/path_provider.dart';

// Theme-aware design colors helper
class _ContentColors {
  final ThemeData theme;
  _ContentColors(this.theme);

  Color get background => theme.appBackground;
  Color get toolbarIsland => theme.appSurface;
  Color get accent => theme.colorScheme.primary;
  Color get saveButton => theme.appAccent;
  Color get subtleGray => theme.appSubtleGray;
  Color get divider => theme.appDivider;
  Color get textPrimary => theme.appTextPrimary;
  Color get textSecondary => theme.appTextSecondary;
}

class ContentArea extends StatefulWidget {
  final ContentViewModel viewModel;

  const ContentArea({super.key, required this.viewModel});

  @override
  State<ContentArea> createState() => _ContentAreaState();
}

class _ContentAreaState extends State<ContentArea> {
  late final AttachmentEmbedBuilder _embedBuilder;
  late final QuillEditorConfig _editorConfig;
  late final FocusNode _focusNode;
  late final ScrollController _scrollController;

  ContentViewModel get viewModel => widget.viewModel;

  // Theme-aware colors - computed from context in build
  late _ContentColors colors;

  @override
  void initState() {
    super.initState();
    _embedBuilder = AttachmentEmbedBuilder(viewModel);
    // Cache local references to avoid property access in build/config
    _focusNode = viewModel.focusNode;
    _scrollController = viewModel.scrollController;

    _editorConfig = QuillEditorConfig(
      autoFocus: false,
      scrollable: true,
      expands: true,
      padding: const EdgeInsets.all(16), // Increased padding here directly
      keyboardAppearance: Brightness.dark,
      embedBuilders: [_embedBuilder],
      onLaunchUrl: (url) {
        viewModel.handleLinkClick(url);
      },
      // Optimization: Disable some heavy features if not needed
      enableInteractiveSelection: true,
      enableSelectionToolbar: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    colors = _ContentColors(theme);
    return LayoutBuilder(
      builder: (context, constraints) {
        // Use a higher breakpoint to trigger "Mobile/Compact" mode earlier,
        // preventing overflow on smaller tablets or when Sidebar is open on desktop.
        final isMobile = constraints.maxWidth < 900;

        return Container(
          color: colors.background,
          child: SafeArea(
            // Ensure status bar doesn't overlap
            child: Column(
              children: [
                // Top Strip - Clean breadcrumb + secondary actions
                ValueListenableBuilder<bool>(
                  valueListenable: viewModel.isLockedNotifier,
                  builder: (context, isLocked, child) {
                    return _buildTopStrip(context, isMobile);
                  },
                ),

                // Floating Toolbar Island (only when not locked)
                ValueListenableBuilder<bool>(
                  valueListenable: viewModel.isLockedNotifier,
                  builder: (context, isLocked, child) {
                    if (isLocked) return const SizedBox.shrink();
                    return _buildFloatingToolbar(isMobile);
                  },
                ),

                // Spacious Editor Area
                Expanded(child: _buildInputArea(context)),

                // Attachments Bar
                ValueListenableBuilder<bool>(
                  valueListenable: viewModel.isLockedNotifier,
                  builder: (context, isLocked, child) {
                    if (isLocked) return const SizedBox.shrink();
                    return ValueListenableBuilder<List<AttachmentModel>>(
                      valueListenable: viewModel.attachmentsNotifier,
                      builder: (context, attachments, child) {
                        if (attachments.isEmpty) return const SizedBox.shrink();
                        return AttachmentBar(viewModel: viewModel);
                      },
                    );
                  },
                ),
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
        Icon(Icons.edit_note_rounded, size: 18, color: colors.accent),
        const SizedBox(width: 8),
        if (!isMobile) ...[
          Text(
            'Editing',
            style: TextStyle(
              color: colors.subtleGray,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 6),
          Icon(
            Icons.chevron_right_rounded,
            size: 16,
            color: colors.subtleGray.withOpacity(0.6),
          ),
          const SizedBox(width: 6),
        ],
        // Editable title
        Expanded(
          child: TextField(
            controller: viewModel.titleController,
            style: TextStyle(
              color: colors.textPrimary,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
            decoration: InputDecoration(
              hintText: 'Untitled note',
              hintStyle: TextStyle(
                color: colors.subtleGray,
                fontWeight: FontWeight.w400,
              ),
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              disabledBorder: InputBorder.none,
              errorBorder: InputBorder.none,
              focusedErrorBorder: InputBorder.none,
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
              color: color ?? (isActive ? colors.accent : colors.subtleGray),
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
        backgroundColor: colors.saveButton,
        foregroundColor: Colors.white,
        disabledBackgroundColor: colors.saveButton.withOpacity(0.5),
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
                ? Icon(Icons.save_rounded, size: 18)
                : Text(
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
        color: colors.toolbarIsland,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.divider.withOpacity(0.3), width: 1),
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
                            color: colors.divider.withOpacity(0.3),
                            height: 1,
                          ),
                          _buildToolbarRow2(),
                        ],
                      ),
              ),
            ),
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
              style: TextStyle(color: colors.textSecondary, fontSize: 12),
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
              textStyle: TextStyle(color: colors.textSecondary),
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
        color: colors.accent.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.accent.withOpacity(0.5)),
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
                  color: colors.accent,
                ),
                const SizedBox(width: 6),
                Text(
                  isHtml ? 'Rich Text' : 'HTML',
                  style: TextStyle(
                    color: colors.accent,
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
      color: colors.divider.withOpacity(0.4),
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
        color: colors.textSecondary,
        iconSize: 18,
      ),
      iconButtonSelectedData: IconButtonData(
        color: colors.accent,
        iconSize: 18,
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.all(
            colors.accent.withOpacity(0.15),
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
                color: colors.toolbarIsland.withOpacity(0.5),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.lock_rounded,
                size: 48,
                color: colors.subtleGray,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'This note is locked',
              style: TextStyle(
                color: colors.textSecondary,
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
                backgroundColor: colors.accent,
                foregroundColor: Colors.white,
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 14,
                ),
              ),
              child: Text(
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
      padding: const EdgeInsets.all(16),
      child: viewModel.isHtmlMode
          ? SizedBox.expand(
              child: CodeTheme(
                data: CodeThemeData(styles: atomOneDarkTheme),
                child: SingleChildScrollView(
                  child: CodeField(
                    controller: viewModel.htmlController,
                    textStyle: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 14,
                      color: colors.textPrimary,
                    ),
                    expands: false,
                    maxLines: null,
                    minLines: 30,
                    background: colors.background,
                    lineNumberStyle: LineNumberStyle(
                      background: colors.background,
                      textStyle: TextStyle(color: colors.subtleGray),
                    ),
                  ),
                ),
              ),
            )
          : RepaintBoundary(
              child: QuillEditor.basic(
                controller: viewModel.quillController,
                config: _editorConfig,
                focusNode: _focusNode,
                scrollController: _scrollController,
              ),
            ),
    );
  }

  void _showSettingsMenu(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: colors.toolbarIsland,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'File Settings',
              style: TextStyle(color: colors.textPrimary, fontSize: 18),
            ),
            if (viewModel.currentFileName != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  viewModel.currentFileName!,
                  style: TextStyle(color: colors.textSecondary, fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            Divider(color: colors.divider),
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
                // Close settings menu first
                Navigator.pop(context);

                // Use State's mounted check and context for remaining operations
                if (!mounted) return;
                final stateContext = this.context;

                if (viewModel.isPasswordSet) {
                  // First, verify the current password
                  final currentPassword = await _showPasswordDialog(
                    stateContext,
                    mode: PasswordMode.unlock,
                  );
                  if (currentPassword == null || currentPassword.isEmpty)
                    return;

                  // Verify the current password
                  final verified = viewModel.verifyPassword(currentPassword);
                  if (!verified) {
                    if (mounted) {
                      ScaffoldMessenger.of(stateContext).showSnackBar(
                        const SnackBar(
                          content: Text('Incorrect current password.'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                    return;
                  }

                  // Now ask for the new password
                  if (!mounted) return;
                  final newPassword = await _showPasswordDialog(
                    stateContext,
                    mode: PasswordMode.set,
                  );
                  if (newPassword == null || newPassword.isEmpty) return;

                  // Show progress dialog
                  if (!mounted) return;
                  showDialog(
                    context: stateContext,
                    barrierDismissible: false,
                    builder: (ctx) => _ProgressDialog(viewModel: viewModel),
                  );

                  final result = await viewModel.changePassword(
                    newPassword,
                    oldPassword: currentPassword,
                  );

                  // Close progress dialog using root navigator
                  if (mounted) {
                    Navigator.of(stateContext, rootNavigator: true).pop();
                  }

                  if (mounted) {
                    ScaffoldMessenger.of(stateContext).showSnackBar(
                      SnackBar(
                        content: Text(result),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } else {
                  final password = await _showPasswordDialog(
                    stateContext,
                    mode: PasswordMode.set,
                  );
                  if (password != null && password.isNotEmpty) {
                    viewModel.setPassword(password);
                    if (mounted) _promptSave(stateContext);
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
                onTap: () async {
                  // Close settings menu first
                  Navigator.pop(context);

                  // Use State's mounted check and context for remaining operations
                  if (!mounted) return;
                  final stateContext = this.context;

                  // Prompt for password verification before removing
                  final password = await _showPasswordDialog(
                    stateContext,
                    mode: PasswordMode.unlock,
                  );
                  if (password == null || password.isEmpty) return;

                  // Verify the password first
                  final verified = viewModel.verifyPassword(password);
                  if (!verified) {
                    if (mounted) {
                      ScaffoldMessenger.of(stateContext).showSnackBar(
                        const SnackBar(
                          content: Text('Incorrect password.'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                    return;
                  }

                  // Show progress dialog
                  if (!mounted) return;
                  showDialog(
                    context: stateContext,
                    barrierDismissible: false,
                    builder: (ctx) => _ProgressDialog(viewModel: viewModel),
                  );

                  final success = await viewModel.removePassword(
                    password: password,
                  );

                  // Close progress dialog using root navigator
                  if (mounted) {
                    Navigator.of(stateContext, rootNavigator: true).pop();
                  }

                  if (mounted) {
                    ScaffoldMessenger.of(stateContext).showSnackBar(
                      SnackBar(
                        content: Text(
                          success
                              ? 'Password removed. Content decrypted.'
                              : 'Failed to remove password.',
                        ),
                        backgroundColor: success ? Colors.green : Colors.red,
                      ),
                    );
                  }
                },
              ),

            // Spacer and Divider before Delete
            const SizedBox(height: 16),
            Divider(color: colors.divider),

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
            child: Text('Close', style: TextStyle(color: colors.subtleGray)),
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
      leading: Icon(icon, color: iconColor ?? colors.textPrimary),
      title: Text(
        title,
        style: TextStyle(color: textColor ?? colors.textPrimary),
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
        backgroundColor: colors.toolbarIsland,
        title: Text(
          "Delete Note?",
          style: TextStyle(color: colors.textPrimary),
        ),
        content: Text(
          "This action cannot be undone.",
          style: TextStyle(color: colors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text("Cancel"),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              viewModel.deleteNote(viewModel.currentFileName!);
            },
            child: Text("Delete", style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }
} // End of ContentArea

/// Progress dialog that shows the current operation status
class _ProgressDialog extends StatelessWidget {
  final ContentViewModel viewModel;

  const _ProgressDialog({required this.viewModel});

  @override
  Widget build(BuildContext context) {
    final colors = _ContentColors(Theme.of(context));
    return Dialog(
      backgroundColor: colors.toolbarIsland,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ValueListenableBuilder<String?>(
          valueListenable: viewModel.progressNotifier,
          builder: (context, progress, _) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 40,
                  height: 40,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    valueColor: AlwaysStoppedAnimation<Color>(colors.accent),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  progress ?? 'Processing...',
                  style: TextStyle(color: colors.textPrimary, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

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

class AttachmentBar extends StatefulWidget {
  final ContentViewModel viewModel;
  const AttachmentBar({super.key, required this.viewModel});

  @override
  State<AttachmentBar> createState() => _AttachmentBarState();
}

class _AttachmentBarState extends State<AttachmentBar>
    with WidgetsBindingObserver {
  bool _isExpanded = true;
  bool _wasExpandedBeforeKeyboard = true;
  bool _keyboardVisible = false;
  late _ContentColors colors;

  ContentViewModel get viewModel => widget.viewModel;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    // Use post-frame callback to ensure we're on the main thread
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      // Check keyboard visibility by looking at view insets
      // Guard against empty views (can happen on desktop/web)
      final views = WidgetsBinding.instance.platformDispatcher.views;
      if (views.isEmpty) return;

      final bottomInset = views.first.viewInsets.bottom;
      final isKeyboardNowVisible = bottomInset > 0;

      if (isKeyboardNowVisible != _keyboardVisible) {
        _keyboardVisible = isKeyboardNowVisible;
        if (_keyboardVisible) {
          // Keyboard opened - remember current state and collapse
          _wasExpandedBeforeKeyboard = _isExpanded;
          if (_isExpanded && mounted) {
            setState(() => _isExpanded = false);
          }
        } else {
          // Keyboard closed - restore previous state
          if (_wasExpandedBeforeKeyboard && !_isExpanded && mounted) {
            setState(() => _isExpanded = true);
          }
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    colors = _ContentColors(Theme.of(context));
    if (viewModel.attachments.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      decoration: BoxDecoration(
        color: colors.background,
        border: Border(top: BorderSide(color: colors.divider.withOpacity(0.3))),
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
                  color: colors.textSecondary,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Text(
                  "Attachments (${viewModel.attachments.length})",
                  style: TextStyle(
                    color: colors.textSecondary,
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
          color: colors.toolbarIsland,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colors.divider.withOpacity(0.3)),
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
                color: colors.toolbarIsland,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colors.divider.withOpacity(0.3)),
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
                              errorBuilder: (c, e, s) => Icon(
                                Icons.broken_image,
                                color: colors.subtleGray,
                                size: 20,
                              ),
                            ),
                          );
                        }
                        return Icon(
                          Icons.broken_image,
                          color: colors.subtleGray,
                          size: 20,
                        );
                      },
                    )
                  : Center(
                      child: Icon(
                        Icons.insert_drive_file,
                        size: 24,
                        color: colors.accent,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: 60,
            child: Text(
              attachment.fileName,
              style: TextStyle(color: colors.textSecondary, fontSize: 9),
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
      backgroundColor: colors.toolbarIsland,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: Icon(Icons.visibility, color: colors.accent),
            title: Text("View", style: TextStyle(color: colors.textPrimary)),
            onTap: () {
              Navigator.pop(context);
              _viewAttachment(context, attachment);
            },
          ),
          ListTile(
            leading: Icon(Icons.save_alt, color: colors.saveButton),
            title: Text(
              "Save As...",
              style: TextStyle(color: colors.textPrimary),
            ),
            onTap: () {
              Navigator.pop(context);
              viewModel.exportAttachment(attachment);
            },
          ),
          ListTile(
            leading: Icon(Icons.delete, color: Colors.redAccent),
            title: Text("Delete", style: TextStyle(color: Colors.redAccent)),
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

  Future<File> _writeToTempFile(String filename, Uint8List bytes) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  _FileType _getFileType(String name, Uint8List? data) {
    final ext = name.split('.').last.toLowerCase();

    // Image
    if (['png', 'jpg', 'jpeg', 'webp', 'gif', 'heic'].contains(ext)) {
      return _FileType.image;
    }
    // PDF
    if (ext == 'pdf') {
      return _FileType.pdf;
    }
    // Video
    if (['mp4', 'mov', 'avi', 'mkv', 'webm'].contains(ext)) {
      return _FileType.video;
    }
    // Text
    if ([
      'txt',
      'md',
      'json',
      'dart',
      'yaml',
      'xml',
      'csv',
      'log',
    ].contains(ext)) {
      return _FileType.text;
    }

    // Magic number checks (fallback)
    if (data != null && data.length > 12) {
      // PDF: %PDF
      if (data[0] == 0x25 &&
          data[1] == 0x50 &&
          data[2] == 0x44 &&
          data[3] == 0x46) {
        return _FileType.pdf;
      }
      // PNG
      if (data[0] == 0x89 &&
          data[1] == 0x50 &&
          data[2] == 0x4E &&
          data[3] == 0x47) {
        return _FileType.image;
      }
      // JPEG
      if (data[0] == 0xFF && data[1] == 0xD8 && data[2] == 0xFF) {
        return _FileType.image;
      }
      // GIF
      if (data[0] == 0x47 &&
          data[1] == 0x49 &&
          data[2] == 0x46 &&
          data[3] == 0x38) {
        return _FileType.image;
      }
    }

    return _FileType.other;
  }

  void _viewAttachment(BuildContext context, AttachmentModel attachment) {
    // Local helper to build consistent dialogs with integrated close button
    Widget buildDialogContent(BuildContext ctx, List<Widget> children) {
      return Container(
        padding: EdgeInsets.zero,
        decoration: BoxDecoration(
          color: colors.toolbarIsland,
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
                icon: Icon(Icons.close, color: colors.textSecondary, size: 20),
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
        insetPadding: EdgeInsets.zero,
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
                Text(
                  "Decrypting...",
                  style: TextStyle(color: colors.textPrimary),
                ),
              ]);
            }

            final data = snapshot.data;
            if (data != null && data.isNotEmpty) {
              final type = _getFileType(attachment.fileName, data);

              // Helper for unsupported or fallback view
              Widget buildFallback() {
                final sizeKb = (attachment.size / 1024).toStringAsFixed(1);
                return buildDialogContent(dialogContext, [
                  Icon(Icons.insert_drive_file, size: 48, color: colors.accent),
                  const SizedBox(height: 16),
                  Text(
                    attachment.fileName,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "$sizeKb KB",
                    style: TextStyle(color: colors.textSecondary, fontSize: 12),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    "No preview available",
                    style: TextStyle(color: colors.subtleGray, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ]);
              }

              switch (type) {
                case _FileType.image:
                  return LayoutBuilder(
                    builder: (context, constraints) {
                      return Stack(
                        alignment: Alignment.center,
                        children: [
                          Container(
                            width: constraints.maxWidth,
                            height: constraints.maxHeight,
                            child: InteractiveViewer(
                              minScale: 0.5,
                              maxScale: 5.0,
                              constrained: true,
                              child: Image.memory(
                                data,
                                fit: BoxFit.contain,
                                width: constraints.maxWidth,
                                height: constraints.maxHeight,
                                errorBuilder: (context, error, stackTrace) {
                                  return const Icon(
                                    Icons.broken_image,
                                    color: Colors.white,
                                    size: 64,
                                  );
                                },
                              ),
                            ),
                          ),
                          Positioned(
                            top: 10,
                            right: 10,
                            child: IconButton(
                              icon: const Icon(
                                Icons.close,
                                color: Colors.white,
                              ),
                              onPressed: () =>
                                  Navigator.of(dialogContext).pop(),
                              tooltip: 'Close',
                            ),
                          ),
                        ],
                      );
                    },
                  );

                case _FileType.pdf:
                  return FutureBuilder<File>(
                    future: _writeToTempFile(attachment.fileName, data),
                    builder: (ctx, fileSnapshot) {
                      if (!fileSnapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      return _PdfPreview(
                        filePath: fileSnapshot.data!.path,
                        onClose: () => Navigator.of(dialogContext).pop(),
                      );
                    },
                  );

                case _FileType.video:
                  return FutureBuilder<File>(
                    future: _writeToTempFile(attachment.fileName, data),
                    builder: (ctx, fileSnapshot) {
                      if (!fileSnapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      return _VideoPreview(
                        file: fileSnapshot.data!,
                        onClose: () => Navigator.of(dialogContext).pop(),
                      );
                    },
                  );

                case _FileType.text:
                  try {
                    final textContent = String.fromCharCodes(data);
                    return _TextPreview(
                      text: textContent,
                      colors: colors,
                      onClose: () => Navigator.of(dialogContext).pop(),
                    );
                  } catch (e) {
                    return buildFallback();
                  }

                default:
                  return buildFallback();
              }
            } else {
              return buildDialogContent(dialogContext, [
                Icon(Icons.error_outline, color: Colors.redAccent, size: 40),
                const SizedBox(height: 16),
                Text(
                  "Failed to load",
                  style: TextStyle(color: colors.textPrimary),
                ),
              ]);
            }
          },
        ),
      ),
    );
  }
}

enum _FileType { image, pdf, video, text, other }

class _PdfPreview extends StatefulWidget {
  final String filePath;
  final VoidCallback onClose;

  const _PdfPreview({required this.filePath, required this.onClose});

  @override
  State<_PdfPreview> createState() => _PdfPreviewState();
}

class _PdfPreviewState extends State<_PdfPreview> {
  // Use dynamic controller type to support both PdfController and PdfControllerPinch
  late dynamic _pdfController;
  late bool _isWindows;
  int _currentPage = 1;
  int _totalPages = 0;

  @override
  void initState() {
    super.initState();
    _isWindows = Platform.isWindows;
    if (_isWindows) {
      _pdfController = PdfController(
        document: PdfDocument.openFile(widget.filePath),
      );
    } else {
      _pdfController = PdfControllerPinch(
        document: PdfDocument.openFile(widget.filePath),
      );
    }
  }

  @override
  void dispose() {
    _pdfController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        _isWindows
            ? PdfView(
                controller: _pdfController as PdfController,
                scrollDirection: Axis.vertical,
                onDocumentLoaded: (document) {
                  setState(() {
                    _totalPages = document.pagesCount;
                  });
                },
                onPageChanged: (page) {
                  setState(() {
                    _currentPage = page;
                  });
                },
              )
            : PdfViewPinch(controller: _pdfController as PdfControllerPinch),
        Positioned(
          top: 10,
          right: 10,
          child: IconButton(
            icon: const Icon(Icons.close, color: Colors.black),
            onPressed: widget.onClose,
            tooltip: 'Close',
          ),
        ),
        // Page navigation for Windows
        if (_isWindows && _totalPages > 1)
          Positioned(
            bottom: 20,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left, color: Colors.black),
                  onPressed: _currentPage > 1
                      ? () => (_pdfController as PdfController).previousPage(
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeInOut,
                        )
                      : null,
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    '$_currentPage / $_totalPages',
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right, color: Colors.black),
                  onPressed: _currentPage < _totalPages
                      ? () => (_pdfController as PdfController).nextPage(
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeInOut,
                        )
                      : null,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _VideoPreview extends StatefulWidget {
  final File file;
  final VoidCallback onClose;

  const _VideoPreview({required this.file, required this.onClose});

  @override
  State<_VideoPreview> createState() => _VideoPreviewState();
}

class _VideoPreviewState extends State<_VideoPreview> {
  late VideoPlayerController _videoPlayerController;
  ChewieController? _chewieController;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    _videoPlayerController = VideoPlayerController.file(widget.file);
    await _videoPlayerController.initialize();
    _chewieController = ChewieController(
      videoPlayerController: _videoPlayerController,
      autoPlay: true,
      looping: false,
      aspectRatio: _videoPlayerController.value.aspectRatio,
      errorBuilder: (context, errorMessage) {
        return Center(
          child: Text(
            errorMessage,
            style: const TextStyle(color: Colors.white),
          ),
        );
      },
    );
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _videoPlayerController.dispose();
    _chewieController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_chewieController == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return Stack(
      alignment: Alignment.center,
      children: [
        Chewie(controller: _chewieController!),
        Positioned(
          top: 10,
          right: 10,
          child: IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: widget.onClose,
            tooltip: 'Close',
          ),
        ),
      ],
    );
  }
}

class _TextPreview extends StatelessWidget {
  final String text;
  final VoidCallback onClose;
  final _ContentColors colors;

  const _TextPreview({
    required this.text,
    required this.onClose,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          width: double.infinity,
          height: double.infinity,
          padding: const EdgeInsets.all(16),
          color: colors.background,
          child: SingleChildScrollView(
            child: SelectableText(
              text,
              style: TextStyle(color: colors.textPrimary),
            ),
          ),
        ),
        Positioned(
          top: 0,
          right: 0,
          child: IconButton(
            icon: Icon(Icons.close, color: colors.textSecondary),
            onPressed: onClose,
            tooltip: 'Close',
          ),
        ),
      ],
    );
  }
}
