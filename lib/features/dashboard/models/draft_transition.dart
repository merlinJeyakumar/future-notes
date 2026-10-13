enum DraftDecision { save, retry, discard, cancel }

enum DraftDecisionKind { firstSave, saveFailure, firstAttachment }

enum DraftTransition { navigation, newNote, lock, library, exit }

class DraftDecisionRequest {
  const DraftDecisionRequest(this.kind, this.transition, {this.failureMessage});

  final DraftDecisionKind kind;
  final DraftTransition transition;
  final String? failureMessage;
}

typedef DraftDecisionHandler =
    Future<DraftDecision> Function(DraftDecisionRequest request);

/// Permission for one exact draft revision; Discard does not mutate the draft.
/// The destination must be ready before consuming this permission.
class DraftTransitionPermit {
  const DraftTransitionPermit({
    required this.generation,
    required this.revision,
    this.discardChanges = false,
  });

  final int generation;
  final int revision;
  final bool discardChanges;
}
