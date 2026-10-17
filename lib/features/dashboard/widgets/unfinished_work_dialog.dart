import 'package:flutter/material.dart';
import '../../../core/platform/mobile_job_binding.dart';
import '../viewmodels/content_viewmodel.dart';

class UnfinishedWorkDialog extends StatefulWidget {
  const UnfinishedWorkDialog({
    super.key,
    required this.jobs,
    required this.model,
    required this.onOpenNote,
    this.jobId,
  });
  final MobileJobBinding jobs;
  final ContentViewModel model;
  final VoidCallback onOpenNote;
  final String? jobId;
  @override
  State<UnfinishedWorkDialog> createState() => _UnfinishedWorkDialogState();
}

class _UnfinishedWorkDialogState extends State<UnfinishedWorkDialog> {
  final _busy = <String>{};
  final _messages = <String, String>{};
  Future<void> _retry(Map<String, dynamic> record) async {
    final id = record['id'] as String;
    if (!_busy.add(id)) return;
    setState(() {});
    try {
      final result = await widget.model.retryInterruptedAttachment(record);
      if (result.isSuccess) await widget.jobs.acknowledgeInterrupted(id);
      if (mounted) _messages[id] = result.message ?? 'Attachment recovered.';
    } catch (_) {
      if (mounted)
        _messages[id] =
            'Recovery could not be acknowledged. Its record was retained.';
    }
    if (mounted) setState(() => _busy.remove(id));
  }

  Future<void> _discard(Map<String, dynamic> record) async {
    final id = record['id'] as String;
    if (!_busy.add(id)) return;
    setState(() {});
    try {
      await widget.model.discardInterruptedSource(record);
      await widget.jobs.acknowledgeInterrupted(id);
    } catch (_) {
      _messages[id] = 'The record could not be removed. It was retained.';
    }
    if (mounted) setState(() => _busy.remove(id));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.jobId == null ? 'Unfinished work' : 'Interrupted job'),
    content: SizedBox(
      width: 440,
      height: MediaQuery.sizeOf(context).height * .55,
      child: ListenableBuilder(
        listenable: Listenable.merge([widget.jobs.retained, widget.model]),
        builder: (context, _) {
          final records = widget.jobs.retained.value
              .where(
                (record) =>
                    widget.jobId == null || record['id'] == widget.jobId,
              )
              .toList();
          if (records.isEmpty)
            return const Center(child: Text('No unfinished work.'));
          return ListView.separated(
            itemCount: records.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final record = records[index];
              final recovery = record['recovery'] is Map
                  ? Map<String, dynamic>.from(record['recovery'] as Map)
                  : <String, dynamic>{};
              final id = record['id'] as String;
              final busy = _busy.contains(id);
              final retry = widget.model.canRetryInterrupted(record);
              return Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        recovery['fileName'] as String? ??
                            record['fileName'] as String? ??
                            'Interrupted operation',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _messages[id] ??
                            (record['operation'] == 'add'
                                ? 'Retry restarts from the original input. Open and unlock its note first. If access expired, select the original file again.'
                                : 'Open the original note and restart this ${record['operation'] ?? 'operation'} using its normal controls.'),
                      ),
                      if (busy)
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: LinearProgressIndicator(),
                        ),
                      Wrap(
                        spacing: 8,
                        children: [
                          TextButton(
                            onPressed: busy
                                ? null
                                : () async {
                                    final result = await widget.model
                                        .openInterruptedNote(record);
                                    if (!context.mounted) return;
                                    if (result.isSuccess) {
                                      Navigator.pop(context);
                                      widget.onOpenNote();
                                    } else
                                      setState(
                                        () => _messages[id] =
                                            result.message ??
                                            'The original note is unavailable.',
                                      );
                                  },
                            child: const Text('Open note'),
                          ),
                          if (record['operation'] == 'add')
                            TextButton(
                              onPressed: busy || !retry
                                  ? null
                                  : () => _retry(record),
                              child: const Text('Retry'),
                            ),
                          TextButton(
                            onPressed: busy ? null : () => _discard(record),
                            child: const Text('Discard'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Done'),
      ),
    ],
  );
}
