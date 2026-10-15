import '../../../core/operations/operation_result.dart';

enum SavePhase { unsavedDraft, dirty, saving, saved, failed }

/// Presentation only. Revision/credential ownership remains in DraftSession.
class SaveUiState {
  const SaveUiState(
    this.phase, {
    this.hasChanges = false,
    this.canRetry = false,
    this.failure,
  });
  final SavePhase phase;
  final bool hasChanges;
  final bool canRetry;
  final OperationOutcome? failure;

  String get label => switch (phase) {
    SavePhase.unsavedDraft => 'Unsaved draft',
    SavePhase.dirty => 'Unsaved changes',
    SavePhase.saving => 'Saving…',
    SavePhase.saved => 'Saved',
    SavePhase.failed => 'Save failed',
  };

  @override
  bool operator ==(Object other) =>
      other is SaveUiState &&
      phase == other.phase &&
      hasChanges == other.hasChanges &&
      canRetry == other.canRetry &&
      failure == other.failure;
  @override
  int get hashCode => Object.hash(phase, hasChanges, canRetry, failure);
}

enum EditorMode { richText, html }
