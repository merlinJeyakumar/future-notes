import 'dart:io';
import 'dart:math' as math;
import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import '../models/attachment_job.dart';
import '../models/note_model.dart';
import '../viewmodels/content_viewmodel.dart';
import 'attachment_viewer.dart';
import 'attachment_presentation.dart';

class AttachmentStrip extends StatefulWidget {
  const AttachmentStrip({
    super.key,
    required this.viewModel,
    this.playerFactory,
  });
  final ContentViewModel viewModel;
  final AttachmentPlayerFactory? playerFactory;
  @override
  State<AttachmentStrip> createState() => _AttachmentStripState();
}

class _AttachmentStripState extends State<AttachmentStrip> {
  bool expanded = false;
  late int _owner;
  late bool _locked;
  String? _path;
  final _openIntents = <String>{};
  ContentViewModel get model => widget.viewModel;

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
  }

  @override
  void didUpdateWidget(covariant AttachmentStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
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
    super.dispose();
  }

  Future<void> _action(
    AttachmentAction action,
    AttachmentModel attachment,
    FocusNode focus,
  ) async {
    final owner = model.draftSession.generation;
    final credential = model.draftSession.credentialGeneration;
    final path = model.currentContentPath;
    final key = '$owner/$credential/$path/${attachment.id}';
    bool current() =>
        mounted &&
        !model.isLocked &&
        owner == model.draftSession.generation &&
        credential == model.draftSession.credentialGeneration &&
        path == model.currentContentPath &&
        model.attachments.any((a) => a.id == attachment.id);
    if (!current()) return;
    if (action == AttachmentAction.open || action == AttachmentAction.system) {
      if (!_openIntents.add(key)) return;
      try {
        final result = await model.openAttachment(
          attachment,
          system: action == AttachmentAction.system,
        );
        if (!mounted ||
            !current() ||
            !result.isSuccess ||
            action == AttachmentAction.system) {
          return;
        }
        await showDialog<void>(
          context: context,
          builder: (_) => AttachmentViewer(
            viewModel: model,
            attachment: attachment,
            file: result.value!,
            playerFactory: widget.playerFactory,
          ),
        );
        if (current() && focus.context != null && focus.canRequestFocus) {
          focus.requestFocus();
        }
      } finally {
        _openIntents.remove(key);
      }
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
    await showDialog<void>(
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
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
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
                        j.progress.value.owner == model.draftSession.generation,
                  )
                  .toList();
              final attachments = model.attachmentsNotifier.value;
              final scale = MediaQuery.textScalerOf(context).scale(1);
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListenableBuilder(
                      listenable: Listenable.merge(jobs.map((j) => j.phase)),
                      builder: (context, _) {
                        final active = jobs
                            .where((j) => j.progress.value.active)
                            .length;
                        return TextButton.icon(
                          onPressed: () => setState(() => expanded = !expanded),
                          icon: Icon(
                            expanded ? Icons.expand_less : Icons.expand_more,
                          ),
                          label: Text(
                            'Attachments (${attachments.length})${active == 0 ? '' : ' · $active background operation${active == 1 ? '' : 's'}'}',
                          ),
                        );
                      },
                    ),
                    SizedBox(
                      key: const ValueKey('attachment-dock-items'),
                      height: _tileHeight(expanded) * scale,
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final maxSlots =
                              ((constraints.maxWidth + 8) /
                                      (expanded ? 84 : 64))
                                  .floor()
                                  .clamp(2, 5);
                          final maximumVisible = math.min(4, maxSlots);
                          final visibleCount = entries.length > maximumVisible
                              ? math.min(4, maxSlots - 1)
                              : entries.length;
                          final hidden = entries.length - visibleCount;
                          final slots = visibleCount + (hidden > 0 ? 1 : 0);
                          final width = math.min(
                            expanded ? 96.0 : 56.0,
                            (constraints.maxWidth - (slots - 1) * 8) / slots,
                          );
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (var index = 0; index < slots; index++) ...[
                                if (index > 0) const SizedBox(width: 8),
                                SizedBox(
                                  width: width,
                                  child: index == visibleCount
                                      ? Tooltip(
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
                                            onPressed: () =>
                                                _showRemaining(visibleCount),
                                            child: !expanded
                                                ? FittedBox(
                                                    fit: BoxFit.scaleDown,
                                                    child: Text('+$hidden'),
                                                  )
                                                : Column(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment
                                                            .center,
                                                    children: [
                                                      const Icon(Icons.add),
                                                      Text('+$hidden'),
                                                    ],
                                                  ),
                                          ),
                                        )
                                      : _AttachmentTile(
                                          key: ValueKey(
                                            '${model.draftSession.generation}/${entries[index].id}',
                                          ),
                                          model: model,
                                          attachment: entries[index].attachment,
                                          job: entries[index].job,
                                          expanded: expanded,
                                          onAction: _action,
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
              );
            },
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
  });
  final ContentViewModel model;
  final bool expanded;
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
        state?.phase == AttachmentJobPhase.finalizing ||
        state?.phase == AttachmentJobPhase.cancelling;
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
    final canOpen = attachment != null && !active;
    final nameStyle = Theme.of(context).textTheme.labelMedium;
    final progressLabel = state == null
        ? ''
        : '${attachmentPhaseLabel(state.phase)}${total == null || waiting ? '' : ' · ${formatAttachmentBytes(state.bytes)} / ${formatAttachmentBytes(total)}${fraction == null ? '' : ' · ${(fraction * 100).floor()}%'}'}';
    final more = AttachmentMoreButton(
      compact: true,
      fileName: name,
      enabled: attachment != null && !active,
      canRemove: attachment != null && !widget.model.hasAttachmentJobs,
      onSelected: action,
      onCancel: !expanded && (state?.cancellable ?? false)
          ? () => widget.model.cancelAttachmentJob(state!.id)
          : null,
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
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: Tooltip(
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
            onTap: canOpen ? () => action(AttachmentAction.open) : null,
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
                                  child: failed
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
                              attachmentPhaseLabel(state!.phase),
                            ),
                          ),
                          if (active) LinearProgressIndicator(value: fraction),
                          if (state.error != null)
                            Tooltip(
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
      final remaining = _entries(model).skip(widget.startIndex).toList();
      return AlertDialog(
        title: const Text('More attachments'),
        content: SizedBox(
          width: 600,
          height: MediaQuery.sizeOf(context).height * .55,
          child: remaining.isEmpty
              ? const Center(child: Text('No more attachments'))
              : SingleChildScrollView(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final entry in remaining)
                        ListenableBuilder(
                          key: ValueKey('overflow/${widget.owner}/${entry.id}'),
                          listenable:
                              entry.job?.phase ?? model.attachmentsNotifier,
                          builder: (context, _) => SizedBox(
                            height:
                                _tileHeight(true) *
                                MediaQuery.textScalerOf(context).scale(1),
                            child: _AttachmentTile(
                              model: model,
                              attachment: entry.attachment,
                              job: entry.job,
                              expanded: true,
                              onAction: widget.onAction,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      );
    },
  );
}
