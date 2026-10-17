import 'package:flutter/material.dart';
import '../../../core/platform/mobile_job_binding.dart';
import '../models/attachment_job.dart';
import '../viewmodels/content_viewmodel.dart';

/// Per-job access also works when Android notifications are disabled.
class MobileJobNotifications extends StatelessWidget {
  const MobileJobNotifications({
    super.key,
    required this.jobs,
    required this.model,
    this.selectedId,
  });
  final MobileJobBinding jobs;
  final ContentViewModel model;
  final String? selectedId;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Notifications'),
    content: SizedBox(
      width: 440,
      height: MediaQuery.sizeOf(context).height * .5,
      child: ValueListenableBuilder<List<AttachmentJobState>>(
        valueListenable: model.attachmentJobsNotifier,
        builder: (context, states, _) => ListenableBuilder(
          listenable: Listenable.merge([
            jobs.retained,
            for (final state in states) state.progress,
          ]),
          builder: (context, _) {
            final active = [
              for (final state in states)
                if (state.progress.value.active) state.progress.value,
            ];
            final activeIds = active.map((job) => job.id).toSet();
            final interrupted = jobs.retained.value
                .where((record) => !activeIds.contains(record['id']))
                .toList();
            final entries = <Widget>[
              for (final job in active) _active(context, job),
              for (final record in interrupted)
                ListTile(
                  selected: record['id'] == selectedId,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.pause_circle_outline),
                  title: Text(
                    record['fileName'] as String? ?? 'Interrupted operation',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: const Text('Interrupted · Tap to review recovery'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.pop(context, record['id'] as String),
                ),
            ];
            if (entries.isEmpty) {
              return const Center(child: Text('No pending jobs.'));
            }
            return ListView.separated(
              itemCount: entries.length,
              itemBuilder: (_, index) => entries[index],
              separatorBuilder: (_, _) => const Divider(height: 16),
            );
          },
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Done'),
      ),
    ],
  );

  Widget _active(BuildContext context, AttachmentJobSnapshot job) {
    final progress = job.total != null && job.total! > 0
        ? (job.bytes / job.total!).clamp(0.0, 1.0)
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          selected: job.id == selectedId,
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.sync),
          title: Text(
            job.fileName,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text('${_operation(job.operation)} · ${_phase(job.phase)}'),
          trailing: job.cancellable
              ? IconButton(
                  tooltip: 'Cancel this job',
                  icon: const Icon(Icons.close),
                  onPressed: () => model.cancelAttachmentJob(job.id),
                )
              : null,
        ),
        LinearProgressIndicator(value: progress, minHeight: 2),
      ],
    );
  }

  String _operation(AttachmentJobOperation operation) => switch (operation) {
    AttachmentJobOperation.add => 'Attach',
    AttachmentJobOperation.open => 'Open',
    AttachmentJobOperation.protection => 'Protection',
    AttachmentJobOperation.export => 'Export',
    AttachmentJobOperation.import => 'Import',
  };

  String _phase(AttachmentJobPhase phase) => switch (phase) {
    AttachmentJobPhase.queued => 'Queued',
    AttachmentJobPhase.preparing => 'Preparing',
    AttachmentJobPhase.decrypting => 'Decrypting',
    AttachmentJobPhase.encrypting => 'Encrypting',
    AttachmentJobPhase.verifying => 'Verifying',
    AttachmentJobPhase.finalizing => 'Finishing safely',
    AttachmentJobPhase.cancelling => 'Cancelling',
    _ => phase.name,
  };
}
