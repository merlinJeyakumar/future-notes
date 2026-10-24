import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_dialog.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_tooltip.dart';
import '../../../core/platform/mobile_export.dart';
import '../../../core/operations/operation_result.dart';
import '../models/attachment_job.dart';
import '../models/note_model.dart';
import '../viewmodels/content_viewmodel.dart';
import '../widgets/attachment_presentation.dart';
import 'attachment_preview.dart';
import 'attachment_progress.dart';
import 'attachment_viewer.dart';
import 'editor_panels.dart';
import 'attachment_thumbnails.dart';

class AttachmentStrip extends StatefulWidget {
  const AttachmentStrip({
    super.key,
    required this.viewModel,
    this.playerFactory,
    this.collapseRequests,
    this.panels,
    this.thumbnailFactory,
  });
  final ContentViewModel viewModel;
  final AttachmentPlayerFactory? playerFactory;
  final Listenable? collapseRequests;
  final MobileEditorPanels? panels;
  final MobileAttachmentThumbnails Function(
    Future<Uint8List?> Function(AttachmentModel),
  )?
  thumbnailFactory;
  @override
  State<AttachmentStrip> createState() => _AttachmentStripState();
}

class _AttachmentStripState extends State<AttachmentStrip> {
  late MobileAttachmentThumbnails _thumbnails;
  void _bindThumbnails() {
    final bound = model;
    _thumbnails =
        widget.thumbnailFactory?.call(bound.restoreAttachmentThumbnail) ??
        MobileAttachmentThumbnails(restore: bound.restoreAttachmentThumbnail);
    bound.attachmentsNotifier.addListener(_syncThumbnails);
    bound.attachmentJobsNotifier.addListener(_syncThumbnails);
    Future.microtask(() {
      if (mounted) _syncThumbnails();
    });
  }

  void _syncThumbnails() => _thumbnails.update(
    owner: (
      model.currentContentPath,
      model.draftSession.generation,
      model.draftSession.credentialGeneration,
    ),
    attachments: model.attachmentsNotifier.value,
    refreshRevision: model.thumbnailRefreshRevision,
    unlocked: !model.isLocked && model.draftSession.isPersisted,
    defer:
        model.hasAttachmentJobs ||
        model.isDeletingCurrent ||
        model.isLibraryCutover,
  );
  bool expanded = false;
  late int _owner;
  late bool _locked;
  String? _path;
  ContentViewModel get model => widget.viewModel;
  void _collapse() {
    widget.panels?.collapse(MobileEditorPanel.attachments);
    if (expanded) setState(() => expanded = false);
  }

  void _panelChanged() {
    final next = widget.panels?.value == MobileEditorPanel.attachments;
    if (next != expanded && mounted) setState(() => expanded = next);
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
        _locked != model.isLocked;
    _rememberOwner();
    if (reset) _collapse();
    _syncThumbnails();
  }

  @override
  void initState() {
    super.initState();
    _rememberOwner();
    _bindThumbnails();
    model.addListener(_syncOwner);
    widget.collapseRequests?.addListener(_collapse);
    widget.panels?.addListener(_panelChanged);
  }

