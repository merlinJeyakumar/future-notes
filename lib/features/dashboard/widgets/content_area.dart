import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_dialog.dart';
import '../models/save_ui_state.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import '../viewmodels/content_viewmodel.dart';
import 'attachment_job_panel.dart';
import 'attachment_strip.dart';
import 'attachment_mentions.dart';
import 'attachment_preview.dart';
import 'expanding_formatting_bar.dart';
import '../../../core/routing/fnotes_uri.dart';
import '../models/note_model.dart';
import 'password_dialog.dart';
import 'note_unlock_form.dart';
import '../../../core/theme/app_theme.dart';

import 'package:code_text_field/code_text_field.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_highlight/themes/github.dart';

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
  final _unlockFocusNode = FocusNode(debugLabel: 'Note unlock password');
  final _htmlFocusNode = FocusNode(debugLabel: 'HTML source');
  final _attachmentCollapseRequests = ValueNotifier<int>(0);
  final _richEditorKey = GlobalKey<EditorState>();
  final _htmlEditorKey = GlobalKey();

  void _collapseAttachments() => _attachmentCollapseRequests.value++;

  void _onEditorFocus() {
    if (_focusNode.hasFocus || _htmlFocusNode.hasFocus) {
      _collapseAttachments();
    }
  }

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
    _focusNode.addListener(_onEditorFocus);
    _htmlFocusNode.addListener(_onEditorFocus);

    _editorConfig = QuillEditorConfig(
      editorKey: _richEditorKey,
      customLinkPrefixes: const ['fnotes://', 'note://'],
      autoFocus: false,
      scrollable: true,
      expands: true,
      padding:
          EdgeInsets.zero, // The input area supplies the single writing inset.
      keyboardAppearance: Brightness.dark,
      embedBuilders: [_embedBuilder],
      onLaunchUrl: (url) {
        if (FnotesTarget.isInternal(url)) {
          final result = viewModel.resolveInternalLink(url);
          if (result.isSuccess) {
            unawaited(
              openAttachmentPreview(
                context,
                viewModel,
                result.value!,
                restoreFocus: _focusNode,
              ),
            );
          } else {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(result.message!)));
          }
        } else {
          viewModel.handleLinkClick(url);
        }
      },
      // Optimization: Disable some heavy features if not needed
      enableInteractiveSelection: true,
      enableSelectionToolbar: true,
    );
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onEditorFocus);
    _htmlFocusNode.removeListener(_onEditorFocus);
    _attachmentCollapseRequests.dispose();
    _unlockFocusNode.dispose();
    _htmlFocusNode.dispose();
    super.dispose();
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
                    if (isLocked || viewModel.isHtmlMode) {
                      return const SizedBox.shrink();
                    }
                    return IgnorePointer(
                      ignoring: viewModel.isLibraryCutover,
                      child: Padding(
                        padding: EdgeInsets.only(
                          left: isMobile ? 12 : 20,
                          right: isMobile ? 12 : 20,
                          top: 8,
                          bottom: 4,
                        ),
                        child: ExpandingFormattingBar(
                          key: ValueKey((
                            viewModel.draftSession.generation,
                            viewModel.currentContentPath,
                          )),
                          surfaceColor: colors.toolbarIsland,
                          outlineColor: colors.divider.withValues(alpha: .3),
                          restoreEditorFocus: _restoreEditorFocus,
                          expandedChild: _buildFormattingControls(
                            expanded: true,
                          ),
                          child: _buildFormattingControls(),
                        ),
                      ),
                    );
                  },
                ),

                // Editor Area
                Expanded(
                  child: AppEntrance(
                    identity:
                        viewModel.currentContentPath ??
                        viewModel.draftSession.generation,
                    trigger: (
                      viewModel.draftSession.generation,
                      viewModel.currentContentPath,
                      viewModel.isLocked,
                      viewModel.editorMode,
                    ),
                    enabled: !viewModel.isLocked,
                    child: Listener(
                      onPointerDown: (_) => _collapseAttachments(),
                      child: AttachmentMentions(
                        model: viewModel,
                        richKey: _richEditorKey,
                        htmlKey: _htmlEditorKey,
                        htmlFocus: _htmlFocusNode,
                        child: _buildInputArea(context, isMobile: isMobile),
                      ),
                    ),
                  ),
                ),

                AttachmentJobPanel(viewModel: viewModel, auxiliaryOnly: true),
                ValueListenableBuilder(
                  valueListenable: viewModel.pendingDeletionsNotifier,
                  builder: (context, pending, _) => Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final reference in pending)
                        Row(
                          children: [
                            const Expanded(
                              child: Text('Permanent deletion is incomplete.'),
                            ),
                            TextButton(
                              onPressed: () =>
                                  viewModel.deleteReviewedNote(reference),
                              child: const Text('Retry cleanup'),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),

                // Attachments Bar
                ValueListenableBuilder<bool>(
                  valueListenable: viewModel.isLockedNotifier,
                  builder: (context, isLocked, child) {
                    if (isLocked) return const SizedBox.shrink();
                    return ValueListenableBuilder<List<AttachmentModel>>(
                      valueListenable: viewModel.attachmentsNotifier,
                      builder: (context, attachments, child) {
                        return AttachmentStrip(
                          viewModel: viewModel,
                          collapseRequests: _attachmentCollapseRequests,
                        );
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

  /// Compact Stitch header; secondary actions reflow without taking title space.
  Widget _buildTopStrip(BuildContext context, bool isMobile) {
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final date = Text(
      viewModel.currentNoteDate == null
          ? 'Not saved'
          : 'Note date ${_formatDate(viewModel.currentNoteDate!)}',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(color: colors.textSecondary, fontSize: 9.504),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 1000 * scale;
          if (wide) {
            return Row(
              children: [
                Expanded(child: _buildHeaderTitle()),
                const SizedBox(width: 16),
                date,
                if (!viewModel.isLocked) ...[
                  const SizedBox(width: 12),
                  _buildModeToggleButton(),
                ],
                const SizedBox(width: 8),
                _buildSecondaryActions(context),
                if (!viewModel.isLocked) ...[
                  const SizedBox(width: 8),
                  _buildSaveButton(false),
                ],
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: _buildHeaderTitle()),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Align(alignment: Alignment.centerRight, child: date),
                  ),
                ],
              ),
              if (!viewModel.isLocked)
                if (constraints.maxWidth >= 600 * scale)
                  Row(
                    children: [
                      _buildModeToggleButton(),
                      const Spacer(),
                      _buildSecondaryActions(context),
                      const SizedBox(width: 8),
                      _buildSaveButton(false),
                    ],
                  )
                else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: _buildModeToggleButton(),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Wrap(
                          alignment: WrapAlignment.end,
                          spacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            _buildSecondaryActions(context),
                            _buildSaveButton(false),
                          ],
                        ),
                      ),
                    ],
                  )
              else
                Align(
                  alignment: Alignment.centerRight,
                  child: _buildSecondaryActions(context),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeaderTitle() => Row(
    children: [
      Icon(
        viewModel.isLocked ? Icons.lock_outline : Icons.edit_note_rounded,
        size: 18,
        color: colors.accent,
      ),
      const SizedBox(width: 8),
      Expanded(
        child: viewModel.isLocked
            ? Text(
                viewModel.titleController.text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 11.232,
                  fontWeight: FontWeight.w600,
                ),
              )
            : TextField(
                controller: viewModel.titleController,
                readOnly:
                    viewModel.isLibraryCutover ||
                    viewModel.isImportCutover ||
                    viewModel.isDeletingCurrent ||
                    !viewModel.draftSession.canWrite,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 11.232,
                  fontWeight: FontWeight.w600,
                ),
                decoration: InputDecoration(
                  hintText: 'Untitled note',
                  hintStyle: TextStyle(color: colors.subtleGray),
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
      ),
    ],
  );

  String _formatDate(DateTime value) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${value.day} ${months[value.month - 1]} ${value.year}';
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
        if (!viewModel.isLocked)
          _buildSubtleIconButton(
            Icons.settings_outlined,
            'Note actions',
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
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      icon: Icon(
        icon,
        size: 20,
        color: color ?? (isActive ? colors.accent : colors.subtleGray),
      ),
    );
  }

  Widget _buildSaveButton(bool isMobile) => ValueListenableBuilder<SaveUiState>(
    valueListenable: viewModel.saveStateNotifier,
    builder: (context, state, _) => ElevatedButton(
      onPressed:
          viewModel.isBusy ||
              !state.hasChanges ||
              state.phase == SavePhase.saving ||
              !viewModel.draftSession.canWrite
          ? null
          : () => viewModel.saveNote(),
      style: ElevatedButton.styleFrom(
        backgroundColor: colors.saveButton,
        foregroundColor: Colors.white,
        disabledBackgroundColor: colors.saveButton.withValues(alpha: .5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        textStyle: const TextStyle(
          fontSize: 10.368,
          fontWeight: FontWeight.w600,
        ),
        elevation: 0,
      ),
      child: Text(
        state.phase == SavePhase.saving
            ? 'Saving…'
            : state.canRetry
            ? 'Retry Save'
            : 'Save Note',
      ),
    ),
  );

  /// Floating toolbar "island" with grouped formatting tools
  Widget _buildFormattingControls({bool expanded = false}) => AbsorbPointer(
    absorbing:
        viewModel.isLibraryCutover ||
        viewModel.isImportCutover ||
        !viewModel.draftSession.canWrite,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: expanded
          ? Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ..._toolbarPrimaryControls(),
                _buildVerticalDivider(),
                ..._toolbarSecondaryControls(),
              ],
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ..._toolbarPrimaryControls(),
                _buildVerticalDivider(),
                ..._toolbarSecondaryControls(),
              ],
            ),
    ),
  );

  List<Widget> _toolbarPrimaryControls() => [
    // Undo/Redo
    QuillToolbarHistoryButton(
      controller: viewModel.quillController,
      isUndo: true,
      options: QuillToolbarHistoryButtonOptions(
        afterButtonPressed: _restoreEditorFocus,
        iconTheme: _getIconTheme(),
      ),
    ),
    QuillToolbarHistoryButton(
      controller: viewModel.quillController,
      isUndo: false,
      options: QuillToolbarHistoryButtonOptions(
        afterButtonPressed: _restoreEditorFocus,
        iconTheme: _getIconTheme(),
      ),
    ),
    _buildVerticalDivider(),

    // Font Size dropdown
    QuillToolbarFontSizeButton(
      controller: viewModel.quillController,
      options: QuillToolbarFontSizeButtonOptions(
        afterButtonPressed: _restoreEditorFocus,
        style: TextStyle(color: colors.textSecondary, fontSize: 9.504),
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
        afterButtonPressed: _restoreEditorFocus,
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
        afterButtonPressed: _restoreEditorFocus,
        textStyle: TextStyle(color: colors.textSecondary),
      ),
    ),
  ];

  List<Widget> _toolbarSecondaryControls() => [
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
        afterButtonPressed: _restoreEditorFocus,
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
        afterButtonPressed: _restoreEditorFocus,
        iconTheme: _getIconTheme(),
      ),
    ),
    QuillToolbarIndentButton(
      controller: viewModel.quillController,
      isIncrease: false,
      options: QuillToolbarIndentButtonOptions(
        afterButtonPressed: _restoreEditorFocus,
        iconTheme: _getIconTheme(),
      ),
    ),
    _buildVerticalDivider(),

    // Link
    QuillToolbarLinkStyleButton(
      controller: viewModel.quillController,
      options: QuillToolbarLinkStyleButtonOptions(iconTheme: _getIconTheme()),
    ),
  ];

  /// Small segmented mode control following the Stitch header refinement.
  Widget _buildModeToggleButton() => ValueListenableBuilder<bool>(
    valueListenable: viewModel.isConvertingNotifier,
    builder: (context, converting, _) => DecoratedBox(
      decoration: BoxDecoration(
        color: colors.toolbarIsland,
        border: Border.all(color: colors.divider),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final mode in EditorMode.values)
            Semantics(
              selected: viewModel.editorMode == mode,
              child: TextButton(
                onPressed:
                    converting ||
                        viewModel.isImportCutover ||
                        !viewModel.draftSession.canWrite
                    ? null
                    : () => viewModel.setEditorMode(mode),
                style: TextButton.styleFrom(
                  foregroundColor: colors.textPrimary,
                  backgroundColor: viewModel.editorMode == mode
                      ? colors.accent.withValues(alpha: .16)
                      : Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                  minimumSize: const Size(64, 32),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  textStyle: const TextStyle(
                    fontSize: 9.504,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: Text(mode == EditorMode.html ? 'HTML' : 'Rich text'),
              ),
            ),
          if (converting)
            const Padding(
              padding: EdgeInsets.all(8),
              child: SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
        ],
      ),
    ),
  );

  Widget _buildVerticalDivider() {
    return Container(
      height: 20,
      width: 1,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: colors.divider.withOpacity(0.4),
    );
  }

  QuillToolbarToggleStyleButtonOptions _getButtonOptions() {
    return QuillToolbarToggleStyleButtonOptions(
      iconTheme: _getIconTheme(),
      afterButtonPressed: _restoreEditorFocus,
    );
  }

  void _restoreEditorFocus() {
    if (!mounted ||
        viewModel.isLocked ||
        viewModel.isHtmlMode ||
        viewModel.isImportCutover ||
        !viewModel.draftSession.canWrite) {
      return;
    }
    _focusNode.requestFocus();
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
      _unlockFocusNode.requestFocus();
    } else if (viewModel.isPasswordSet) {
      // Lock the file manually as requested
      viewModel.manualLock();
    } else {
      if (!viewModel.ensureExtendedNoteOperations()) return;
      final password = await _showPasswordDialog(
        context,
        mode: PasswordMode.set,
      );
      if (password != null && password.isNotEmpty) {
        final result = await viewModel.setPassword(password);
        if (!mounted || !result.isSuccess) return;
        if (!viewModel.usesOwnedStorage || !viewModel.draftSession.isPersisted)
          _promptSave(this.context);
      }
    }
  }

  Future<String?> _showPasswordDialog(
    BuildContext context, {
    PasswordMode mode = PasswordMode.unlock,
  }) async {
    return showAppDialog<String>(
      context: context,
      builder: (context) {
        return PasswordDialog(
          mode: mode,
          onVerifyCurrent: (password) async {
            if (mode == PasswordMode.unlock) {
              return await viewModel.verifyStoredPassword(password);
            }
            return viewModel.verifyPassword(password);
          },
          onConfirm: (_) {}, // Handled by return value
        );
      },
    );
  }

  Widget _buildInputArea(BuildContext context, {required bool isMobile}) {
    if (viewModel.isLocked) {
      return NoteUnlockForm(
        key: ValueKey(viewModel.draftSession.generation),
        focusNode: _unlockFocusNode,
        onUnlock: (password) async {
          final unlocked = await viewModel.unlockNote(password);
          if (unlocked && mounted) {
            final generation = viewModel.draftSession.generation;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted &&
                  !viewModel.isLocked &&
                  generation == viewModel.draftSession.generation) {
                _focusNode.requestFocus();
              }
            });
          }
          return unlocked;
        },
      );
    }

    // One modest inset, shared by Rich text and HTML.
    return Padding(
      padding: EdgeInsets.only(
        left: isMobile ? 12 : 20,
        right: isMobile ? 12 : 20,
        top: 4,
        bottom: 8,
      ),
      child: viewModel.isHtmlMode
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: ValueListenableBuilder<bool>(
                    valueListenable: viewModel.isConvertingNotifier,
                    builder: (context, converting, _) => TextButton.icon(
                      onPressed:
                          converting ||
                              !viewModel.draftSession.canWrite ||
                              viewModel.isLibraryCutover ||
                              viewModel.isImportCutover ||
                              viewModel.isDeletingCurrent
                          ? null
                          : () async {
                              await viewModel.formatHtml();
                              if (mounted &&
                                  viewModel.isHtmlMode &&
                                  !viewModel.isLocked) {
                                _htmlFocusNode.requestFocus();
                              }
                            },
                      icon: const Icon(Icons.format_align_left, size: 15),
                      label: Text(
                        converting ? 'Formatting…' : 'Format HTML',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: CodeTheme(
                    data: CodeThemeData(
                      styles: Theme.of(context).brightness == Brightness.dark
                          ? atomOneDarkTheme
                          : githubTheme,
                    ),
                    child: SingleChildScrollView(
                      child: CodeField(
                        key: _htmlEditorKey,
                        controller: viewModel.htmlController,
                        focusNode: _htmlFocusNode,
                        readOnly:
                            viewModel.isLibraryCutover ||
                            viewModel.isImportCutover ||
                            viewModel.isDeletingCurrent ||
                            !viewModel.draftSession.canWrite,
                        textStyle: TextStyle(
                          fontFamily: 'Consolas',
                          fontFamilyFallback: const [
                            'Courier New',
                            'monospace',
                          ],
                          fontSize: 12,
                          height: 1.5,
                          color: colors.textPrimary,
                        ),
                        expands: false,
                        maxLines: null,
                        minLines: 30,
                        background: colors.background,
                        lineNumberStyle: LineNumberStyle(
                          background: colors.background,
                          textStyle: TextStyle(
                            color: colors.subtleGray,
                            fontSize: 12,
                            height: 1.5,
                            fontFamily: 'Consolas',
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
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
    if (!viewModel.ensureExtendedNoteOperations()) return;
    showAppDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: colors.toolbarIsland,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Note actions',
              style: TextStyle(color: colors.textPrimary, fontSize: 13.824),
            ),
            if (viewModel.currentFileName != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  viewModel.currentFileName!,
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 9.504,
                  ),
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

                  // Legacy operations retain their existing modal; owned
                  // preparation uses the nonblocking per-file/batch channels.
                  if (!mounted) return;
                  if (!viewModel.usesOwnedStorage)
                    showAppDialog(
                      context: stateContext,
                      barrierDismissible: false,
                      builder: (ctx) => _ProgressDialog(viewModel: viewModel),
                    );

                  final result = await viewModel.changePasswordResult(
                    newPassword,
                    oldPassword: currentPassword,
                  );

                  // Close progress dialog using root navigator
                  if (mounted && !viewModel.usesOwnedStorage) {
                    Navigator.of(stateContext, rootNavigator: true).pop();
                  }

                  if (mounted) {
                    ScaffoldMessenger.of(stateContext).showSnackBar(
                      SnackBar(
                        content: Text(
                          result.isSuccess
                              ? 'Password changed successfully'
                              : result.message ?? 'Password change failed.',
                        ),
                        backgroundColor: result.isSuccess
                            ? Colors.green
                            : Colors.red,
                      ),
                    );
                  }
                } else {
                  final password = await _showPasswordDialog(
                    stateContext,
                    mode: PasswordMode.set,
                  );
                  if (password != null && password.isNotEmpty) {
                    final saved = await viewModel.setPassword(password);
                    if (mounted &&
                        saved.isSuccess &&
                        (!viewModel.usesOwnedStorage ||
                            !viewModel.draftSession.isPersisted)) {
                      _promptSave(this.context);
                    }
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
                  if (!viewModel.usesOwnedStorage)
                    showAppDialog(
                      context: stateContext,
                      barrierDismissible: false,
                      builder: (ctx) => _ProgressDialog(viewModel: viewModel),
                    );

                  final success = await viewModel.removePassword(
                    password: password,
                  );

                  // Close progress dialog using root navigator
                  if (mounted && !viewModel.usesOwnedStorage) {
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

  Future<void> _promptSave(BuildContext context) async {
    final result = await viewModel.saveNote();
    if (!context.mounted || !result.isSuccess) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Note saved"),
        duration: Duration(seconds: 1),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    if (!viewModel.usesOwnedStorage &&
        !viewModel.ensureExtendedNoteOperations())
      return;
    if (viewModel.currentFileName == null) return;
    final fileName = viewModel.currentFileName!;
    final reference = viewModel.usesOwnedStorage
        ? await viewModel.reviewDeletion(fileName)
        : null;
    if (!context.mounted || (viewModel.usesOwnedStorage && reference == null))
      return;
    showAppDialog(
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
              if (reference != null) {
                viewModel.deleteReviewedNote(reference);
              } else {
                viewModel.deleteNote(fileName);
              }
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
                  style: TextStyle(color: colors.textPrimary, fontSize: 11.232),
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
