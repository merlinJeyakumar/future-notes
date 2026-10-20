import '../../../core/theme/app_tooltip.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_dialog.dart';
import 'dart:io';
import 'dart:math' as math;
import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import '../../../core/platform/directory_attachment_export.dart';
import '../../../core/operations/operation_result.dart';
import '../models/attachment_job.dart';
import '../models/note_model.dart';
import '../viewmodels/content_viewmodel.dart';
import 'attachment_viewer.dart';
import 'attachment_preview.dart';
import 'attachment_presentation.dart';

class AttachmentStrip extends StatefulWidget {
  const AttachmentStrip({
    super.key,
    required this.viewModel,
    this.playerFactory,
    this.collapseRequests,
  });
  final ContentViewModel viewModel;
  final AttachmentPlayerFactory? playerFactory;
  final Listenable? collapseRequests;
  @override
  State<AttachmentStrip> createState() => _AttachmentStripState();
}

class _AttachmentStripState extends State<AttachmentStrip> {
  bool expanded = false;
  late int _owner;
  late bool _locked;
  String? _path;
  ContentViewModel get model => widget.viewModel;

  void _collapse() {
    if (expanded) setState(() => expanded = false);
  }

  void _rememberOwner() {
    _owner = model.draftSession.generation;
    _path = model.currentContentPath;
    _locked = model.isLocked;
  }

  void _syncOwner() {
    final reset =
        _owner != model.draftSession.generation ||
        _path != model.currentContentPath ||
        (_locked && !model.isLocked);
    _rememberOwner();
    if (reset && expanded && mounted) setState(() => expanded = false);
  }

  @override
  void initState() {
    super.initState();
    _rememberOwner();
    model.addListener(_syncOwner);
    widget.collapseRequests?.addListener(_collapse);
  }

