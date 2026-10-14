import 'package:flutter/material.dart';

import '../models/attachment_job.dart';
import '../viewmodels/content_viewmodel.dart';

/// Structural events rebuild the strip; byte events rebuild its header and the
/// individual card only. The editor never subscribes to progress.
class AttachmentJobPanel extends StatefulWidget {
  const AttachmentJobPanel({super.key, required this.viewModel});
  final ContentViewModel viewModel;
  @override
  State<AttachmentJobPanel> createState() => _AttachmentJobPanelState();
}

class _AttachmentJobPanelState extends State<AttachmentJobPanel> {
  bool expanded = true;
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: widget.viewModel.isLockedNotifier,
    builder: (context, locked, _) =>
        locked ? const SizedBox.shrink() : _buildJobs(context),
  );

  Widget _buildJobs(
    BuildContext context,
  ) => ValueListenableBuilder<List<AttachmentJobState>>(
    valueListenable: widget.viewModel.attachmentJobsNotifier,
    builder: (context, jobs, _) {
      if (jobs.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListenableBuilder(
              listenable: Listenable.merge(jobs.map((job) => job.progress)),
              builder: (context, _) {
                final active = jobs
                    .where((job) => job.progress.value.active)
                    .toList();
                final batch = active
                    .where((job) => job.progress.value.batch)
                    .toList();
                return Row(
                  children: [
                    TextButton.icon(
                      onPressed: () => setState(() => expanded = !expanded),
                      icon: Icon(
                        expanded ? Icons.expand_less : Icons.expand_more,
                      ),
                      label: Text(
                        batch.isNotEmpty
                            ? 'Password change: ${jobs.where((j) => j.progress.value.batch && j.progress.value.originalAttachmentId != null).length} files'
                            : 'Attachments: ${active.length} active operations',
                      ),
                    ),
                    const Spacer(),
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
            if (expanded)
              SizedBox(
                height: 160 * MediaQuery.textScalerOf(context).scale(1),
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: jobs.length,
                  separatorBuilder: (_, index) => const SizedBox(width: 8),
                  itemBuilder: (context, index) =>
                      _JobCard(job: jobs[index], viewModel: widget.viewModel),
                ),
              ),
          ],
        ),
      );
    },
  );
}

class _JobCard extends StatelessWidget {
  const _JobCard({required this.job, required this.viewModel});
  final AttachmentJobState job;
  final ContentViewModel viewModel;
  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<AttachmentJobSnapshot>(
        valueListenable: job.progress,
        builder: (context, state, _) {
          final label = switch (state.phase) {
            AttachmentJobPhase.queued => 'Queued',
            AttachmentJobPhase.preparing => 'Preparing',
            AttachmentJobPhase.decrypting => 'Decrypting',
            AttachmentJobPhase.encrypting => 'Encrypting',
            AttachmentJobPhase.verifying => 'Verifying',
            AttachmentJobPhase.finalizing => 'Finalizing',
            AttachmentJobPhase.completed => 'Completed',
            AttachmentJobPhase.cancelled => 'Cancelled',
            AttachmentJobPhase.failed => 'Failed',
          };
          final total = state.total;
          final fraction = total != null && total > 0
              ? (state.bytes / total).clamp(0.0, 1.0)
              : null;
          return SizedBox(
            width: 246,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      state.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(label, style: Theme.of(context).textTheme.labelSmall),
                    if (state.error != null)
                      Tooltip(
                        message: state.error!,
                        child: Text(
                          state.error!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ),
                    if (state.active) ...[
                      const SizedBox(height: 6),
                      LinearProgressIndicator(
                        value: state.phase == AttachmentJobPhase.finalizing
                            ? null
                            : fraction,
                      ),
                      if (total != null)
                        Text(
                          '${state.bytes} / $total bytes',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                    ],
                    const Spacer(),
                    if (state.phase == AttachmentJobPhase.failed)
                      Row(
                        children: [
                          if (!state.batch)
                            Flexible(
                              child: TextButton(
                                onPressed: () =>
                                    viewModel.retryAttachmentJob(state.id),
                                child: const Text('Retry'),
                              ),
                            ),
                          Flexible(
                            child: TextButton(
                              onPressed: () => viewModel
                                  .removePendingAttachmentJob(state.id),
                              child: const Text('Remove pending'),
                            ),
                          ),
                        ],
                      )
                    else if (state.cancellable)
                      TextButton(
                        onPressed: () =>
                            viewModel.cancelAttachmentJob(state.id),
                        child: const Text('Cancel'),
                      )
                    else if (!state.active)
                      TextButton(
                        onPressed: () =>
                            viewModel.removePendingAttachmentJob(state.id),
                        child: const Text('Dismiss'),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      );
}
