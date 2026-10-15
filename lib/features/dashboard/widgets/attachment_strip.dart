import 'dart:io';
import 'package:flutter/material.dart';
import '../models/attachment_job.dart';
import '../models/note_model.dart';
import '../viewmodels/content_viewmodel.dart';
import 'attachment_viewer.dart';

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
  ContentViewModel get model => widget.viewModel;
  Future<void> _action(
    AttachmentAction action,
    AttachmentModel attachment,
  ) async {
    switch (action) {
      case AttachmentAction.open:
        final result = await model.openAttachment(attachment);
        if (!mounted || !result.isSuccess || model.isLocked) return;
        await showDialog<void>(
          context: context,
          builder: (_) => AttachmentViewer(
            viewModel: model,
            attachment: attachment,
            file: result.value!,
            playerFactory: widget.playerFactory,
          ),
        );
      case AttachmentAction.system:
        await model.openAttachment(attachment, system: true);
      case AttachmentAction.save:
        await model.exportAttachment(attachment);
      case AttachmentAction.remove:
        await model.removeAttachment(attachment.id);
    }
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: model.isLockedNotifier,
    builder: (_, locked, child) => locked
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
                    (job) =>
                        job.progress.value.owner ==
                        model.draftSession.generation,
                  )
                  .toList();
              final pending = jobs
                  .where(
                    (job) =>
                        job.progress.value.operation ==
                            AttachmentJobOperation.add &&
                        !attachments.any(
                          (a) => a.id == job.progress.value.id,
                        ) &&
                        job.progress.value.phase !=
                            AttachmentJobPhase.completed &&
                        job.progress.value.phase !=
                            AttachmentJobPhase.cancelled,
                  )
                  .toList();
              if (attachments.isEmpty && pending.isEmpty) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ListenableBuilder(
                      listenable: Listenable.merge(jobs.map((j) => j.progress)),
                      builder: (context, _) {
                        final active = jobs
                            .where((job) => job.progress.value.active)
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
                        height: 180 * MediaQuery.textScalerOf(context).scale(1),
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: attachments.length + pending.length,
                          separatorBuilder: (_, index) =>
                              const SizedBox(width: 8),
                          itemBuilder: (context, index) {
                            if (index >= attachments.length) {
                              return _pending(
                                pending[index - attachments.length],
                              );
                            }
                            final attachment = attachments[index];
                            final matching = jobs
                                .where(
                                  (j) =>
                                      j.progress.value.originalAttachmentId ==
                                      attachment.id,
                                )
                                .toList();
                            return matching.isEmpty
                                ? _card(attachment, null)
                                : ValueListenableBuilder<AttachmentJobSnapshot>(
                                    valueListenable: matching.last.progress,
                                    builder: (_, state, child) =>
                                        _card(attachment, state),
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
  Widget _progress(AttachmentJobSnapshot state) {
    final label = switch (state.phase) {
      AttachmentJobPhase.queued => 'Queued',
      AttachmentJobPhase.preparing => 'Preparing',
      AttachmentJobPhase.decrypting => 'Decrypting',
      AttachmentJobPhase.encrypting => 'Encrypting',
      AttachmentJobPhase.verifying => 'Verifying',
      AttachmentJobPhase.finalizing => 'Finalizing',
      AttachmentJobPhase.completed => 'Ready',
      AttachmentJobPhase.cancelled => 'Cancelled',
      AttachmentJobPhase.failed => 'Failed',
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelSmall),
        if (state.active)
          LinearProgressIndicator(
            value:
                state.phase == AttachmentJobPhase.finalizing ||
                    state.total == null ||
                    state.total == 0
                ? null
                : (state.bytes / state.total!).clamp(0, 1),
          ),
        if (state.total != null && state.active)
          Text(
            '${state.bytes} / ${state.total} bytes',
            style: Theme.of(context).textTheme.labelSmall,
          ),
        if (state.error != null)
          Tooltip(
            message: state.error!,
            child: Text(
              state.error!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
    );
  }

  Widget _container(List<Widget> children) => SizedBox(
    width: 240,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    ),
  );
  Widget _card(AttachmentModel attachment, AttachmentJobSnapshot? state) {
    final cached = model.cachedAttachment(attachment.id);
    final extension = attachment.fileName.split('.').last.toLowerCase();
    final image =
        cached != null &&
        ['jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp'].contains(extension);
    return _container([
      Row(
        children: [
          Expanded(
            child: Text(
              attachment.fileName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          AttachmentMoreButton(
            onSelected: (action) => _action(action, attachment),
            enabled: state?.active != true,
            canRemove: !model.hasAttachmentJobs,
          ),
        ],
      ),
      Expanded(
        child: InkWell(
          onTap: state?.active == true
              ? null
              : () => _action(AttachmentAction.open, attachment),
          child: Center(
            child: image
                ? Image.file(
                    File(cached.path),
                    cacheWidth: 120,
                    cacheHeight: 120,
                    errorBuilder: (_, error, stack) =>
                        const Icon(Icons.insert_drive_file),
                  )
                : Icon(
                    extension == 'mp4'
                        ? Icons.play_circle_outline
                        : Icons.insert_drive_file,
                    size: 32,
                  ),
          ),
        ),
      ),
      if (state != null &&
          (state.active || state.phase == AttachmentJobPhase.failed))
        _progress(state),
      if (state?.cancellable == true)
        TextButton(
          onPressed: () => model.cancelAttachmentJob(state!.id),
          child: const Text('Cancel'),
        ),
    ]);
  }

  Widget _pending(AttachmentJobState job) =>
      ValueListenableBuilder<AttachmentJobSnapshot>(
        valueListenable: job.progress,
        builder: (_, state, child) => _container([
          Row(
            children: [
              Expanded(
                child: Text(
                  state.fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              AttachmentMoreButton(
                enabled: false,
                canRemove: state.phase != AttachmentJobPhase.finalizing,
                onSelected: (action) async {
                  if (action == AttachmentAction.remove) {
                    await model.cancelAttachmentJob(state.id);
                    model.removePendingAttachmentJob(state.id);
                  }
                },
              ),
            ],
          ),
          _progress(state),
          const Spacer(),
          if (state.cancellable)
            TextButton(
              onPressed: () => model.cancelAttachmentJob(state.id),
              child: const Text('Cancel'),
            ),
          if (state.phase == AttachmentJobPhase.failed)
            Row(
              children: [
                Flexible(
                  child: TextButton(
                    onPressed: () => model.retryAttachmentJob(state.id),
                    child: const Text('Retry'),
                  ),
                ),
                Flexible(
                  child: TextButton(
                    onPressed: () => model.removePendingAttachmentJob(state.id),
                    child: const Text('Remove pending'),
                  ),
                ),
              ],
            ),
        ]),
      );
}
