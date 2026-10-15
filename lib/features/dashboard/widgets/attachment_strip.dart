import 'dart:io';
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
  bool expanded = true;
  final _openIntents = <String>{};
  ContentViewModel get model => widget.viewModel;

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
              final attachments = model.attachmentsNotifier.value;
              final jobs = model.attachmentJobsNotifier.value
                  .where(
                    (j) =>
                        j.progress.value.owner == model.draftSession.generation,
                  )
                  .toList();
              final latest = <String, AttachmentJobState>{};
              for (final job in jobs) {
                final id = job.progress.value.originalAttachmentId;
                if (id != null) latest[id] = job;
              }
              final ids = attachments.map((a) => a.id).toSet();
              final pending = jobs
                  .where(
                    (j) =>
                        j.progress.value.operation ==
                            AttachmentJobOperation.add &&
                        !ids.contains(j.progress.value.id) &&
                        (j.progress.value.active ||
                            j.progress.value.phase ==
                                AttachmentJobPhase.failed),
                  )
                  .toList();
              if (attachments.isEmpty && pending.isEmpty)
                return const SizedBox.shrink();
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
                    if (expanded)
                      SizedBox(
                        height:
                            (jobs.any(
                                  (j) =>
                                      j.progress.value.phase ==
                                      AttachmentJobPhase.failed,
                                )
                                ? 200
                                : jobs.any(
                                    (j) =>
                                        j.progress.value.active ||
                                        j.progress.value.phase ==
                                            AttachmentJobPhase.failed,
                                  )
                                ? 154
                                : 110) *
                            scale,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: attachments.length + pending.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 8),
                          itemBuilder: (context, index) {
                            final attachment = index < attachments.length
                                ? attachments[index]
                                : null;
                            final job = attachment == null
                                ? pending[index - attachments.length]
                                : latest[attachment.id];
                            final key =
                                '${model.draftSession.generation}/${attachment?.id ?? job!.progress.value.id}';
                            return _AttachmentTile(
                              key: ValueKey(key),
                              model: model,
                              attachment: attachment,
                              job: job,
                              onAction: _action,
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
  });
  final ContentViewModel model;
  final AttachmentModel? attachment;
  final AttachmentJobState? job;
  final Future<void> Function(AttachmentAction, AttachmentModel, FocusNode)
  onAction;
  @override
  State<_AttachmentTile> createState() => _AttachmentTileState();
}

class _AttachmentTileState extends State<_AttachmentTile> {
  final _focus = FocusNode();
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

    return SizedBox(
      width: 276,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (cached != null && kind == AttachmentVisualKind.image)
                    Image.file(
                      File(cached.path),
                      width: 24,
                      height: 24,
                      cacheWidth: 120,
                      cacheHeight: 120,
                      errorBuilder: (_, _, _) => Icon(icon, size: 24),
                    )
                  else
                    IconButton(
                      tooltip: 'Open $name',
                      onPressed: attachment == null || active
                          ? null
                          : () => action(AttachmentAction.open),
                      icon: Icon(icon, size: 24),
                    ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Tooltip(
                      message: name,
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  if (attachment != null)
                    TextButton(
                      focusNode: _focus,
                      onPressed: active
                          ? null
                          : () => action(AttachmentAction.open),
                      child: Text('Open', semanticsLabel: 'Open $name'),
                    ),
                  AttachmentMoreButton(
                    fileName: name,
                    enabled: attachment != null && !active,
                    canRemove:
                        attachment != null && !widget.model.hasAttachmentJobs,
                    onSelected: action,
                  ),
                ],
              ),
              if (active || state?.phase == AttachmentJobPhase.failed) ...[
                Semantics(
                  liveRegion: true,
                  child: Text(
                    attachmentPhaseLabel(state!.phase),
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
                if (active) LinearProgressIndicator(value: fraction),
                if (state.error != null)
                  Tooltip(
                    message: state.error!,
                    child: Text(
                      state.error!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  )
                else if (total != null && !waiting)
                  Text(
                    '${formatAttachmentBytes(state.bytes)} / ${formatAttachmentBytes(total)}${fraction == null ? '' : ' · ${(fraction * 100).floor()}%'}',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
              ] else
                Text(
                  '${kind.name} · ${formatAttachmentBytes(attachment?.size ?? 0)}',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              const Spacer(),
              Wrap(
                children: [
                  if (state?.cancellable ?? false)
                    TextButton(
                      onPressed: () =>
                          widget.model.cancelAttachmentJob(state!.id),
                      child: const Text('Cancel'),
                    ),
                  if (attachment == null &&
                      state?.phase == AttachmentJobPhase.failed) ...[
                    TextButton(
                      onPressed: () =>
                          widget.model.retryAttachmentJob(state!.id),
                      child: const Text('Retry'),
                    ),
                    TextButton(
                      onPressed: () =>
                          widget.model.removePendingAttachmentJob(state!.id),
                      child: const Text('Remove pending'),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
