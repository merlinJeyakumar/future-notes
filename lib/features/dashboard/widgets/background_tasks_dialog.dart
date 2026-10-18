import 'package:flutter/material.dart';
import '../../../core/platform/mobile_job_binding.dart';
import '../models/attachment_job.dart';
import '../viewmodels/content_viewmodel.dart';
import 'attachment_presentation.dart' show formatAttachmentBytes;

/// Per-job access also works when Android notifications are disabled.
class BackgroundTasksDialog extends StatefulWidget {
  const BackgroundTasksDialog({
    super.key,
    this.jobs,
    this.selectExportJobs = true,
    required this.model,
    this.selectedId,
  });
  final MobileJobBinding? jobs;
  final bool selectExportJobs;
  final ContentViewModel model;
  final String? selectedId;
  @override
  State<BackgroundTasksDialog> createState() => _BackgroundTasksDialogState();
}

class _BackgroundTasksDialogState extends State<BackgroundTasksDialog> {
  final _seen = <String, AttachmentJobSnapshot>{};
  final _observed = <String, AttachmentJobState>{};
  ContentViewModel get model => widget.model;
  MobileJobBinding? get jobs => widget.jobs;
  String? get selectedId => widget.selectedId;

  void _capture() {
    for (final state in model.attachmentJobsNotifier.value) {
      final snapshot = state.progress.value;
      if (snapshot.active || _seen.containsKey(snapshot.id))
        _seen[snapshot.id] = snapshot;
    }
  }

  void _progress() {
    _capture();
    if (mounted) setState(() {});
  }

  void _sync() {
    final states = model.attachmentJobsNotifier.value;
    final currentIds = states.map((state) => state.progress.value.id).toSet();
    // Keep acknowledged terminal results, never an orphaned live snapshot.
    _seen.removeWhere(
      (id, snapshot) => snapshot.active && !currentIds.contains(id),
    );
    for (final state in _observed.values.toList()) {
      if (!states.contains(state)) {
        state.progress.removeListener(_progress);
        _observed.remove(state.progress.value.id);
      }
    }
    for (final state in states) {
      if (!_observed.containsKey(state.progress.value.id)) {
        _observed[state.progress.value.id] = state;
        state.progress.addListener(_progress);
      }
    }
    _progress();
  }

  @override
  void initState() {
    super.initState();
    model.attachmentJobsNotifier.addListener(_sync);
    _sync();
  }

  @override
  void dispose() {
    model.attachmentJobsNotifier.removeListener(_sync);
    for (final state in _observed.values) {
      state.progress.removeListener(_progress);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Background tasks'),
    content: SizedBox(
      width: 440,
      height: MediaQuery.sizeOf(context).height * .5,
      child: ValueListenableBuilder<List<AttachmentJobState>>(
        valueListenable: model.attachmentJobsNotifier,
        builder: (context, states, _) => ListenableBuilder(
          listenable: Listenable.merge([
            if (jobs != null) jobs!.retained,
            for (final state in states) state.progress,
          ]),
          builder: (context, _) {
            final active = _seen.values.toList();
            final activeIds = active.map((job) => job.id).toSet();
            final interrupted =
                (jobs?.retained.value ?? <Map<String, dynamic>>[])
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
                  trailing: record['notificationDismissed'] == true
                      ? const Tooltip(
                          message: 'Notification dismissed',
                          child: Icon(Icons.notifications_off_outlined),
                        )
                      : IconButton(
                          tooltip: 'Dismiss notification',
                          icon: const Icon(Icons.close),
                          onPressed: () async {
                            try {
                              await jobs!.dismissInterruptedNotification(
                                record['id'] as String,
                              );
                            } catch (_) {
                              if (context.mounted)
                                ScaffoldMessenger.maybeOf(
                                  context,
                                )?.showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'The task could not be dismissed. Please retry.',
                                    ),
                                  ),
                                );
                            }
                          },
                        ),
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
    final file = job.fileProgress;
    String metric(int bytes, int total) =>
        '${formatAttachmentBytes(bytes)} / ${formatAttachmentBytes(total)} · ${((bytes / total).clamp(0.0, 1.0) * 100).round()}%';
    final progress = job.total != null && job.total! > 0
        ? (job.bytes / job.total!).clamp(0.0, 1.0)
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          selected: job.id == selectedId,
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            job.active
                ? Icons.sync
                : job.phase == AttachmentJobPhase.completed
                ? Icons.check_circle_outline
                : job.phase == AttachmentJobPhase.cancelled
                ? Icons.cancel_outlined
                : Icons.error_outline,
          ),
          title: Text(
            job.fileName,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            '${_operation(job.operation)} · ${job.active ? job.detail ?? _phase(job.phase) : job.error ?? _phase(job.phase)}'
            '${job.active && file != null && file.total > 0 && file.overallTotal > 0 ? '\nCurrent file: ${metric(file.bytes, file.total)}\nOverall saving: ${metric(file.overallBytes, file.overallTotal)}' : ''}',
          ),
          onTap:
              widget.selectExportJobs &&
                  job.active &&
                  job.operation == AttachmentJobOperation.export
              ? () => Navigator.pop(context, job.id)
              : null,
          trailing: job.cancellable
              ? IconButton(
                  tooltip: 'Cancel this job',
                  icon: const Icon(Icons.close),
                  onPressed: () => model.cancelAttachmentJob(job.id),
                )
              : null,
        ),
        if (job.active) LinearProgressIndicator(value: progress, minHeight: 2),
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
    AttachmentJobPhase.completed => 'Completed',
    AttachmentJobPhase.failed => 'Failed',
    AttachmentJobPhase.cancelled => 'Cancelled',
  };
}
