import '../../../core/theme/app_tooltip.dart';
import '../../../core/theme/app_motion.dart';
import 'attachment_presentation.dart';
import 'package:flutter/material.dart';

import '../models/attachment_job.dart';
import '../viewmodels/content_viewmodel.dart';

/// Structural events rebuild the panel; byte events rebuild the individual
/// status row only. The editor never subscribes to progress.
class AttachmentJobPanel extends StatefulWidget {
  const AttachmentJobPanel({
    super.key,
    required this.viewModel,
    this.auxiliaryOnly = false,
    this.excludedOperations = const {},
  });
  final bool auxiliaryOnly;

  /// Operations presented by a platform-specific progress surface instead.
  final Set<AttachmentJobOperation> excludedOperations;
  final ContentViewModel viewModel;
  @override
  State<AttachmentJobPanel> createState() => _AttachmentJobPanelState();
}

class _AttachmentJobPanelState extends State<AttachmentJobPanel> {
  bool expanded = true;
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: widget.viewModel.isLockedNotifier,
    builder: (context, locked, _) => locked
        ? const SizedBox.shrink()
        : AnimatedSize(
            key: ValueKey((
              widget.viewModel.draftSession.generation,
              widget.viewModel.currentContentPath,
            )),
            duration: AppMotion.duration(context, AppMotion.panelIn),
            reverseDuration: AppMotion.duration(context, AppMotion.panelOut),
            alignment: Alignment.topLeft,
            child: _buildJobs(context),
          ),
  );

  Widget _buildJobs(
    BuildContext context,
  ) => ValueListenableBuilder<List<AttachmentJobState>>(
    valueListenable: widget.viewModel.attachmentJobsNotifier,
    builder: (context, jobs, _) {
      jobs = jobs
          .where(
            (job) =>
                job.progress.value.operation != AttachmentJobOperation.import &&
                !widget.excludedOperations.contains(
                  job.progress.value.operation,
                ),
          )
          .toList();
      if (widget.auxiliaryOnly) {
        jobs = jobs
            .where(
              (job) =>
                  job.progress.value.operation != AttachmentJobOperation.add &&
                  job.progress.value.operation != AttachmentJobOperation.open &&
                  job.progress.value.operation !=
                      AttachmentJobOperation.thumbnail &&
                  job.progress.value.owner ==
                      widget.viewModel.draftSession.generation,
            )
            .toList();
      }
      if (jobs.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListenableBuilder(
              listenable: Listenable.merge(jobs.map((job) => job.phase)),
              builder: (context, _) {
                final active = jobs
                    .where((job) => job.progress.value.active)
                    .toList();
                final batch = active
                    .where((job) => job.progress.value.batch)
                    .toList();
                final operation = jobs.any((job) => job.progress.value.batch)
                    ? 'Password change'
                    : jobs.every(
                        (job) =>
                            job.progress.value.operation ==
                            AttachmentJobOperation.export,
                      )
                    ? 'Export'
                    : jobs.every(
                        (job) =>
                            job.progress.value.operation ==
                            AttachmentJobOperation.import,
                      )
                    ? 'Import'
                    : 'Background operations';
                return Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    TextButton.icon(
                      onPressed: () => setState(() => expanded = !expanded),
                      icon: AppDisclosure(expanded: expanded),
                      label: Text(
                        active.isEmpty
                            ? operation
                            : '$operation: ${active.length} active',
                      ),
                    ),
                    if (batch.any((job) => job.progress.value.cancellable))
                      TextButton(
                        onPressed: () => widget.viewModel.cancelAttachmentJob(
                          batch.first.progress.value.id,
                        ),
                        child: const Text('Cancel batch'),
                      ),
                    if (active.any(
                      (job) =>
                          job.progress.value.phase ==
                          AttachmentJobPhase.finalizing,
                    ))
                      const Text('Finishing'),
                  ],
                );
              },
            ),
            AppReveal(
              visible: expanded,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: 160 * MediaQuery.textScalerOf(context).scale(1),
                ),
                child: SingleChildScrollView(
                  primary: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var index = 0; index < jobs.length; index++) ...[
                        if (index > 0) const SizedBox(height: 8),
                        _JobRow(
                          key: ValueKey(jobs[index].progress.value.id),
                          job: jobs[index],
                          viewModel: widget.viewModel,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _JobRow extends StatelessWidget {
  const _JobRow({super.key, required this.job, required this.viewModel});
  final AttachmentJobState job;
  final ContentViewModel viewModel;
  @override
  Widget build(
    BuildContext context,
  ) => ValueListenableBuilder<AttachmentJobSnapshot>(
    valueListenable: job.progress,
    builder: (context, state, _) {
      final label = state.detail ?? attachmentPhaseLabel(state.phase);
      final total = state.total;
      final fraction = total != null && total > 0
          ? (state.bytes / total).clamp(0.0, 1.0)
          : null;
      return Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: AppTooltip(
                      message: state.fileName,
                      child: Text(
                        state.fileName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  if (state.cancellable)
                    TextButton(
                      onPressed: () => viewModel.cancelAttachmentJob(state.id),
                      child: const Text('Cancel'),
                    )
                  else if (!state.active &&
                      state.phase != AttachmentJobPhase.failed)
                    TextButton(
                      onPressed: () =>
                          viewModel.removePendingAttachmentJob(state.id),
                      child: const Text('Dismiss'),
                    ),
                ],
              ),
              Text(label, style: Theme.of(context).textTheme.labelSmall),
              if (state.error != null)
                AppTooltip(
                  message: state.error!,
                  child: Text(
                    state.error!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
              if (state.active) ...[
                const SizedBox(height: 6),
                LinearProgressIndicator(
                  value:
                      (state.phase == AttachmentJobPhase.finalizing ||
                          state.phase == AttachmentJobPhase.cancelling)
                      ? null
                      : fraction,
                ),
                if (total != null)
                  Text(
                    '${formatAttachmentBytes(state.bytes)} / ${formatAttachmentBytes(total)}',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
              ],
              if (state.phase == AttachmentJobPhase.failed)
                Wrap(
                  spacing: 8,
                  children: [
                    if (!state.batch)
                      TextButton(
                        onPressed: () => viewModel.retryAttachmentJob(state.id),
                        child: const Text('Retry'),
                      ),
                    TextButton(
                      onPressed: () =>
                          viewModel.removePendingAttachmentJob(state.id),
                      child: const Text('Remove pending'),
                    ),
                  ],
                ),
            ],
          ),
        ),
      );
    },
  );
}
