import 'package:flutter/material.dart';

import '../models/draft_transition.dart';

/// Uses the existing Material dialog pattern; no note body or title is shown.
class DraftDecisionDialog extends StatelessWidget {
  const DraftDecisionDialog({super.key, required this.request});

  final DraftDecisionRequest request;

  @override
  Widget build(BuildContext context) {
    final failure = request.kind == DraftDecisionKind.saveFailure;
    final attachment = request.kind == DraftDecisionKind.firstAttachment;
    if (request.kind == DraftDecisionKind.activeAttachments) {
      return AlertDialog(
        title: const Text('Attachment processing'),
        content: const Text(
          'Cancel the active attachment operation and wait for its files to close before continuing?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, DraftDecision.cancel),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, DraftDecision.discard),
            child: const Text('Cancel & wait'),
          ),
        ],
      );
    }
    return AlertDialog(
      title: Text(failure ? 'Save failed' : 'Save this new note?'),
      content: Text(
        failure
            ? request.failureMessage ?? 'The draft could not be saved.'
            : attachment
            ? 'Save this note before adding its first attachment.'
            : 'Choose Save to keep this draft, or Discard to continue without saving.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, DraftDecision.cancel),
          child: const Text('Cancel'),
        ),
        if (!attachment)
          TextButton(
            onPressed: () => Navigator.pop(context, DraftDecision.discard),
            child: const Text('Discard'),
          ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            failure ? DraftDecision.retry : DraftDecision.save,
          ),
          child: Text(
            failure
                ? 'Retry'
                : attachment
                ? 'Save & Continue'
                : 'Save',
          ),
        ),
      ],
    );
  }
}
