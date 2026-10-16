import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import '../models/attachment_mention.dart';
import '../models/note_model.dart';
import '../viewmodels/content_viewmodel.dart';
import 'attachment_presentation.dart';

/// Owns only suggestion state. Editors, workers and payload cache remain owned
/// by their existing components. The overlay never requests keyboard focus.
class AttachmentMentions extends StatefulWidget {
  const AttachmentMentions({
    super.key,
    required this.model,
    required this.richKey,
    required this.htmlKey,
    required this.htmlFocus,
    required this.child,
  });
  final ContentViewModel model;
  final GlobalKey<EditorState> richKey;
  final GlobalKey htmlKey;
  final FocusNode htmlFocus;
  final Widget child;
  @override
  State<AttachmentMentions> createState() => _AttachmentMentionsState();
}

class _AttachmentMentionsState extends State<AttachmentMentions> {
  OverlayEntry? _overlay;
  AttachmentMentionQuery? _query;
  List<AttachmentModel> _matches = [];
  final _rows = ScrollController();
  int _selected = 0;
  Object? _owner;
  Object? _queryOwner;
  int? _queryGeneration;
  int? _dismissedStart;
  bool _scheduled = false;
  bool _awaitingInput = false;
  ValueNotifier<TextRange>? _composition;
  ContentViewModel get model => widget.model;
  bool get _focused =>
      model.isHtmlMode ? widget.htmlFocus.hasFocus : model.focusNode.hasFocus;
  bool get _composing => model.isHtmlMode
      ? !model.htmlController.value.composing.isCollapsed
      : !(_composition?.value.isCollapsed ?? true);

  @override
  void initState() {
    super.initState();
    model.addListener(_refresh);
    model.quillController.addListener(_refresh);
    model.htmlController.addListener(_refresh);
    model.attachmentsNotifier.addListener(_refresh);
    model.scrollController.addListener(_position);
    model.focusNode.addListener(_focusChanged);
    widget.htmlFocus.addListener(_focusChanged);
    FocusManager.instance.addEarlyKeyEventHandler(_key);
    _refresh();
  }

  void _focusChanged() {
    if (!_focused) {
      _dismiss();
    } else {
      _refresh();
    }
  }

  void _dismiss() {
    _dismissedStart = _query?.start ?? _dismissedStart;
    _remove();
  }

  void _remove() {
    _overlay?.remove();
    _overlay?.dispose();
    _overlay = null;
    _query = null;
  }