  @override
  void didUpdateWidget(covariant AttachmentStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.collapseRequests != widget.collapseRequests) {
      oldWidget.collapseRequests?.removeListener(_collapse);
      widget.collapseRequests?.addListener(_collapse);
    }
    if (oldWidget.viewModel != model) {
      oldWidget.viewModel.removeListener(_syncOwner);
      expanded = false;
      _rememberOwner();
      model.addListener(_syncOwner);
    }
  }

  @override
  void dispose() {
    model.removeListener(_syncOwner);
    widget.collapseRequests?.removeListener(_collapse);
    super.dispose();
  }

  Future<void> _action(
    AttachmentAction action,
    AttachmentModel attachment,
    FocusNode focus,
  ) async {
    if (action == AttachmentAction.open || action == AttachmentAction.system) {
      await openAttachmentPreview(
        context,
        model,
        attachment,
        system: action == AttachmentAction.system,
        restoreFocus: focus,
        playerFactory: widget.playerFactory,
      );
    } else if (action == AttachmentAction.save) {
      await model.exportAttachment(attachment);
    } else {
      await model.removeAttachment(attachment.id);
    }
  }

  Future<void> _showRemaining(int startIndex) async {
    final owner = model.draftSession.generation;
    final credentials = model.draftSession.credentialGeneration;
    final path = model.currentContentPath;
    await showAppDialog<void>(
      context: context,
      builder: (_) => _AttachmentGallery(
        model: model,
        owner: owner,
        credentials: credentials,
        contentPath: path,
        startIndex: startIndex,
        onAction: _action,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedSize(
    key: ValueKey((model.draftSession.generation, model.currentContentPath)),
    duration: AppMotion.duration(context, AppMotion.panelIn),
    reverseDuration: AppMotion.duration(context, AppMotion.panelOut),
    curve: expanded ? AppMotion.enterCurve : AppMotion.exitCurve,
    alignment: Alignment.topLeft,
    child: ValueListenableBuilder<bool>(
      valueListenable: model.isLockedNotifier,
      builder: (_, locked, _) => locked
          ? const SizedBox.shrink()
          : ListenableBuilder(
              listenable: Listenable.merge([
                model.attachmentsNotifier,
                model.attachmentJobsNotifier,
                model.attachmentCacheNotifier,
              ]),
              builder: (context, _) {
                final entries = _entries(model);
                if (entries.isEmpty) return const SizedBox.shrink();
                final jobs = model.attachmentJobsNotifier.value
                    .where(
                      (j) =>
                          j.progress.value.owner ==
                          model.draftSession.generation,
                    )
                    .toList();
                final attachments = model.attachmentsNotifier.value;
                final scale = MediaQuery.textScalerOf(context).scale(1);
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          TextButton.icon(
                            onPressed: () => _showRemaining(0),
                            icon: const Icon(Icons.grid_view, size: 16),
                            label: const Text('Show all'),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: ListenableBuilder(
                              listenable: Listenable.merge(
                                jobs.map((j) => j.phase),
                              ),
                              builder: (context, _) {
                                final active = jobs
                                    .where((j) => j.progress.value.active)
                                    .length;
                                final label =
                                    'Attachments (${attachments.length})${active == 0 ? '' : ' · $active background operation${active == 1 ? '' : 's'}'}';
                                return AppTooltip(
                                  message: label,
                                  child: TextButton.icon(
                                    onPressed: () =>
                                        setState(() => expanded = !expanded),
                                    icon: AppDisclosure(expanded: expanded),
                                    label: Text(
                                      label,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                      ConstrainedBox(
                        key: const ValueKey('attachment-dock-items'),
                        constraints: BoxConstraints(
                          maxHeight: expanded
                              ? math.max(
                                  _tileHeight(true) * scale,
                                  math.min(
                                    280,
                                    MediaQuery.sizeOf(context).height * .35,
                                  ),
                                )
                              : _tileHeight(false) * scale,
                        ),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final maxSlots = ((constraints.maxWidth + 8) / 64)
                                .floor()
                                .clamp(2, 5);
                            final maximumVisible = math.min(4, maxSlots);
                            final visibleCount = expanded
                                ? entries.length
                                : entries.length > maximumVisible
                                ? math.min(4, maxSlots - 1)
                                : entries.length;
                            final hidden = entries.length - visibleCount;
                            final slots = visibleCount + (hidden > 0 ? 1 : 0);
                            final width = expanded
                                ? math.min(96.0, constraints.maxWidth)
                                : math.min(
                                    56.0,
                                    (constraints.maxWidth - (slots - 1) * 8) /
                                        slots,
                                  );
                            return SingleChildScrollView(
                              primary: false,
                              child: Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  for (
                                    var index = 0;
                                    index < slots;
                                    index++
                                  ) ...[
                                    SizedBox(
                                      width: width,
                                      height: _tileHeight(expanded) * scale,
                                      child: index == visibleCount
                                          ? AppTooltip(
                                              message:
                                                  'Show $hidden more attachments',
                                              child: OutlinedButton(
                                                style: OutlinedButton.styleFrom(
                                                  padding: EdgeInsets.zero,
                                                  minimumSize: Size.zero,
                                                ),
                                                key: const ValueKey(
                                                  'attachment-overflow',
                                                ),
                                                onPressed: () => _showRemaining(
                                                  visibleCount,
                                                ),
                                                child: FittedBox(
                                                  fit: BoxFit.scaleDown,
                                                  child: Text('+$hidden'),
                                                ),
                                              ),
                                            )
                                          : _AttachmentTile(
                                              key: ValueKey(
                                                '${model.draftSession.generation}/${entries[index].id}',
                                              ),
                                              model: model,
                                              attachment:
                                                  entries[index].attachment,
                                              job: entries[index].job,
                                              expanded: expanded,
                                              onAction: _action,
                                            ),
                                    ),
                                  ],
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    ),
  );
}

class _AttachmentTile extends StatefulWidget {
  const _AttachmentTile({
    super.key,
    required this.model,
    required this.attachment,
    required this.job,
    required this.onAction,
    required this.expanded,
    this.selectionMode = false,
    this.selected = false,
    this.onSelect,
    this.disambiguate = false,
  });
  final ContentViewModel model;
  final bool expanded;
  final bool selectionMode, selected, disambiguate;
  final VoidCallback? onSelect;
  final AttachmentModel? attachment;
  final AttachmentJobState? job;
  final Future<void> Function(AttachmentAction, AttachmentModel, FocusNode)
  onAction;
  @override
  State<_AttachmentTile> createState() => _AttachmentTileState();
}

class _AttachmentTileState extends State<_AttachmentTile> {
  final _focus = FocusNode();
  String? _dateKey;
  Future<DateTime?>? _storedDate;

  @override
  void initState() {
    super.initState();
    _bindDate();
  }

  @override
  void didUpdateWidget(covariant _AttachmentTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    _bindDate();
  }

  void _bindDate() {
    final model = widget.model;
    final key =
        '${identityHashCode(model)}/${model.draftSession.generation}/${model.draftSession.credentialGeneration}/${model.currentContentPath}/${widget.attachment?.id}';
    if (_dateKey == key) return;
    _dateKey = key;
    _storedDate = widget.attachment == null
        ? null
        : model.attachmentStoredDate(widget.attachment!.id);
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.job == null
      ? _card(context, null)
      : ValueListenableBuilder<AttachmentJobSnapshot>(
          valueListenable: widget.job!.progress,
          builder: (context, state, _) => _card(context, state),
        );

  Widget _card(BuildContext context, AttachmentJobSnapshot? state) {
    final attachment = widget.attachment;
    final name = attachment?.fileName ?? state!.fileName;
    final kind = attachmentVisualKind(name);
    final cached = attachment == null
        ? null
        : widget.model.cachedAttachment(attachment.id);
    final active = state?.active ?? false;
    final waiting =
        state?.phase == AttachmentJobPhase.cancelling ||
        (state?.phase == AttachmentJobPhase.finalizing && state?.total == null);
    final total = state?.total;
    final fraction = !waiting && total != null && total > 0
        ? (state!.bytes / total).clamp(0.0, 1.0)
        : null;
    final icon = switch (kind) {
      AttachmentVisualKind.image => Icons.image_outlined,
      AttachmentVisualKind.video => Icons.play_circle_outline,
      AttachmentVisualKind.audio => Icons.audio_file_outlined,
      AttachmentVisualKind.document => Icons.description_outlined,
      AttachmentVisualKind.file => Icons.insert_drive_file_outlined,
    };
    void action(AttachmentAction action) {
      if (attachment != null) widget.onAction(action, attachment, _focus);
    }

    final expanded = widget.expanded;
    final failed = state?.phase == AttachmentJobPhase.failed;
    final showMore = !active && (attachment != null || (!expanded && failed));
    final canOpen = attachment != null && !active;
    final nameStyle = Theme.of(context).textTheme.labelMedium;
    final progressLabel = state == null
        ? ''
        : '${state.detail ?? attachmentPhaseLabel(state.phase)}${total == null || waiting ? '' : ' · ${formatAttachmentBytes(state.bytes)} / ${formatAttachmentBytes(total)}${fraction == null ? '' : ' · ${(fraction * 100).floor()}%'}'}';
    final more = AttachmentMoreButton(
      compact: true,
      fileName: name,
      enabled: attachment != null && !active,
      canRemove: attachment != null && !widget.model.hasAttachmentJobs,
      onSelected: action,
      onRetry: !expanded && attachment == null && failed
          ? () => widget.model.retryAttachmentJob(state!.id)
          : null,
      onRemovePending: !expanded && attachment == null && failed
          ? () => widget.model.removePendingAttachmentJob(state!.id)
          : null,
    );
    return SizedBox(
      width: expanded ? 96 : 56,
      child: Card(
        color: widget.selected
            ? Theme.of(context).colorScheme.primaryContainer
            : null,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: AppTooltip(
          message: !expanded && (active || failed)
              ? '$name\n$progressLabel${state?.error == null ? '' : '\n${state!.error}'}'
              : name,
          waitDuration: const Duration(milliseconds: 350),
          showDuration: const Duration(seconds: 6),
          child: InkWell(
            key: ValueKey('attachment-open-${attachment?.id ?? state!.id}'),
            focusNode: _focus,
            mouseCursor: canOpen
                ? SystemMouseCursors.click
                : SystemMouseCursors.basic,
            onTap: canOpen || widget.onSelect != null
                ? () {
                    final keys = HardwareKeyboard.instance;
                    if (widget.selectionMode ||
                        (widget.onSelect != null &&
                            (keys.isControlPressed ||
                                keys.isMetaPressed ||
                                keys.isShiftPressed))) {
                      widget.onSelect?.call();
                    } else if (canOpen) {
                      action(AttachmentAction.open);
                    }
                  }
                : null,
            onLongPress: widget.onSelect,
            child: !expanded
                ? Semantics(
                    label: name,
                    value: active || failed ? progressLabel : null,
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Stack(
                        children: [
                          Positioned.fill(
                            bottom: active ? 4 : 0,
                            child: Row(
                              children: [
                                Expanded(
                                  child: active
                                      ? const SizedBox.shrink()
                                      : failed
                                      ? const Icon(
                                          Icons.error_outline,
                                          size: 20,
                                        )
                                      : cached != null &&
                                            kind == AttachmentVisualKind.image
                                      ? TickerMode(
                                          enabled: false,
                                          child: Image.file(
                                            File(cached.path),
                                            fit: BoxFit.cover,
                                            cacheWidth: 320,
                                            cacheHeight: 160,
                                            errorBuilder: (_, _, _) =>
                                                Icon(icon, size: 20),
                                          ),
                                        )
                                      : Icon(icon, size: 20),
                                ),
                                if (active && (state?.cancellable ?? false))
                                  _jobButton(
                                    'Cancel attachment',
                                    Icons.close,
                                    () => widget.model.cancelAttachmentJob(
                                      state!.id,
                                    ),
                                  )
                                else if (showMore)
                                  SizedBox(width: 20, height: 28, child: more),
                              ],
                            ),
                          ),
                          if (active)
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              child: LinearProgressIndicator(
                                value: fraction,
                                minHeight: 2,
                              ),
                            ),
                        ],
                      ),
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.all(4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          height: expanded ? 32 : 24,
                          width: double.infinity,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              if (!active)
                                cached != null &&
                                        kind == AttachmentVisualKind.image
                                    ? TickerMode(
                                        enabled: false,
                                        child: Image.file(
                                          File(cached.path),
                                          fit: BoxFit.cover,
                                          cacheWidth: 320,
                                          cacheHeight: 160,
                                          errorBuilder: (_, _, _) => Icon(
                                            icon,
                                            size: expanded ? 24.0 : 18.0,
                                          ),
                                        ),
                                      )
                                    : Icon(icon, size: expanded ? 24.0 : 18.0),
                              if (state?.cancellable ?? false)
                                Positioned(
                                  left: 0,
                                  top: 0,
                                  child: _jobButton(
                                    'Cancel attachment',
                                    Icons.close,
                                    () => widget.model.cancelAttachmentJob(
                                      state!.id,
                                    ),
                                  ),
                                ),
                              if (attachment == null && failed)
                                Positioned(
                                  left: 0,
                                  top: 0,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      _jobButton(
                                        'Retry',
                                        Icons.refresh,
                                        () => widget.model.retryAttachmentJob(
                                          state!.id,
                                        ),
                                      ),
                                      _jobButton(
                                        'Remove pending',
                                        Icons.close,
                                        () => widget.model
                                            .removePendingAttachmentJob(
                                              state!.id,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                              if (widget.selectionMode &&
                                  widget.onSelect != null)
                                Positioned(
                                  right: 0,
                                  top: 0,
                                  child: SizedBox(
                                    width: 28,
                                    height: 28,
                                    child: Checkbox(
                                      key: ValueKey(
                                        'attachment-select-${attachment!.id}',
                                      ),
                                      value: widget.selected,
                                      onChanged: (_) => widget.onSelect!(),
                                      semanticLabel: 'Select $name',
                                    ),
                                  ),
                                ),
                              if (showMore && !widget.selectionMode)
                                Positioned(
                                  right: 0,
                                  top: 0,
                                  child: SizedBox(
                                    width: 28,
                                    height: 28,
                                    child: more,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Text(
                          name,
                          maxLines: 2,
                          softWrap: true,
                          overflow: TextOverflow.ellipsis,
                          style: nameStyle?.copyWith(
                            fontSize: (nameStyle.fontSize ?? 12) * .88,
                            height: 1.15,
                          ),
                        ),
                        if (!active && !failed) ...[
                          if (widget.disambiguate && attachment != null)
                            _caption(
                              context,
                              'ID ${attachment.id.substring(0, math.min(8, attachment.id.length))}',
                            ),
                          _caption(
                            context,
                            '${kind.name} · ${formatAttachmentBytes(attachment?.size ?? state?.total ?? 0)}',
                          ),
                          if (attachment == null)
                            _caption(context, 'Pending')
                          else
                            FutureBuilder<DateTime?>(
                              future: _storedDate,
                              builder: (context, snapshot) => _caption(
                                context,
                                snapshot.data == null
                                    ? 'Date unavailable'
                                    : 'Stored ${DateFormat('dd/MM HH:mm').format(snapshot.data!.toLocal())}',
                              ),
                            ),
                        ],
                        if (active || failed) ...[
                          Semantics(
                            liveRegion: true,
                            child: _caption(
                              context,
                              state!.detail ??
                                  attachmentPhaseLabel(state.phase),
                            ),
                          ),
                          if (active) LinearProgressIndicator(value: fraction),
                          if (state.error != null)
                            AppTooltip(
                              message: '$name\n${state.error!}',
                              child: Text(
                                state.error!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: _captionStyle(context),
                              ),
                            )
                          else if (total != null && !waiting)
                            _caption(
                              context,
                              '${formatAttachmentBytes(state.bytes)} / ${formatAttachmentBytes(total)}${fraction == null ? '' : ' · ${(fraction * 100).floor()}%'}',
                            ),
                        ],
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _jobButton(String tooltip, IconData icon, VoidCallback onPressed) =>
      IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 20, height: 24),
        style: IconButton.styleFrom(
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        icon: Icon(icon, size: 18),
      );

  TextStyle? _captionStyle(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall;
    return style?.copyWith(
      fontSize: (style.fontSize ?? 11) * .88,
      height: 1.15,
    );
  }

  Widget _caption(BuildContext context, String text) => SizedBox(
    width: double.infinity,
    child: FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Text(text, style: _captionStyle(context)),
    ),
  );
}

// Presentation entries only: pending jobs never become durable metadata here.
class _AttachmentEntry {
  const _AttachmentEntry(this.attachment, this.job);
  final AttachmentModel? attachment;
  final AttachmentJobState? job;
  String get id => attachment?.id ?? job!.progress.value.id;
}

List<_AttachmentEntry> _entries(ContentViewModel model) {
  final attachments = model.attachmentsNotifier.value;
  final jobs = model.attachmentJobsNotifier.value.where(
    (j) => j.progress.value.owner == model.draftSession.generation,
  );
  final latest = <String, AttachmentJobState>{};
  for (final job in jobs) {
    final id = job.progress.value.originalAttachmentId;
    if (id != null) latest[id] = job;
  }
  final ids = attachments.map((a) => a.id).toSet();
  return [
    for (final attachment in attachments)
      _AttachmentEntry(attachment, latest[attachment.id]),
    for (final job in jobs)
      if (job.progress.value.operation == AttachmentJobOperation.add &&
          !ids.contains(job.progress.value.id) &&
          (job.progress.value.active ||
              job.progress.value.phase == AttachmentJobPhase.failed))
        _AttachmentEntry(null, job),
  ];
}

// Job progress replaces captions inside the card; it never resizes the dock.
double _tileHeight(bool expanded) => expanded ? 104.0 : 36.0;

class _AttachmentGallery extends StatefulWidget {
  const _AttachmentGallery({
    required this.model,
    required this.owner,
    required this.credentials,
    required this.contentPath,
    required this.startIndex,
    required this.onAction,
  });
  final ContentViewModel model;
  final int owner;
  final int credentials;
  final String? contentPath;
  final int startIndex;
  final Future<void> Function(AttachmentAction, AttachmentModel, FocusNode)
  onAction;
  @override
  State<_AttachmentGallery> createState() => _AttachmentGalleryState();
}

class _AttachmentGalleryState extends State<_AttachmentGallery> {
  bool _closing = false;
  bool _selecting = false, _busy = false, _confirming = false;
  String? _anchor, _actionError;
  final _selected = <String>{};
  final _search = TextEditingController();
  final _searchFocus = FocusNode();

  bool _current() =>
      mounted &&
      !widget.model.isLocked &&
      widget.model.draftSession.generation == widget.owner &&
      widget.model.draftSession.credentialGeneration == widget.credentials &&
      widget.model.currentContentPath == widget.contentPath;

  void _clearSelection() {
    if (_busy || _confirming) return;
    setState(() {
      _selecting = false;
      _selected.clear();
      _anchor = null;
    });
  }

  void _toggle(_AttachmentEntry entry, List<String> visible) {
    if (_busy || _confirming || !_current()) return;
    final keys = HardwareKeyboard.instance;
    _searchFocus.unfocus();
    setState(() {
      _selecting = true;
      final first = visible.indexOf(_anchor ?? '');
      final last = visible.indexOf(entry.id);
      if (keys.isShiftPressed && first >= 0 && last >= 0) {
        if (!keys.isControlPressed && !keys.isMetaPressed) _selected.clear();
        _selected.addAll(
          visible.sublist(math.min(first, last), math.max(first, last) + 1),
        );
      } else {
        if (!_selected.add(entry.id)) _selected.remove(entry.id);
        _anchor = entry.id;
      }
    });
  }

  Future<void> _saveSelected() async {
    if (!_current() || _busy || _confirming || _selected.isEmpty) return;
    final ids = Set<String>.of(_selected);
    setState(() {
      _busy = true;
      _actionError = null;
    });
    DirectoryAttachmentExport? output;
    try {
      final parent = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Choose folder for selected attachments',
      );
      if (parent == null || !_current()) return;
      output = await DirectoryAttachmentExport.create(parent);
      if (!_current()) return;
      final result = await widget.model.exportAttachments(ids, output: output);
      if (!_current()) return;
      setState(() {
        if (result.isSuccess) {
          _selected.clear();
          _selecting = false;
        } else if (result.outcome != OperationOutcome.cancelled) {
          _actionError = result.message ?? 'Selected files could not be saved.';
        }
      });
      if (result.isSuccess) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text(
              'Saved ${ids.length} attachments in ${Directory(output.directory.path).uri.pathSegments.where((s) => s.isNotEmpty).last}.',
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted)
        setState(
          () => _actionError =
              'The export folder could not be used. Choose another folder.',
        );
    } finally {
      await output?.cleanup(const []);
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removeSelected() async {
    if (!_current() ||
        _busy ||
        _confirming ||
        _selected.isEmpty ||
        widget.model.hasAttachmentJobs)
      return;
    final ids = Set<String>.of(_selected);
    setState(() => _confirming = true);
    try {
      final confirmed = await showAppDialog<bool>(
        context: context,
        builder: (dialogContext) => ListenableBuilder(
          listenable: Listenable.merge([
            widget.model,
            widget.model.attachmentJobsNotifier,
          ]),
          builder: (_, _) {
            if (!_current()) {
              final navigator = Navigator.of(dialogContext);
              final route = ModalRoute.of(dialogContext)!;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (route.isActive) navigator.removeRoute(route);
              });
              return const SizedBox.shrink();
            }
            return AlertDialog(
              title: Text(
                'Remove ${ids.length} ${ids.length == 1 ? 'attachment' : 'attachments'}?',
              ),
              content: const Text('Remove these files from this note?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: widget.model.hasAttachmentJobs
                      ? null
                      : () => Navigator.pop(dialogContext, true),
                  child: const Text('Remove'),
                ),
              ],
            );
          },
        ),
      );
      if (confirmed != true || !_current() || widget.model.hasAttachmentJobs)
        return;
      setState(() => _busy = true);
      final result = await widget.model.removeAttachments(ids);
      if (_current())
        setState(() {
          if (result.isSuccess) {
            _selected.clear();
            _selecting = false;
          } else if (result.outcome != OperationOutcome.cancelled)
            _actionError = result.message;
        });
    } finally {
      if (mounted)
        setState(() {
          _busy = false;
          _confirming = false;
        });
    }
  }

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      widget.model,
      widget.model.isLockedNotifier,
      widget.model.attachmentsNotifier,
      widget.model.attachmentJobsNotifier,
      widget.model.attachmentCacheNotifier,
    ]),
    builder: (context, _) {
      final model = widget.model;
      if (model.isLockedNotifier.value ||
          model.draftSession.generation != widget.owner ||
          model.draftSession.credentialGeneration != widget.credentials ||
          model.currentContentPath != widget.contentPath) {
        if (!_closing) {
          _closing = true;
          final navigator = Navigator.of(context);
          final route = ModalRoute.of(context)!;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && route.isActive) navigator.removeRoute(route);
          });
        }
        return const SizedBox.shrink();
      }
      final all = _entries(model).skip(widget.startIndex).toList();
      final query = _search.text.trim().toLowerCase();
      final remaining = all
          .where(
            (entry) =>
                (entry.attachment?.fileName ??
                        entry.job!.progress.value.fileName)
                    .toLowerCase()
                    .contains(query),
          )
          .toList();
      final eligible = all
          .where(
            (e) => e.attachment != null && e.job?.progress.value.active != true,
          )
          .map((e) => e.id)
          .toSet();
      final visible = remaining
          .where((e) => eligible.contains(e.id))
          .map((e) => e.id)
          .toList();
      _selected.retainAll(
        all.where((e) => e.attachment != null).map((e) => e.id),
      );
      final actionable =
          !_busy &&
          !_confirming &&
          _selected.isNotEmpty &&
          _selected.every(eligible.contains);
      final names = <String, int>{};
      for (final e in all) {
        if (e.attachment != null)
          names.update(
            e.attachment!.fileName.toLowerCase(),
            (n) => n + 1,
            ifAbsent: () => 1,
          );
      }
      void selectVisible() {
        setState(() {
          _selecting = true;
          if (visible.every(_selected.contains))
            _selected.removeAll(visible);
          else
            _selected.addAll(visible);
        });
      }

      return Focus(
        onKeyEvent: (_, event) {
          if (event is! KeyDownEvent || _busy || _confirming)
            return KeyEventResult.ignored;
          if (event.logicalKey == LogicalKeyboardKey.escape && _selecting) {
            _clearSelection();
            return KeyEventResult.handled;
          }
          if (_searchFocus.hasFocus) return KeyEventResult.ignored;
          if (event.logicalKey == LogicalKeyboardKey.keyA &&
              (HardwareKeyboard.instance.isControlPressed ||
                  HardwareKeyboard.instance.isMetaPressed)) {
            setState(() {
              _selecting = true;
              _selected.addAll(visible);
            });
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: AlertDialog(
          titlePadding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          contentPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          actionsPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          title: OverflowBar(
            alignment: MainAxisAlignment.spaceBetween,
            overflowAlignment: OverflowBarAlignment.end,
            spacing: 12,
            children: [
              Text(
                widget.startIndex == 0 ? 'All attachments' : 'More attachments',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              TextButton(
                onPressed: _busy || _confirming || eligible.isEmpty
                    ? null
                    : () {
                        _searchFocus.unfocus();
                        if (_selecting) {
                          _clearSelection();
                        } else {
                          setState(() => _selecting = true);
                        }
                      },
                child: Text(_selecting ? 'Exit selection' : 'Select'),
              ),
            ],
          ),
          content: SizedBox(
            width: 600,
            height: math.min(
              MediaQuery.sizeOf(context).height * .55,
              math.max(
                100,
                MediaQuery.sizeOf(context).height -
                    MediaQuery.viewInsetsOf(context).bottom -
                    260 * MediaQuery.textScalerOf(context).scale(1),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  key: const ValueKey('attachment-filename-search'),
                  controller: _search,
                  focusNode: _searchFocus,
                  enabled: !_busy,
                  autofocus: true,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Search filenames',
                    isDense: true,
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _search.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear attachment search',
                            icon: const Icon(Icons.close),
                            onPressed: () {
                              setState(_search.clear);
                              _searchFocus.requestFocus();
                            },
                          ),
                  ),
                ),
                const SizedBox(height: 12),
                if (_selecting)
                  Row(
                    children: [
                      Checkbox(
                        value: visible.isEmpty
                            ? false
                            : visible.every(_selected.contains)
                            ? true
                            : visible.any(_selected.contains)
                            ? null
                            : false,
                        tristate: true,
                        onChanged: _busy || visible.isEmpty
                            ? null
                            : (_) => selectVisible(),
                        semanticLabel: 'Select all visible attachments',
                      ),
                      Text('${_selected.length} selected'),
                      if (_selected.any((id) => !visible.contains(id)))
                        Text(
                          ' · ${_selected.where((id) => !visible.contains(id)).length} hidden',
                        ),
                    ],
                  ),
                Expanded(
                  child: remaining.isEmpty
                      ? Center(
                          child: Text(
                            all.isEmpty
                                ? 'No attachments'
                                : 'No matching attachments',
                          ),
                        )
                      : LayoutBuilder(
                          builder: (context, constraints) {
                            final scale = MediaQuery.textScalerOf(
                              context,
                            ).scale(1);
                            final columns = math.max(
                              1,
                              ((constraints.maxWidth + 8) / (96 * scale + 8))
                                  .floor(),
                            );
                            final cardWidth =
                                (constraints.maxWidth - 8 * (columns - 1)) /
                                columns;
                            return SingleChildScrollView(
                              primary: false,
                              child: Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  for (final entry in remaining)
                                    ListenableBuilder(
                                      key: ValueKey(
                                        'overflow/${widget.owner}/${entry.id}',
                                      ),
                                      listenable:
                                          entry.job?.phase ??
                                          model.attachmentsNotifier,
                                      builder: (context, _) => SizedBox(
                                        width: cardWidth,
                                        height:
                                            _tileHeight(true) *
                                            MediaQuery.textScalerOf(
                                              context,
                                            ).scale(1),
                                        child: _AttachmentTile(
                                          model: model,
                                          attachment: entry.attachment,
                                          job: entry.job,
                                          expanded: true,
                                          onAction: widget.onAction,
                                          selectionMode: _selecting,
                                          selected: _selected.contains(
                                            entry.id,
                                          ),
                                          disambiguate:
                                              (names[entry.attachment?.fileName
                                                      .toLowerCase()] ??
                                                  0) >
                                              1,
                                          onSelect:
                                              _busy ||
                                                  _confirming ||
                                                  !eligible.contains(entry.id)
                                              ? null
                                              : () => _toggle(entry, visible),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
          actions: [
            if (_actionError != null)
              Text(
                _actionError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (_selecting) ...[
              TextButton.icon(
                onPressed: actionable ? _saveSelected : null,
                icon: const Icon(Icons.save_alt),
                label: const Text('Save selected'),
              ),
              TextButton.icon(
                onPressed: actionable && !model.hasAttachmentJobs
                    ? _removeSelected
                    : null,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Remove selected'),
              ),
            ],
            if (_busy) ...[
              for (final job in model.attachmentJobsNotifier.value.where(
                (j) =>
                    j.progress.value.active &&
                    j.progress.value.batch &&
                    j.progress.value.owner == widget.owner,
              ))
                ValueListenableBuilder<AttachmentJobSnapshot>(
                  valueListenable: job.progress,
                  builder: (_, state, _) => Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SizedBox(
                        width: 140,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            LinearProgressIndicator(
                              value: state.total != null && state.total! > 0
                                  ? (state.bytes / state.total!).clamp(0.0, 1.0)
                                  : null,
                            ),
                            Text(
                              state.detail ?? attachmentPhaseLabel(state.phase),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (state.total != null && state.total! > 0)
                              Text(
                                '${formatAttachmentBytes(state.bytes)} / ${formatAttachmentBytes(state.total!)} · ${(state.bytes * 100 / state.total!).clamp(0, 100).floor()}%',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: state.cancellable
                            ? () => model.cancelAttachmentJob(state.id)
                            : null,
                        child: const Text('Cancel export'),
                      ),
                    ],
                  ),
                ),
            ],
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    },
  );
}