  @override
  void didUpdateWidget(covariant AttachmentStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.panels != widget.panels) {
      oldWidget.panels?.removeListener(_panelChanged);
      widget.panels?.addListener(_panelChanged);
      expanded = widget.panels?.value == MobileEditorPanel.attachments;
    }
    if (oldWidget.collapseRequests != widget.collapseRequests) {
      oldWidget.collapseRequests?.removeListener(_collapse);
      widget.collapseRequests?.addListener(_collapse);
    }
    if (oldWidget.viewModel != model ||
        oldWidget.thumbnailFactory != widget.thumbnailFactory) {
      oldWidget.viewModel.attachmentsNotifier.removeListener(_syncThumbnails);
      oldWidget.viewModel.attachmentJobsNotifier.removeListener(
        _syncThumbnails,
      );
      _thumbnails.dispose();
      _bindThumbnails();
      oldWidget.viewModel.removeListener(_syncOwner);
      expanded = false;
      _rememberOwner();
      model.addListener(_syncOwner);
    }
  }

  @override
  void dispose() {
    model.attachmentsNotifier.removeListener(_syncThumbnails);
    model.attachmentJobsNotifier.removeListener(_syncThumbnails);
    _thumbnails.dispose();
    model.removeListener(_syncOwner);
    widget.collapseRequests?.removeListener(_collapse);
    widget.panels?.removeListener(_panelChanged);
    super.dispose();
  }

  Future<void> _action(
    AttachmentAction action,
    AttachmentModel attachment,
    FocusNode focus,
  ) async {
    widget.panels?.collapse();
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

  Future<void> _showAll() {
    widget.panels?.collapse();
    final owner = model.draftSession.generation;
    final credentials = model.draftSession.credentialGeneration;
    final path = model.currentContentPath;
    return showAppDialog<void>(
      context: context,
      useSafeArea: false,
      builder: (_) => _AttachmentGallery(
        thumbnails: _thumbnails,
        model: model,
        owner: owner,
        credentials: credentials,
        contentPath: path,
        onAction: _action,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: model.isLockedNotifier,
    builder: (_, locked, _) => locked
        ? const SizedBox.shrink()
        : ListenableBuilder(
            listenable: Listenable.merge([
              model.attachmentsNotifier,
              model.attachmentJobsNotifier,
              model.attachmentCacheNotifier,
              _thumbnails,
            ]),
            builder: (context, _) {
              final entries = _entries(model);
              if (entries.isEmpty) return const SizedBox.shrink();
              final available =
                  MediaQuery.sizeOf(context).height -
                  MediaQuery.viewInsetsOf(context).bottom;
              // The dock owns one bounded scroller, including on IME/landscape changes.
              final listHeight = math.min(
                (available * .24).clamp(88.0, 224.0),
                entries.length * 104.0,
              );
              final duplicates = _duplicateNames(entries);
              return AnimatedSize(
                key: ValueKey((
                  model.draftSession.generation,
                  model.currentContentPath,
                )),
                duration: AppMotion.duration(context, AppMotion.panelIn),
                reverseDuration: AppMotion.duration(
                  context,
                  AppMotion.panelOut,
                ),
                curve: expanded ? AppMotion.enterCurve : AppMotion.exitCurve,
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Material(
                    color: Theme.of(context).colorScheme.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: InkWell(
                                key: const ValueKey('attachment-expand-toggle'),
                                onTap: () {
                                  if (widget.panels != null) {
                                    widget.panels!.toggle(
                                      MobileEditorPanel.attachments,
                                    );
                                  } else {
                                    setState(() => expanded = !expanded);
                                  }
                                },
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    12,
                                    12,
                                    4,
                                    12,
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.attach_file, size: 19),
                                      const SizedBox(width: 8),
                                      Flexible(
                                        child: Text(
                                          'Attachments',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(
                                            context,
                                          ).textTheme.titleSmall,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      _CountBadge(
                                        count: model
                                            .attachmentsNotifier
                                            .value
                                            .length,
                                      ),
                                      const SizedBox(width: 4),
                                      AppDisclosure(expanded: expanded),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            if (MediaQuery.textScalerOf(context).scale(14) >
                                    20 ||
                                MediaQuery.sizeOf(context).width < 320)
                              IconButton(
                                key: const ValueKey('attachment-show-all'),
                                tooltip: 'All attachments',
                                onPressed: _showAll,
                                icon: const Icon(Icons.arrow_forward_rounded),
                              )
                            else
                              TextButton(
                                key: const ValueKey('attachment-show-all'),
                                onPressed: _showAll,
                                child: const Text('See all'),
                              ),
                            const SizedBox(width: 4),
                          ],
                        ),
                        if (expanded) ...[
                          const Divider(height: 1),
                          SizedBox(
                            height: listHeight,
                            child: ListView.separated(
                              key: ValueKey((
                                'attachment-expanded-list',
                                model.draftSession.generation,
                              )),
                              primary: false,
                              padding: EdgeInsets.zero,
                              itemCount: entries.length,
                              separatorBuilder: (_, _) => const Divider(
                                height: 1,
                                indent: 68,
                                endIndent: 12,
                              ),
                              itemBuilder: (_, index) => _AttachmentTile(
                                thumbnails: _thumbnails,
                                key: ValueKey(entries[index].id),
                                model: model,
                                entry: entries[index],
                                expanded: true,
                                disambiguate: duplicates.contains(
                                  entries[index].name.toLowerCase(),
                                ),
                                onAction: _action,
                              ),
                            ),
                          ),
                        ] else
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                final slots = ((constraints.maxWidth + 8) / 56)
                                    .floor()
                                    .clamp(2, 5);
                                final count =
                                    entries.length > math.min(4, slots)
                                    ? math.min(4, slots - 1)
                                    : entries.length;
                                return Row(
                                  children: [
                                    for (
                                      var index = 0;
                                      index < count;
                                      index++
                                    ) ...[
                                      if (index > 0) const SizedBox(width: 8),
                                      SizedBox(
                                        width: 48,
                                        height: 48,
                                        child: _AttachmentTile(
                                          thumbnails: _thumbnails,
                                          key: ValueKey(entries[index].id),
                                          model: model,
                                          entry: entries[index],
                                          expanded: false,
                                          onAction: _action,
                                        ),
                                      ),
                                    ],
                                    if (entries.length > count) ...[
                                      const SizedBox(width: 8),
                                      SizedBox(
                                        width: 48,
                                        height: 48,
                                        child: OutlinedButton(
                                          key: const ValueKey(
                                            'attachment-overflow',
                                          ),
                                          onPressed: _showAll,
                                          style: OutlinedButton.styleFrom(
                                            padding: EdgeInsets.zero,
                                          ),
                                          child: Text(
                                            '+${entries.length - count}',
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                );
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
  );
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});
  final int count;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.primary.withValues(alpha: .10),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      '$count',
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
        color: Theme.of(context).colorScheme.primary,
      ),
    ),
  );
}

class _AttachmentTile extends StatefulWidget {
  const _AttachmentTile({
    required this.thumbnails,
    super.key,
    required this.model,
    required this.entry,
    required this.expanded,
    required this.onAction,
    this.disambiguate = false,
    this.selectionMode = false,
    this.selected = false,
    this.onToggleSelection,
  });
  final ContentViewModel model;
  final MobileAttachmentThumbnails thumbnails;
  final _AttachmentEntry entry;
  final bool expanded;
  final bool disambiguate;
  final bool selectionMode;
  final bool selected;
  final VoidCallback? onToggleSelection;
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
        '${identityHashCode(model)}/${model.draftSession.generation}/${model.draftSession.credentialGeneration}/${model.currentContentPath}/${widget.entry.id}/${widget.expanded}';
    if (_dateKey == key) return;
    _dateKey = key;
    _storedDate = !widget.expanded || widget.entry.attachment == null
        ? null
        : model.attachmentStoredDate(widget.entry.id);
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.entry.job == null
      ? _row(context, null)
      : ValueListenableBuilder<AttachmentJobSnapshot>(
          valueListenable: widget.entry.job!.progress,
          builder: (context, state, _) => _row(context, state),
        );
  Widget _row(BuildContext context, AttachmentJobSnapshot? state) {
    final entry = widget.entry;
    final attachment = entry.attachment;
    final name = entry.name;
    final active = state?.active ?? false;
    final failed = state?.phase == AttachmentJobPhase.failed;
    final canOpen = attachment != null && !active;
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final kind = attachmentVisualKind(name);
    final thumbnail = widget.thumbnails.image(entry.id);
    final cached = attachment == null
        ? null
        : widget.model.cachedAttachment(attachment.id);
    final icon = switch (kind) {
      AttachmentVisualKind.image => Icons.image_outlined,
      AttachmentVisualKind.video => Icons.play_circle_outline_rounded,
      AttachmentVisualKind.audio => Icons.audio_file_outlined,
      AttachmentVisualKind.document => Icons.description_outlined,
      AttachmentVisualKind.file => Icons.insert_drive_file_outlined,
    };
    final total = state?.total;
    final exporting = state?.operation == AttachmentJobOperation.export;
    final otherExportFile =
        exporting && state?.originalAttachmentId != entry.id;
    final waiting =
        otherExportFile ||
        state?.phase == AttachmentJobPhase.cancelling ||
        (state?.phase == AttachmentJobPhase.finalizing && total == null);
    final fraction = !waiting && total != null && total > 0
        ? (state!.bytes / total).clamp(0.0, 1.0)
        : null;
    void action(AttachmentAction action) {
      if (attachment != null) widget.onAction(action, attachment, _focus);
    }

    final leading = Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(12),
      ),
      child: active
          ? SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(value: fraction, strokeWidth: 2),
            )
          : thumbnail != null
          ? ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.memory(
                    thumbnail,
                    fit: BoxFit.cover,
                    key: ValueKey('attachment-thumbnail-${entry.id}'),
                    errorBuilder: (_, _, _) {
                      widget.thumbnails.reportDecodeFailure(
                        entry.id,
                        thumbnail,
                      );
                      return Icon(icon, color: colors.primary, size: 25);
                    },
                  ),
                  if (kind == AttachmentVisualKind.video)
                    const Icon(
                      Icons.play_circle_outline_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                ],
              ),
            )
          : cached != null && kind == AttachmentVisualKind.image && !failed
          ? ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: TickerMode(
                enabled: false,
                child: Image.file(
                  File(cached.path),
                  width: 44,
                  height: 44,
                  fit: BoxFit.cover,
                  cacheWidth: 88,
                  cacheHeight: 88,
                  errorBuilder: (_, _, _) =>
                      Icon(icon, color: colors.primary, size: 25),
                ),
              ),
            )
          : Icon(
              failed ? Icons.error_outline_rounded : icon,
              color: failed ? colors.error : colors.primary,
              size: 25,
            ),
    );
    final phase = state == null
        ? ''
        : exporting
        ? otherExportFile
              ? 'Export in progress…'
              : 'Export · ${attachmentPhaseLabel(state.phase)}'
        : state.detail ?? attachmentPhaseLabel(state.phase);
    return Material(
      color: widget.selected
          ? colors.primary.withValues(alpha: .08)
          : Colors.transparent,
      child: AppTooltip(
        message: name,
        child: InkWell(
          key: ValueKey('attachment-open-${entry.id}'),
          focusNode: _focus,
          onTap: widget.selectionMode
              ? widget.onToggleSelection
              : canOpen
              ? () => action(AttachmentAction.open)
              : null,
          onLongPress: canOpen ? widget.onToggleSelection : null,
          child: widget.expanded
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      if (widget.selectionMode && !active)
                        SizedBox(
                          width: 44,
                          height: 48,
                          child: Checkbox(
                            value: widget.selected,
                            onChanged: widget.onToggleSelection == null
                                ? null
                                : (_) => widget.onToggleSelection!(),
                          ),
                        )
                      else
                        ExcludeSemantics(child: leading),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: text.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 3),
                            if (active || failed) ...[
                              Text(
                                phase,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: text.bodySmall?.copyWith(
                                  color: failed ? colors.error : colors.primary,
                                ),
                              ),
                              const SizedBox(height: 3),
                              if (active)
                                LinearProgressIndicator(
                                  value: fraction,
                                  minHeight: 2,
                                ),
                              Text(
                                state?.error ??
                                    (total == null || waiting
                                        ? ' '
                                        : '${formatAttachmentBytes(state!.bytes)} / ${formatAttachmentBytes(total)}${fraction == null ? '' : ' · ${(fraction * 100).floor()}%'}'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: text.bodySmall,
                              ),
                            ] else ...[
                              Text(
                                '${_fileType(name, kind)} · ${formatAttachmentBytes(attachment?.size ?? 0)}${widget.disambiguate ? ' · ${_shortId(entry.id)}' : ''}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: text.bodySmall,
                              ),
                              FutureBuilder<DateTime?>(
                                future: _storedDate,
                                builder: (context, snapshot) => Text(
                                  snapshot.data == null
                                      ? ' '
                                      : DateFormat(
                                          'd MMM yyyy · HH:mm',
                                        ).format(snapshot.data!.toLocal()),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: text.bodySmall?.copyWith(
                                    color: colors.onSurface.withValues(
                                      alpha: .5,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 4),
                      if (active)
                        SizedBox(
                          width: 48,
                          child: state!.cancellable
                              ? IconButton(
                                  tooltip: 'Cancel attachment',
                                  onPressed: () => widget.model
                                      .cancelAttachmentJob(state.id),
                                  icon: const Icon(
                                    Icons.close_rounded,
                                    size: 20,
                                  ),
                                )
                              : null,
                        )
                      else if (!widget.selectionMode &&
                          (attachment != null || failed))
                        SizedBox(
                          width: 48,
                          child: AttachmentMoreButton(
                            fileName: name,
                            enabled: attachment != null,
                            canRemove:
                                attachment != null &&
                                !widget.model.hasAttachmentJobs,
                            onSelected: action,
                            onRetry: attachment == null && failed
                                ? () =>
                                      widget.model.retryAttachmentJob(state!.id)
                                : null,
                            onRemovePending: attachment == null && failed
                                ? () => widget.model.removePendingAttachmentJob(
                                    state!.id,
                                  )
                                : null,
                          ),
                        ),
                    ],
                  ),
                )
              : Semantics(
                  label: name,
                  value: active || failed ? phase : null,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      leading,
                      if (active && state!.cancellable)
                        Positioned.fill(
                          child: IconButton(
                            tooltip: 'Cancel attachment',
                            onPressed: () =>
                                widget.model.cancelAttachmentJob(state.id),
                            icon: const Icon(Icons.close_rounded, size: 14),
                          ),
                        ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

String _fileType(String name, AttachmentVisualKind kind) {
  final dot = name.lastIndexOf('.');
  final extension = dot < 0 ? '' : name.substring(dot + 1);
  return RegExp(r'^[a-zA-Z0-9]{1,8}$').hasMatch(extension)
      ? extension.toUpperCase()
      : '${kind.name[0].toUpperCase()}${kind.name.substring(1)}';
}

String _shortId(String id) => id.length <= 5 ? id : id.substring(id.length - 5);
Set<String> _duplicateNames(List<_AttachmentEntry> entries) {
  final seen = <String>{};
  final duplicates = <String>{};
  for (final entry in entries) {
    final name = entry.name.toLowerCase();
    if (!seen.add(name)) duplicates.add(name);
  }
  return duplicates;
}

// Presentation entries only: pending jobs never become durable metadata here.
class _AttachmentEntry {
  const _AttachmentEntry(this.attachment, this.job);
  final AttachmentModel? attachment;
  final AttachmentJobState? job;
  String get id => attachment?.id ?? job!.progress.value.id;
  String get name => attachment?.fileName ?? job!.progress.value.fileName;
}

List<_AttachmentEntry> _entries(ContentViewModel model) {
  final attachments = model.attachmentsNotifier.value;
  final jobs = model.attachmentJobsNotifier.value.where(
    (j) => j.progress.value.owner == model.draftSession.generation,
  );
  final latest = <String, AttachmentJobState>{};
  for (final job in jobs) {
    final state = job.progress.value;
    if (state.operation == AttachmentJobOperation.export) {
      if (state.active) {
        for (final id in {
          ...state.attachmentIds,
          ?state.originalAttachmentId,
        }) {
          latest[id] = job;
        }
      }
      continue;
    }
    final id =
        state.originalAttachmentId ??
        (state.operation == AttachmentJobOperation.add ? state.id : null);
    if (id != null && latest[id]?.progress.value.active != true) {
      latest[id] = job;
    }
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

class _AttachmentGallery extends StatefulWidget {
  const _AttachmentGallery({
    required this.thumbnails,
    required this.model,
    required this.owner,
    required this.credentials,
    required this.contentPath,
    required this.onAction,
  });
  final ContentViewModel model;
  final MobileAttachmentThumbnails thumbnails;
  final int owner;
  final int credentials;
  final String? contentPath;
  final Future<void> Function(AttachmentAction, AttachmentModel, FocusNode)
  onAction;
  @override
  State<_AttachmentGallery> createState() => _AttachmentGalleryState();
}

class _AttachmentGalleryState extends State<_AttachmentGallery> {
  bool _closing = false;
  bool _selecting = false;
  bool _busy = false;
  bool _confirming = false;
  String? _actionError;
  final _selected = <String>{};
  final _search = TextEditingController();
  final _searchFocus = FocusNode();

  bool _current() =>
      mounted &&
      !widget.model.isLockedNotifier.value &&
      widget.model.draftSession.generation == widget.owner &&
      widget.model.draftSession.credentialGeneration == widget.credentials &&
      widget.model.currentContentPath == widget.contentPath;
  void _clearSelection() {
    if (_busy) return;
    setState(() {
      _selecting = false;
      _selected.clear();
    });
  }

  void _toggle(_AttachmentEntry entry) {
    if (_busy || !_current()) return;
    if (!_selected.contains(entry.id) &&
        (entry.attachment == null || entry.job?.progress.value.active == true))
      return;
    _searchFocus.unfocus();
    setState(() {
      _selecting = true;
      if (!_selected.add(entry.id)) _selected.remove(entry.id);
    });
  }

  Future<void> _shareSelected() async {
    if (!_current() || _busy || _confirming || _selected.isEmpty) return;
    final ids = Set<String>.of(_selected);
    setState(() {
      _busy = true;
      _actionError = null;
    });
    try {
      final result = await widget.model.exportAttachments(
        ids,
        output: const MobileAttachmentBatchExport(),
      );
      if (!_current()) return;
      if (!result.isSuccess && result.outcome != OperationOutcome.cancelled) {
        setState(
          () => _actionError =
              result.message ?? 'The selected files could not be exported.',
        );
      }
      if (result.isSuccess)
        setState(() {
          _selected.clear();
          _selecting = false;
        });
    } finally {
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
            widget.model.isLockedNotifier,
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
      setState(() {
        _busy = true;
        _actionError = null;
      });
      final result = await widget.model.removeAttachments(ids);
      if (_current() &&
          !result.isSuccess &&
          result.outcome != OperationOutcome.cancelled) {
        setState(
          () => _actionError =
              result.message ??
              'The selected attachments could not be removed.',
        );
      }
      if (_current() && result.isSuccess)
        setState(() {
          _selected.clear();
          _selecting = false;
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
      widget.thumbnails,
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
      final all = _entries(model);
      final query = _search.text.trim().toLowerCase();
      final remaining = all
          .where((entry) => entry.name.toLowerCase().contains(query))
          .toList();
      final duplicates = _duplicateNames(all);
      final available = all
          .where(
            (entry) =>
                entry.attachment != null &&
                entry.job?.progress.value.active != true,
          )
          .map((entry) => entry.id)
          .toSet();
      _selected.retainAll(
        all.where((entry) => entry.attachment != null).map((entry) => entry.id),
      );
      final actionable =
          !_busy &&
          !_confirming &&
          _selected.isNotEmpty &&
          _selected.every(available.contains);
      final visible = remaining
          .where((entry) => available.contains(entry.id))
          .map((entry) => entry.id)
          .toSet();
      return PopScope(
        canPop: !_selecting && !_busy,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && !_busy) _clearSelection();
        },
        child: Dialog.fullscreen(
          child: Scaffold(
            appBar: AppBar(
              leading: _selecting
                  ? IconButton(
                      tooltip: 'Exit selection',
                      icon: const Icon(Icons.close_rounded),
                      onPressed: _busy ? null : _clearSelection,
                    )
                  : BackButton(onPressed: () => Navigator.pop(context)),
              title: Text(
                _selecting ? '${_selected.length} selected' : 'All attachments',
              ),
              actions: [
                if (_selecting)
                  IconButton(
                    tooltip: 'Select all visible attachments',
                    icon: const Icon(Icons.select_all_rounded),
                    onPressed: _busy || visible.isEmpty
                        ? null
                        : () => setState(() {
                            if (visible.every(_selected.contains))
                              _selected.removeAll(visible);
                            else
                              _selected.addAll(visible);
                          }),
                  )
                else
                  TextButton(
                    onPressed: available.isEmpty
                        ? null
                        : () {
                            _searchFocus.unfocus();
                            setState(() => _selecting = true);
                          },
                    child: const Text('Select'),
                  ),
                const SizedBox(width: 4),
              ],
            ),
            body: SafeArea(
              top: false,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: TextField(
                      key: const ValueKey('attachment-filename-search'),
                      controller: _search,
                      focusNode: _searchFocus,
                      enabled: !_busy,
                      onChanged: (_) => setState(() {}),
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: 'Search attachments',
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: _search.text.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Clear attachment search',
                                onPressed: () {
                                  setState(_search.clear);
                                  _searchFocus.requestFocus();
                                },
                                icon: const Icon(Icons.close_rounded),
                              ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        query.isEmpty
                            ? '${all.length} ${all.length == 1 ? 'attachment' : 'attachments'}'
                            : '${remaining.length} of ${all.length} ${all.length == 1 ? 'attachment' : 'attachments'}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ),
                  Expanded(
                    child: remaining.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  all.isEmpty
                                      ? Icons.attach_file
                                      : Icons.search_off_rounded,
                                  size: 36,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  all.isEmpty
                                      ? 'No attachments'
                                      : 'No matching attachments',
                                  style: Theme.of(context).textTheme.bodyLarge,
                                ),
                              ],
                            ),
                          )
                        : ListView.separated(
                            key: const ValueKey('attachment-gallery-list'),
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            keyboardDismissBehavior:
                                ScrollViewKeyboardDismissBehavior.onDrag,
                            itemCount: remaining.length,
                            separatorBuilder: (_, _) =>
                                const Divider(height: 1, indent: 68),
                            itemBuilder: (_, index) => _AttachmentTile(
                              thumbnails: widget.thumbnails,
                              key: ValueKey(
                                'gallery/${widget.owner}/${remaining[index].id}',
                              ),
                              model: model,
                              entry: remaining[index],
                              expanded: true,
                              disambiguate: duplicates.contains(
                                remaining[index].name.toLowerCase(),
                              ),
                              onAction: widget.onAction,
                              selectionMode: _selecting,
                              selected: _selected.contains(remaining[index].id),
                              onToggleSelection:
                                  _busy ||
                                      (!available.contains(
                                            remaining[index].id,
                                          ) &&
                                          !_selected.contains(
                                            remaining[index].id,
                                          ))
                                  ? null
                                  : () => _toggle(remaining[index]),
                            ),
                          ),
                  ),
                  if (_selecting)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_actionError != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text(
                                _actionError!,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.error,
                                    ),
                              ),
                            ),
                          if (_busy) ...[
                            if (!model.attachmentJobsNotifier.value.any(
                              (j) =>
                                  j.progress.value.active &&
                                  j.progress.value.owner == widget.owner &&
                                  j.progress.value.batch &&
                                  j.progress.value.operation ==
                                      AttachmentJobOperation.export,
                            )) ...[
                              const LinearProgressIndicator(minHeight: 2),
                              const SizedBox(height: 8),
                              Text(
                                'Preparing selected attachments…',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                            for (final job
                                in model.attachmentJobsNotifier.value.where(
                                  (j) =>
                                      j.progress.value.active &&
                                      j.progress.value.owner == widget.owner &&
                                      j.progress.value.batch &&
                                      j.progress.value.operation ==
                                          AttachmentJobOperation.export,
                                ))
                              MobileAttachmentJobProgress(
                                key: ValueKey(
                                  'gallery-export-${job.progress.value.id}',
                                ),
                                state: job,
                                model: model,
                                cancelLabel: 'Cancel export',
                              ),
                          ],
                          OverflowBar(
                            alignment: MainAxisAlignment.spaceEvenly,
                            spacing: 12,
                            overflowSpacing: 8,
                            children: [
                              FilledButton.tonalIcon(
                                key: const ValueKey(
                                  'attachment-share-selected',
                                ),
                                onPressed:
                                    actionable && !model.hasAttachmentJobs
                                    ? _shareSelected
                                    : null,
                                icon: const Icon(
                                  Icons.ios_share_rounded,
                                  size: 20,
                                ),
                                label: const Text('Share / Save'),
                              ),
                              OutlinedButton.icon(
                                key: const ValueKey(
                                  'attachment-remove-selected',
                                ),
                                onPressed:
                                    actionable && !model.hasAttachmentJobs
                                    ? _removeSelected
                                    : null,
                                icon: const Icon(
                                  Icons.delete_outline_rounded,
                                  size: 20,
                                ),
                                label: const Text('Remove'),
                              ),
                            ],
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
  );
}
