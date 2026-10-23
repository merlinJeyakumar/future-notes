import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_dialog.dart';
import '../models/save_ui_state.dart';
import '../models/attachment_job.dart';
import 'dart:async';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import '../viewmodels/content_viewmodel.dart';
import '../widgets/attachment_job_panel.dart';
import 'attachment_strip.dart';
import 'attachment_progress.dart';
import 'attachment_mentions.dart';
import 'attachment_preview.dart';
import 'expanding_formatting_bar.dart';
import 'editor_panels.dart';
import 'editor_focus.dart';
import 'selection_toolbar.dart';
import 'job_notifications.dart';
import '../../../core/routing/fnotes_uri.dart';
import '../models/note_model.dart';
import '../widgets/password_dialog.dart';
import '../widgets/note_unlock_form.dart';
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
  Color get subtleGray => theme.appSubtleGray;
  Color get divider => theme.appDivider;
  Color get textPrimary => theme.appTextPrimary;
  Color get textSecondary => theme.appTextSecondary;
}

class MobileContentArea extends StatefulWidget {
  final ContentViewModel viewModel;

  const MobileContentArea({
    super.key,
    required this.viewModel,
    this.onBack,
    this.jobNotificationCount,
    this.activeJobCount,
    this.onJobNotifications,
    this.onExport,
    this.exportRequests,
    this.dismissPanels,
  });
  final VoidCallback? onBack;
  final ValueListenable<int>? jobNotificationCount;
  final ValueListenable<int>? activeJobCount;
  final VoidCallback? onJobNotifications;
  final Future<void> Function()? onExport;
  final ValueListenable<int>? exportRequests;
  final Listenable? dismissPanels;

  @override
  State<MobileContentArea> createState() => _MobileContentAreaState();
}