  void _refresh() {
    if (!mounted) return;
    final owner = (
      model.draftSession.generation,
      model.currentContentPath,
      model.draftSession.credentialGeneration,
      model.isLocked,
      model.editorMode,
    );
    if (_owner != owner) {
      if (_owner != null) {
        _dismiss();
        _awaitingInput = true;
      }
      _owner = owner;
    }
    // Lock/navigation/focus revoke the popup synchronously, without exit retention.
    if (!_focused ||
        model.isLocked ||
        model.isLibraryCutover ||
        model.isImportCutover) {
      _dismiss();
      return;
    }
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted) return;
      final state = widget.richKey.currentState;
      final composing = state is QuillRawEditorState
          ? state.composingRange
          : null;
      if (_composition != composing) {
        _composition?.removeListener(_refresh);
        _composition = composing;
        _composition?.addListener(_refresh);
      }
      final query = _focused && !_composing && !_awaitingInput
          ? model.attachmentMentionQuery()
          : null;
      if (query == null) {
        if (!_composing) _dismissedStart = null;
        _remove();
        return;
      }
      if (query.start == _dismissedStart) {
        _remove();
        return;
      }
      if (_query?.text != query.text || _query?.start != query.start) {
        _selected = 0;
      }
      _query = query;
      _queryOwner = _owner;
      _queryGeneration = model.draftSession.generation;
      _matches = query.match(model.attachments);
      _selected = _selected.clamp(0, math.max(0, _matches.length - 1));
      if (_overlay == null) {
        _overlay = OverlayEntry(builder: _buildPopup);
        Overlay.of(context).insert(_overlay!);
      } else {
        _position();
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _position() => _overlay?.markNeedsBuild();

  KeyEventResult _key(KeyEvent event) {
    if (_focused && event is KeyDownEvent && _awaitingInput) {
      _awaitingInput = false;
      _refresh();
    }
    if (_overlay == null ||
        !_focused ||
        _composing ||
        event is KeyUpEvent ||
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isAltPressed ||
        HardwareKeyboard.instance.isMetaPressed) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      _dismiss();
      return KeyEventResult.handled;
    }
    if (_matches.isEmpty) return KeyEventResult.ignored;
    if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowUp) {
      _selected =
          (_selected + (key == LogicalKeyboardKey.arrowDown ? 1 : -1)) %
          _matches.length;
      if (_rows.hasClients) {
        _rows.jumpTo(
          (_selected * 48.0).clamp(0, _rows.position.maxScrollExtent),
        );
      }
      _position();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.tab) {
      _insert(_matches[_selected]);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _insert(AttachmentModel attachment) {
    final query = _query;
    if (query == null || !_focused || _composing || _queryOwner != _owner) {
      return;
    }
    final result = model.insertAttachmentMention(
      attachmentId: attachment.id,
      query: query,
      owner: _queryGeneration!,
      mode: model.editorMode,
    );
    _dismiss();
    if (!result.isSuccess && mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(result.message ?? 'Attachment unavailable.')),
      );
    }
  }

  Rect? _caret() {
    if (!model.isHtmlMode) {
      final render = widget.richKey.currentState?.renderEditor;
      if (render == null || !render.attached) return null;
      final rect = render.getLocalRectForCaret(
        model.quillController.selection.extent,
      );
      return rect.shift(render.localToGlobal(Offset.zero));
    }
    RenderEditable? render;
    void visit(Element element) {
      if (element is StatefulElement && element.state is EditableTextState) {
        render = (element.state as EditableTextState).renderEditable;
      } else {
        element.visitChildren(visit);
      }
    }

    final html = widget.htmlKey.currentContext;
    if (html is Element) visit(html);
    if (render == null || !render!.attached) return null;
    return render!
        .getLocalRectForCaret(model.htmlController.selection.extent)
        .shift(render!.localToGlobal(Offset.zero));
  }

  Widget _buildPopup(BuildContext context) {
    if (_query == null || !_focused || model.isLocked) {
      return const SizedBox.shrink();
    }
    final rect = _caret();
    if (rect == null) return const SizedBox.shrink();
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final anchor = overlay.globalToLocal(rect.bottomLeft);
    final width = math.min(320.0, overlay.size.width - 16);
    final height = math.min(6, math.max(1, _matches.length)) * 48.0 + 29;
    final below = anchor.dy + 4;
    final top = below + height <= overlay.size.height - 8
        ? below
        : math.max(8.0, anchor.dy - rect.height - height - 4);
    final theme = Theme.of(context);
    return Positioned(
      left: anchor.dx.clamp(8.0, math.max(8.0, overlay.size.width - width - 8)),
      top: top,
      width: width,
      child: TextFieldTapRegion(
        child: ExcludeFocus(
          child: Material(
            key: const ValueKey('attachment-mention-popup'),
            elevation: 8,
            color: theme.colorScheme.surfaceContainerHigh,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: theme.dividerColor),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: height - 29,
                  child: _matches.isEmpty
                      ? const Center(
                          child: Text(
                            'No matching attachments',
                            style: TextStyle(fontSize: 12),
                          ),
                        )
                      : ListView.builder(
                          controller: _rows,
                          itemExtent: 48,
                          padding: EdgeInsets.zero,
                          itemCount: _matches.length,
                          itemBuilder: (_, index) {
                            final a = _matches[index];
                            final duplicate =
                                model.attachments
                                    .where((e) => e.fileName == a.fileName)
                                    .length >
                                1;
                            final id = a.mentionIdentity;
                            final ext = a.fileName.contains('.')
                                ? a.fileName.split('.').last.toUpperCase()
                                : 'FILE';
                            return Semantics(
                              selected: _selected == index,
                              button: true,
                              child: InkWell(
                                canRequestFocus: false,
                                onHover: (hover) {
                                  if (hover) {
                                    _selected = index;
                                    _position();
                                  }
                                },
                                onTap: () => _insert(a),
                                child: ColoredBox(
                                  color: _selected == index
                                      ? theme.colorScheme.primary.withValues(
                                          alpha: .14,
                                        )
                                      : Colors.transparent,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 5,
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.attach_file,
                                          size: 18,
                                          color: theme.colorScheme.primary,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                a.fileName,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                ),
                                              ),
                                              Text(
                                                '$ext · ${formatAttachmentBytes(a.size)}${duplicate ? ' · ${id.substring(math.max(0, id.length - 5))}' : ''}',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  color: theme
                                                      .colorScheme
                                                      .onSurfaceVariant,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
                const SizedBox(
                  height: 29,
                  child: Center(
                    child: Text(
                      '↑ ↓ choose   Enter/Tab insert   Esc close',
                      style: TextStyle(fontSize: 10),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    FocusManager.instance.removeEarlyKeyEventHandler(_key);
    model.removeListener(_refresh);
    model.quillController.removeListener(_refresh);
    model.htmlController.removeListener(_refresh);
    model.attachmentsNotifier.removeListener(_refresh);
    model.scrollController.removeListener(_position);
    model.focusNode.removeListener(_focusChanged);
    widget.htmlFocus.removeListener(_focusChanged);
    _composition?.removeListener(_refresh);
    _remove();
    _rows.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      NotificationListener<ScrollNotification>(
        onNotification: (_) {
          _position();
          return false;
        },
        child: widget.child,
      );
}
