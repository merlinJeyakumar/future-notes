import 'package:flutter/material.dart';
import '../models/attachment_job.dart';
import '../models/draft_transition.dart';
import '../viewmodels/content_viewmodel.dart';

/// Copy reflects current jobs. The existing transition coordinator decides safety.
class MobileWorkDecisionDialog extends StatelessWidget {
  const MobileWorkDecisionDialog({
    super.key,
    required this.model,
    required this.transition,
  });
  final ContentViewModel model;
  final DraftTransition transition;

  @override
  Widget build(
    BuildContext context,
  ) => ValueListenableBuilder<List<AttachmentJobState>>(
    valueListenable: model.attachmentJobsNotifier,
    builder: (context, states, _) => ListenableBuilder(
      listenable: Listenable.merge(states.map((s) => s.phase).toList()),
      builder: (context, _) {
        final active = states
            .map((s) => s.progress.value)
            .where((job) => job.active)
            .toList();
        final exporting =
            active.isNotEmpty &&
            active.every(
              (job) => job.operation == AttachmentJobOperation.export,
            );
        final name = exporting ? 'export' : 'background work';
        final continuation = switch (transition) {
          DraftTransition.exit => 'exiting',
          DraftTransition.lock => 'locking this note',
          DraftTransition.library => 'changing libraries',
          DraftTransition.newNote => 'creating a note',
          DraftTransition.navigation => 'opening another note',
        };
        final canCancel = active.every((job) => job.cancellable);
        return AlertDialog(
          title: Text(
            active.isEmpty
                ? 'Work finished'
                : exporting
                ? 'Export in progress'
                : 'Background work in progress',
          ),
          content: Text(
            active.isEmpty
                ? 'The operation has finished. You can continue.'
                : canCancel
                ? 'Cancel the $name and wait for cleanup before $continuation, or keep it running.'
                : 'The $name is finishing. Wait for it to complete before $continuation.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, DraftDecision.cancel),
              child: Text(exporting ? 'Keep exporting' : 'Keep running'),
            ),
            FilledButton(
              onPressed: canCancel
                  ? () => Navigator.pop(context, DraftDecision.discard)
                  : null,
              child: Text(
                active.isEmpty
                    ? 'Continue'
                    : exporting
                    ? 'Cancel export'
                    : 'Cancel work',
              ),
            ),
          ],
        );
      },
    ),
  );
}
