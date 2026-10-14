# Windows exit trace — approved, subsequently stopped by user

The user approved this diagnostic, then reported the app had already closed and
requested manual testing instead of agent testing. No trace patch or diagnostic
launch was performed. The user confirmed typing/closing in the normal run.
The commands below are historical gate details, not a pending execution request.

The last runtime gate failed: cleanup completed in 53 ms but the window remained
open beyond ten seconds. This proposal needs confirmation before implementation
or runtime actions. No repair to the native exit path is claimed yet.

Add sanitized diagnostic labels only:

- Dashboard: exit callback admission, acknowledged cleanup and returned response.
- Windows runner: WM_CLOSE arrival, whether Flutter consumes it, and WM_DESTROY.

Keep cancellation, save decisions, handles, encryption and normal runner exit
behavior unchanged. Do not modify the Flutter SDK or install dependencies. The
labels must contain no titles, note text, paths or keys.

First request one further normal Close on the already closed-storage candidate.
Join session 56635. If it remains live after ten seconds, the following narrowly
scoped fallback needs explicit approval as part of this gate:

```powershell
$exitTraceApp = Get-Process -Id 77620 -ErrorAction Stop
if ($exitTraceApp.ProcessName -ne 'flutter_application_1' -or $exitTraceApp.Path -ne 'D:\Project\NativeDevps\future-notes\build\windows\x64\runner\Debug\flutter_application_1.exe' -or $exitTraceApp.StartTime.ToUniversalTime().ToString('o') -ne '2026-10-13T12:11:01.0118964Z') {
  throw 'Process identity changed; stop for inspection.'
}
Stop-Process -InputObject $exitTraceApp
```

Join the same session and require zero instances. Preserve prior checkpoints.
From `D:\Project\NativeDevps\future-notes`, after the diagnostic-only patch:

```powershell
& 'C:\src\flutter\bin\dart.bat' format lib/features/dashboard/views/dashboard_screen.dart
git diff --check
& 'C:\src\flutter\bin\flutter.bat' analyze --no-pub --no-fatal-infos --no-fatal-warnings
& 'C:\src\flutter\bin\flutter.bat' test --no-pub test/storage/shutdown_sequence_test.dart
if (@(Get-Process -Name flutter_application_1 -ErrorAction SilentlyContinue).Count -gt 0) {
  throw 'A project app is already running; no second instance will be launched.'
}
& 'C:\src\flutter\bin\flutter.bat' run -d windows --debug --no-pub --no-hot -t lib/validation_main.dart --dart-define=FN_VALIDATION_MODE=true --dart-define=FN_VALIDATION_ROOT=D:/Project/NativeDevps/future-notes/.validation/future-notes-validation-runtime-20261013a --dart-define=FN_DATA_ROOT=D:/Project/NativeDevps/future-notes/.validation/future-notes-validation-runtime-20261013a/library --dart-define=FN_SETTINGS_PATH=D:/Project/NativeDevps/future-notes/.validation/future-notes-validation-runtime-20261013a/configuration/settings.json
```

Use SDK-cache access. One relevant five-test suite and one compilation, no full
suite duplicate or separate build. Retain the latest 99-diagnostic exception
(97 info, original two warnings, no errors); stop on new warnings/errors or a
failed command. After visible startup, request one normal idle close and collect
the response/runner labels. Report the result and stop; no automatic repair,
retry, reopen or termination of that new diagnostic process is authorized.

No automated keys, original-note access, real-library activation or unfinished
attachment/password/package/Delete actions. Forced termination of the current
PID is conditional on its cleanup acknowledgement and repeated normal-close
failure, and may still interrupt native teardown. No other process is targeted.