class _MobileContentAreaState extends State<MobileContentArea>
    with WidgetsBindingObserver {
  bool _keyboardVisible = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _keyboardVisible = View.of(context).viewInsets.bottom > 0;
  }

  @override
  void didChangeMetrics() {
    if (!mounted) return;
    // Scaffold removes the consumed bottom inset from its body MediaQuery.
    // Observe the owning view, so both Rich text and HTML use the real IME.
    final visible = View.of(context).viewInsets.bottom > 0;
    if (visible != _keyboardVisible) {
      // Insets also disappear for hardware keyboards and transient resizing.
      // Only actual focus, navigation or lifecycle changes end editing intent.
      setState(() => _keyboardVisible = visible);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _editorFocus.dismiss();
  }

  bool _exporting = false;
  bool _readOnlyBeforeExport = false;

  void _restoreExportReadOnly() {
    viewModel.quillController.readOnly =
        _readOnlyBeforeExport ||
        viewModel.isLibraryCutover ||
        viewModel.isImportCutover ||
        viewModel.isDeletingCurrent;
  }

  void _exportChanged() => _syncExportState();

  void _syncExportState({bool rebuild = true}) {
    final active =
        (widget.exportRequests?.value ?? 0) > 0 || viewModel.hasActiveExport;
    if (active == _exporting) return;
    if (active) {
      _readOnlyBeforeExport = viewModel.quillController.readOnly;
      viewModel.quillController.readOnly = true;
      _focusNode.unfocus();
      _htmlFocusNode.unfocus();
    } else {
      _restoreExportReadOnly();
    }
    _exporting = active;
    if (rebuild && mounted) setState(() {});
  }

  Widget _exportDisabled(Widget child) => ExcludeFocus(
    excluding: _exporting,
    child: ExcludeSemantics(
      excluding: _exporting,
      child: IgnorePointer(
        ignoring: _exporting,
        child: Opacity(opacity: _exporting ? .45 : 1, child: child),
      ),
    ),
  );
  static const _touch = true;
  late final AttachmentEmbedBuilder _embedBuilder;
  late final QuillEditorConfig _editorConfig;
  late final FocusNode _focusNode;
  late final ScrollController _scrollController;
  final _unlockFocusNode = FocusNode(debugLabel: 'Note unlock password');
  final _htmlFocusNode = FocusNode(debugLabel: 'HTML source');
  late final MobileEditorFocus _editorFocus;
  final _panels = MobileEditorPanels();
  final _editorViewportKey = GlobalKey(debugLabel: 'mobile-editor-viewport');
  Object? _panelOwner;
  Object? _watchedDocument;
  StreamSubscription? _bodyChanges;
  String _htmlText = '';
  final _richEditorKey = GlobalKey<EditorState>();
  final _htmlEditorKey = GlobalKey();

  void _collapseAttachments() => _panels.collapse();

  bool get _canEditBody =>
      !_exporting &&
      !viewModel.isLocked &&
      !viewModel.isLibraryCutover &&
      !viewModel.isImportCutover &&
      !viewModel.isDeletingCurrent &&
      viewModel.draftSession.canWrite;

  void _syncPanels() {
    final owner = (
      viewModel.draftSession.generation,
      viewModel.currentContentPath,
      viewModel.draftSession.credentialGeneration,
      viewModel.isLocked,
      viewModel.editorMode,
    );
    if (_panelOwner != owner) {
      _panelOwner = owner;
      _panels.collapse();
      _editorFocus.dismiss();
    }
    final document = viewModel.quillController.document;
    if (!identical(document, _watchedDocument)) {
      _bodyChanges?.cancel();
      _watchedDocument = document;
      _bodyChanges = viewModel.quillController.changes.listen((change) {
        if (change.source == ChangeSource.local &&
            _focusNode.hasFocus &&
            change.change.toList().any((op) => op.isInsert || op.isDelete)) {
          _panels.collapse();
        }
      });
    }
  }

  void _htmlChanged() {
    final text = viewModel.htmlController.text;
    if (text != _htmlText && _htmlFocusNode.hasFocus) _panels.collapse();
    _htmlText = text;
  }

  void _onEditorFocus() {
    if (_focusNode.hasFocus || _htmlFocusNode.hasFocus) {
      _panels.editorFocused();
    }
  }

  ContentViewModel get viewModel => widget.viewModel;

  // Theme-aware colors - computed from context in build
  late _ContentColors colors;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _embedBuilder = AttachmentEmbedBuilder(viewModel);
    // Cache local references to avoid property access in build/config
    _focusNode = viewModel.focusNode;
    _scrollController = viewModel.scrollController;
    _editorFocus = MobileEditorFocus([_focusNode, _htmlFocusNode]);
    _focusNode.addListener(_onEditorFocus);
    _htmlFocusNode.addListener(_onEditorFocus);
    viewModel.addListener(_syncPanels);
    viewModel.quillController.addListener(_syncPanels);
    viewModel.htmlController.addListener(_htmlChanged);
    _htmlText = viewModel.htmlController.text;
    _syncPanels();
    widget.dismissPanels?.addListener(_collapseAttachments);

    _editorConfig = QuillEditorConfig(
      editorKey: _richEditorKey,
      customLinkPrefixes: const ['fnotes://', 'note://'],
      autoFocus: false,
      onTapOutside: (_, _) => _editorFocus.dismiss(),
      scrollable: true,
      expands: true,
      padding:
          EdgeInsets.zero, // The input area supplies the single writing inset.
      embedBuilders: [_embedBuilder],
      onLaunchUrl: (url) {
        if (_exporting) return;
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
      contextMenuBuilder: (context, state) => MobileSelectionToolbar(
        viewportKey: _editorViewportKey,
        anchors: state.contextMenuAnchors,
        buttonItems: state.contextMenuButtonItems,
        layoutChanges: _panels,
      ),
    );
    viewModel.attachmentJobsNotifier.addListener(_exportChanged);
    widget.exportRequests?.addListener(_exportChanged);
    _syncExportState(rebuild: false);
  }

  @override
  void didUpdateWidget(covariant MobileContentArea oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dismissPanels != widget.dismissPanels) {
      oldWidget.dismissPanels?.removeListener(_collapseAttachments);
      widget.dismissPanels?.addListener(_collapseAttachments);
    }
    if (oldWidget.exportRequests != widget.exportRequests) {
      oldWidget.exportRequests?.removeListener(_exportChanged);
      widget.exportRequests?.addListener(_exportChanged);
      _syncExportState(rebuild: false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    viewModel.attachmentJobsNotifier.removeListener(_exportChanged);
    widget.exportRequests?.removeListener(_exportChanged);
    if (_exporting) _restoreExportReadOnly();
    _focusNode.removeListener(_onEditorFocus);
    _htmlFocusNode.removeListener(_onEditorFocus);
    viewModel.removeListener(_syncPanels);
    viewModel.quillController.removeListener(_syncPanels);
    viewModel.htmlController.removeListener(_htmlChanged);
    _bodyChanges?.cancel();
    widget.dismissPanels?.removeListener(_collapseAttachments);
    _panels.dispose();
    _editorFocus.dispose();
    _unlockFocusNode.dispose();
    _htmlFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    colors = _ContentColors(theme);
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (_, event) {
        if (_canEditBody &&
            event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.tab &&
            !HardwareKeyboard.instance.isControlPressed &&
            !HardwareKeyboard.instance.isAltPressed &&
            !HardwareKeyboard.instance.isMetaPressed) {
          _editorFocus.allowTraversal();
        }
        return KeyEventResult.ignored;
      },
      child: _buildLayout(context),
    );
  }

  Widget _buildLayout(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Mobile presentation owns phone/tablet insets independently.
        final isMobile = constraints.maxWidth < 600;

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
                    return Listener(
                      onPointerDown: (_) {
                        _panels.collapse();
                        _editorFocus.dismiss();
                      },
                      child: Focus(
                        onFocusChange: (focused) {
                          if (focused) _panels.collapse();
                        },
                        child: _buildTopStrip(context, isMobile),
                      ),
                    );
                  },
                ),

                // Floating Toolbar Island (only when not locked)
                ValueListenableBuilder<bool>(
                  valueListenable: viewModel.isLockedNotifier,
                  builder: (context, isLocked, child) {
                    if (isLocked || viewModel.isHtmlMode) {
                      return const SizedBox.shrink();
                    }
                    return _exportDisabled(
                      IgnorePointer(
                        ignoring: viewModel.isLibraryCutover,
                        child: Padding(
                          padding: EdgeInsets.only(
                            left: 16,
                            right: 16,
                            top: 0,
                            bottom: 4,
                          ),
                          child: MobileFormattingBar(
                            panels: _panels,
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
                            collapsedChild: _buildFormattingControls(
                              scrollable: true,
                            ),
                          ),
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
                      onPointerUp: (_) => _collapseAttachments(),
                      child: AttachmentMentions(
                        enabled: !_exporting,
                        model: viewModel,
                        richKey: _richEditorKey,
                        htmlKey: _htmlEditorKey,
                        htmlFocus: _htmlFocusNode,
                        child: ExcludeFocus(
                          excluding: _exporting && !viewModel.isLocked,
                          child: _buildInputArea(context, isMobile: isMobile),
                        ),
                      ),
                    ),
                  ),
                ),

                Visibility(
                  key: const ValueKey('mobile-attachment-shelf'),
                  visible: !_keyboardVisible,
                  maintainState: true,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AttachmentJobPanel(
                        viewModel: viewModel,
                        auxiliaryOnly: true,
                        excludedOperations: const {
                          AttachmentJobOperation.export,
                        },
                      ),
                      MobileAttachmentProgress(model: viewModel),
                      ValueListenableBuilder(
                        valueListenable: viewModel.pendingDeletionsNotifier,
                        builder: (context, pending, _) => Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (final reference in pending)
                              Row(
                                children: [
                                  const Expanded(
                                    child: Text(
                                      'Permanent deletion is incomplete.',
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: _exporting
                                        ? null
                                        : () => viewModel.deleteReviewedNote(
                                            reference,
                                          ),
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
                              return _exportDisabled(
                                MobilePanelRegion(
                                  panels: _panels,
                                  panel: MobileEditorPanel.attachments,
                                  child: AttachmentStrip(
                                    viewModel: viewModel,
                                    panels: _panels,
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTopStrip(BuildContext context, bool isMobile) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 56,
          child: Row(
            children: [
              if (widget.onBack != null)
                IconButton(
                  tooltip: 'Back to notes',
                  onPressed: widget.onBack,
                  icon: const Icon(Icons.arrow_back),
                ),
              Expanded(child: _buildHeaderTitle()),
              IconButton(
                tooltip: 'Note actions',
                icon: const Icon(Icons.more_vert),
                onPressed: () => _showSettingsMenu(context),
              ),
            ],
          ),
        ),
        if (!viewModel.isLocked)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: OverflowBar(
              alignment: MainAxisAlignment.spaceBetween,
              overflowAlignment: OverflowBarAlignment.end,
              spacing: 8,
              children: [
                _buildModeToggleButton(),
                _buildSecondaryActions(context),
              ],
            ),
          ),
      ],
    ),
  );

  Widget _buildHeaderTitle() => Row(
    children: [
      Expanded(
        child: viewModel.isLocked
            ? Text(
                viewModel.titleController.text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: _touch ? 16 : 11.232,
                  fontWeight: FontWeight.w600,
                ),
              )
            : TextField(
                controller: viewModel.titleController,
                readOnly:
                    _exporting ||
                    viewModel.isLibraryCutover ||
                    viewModel.isImportCutover ||
                    viewModel.isDeletingCurrent ||
                    !viewModel.draftSession.canWrite,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: _touch ? 16 : 11.232,
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

  /// Attachment, lock and Save actions share one right-aligned group.
  Widget _buildSecondaryActions(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!viewModel.isLocked)
          _buildSubtleIconButton(
            Icons.attach_file_rounded,
            'Attach file',
            onPressed: _exporting ? null : viewModel.pickAttachment,
          ),
        if (viewModel.isLocked || viewModel.isPasswordSet)
          _buildSubtleIconButton(
            viewModel.isLocked ? Icons.lock_rounded : Icons.lock_open_rounded,
            viewModel.isLocked ? 'Unlock' : 'Lock File',
            onPressed: _exporting && !viewModel.isLocked
                ? null
                : () => _handleLockAction(context),
            isActive: true,
          ),
        if (!viewModel.isLocked) _buildSaveButton(),
      ],
    );
  }

  /// Subtle icon button for secondary actions
  Widget _buildSubtleIconButton(
    IconData icon,
    String tooltip, {
    required VoidCallback? onPressed,
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
        color: onPressed == null
            ? colors.subtleGray.withValues(alpha: .4)
            : color ?? (isActive ? colors.accent : colors.subtleGray),
      ),
    );
  }

  Widget _buildSaveButton() => ValueListenableBuilder<SaveUiState>(
    valueListenable: viewModel.saveStateNotifier,
    builder: (context, state, _) => IconButton(
      tooltip: state.phase == SavePhase.saving
          ? 'Saving…'
          : state.canRetry
          ? 'Retry Save'
          : 'Save note',
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      color: colors.accent,
      disabledColor: colors.subtleGray.withValues(alpha: .45),
      onPressed:
          _exporting ||
              viewModel.isBusy ||
              !state.hasChanges ||
              state.phase == SavePhase.saving ||
              !viewModel.draftSession.canWrite
          ? null
          : () => viewModel.saveNote(),
      icon: state.phase == SavePhase.saving
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.save_outlined, size: 20),
    ),
  );

  /// Floating toolbar "island" with grouped formatting tools
  Widget _buildFormattingControls({
    bool expanded = false,
    bool scrollable = false,
  }) => AbsorbPointer(
    absorbing:
        viewModel.isLibraryCutover ||
        viewModel.isImportCutover ||
        !viewModel.draftSession.canWrite,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: expanded
          ? Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final entry in _toolbarPrimaryControls().asMap().entries)
                  if (![0, 1, 2, 5, 6].contains(entry.key)) entry.value,
                _buildVerticalDivider(),
                ..._toolbarSecondaryControls(),
              ],
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
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
                if (scrollable) ...[
                  for (final entry in _toolbarPrimaryControls().asMap().entries)
                    if (![0, 1, 2, 5, 6].contains(entry.key)) entry.value,
                  _buildVerticalDivider(),
                  ..._toolbarSecondaryControls(),
                ],
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
        style: TextStyle(
          color: colors.textSecondary,
          fontSize: _touch ? 14 : 9.504,
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

  /// Compact visible rail inside full-height, independently focusable targets.
  Widget _buildModeToggleButton() => ValueListenableBuilder<bool>(
    valueListenable: viewModel.isConvertingNotifier,
    builder: (context, converting, _) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 48,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned.fill(
                top: 6,
                bottom: 6,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.toolbarIsland,
                    border: Border.all(
                      color: colors.divider.withValues(alpha: .25),
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final mode in EditorMode.values)
                    Semantics(
                      selected: viewModel.editorMode == mode,
                      child: TextButton(
                        onPressed:
                            _exporting ||
                                converting ||
                                viewModel.isImportCutover ||
                                !viewModel.draftSession.canWrite
                            ? null
                            : () async {
                                final generation =
                                    viewModel.draftSession.generation;
                                final result = await viewModel.setEditorMode(
                                  mode,
                                );
                                if (mounted &&
                                    result.isSuccess &&
                                    !_exporting &&
                                    mode == EditorMode.html &&
                                    viewModel.isHtmlMode &&
                                    viewModel.draftSession.generation ==
                                        generation) {
                                  await viewModel.formatHtml(
                                    expandTextBlocks: true,
                                  );
                                }
                              },
                        style: TextButton.styleFrom(
                          foregroundColor: viewModel.editorMode == mode
                              ? colors.accent
                              : colors.textSecondary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          minimumSize: const Size(76, 48),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 9,
                          ),
                          textStyle: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            minWidth: 68,
                            minHeight: 30,
                          ),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: viewModel.editorMode == mode
                                  ? colors.accent.withValues(alpha: .14)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(9),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                              ),
                              child: Center(
                                widthFactor: 1,
                                child: Text(
                                  mode == EditorMode.html
                                      ? 'HTML'
                                      : 'Rich text',
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
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
        _exporting ||
        viewModel.isLocked ||
        viewModel.isHtmlMode ||
        viewModel.isImportCutover ||
        !viewModel.draftSession.canWrite) {
      return;
    }
    // Formatting keeps the retained selection; only an input gesture may
    // start a new keyboard session after focus or the keyboard was dismissed.
  }

  QuillToolbarColorButtonOptions _getColorButtonOptions() {
    return QuillToolbarColorButtonOptions(iconTheme: _getIconTheme());
  }

  QuillIconTheme _getIconTheme() {
    return QuillIconTheme(
      iconButtonUnselectedData: IconButtonData(
        color: colors.textSecondary,
        iconSize: 22,
        style: const ButtonStyle(
          minimumSize: WidgetStatePropertyAll(Size(48, 48)),
          maximumSize: WidgetStatePropertyAll(Size(48, 48)),
          padding: WidgetStatePropertyAll(EdgeInsets.zero),
          shape: WidgetStatePropertyAll(CircleBorder()),
        ),
      ),
      iconButtonSelectedData: IconButtonData(
        color: colors.accent,
        iconSize: 22,
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
          maximumSize: const WidgetStatePropertyAll(Size(48, 48)),
          padding: const WidgetStatePropertyAll(EdgeInsets.zero),
          shape: const WidgetStatePropertyAll(CircleBorder()),
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
          final unlocked = await viewModel.unlockNote(
            password,
            readOnlyExport: _exporting,
          );
          if (unlocked && mounted) {
            if (_exporting) {
              _readOnlyBeforeExport = !viewModel.draftSession.canWrite;
              viewModel.quillController.readOnly = true;
            }
            _editorFocus.dismiss();
          }
          return unlocked;
        },
      );
    }

    // One modest inset, shared by Rich text and HTML.
    return Padding(
      key: _editorViewportKey,
      padding: EdgeInsets.only(left: 16, right: 16, top: 4, bottom: 8),
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
                          _exporting ||
                              converting ||
                              !viewModel.draftSession.canWrite ||
                              viewModel.isLibraryCutover ||
                              viewModel.isImportCutover ||
                              viewModel.isDeletingCurrent
                          ? null
                          : () async {
                              await viewModel.formatHtml(
                                expandTextBlocks: true,
                              );
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
                      child: MobileEditorInputRegion(
                        focus: _editorFocus,
                        node: _htmlFocusNode,
                        enabled: _canEditBody,
                        child: CodeField(
                          key: _htmlEditorKey,
                          controller: viewModel.htmlController,
                          focusNode: _htmlFocusNode,
                          wrap: false,
                          horizontalScroll: true,
                          keyboardType: TextInputType.multiline,
                          smartQuotesType: SmartQuotesType.disabled,
                          readOnly:
                              _exporting ||
                              viewModel.isLibraryCutover ||
                              viewModel.isImportCutover ||
                              viewModel.isDeletingCurrent ||
                              !viewModel.draftSession.canWrite,
                          textStyle: TextStyle(
                            fontFamily: 'monospace',
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
                            width: 32,
                            margin: 8,
                            background: colors.background,
                            textStyle: TextStyle(
                              color: colors.subtleGray,
                              fontSize: 12,
                              height: 1.5,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            )
          : RepaintBoundary(
              child: MobileEditorInputRegion(
                focus: _editorFocus,
                node: _focusNode,
                enabled: _canEditBody,
                child: QuillEditor.basic(
                  controller: viewModel.quillController,
                  config: _editorConfig,
                  focusNode: _focusNode,
                  scrollController: _scrollController,
                ),
              ),
            ),
    );
  }

  void _showSettingsMenu(BuildContext context) {
    if (!viewModel.ensureExtendedNoteOperations()) return;
    showAppDialog(
      context: context,
      builder: (context) => ListenableBuilder(
        listenable: Listenable.merge([
          viewModel.attachmentJobsNotifier,
          if (widget.exportRequests != null) widget.exportRequests!,
        ]),
        builder: (context, _) => AlertDialog(
          scrollable: true,
          backgroundColor: colors.toolbarIsland,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
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
              ListTile(
                leading: const Icon(Icons.pending_actions),
                title: const Text('Background tasks'),
                onTap: () {
                  Navigator.pop(context);
                  if (widget.onJobNotifications != null) {
                    widget.onJobNotifications!();
                  } else {
                    showAppDialog<void>(
                      context: this.context,
                      builder: (_) => BackgroundTasksDialog(
                        model: viewModel,
                        selectExportJobs: false,
                      ),
                    );
                  }
                },
              ),
              if (widget.onExport != null)
                _buildSettingsTile(
                  icon: Icons.ios_share_rounded,
                  title: 'Export',
                  onTap: () {
                    Navigator.pop(context);
                    unawaited(widget.onExport!());
                  },
                ),
              // Change/Set Password
              _buildSettingsTile(
                icon: viewModel.isPasswordSet
                    ? Icons.lock_reset_rounded
                    : Icons.lock_outline_rounded,
                title: viewModel.isPasswordSet
                    ? 'Change Password'
                    : 'Set Password',
                enabled: !_exporting,
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
                  enabled: !_exporting,
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
                enabled: !_exporting,
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
      ),
    );
  }

  Widget _buildSettingsTile({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    Color? textColor,
    Color? iconColor,
    bool enabled = true,
  }) {
    return ListTile(
      leading: Icon(
        icon,
        color: enabled
            ? iconColor ?? colors.textPrimary
            : colors.subtleGray.withValues(alpha: .4),
      ),
      title: Text(
        title,
        style: TextStyle(
          color: enabled
              ? textColor ?? colors.textPrimary
              : colors.subtleGray.withValues(alpha: .4),
        ),
      ),
      enabled: enabled,
      onTap: enabled ? onTap : null,
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
} // End of MobileContentArea

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
