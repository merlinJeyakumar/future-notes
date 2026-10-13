# Shutdown fix — approved gate, validation resumed

The user approved this gate, then approved correcting the undefined test getter
and resuming. Analysis and all 353 tests now pass; runtime is waiting for the old
app's normal shutdown. See [results](SHUTDOWN_FIX_RESULTS.md).

Date: 2026-10-13. [Flow and limits](SHUTDOWN_FIX_FLOW.md). Seven new regressions
are prepared, not run; expected total 353. Retain the prior 97-diagnostic
exception (95 info, original two warnings, no errors). Stop on failed checks or
new warnings/errors and inspect info changes.

The previous 84-file source/executable checkpoint remains preserved. The
unchanged runtime Debug tree was also copied to
`.validation/future-notes-validation-shutdown-baseline-20261013/Debug`; executable
and kernel hashes match KEYBOARD_RESTART_GATE.md. This preserves the binary,
not a newly validated source checkpoint.

From `D:\Project\NativeDevps\future-notes`, sequentially:

```powershell
$shutdownPaths = @(
  'lib/core/operations/shutdown_sequence.dart',
  'lib/core/storage/validation_app_services.dart',
  'lib/features/dashboard/viewmodels/content_viewmodel.dart',
  'lib/features/dashboard/views/dashboard_screen.dart',
  'test/storage/shutdown_sequence_test.dart',
  'test/viewmodels/discovery_search_test.dart'
)
& 'C:\src\flutter\bin\dart.bat' format @shutdownPaths
git diff --check
& 'C:\src\flutter\bin\flutter.bat' analyze --no-pub --no-fatal-infos --no-fatal-warnings
& 'C:\src\flutter\bin\flutter.bat' test --no-pub
```

One suite, no duplicate focused/full run. After passing lint/tests, preserve edits
in the unchanged isolated app, close normally and join the same process/session.
No force termination, second instance or discard; old cleanup may still be slow.
Then build/launch once with SDK-cache access:

```powershell
if (@(Get-Process -Name flutter_application_1 -ErrorAction SilentlyContinue).Count -gt 0) {
  throw 'A project app is already running; no second instance will be launched.'
}
& 'C:\src\flutter\bin\flutter.bat' run -d windows --debug --no-pub --no-hot -t lib/validation_main.dart --dart-define=FN_VALIDATION_MODE=true --dart-define=FN_VALIDATION_ROOT=D:/Project/NativeDevps/future-notes/.validation/future-notes-validation-runtime-20261013a --dart-define=FN_DATA_ROOT=D:/Project/NativeDevps/future-notes/.validation/future-notes-validation-runtime-20261013a/library --dart-define=FN_SETTINGS_PATH=D:/Project/NativeDevps/future-notes/.validation/future-notes-validation-runtime-20261013a/configuration/settings.json
```

No separate build. Verify visible startup/logs, then request normal close on the
blank unchanged draft. Record phase timings and exit response. An idle close over
ten seconds remains a latency failure: report its stage and stop affected work,
retaining owned handles until cleanup completes. Changing the message alone is
not full repair acceptance. No further correction after failure without approval.

Only after successful normal exit, reopen the same candidate once without
rebuilding and leave one isolated app running:

```powershell
if (@(Get-Process -Name flutter_application_1 -ErrorAction SilentlyContinue).Count -gt 0) {
  throw 'A project app is already running; no second instance will be launched.'
}
& 'C:\src\flutter\bin\flutter.bat' run -d windows --debug --no-pub --no-hot -t lib/validation_main.dart --use-application-binary='D:\Project\NativeDevps\future-notes\build\windows\x64\runner\Debug\flutter_application_1.exe'
```

Runtime scope: startup, idle shutdown and clean reopen; manual physical input may
be checked. No automated keys, original-note access, real-library activation or
attachment/password/package/Delete workflows. Broader performance/continuous-use
acceptance remains pending.

RULESBOOK.md requires “Before builds, tests, device/emulator validation, CI, or
production actions, state the exact command and wait for approval”. Previous
approval covered an unchanged text probe/recovery, not this source candidate.
