# Close handoff diagnostic candidate

Status: proposed, not implemented or validated. The activated candidate failed
the user's manual close check; storage completed at 40 ms, but the window stayed
open. Preserve the existing app, notes, backup and previous executable.

Add a debug-only binding trace around the complete handleRequestAppExit result,
delegating observer aggregation to super without changing its decisions. Log
entry, final exit/cancel or failure, and elapsed time without note content.
Keep existing native WM_CLOSE/WM_DESTROY traces. Do not force exit, change the
SDK, bypass cancellation or introduce speculative shutdown behavior.

Review callback-to-binding-to-native flow before lint. Test the trace's delegated
exit, cancellation and error behavior plus the existing cleanup regressions.
Only after the user closes the current app normally and zero instances are
verified, compile the traced candidate with explicit disposable paths. No
original-library activation, agent input, forced stop or automatic launch is
included. A source change invalidates the existing activation test receipt.

Proposed exact commands from D:\Project\NativeDevps\future-notes, sequentially,
stopping at failure or a new warning/error; retain the existing analyzer baseline:

```powershell
& 'C:\src\flutter\bin\dart.bat' format lib/core/operations/exit_trace_binding.dart lib/main.dart lib/validation_main.dart test/storage/exit_trace_binding_test.dart
git diff --check
& 'C:\src\flutter\bin\flutter.bat' analyze --no-pub --no-fatal-infos --no-fatal-warnings
& 'C:\src\flutter\bin\flutter.bat' test --no-pub test/storage/exit_trace_binding_test.dart test/storage/shutdown_sequence_test.dart
if (@(Get-Process -Name flutter_application_1 -ErrorAction SilentlyContinue).Count -gt 0) {
  throw 'An app is running; no executable will be replaced.'
}
& 'C:\src\flutter\bin\flutter.bat' build windows --debug --no-pub -t lib/validation_main.dart --dart-define=FN_VALIDATION_MODE=true --dart-define=FN_VALIDATION_ROOT=D:/Project/NativeDevps/future-notes/.validation/future-notes-validation-close-handoff-20261013 --dart-define=FN_DATA_ROOT=D:/Project/NativeDevps/future-notes/.validation/future-notes-validation-close-handoff-20261013/library --dart-define=FN_SETTINGS_PATH=D:/Project/NativeDevps/future-notes/.validation/future-notes-validation-close-handoff-20261013/configuration/settings.json
```

Do not compile over a running executable. If normal close remains unavailable,
report that boundary rather than terminating the app. The user's manual launch
and close trace will be needed for runtime evidence; passing checks alone will
not close this finding. No duplicate full suite or optional build is proposed.
