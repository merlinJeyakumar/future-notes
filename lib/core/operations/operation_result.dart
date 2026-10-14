enum OperationOutcome {
  success,
  cancelled,
  conflict,
  rejectedInput,
  ioFailure,
  recoveryRequired,
}

/// Sanitized outcome; errors and paths must not be persisted as note content.
class OperationResult<T> {
  const OperationResult.success([this.value])
    : outcome = OperationOutcome.success,
      message = null;

  const OperationResult.failure(this.outcome, this.message) : value = null;

  /// A failed operation can still report irreversible partial progress.
  const OperationResult.partial(this.outcome, this.message, this.value);

  final OperationOutcome outcome;
  final T? value;
  final String? message;

  bool get isSuccess => outcome == OperationOutcome.success;
}
