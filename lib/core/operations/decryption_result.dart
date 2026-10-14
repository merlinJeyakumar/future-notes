enum DecryptionFailure { invalidCiphertext }

/// Successful legacy decryption is not evidence of authenticated integrity.
/// Empty payloads are valid; failure details never travel as payload content.
class DecryptionResult<T> {
  const DecryptionResult.success(this.value, {this.usedLegacyFallback = false})
    : failure = null;

  const DecryptionResult.failure(DecryptionFailure reason)
    : failure = reason,
      value = null,
      usedLegacyFallback = false;

  final T? value;
  final DecryptionFailure? failure;
  final bool usedLegacyFallback;

  bool get isSuccess => failure == null;
}
