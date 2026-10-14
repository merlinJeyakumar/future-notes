# Proposed correction after the failed activation suite

No correction below has been applied. The backup and prior executable remain
retained; the original library has not been activated. See
[STORAGE_ACTIVATION_RESULTS.md](STORAGE_ACTIVATION_RESULTS.md) for the eight failures.

## Narrow correction scope

1. Update the seven failing lease scenarios to use an independent owned worker
   for contention and reacquisition probes. Keep conflict, retained-ownership,
   no-write and retry assertions. Do not change the production alias contract.
   Close the probe worker in test-owned cleanup.
2. Bind **GetLastError only** with `isLeaf: true`, capture it immediately after a
   failed move, and retain all no-replacement flags and cleanup/error semantics.
   MoveFileExW remains a normal, potentially blocking FFI call. This is a
   candidate for the observed zero-error capture; its effectiveness is unproven.
3. Add one bounded native regression covering 20 distinct destination conflicts,
   verifying both objects' bytes and typed outcomes. This is one test invocation,
   not a repeated suite. Do not downgrade expected conflict to generic failure.
4. Require a successful test receipt before the activation launcher can run.
   Bind the receipt to the current `lib/**/*.dart` and `windows/runner` source
   hashes. A passing copy-recovery receipt alone must not enable a candidate
   whose required integration suite failed. Keep launch commands unchanged.

If the native regression fails, stop; do not iterate speculative alternatives.
A native wrapper capturing MoveFileExW and GetLastError within one native call
would require its own reviewed build/interop design, not an incidental dependency
or a falsely marked blocking leaf call.

## Exact resumed validation

From `D:\Project\NativeDevps\future-notes`, sequentially. Reuse the retained
backup and disposable copy; do not copy or hash original notes again until the
already-approved preactivation verification. Keep the failed test log unchanged.

```powershell
& 'C:\src\flutter\bin\dart.bat' format lib/core/storage/windows_file_actions.dart test/storage/windows_file_actions_test.dart test/storage/owned_note_service_test.dart test/storage/owned_settings_test.dart
git diff --check
& 'C:\src\flutter\bin\cache\dart-sdk\bin\dart.exe' analyze --no-fatal-warnings
$env:FN_REHEARSAL_ROOT = 'D:\Project\NativeDevps\future-notes\.validation\future-notes-validation-activation-rehearsal-20261013'
try {
  & 'C:\src\flutter\bin\flutter.bat' test --no-pub --concurrency=1 test/storage/windows_file_actions_test.dart test/storage/owned_note_service_test.dart test/storage/owned_settings_test.dart test/storage/recoverable_store_test.dart test/storage/storage_owner_worker_test.dart test/storage/native_storage_integration_test.dart test/storage/activation_rehearsal_test.dart
  if ($LASTEXITCODE -ne 0) { throw 'Required corrected integration checks failed.' }
} finally {
  Remove-Item Env:\FN_REHEARSAL_ROOT -ErrorAction SilentlyContinue
}
& '.\scripts\storage\Start-RecoverableNotes.ps1'
```

Capture this single corrected test command to a new private log. Write the
candidate-bound success receipt only after its actual exit code is zero. Script
syntax parsing after the launcher change is static preparation, not script
execution. Retain the 101-diagnostic analyzer baseline: 99 info, original two
warnings, no errors; stop on new warnings/errors or failed required checks.

This reruns only the changed lease scenarios and persistence paths affected by
native move error capture, including copied-note recovery. The other 317 passing
checks are not repeated as a full suite. One Windows compilation/launch after
passing checks, with the exact launch command and private defines already
approved in [STORAGE_ACTIVATION_GATE.md](STORAGE_ACTIVATION_GATE.md). No backup
overwrite, original-note edits for testing, agent app interaction, forced stop,
dependency change, push or merge. The user tests the running app manually.

RULESBOOK requires confirmation after a failed validation before affected fixes
and continued execution. Approval is pending.
