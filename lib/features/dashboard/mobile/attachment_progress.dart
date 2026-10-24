import 'package:flutter/material.dart';
import '../../../core/theme/app_motion.dart';
import '../models/attachment_job.dart';
import '../viewmodels/content_viewmodel.dart';
import '../widgets/attachment_presentation.dart';

/// Current-note preparation is visible independently of the attachment gallery.
/// Byte updates rebuild only their status row, never the editor or job owner.
class MobileAttachmentProgress extends StatefulWidget {
  const MobileAttachmentProgress({super.key, required this.model});
  final ContentViewModel model;

  @override
  State<MobileAttachmentProgress> createState() =>
      _MobileAttachmentProgressState();
}

class _MobileAttachmentProgressState extends State<MobileAttachmentProgress> {
  final _scroll = ScrollController(keepScrollOffset: false);

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: widget.model.isLockedNotifier,
    builder: (context, locked, _) => locked
        ? const SizedBox.shrink()
        : AnimatedSize(
            duration: AppMotion.duration(context, AppMotion.panelIn),
            reverseDuration: AppMotion.duration(context, AppMotion.panelOut),
            alignment: Alignment.topLeft,
            child: ValueListenableBuilder<List<AttachmentJobState>>(
              valueListenable: widget.model.attachmentJobsNotifier,
              builder: (context, states, _) {
                final jobs = states.where((state) {
                  final job = state.progress.value;
                  return job.owner == widget.model.draftSession.generation &&
                      job.active &&
                      (job.operation == AttachmentJobOperation.add ||
                          job.operation == AttachmentJobOperation.open ||
                          job.operation == AttachmentJobOperation.thumbnail ||
                          job.operation == AttachmentJobOperation.export);
                }).toList();
                if (jobs.isEmpty) return const SizedBox.shrink();
                final available =
                    MediaQuery.sizeOf(context).height -
                    MediaQuery.viewInsetsOf(context).bottom;
                return Card(
                  key: const ValueKey('mobile-attachment-progress'),
                  margin: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: (available * .2).clamp(96.0, 144.0),
                    ),
                    child: Scrollbar(
                      controller: _scroll,
                      thumbVisibility: jobs.length > 1,
                      child: SingleChildScrollView(
                        controller: _scroll,
                        primary: false,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (
                              var index = 0;
                              index < jobs.length;
                              index++
                            ) ...[
                              if (index > 0) const Divider(height: 1),
                              MobileAttachmentJobProgress(
                                key: ValueKey(jobs[index].progress.value.id),
                                state: jobs[index],
                                model: widget.model,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
  );
}

/// One job's live byte progress, shared by the editor and export gallery.
/// Listening here keeps progress ticks from rebuilding either file list.
class MobileAttachmentJobProgress extends StatelessWidget {
  const MobileAttachmentJobProgress({
    super.key,
    required this.state,
    required this.model,
    this.cancelLabel,
  });
  final AttachmentJobState state;
  final ContentViewModel model;
  final String? cancelLabel;

  @override
  Widget build(
    BuildContext context,
  ) => ValueListenableBuilder<AttachmentJobSnapshot>(
    valueListenable: state.progress,
    builder: (context, job, _) {
      if (!job.active) return const SizedBox.shrink();
      final total = job.total;
      final waiting =
          job.phase == AttachmentJobPhase.cancelling ||
          (job.phase == AttachmentJobPhase.finalizing && total == null);
      final fraction = !waiting && total != null && total > 0
          ? (job.bytes / total).clamp(0.0, 1.0)
          : null;
      final batchExport =
          job.batch && job.operation == AttachmentJobOperation.export;
      final title = Text(
        job.fileName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelLarge,
      );
      final details = <Widget>[
        Text(
          job.detail ?? attachmentPhaseLabel(job.phase),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (batchExport && job.detail != null)
          Text(
            attachmentPhaseLabel(job.phase),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        const SizedBox(height: 4),
        LinearProgressIndicator(value: fraction, minHeight: 2),
        if (!waiting && total != null)
          Text(
            '${formatAttachmentBytes(job.bytes)} / ${formatAttachmentBytes(total)}${fraction == null ? '' : ' · ${(fraction * 100).floor()}%'}',
            maxLines: batchExport ? null : 1,
            overflow: batchExport ? null : TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
      ];
      final cancel = cancelLabel != null
          ? TextButton(
              onPressed: () => model.cancelAttachmentJob(job.id),
              child: Text(cancelLabel!),
            )
          : IconButton(
              tooltip: 'Cancel attachment operation',
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              icon: const Icon(Icons.close, size: 20),
              onPressed: () => model.cancelAttachmentJob(job.id),
            );
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: batchExport
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  OverflowBar(
                    alignment: MainAxisAlignment.spaceBetween,
                    overflowAlignment: OverflowBarAlignment.end,
                    children: [title, if (job.cancellable) cancel],
                  ),
                  ...details,
                ],
              )
            : Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [title, ...details],
                    ),
                  ),
                  if (job.cancellable) cancel,
                ],
              ),
      );
    },
  );
}
