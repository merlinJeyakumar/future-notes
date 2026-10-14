# Isolated application lint-first and runtime gate — approved, runtime blocked

The approved gate passed analysis, 346 tests, Windows Debug build and visible
startup. Title input did not take effect after a bounded retry; further workflow
validation stopped. Evidence: [VALIDATION_APP_RESULTS.md](VALIDATION_APP_RESULTS.md).

After an approved ordinary-key probe succeeded, conditional runtime checks
resumed. Save/autosave/reopen, close cancellation and switching to the second
disposable library were observed. A log check then exposed Flutter keyboard
event consistency assertions; validation stopped again. No SDK checks repeated
and no source changes or second instance followed. Full runtime acceptance is
still pending; the same results document retains both stopping points.

Review: [VALIDATION_APP_FLOW.md](VALIDATION_APP_FLOW.md).
Expected registrations: 346 (337 validated previously, nine additions).
Retain the approved analyzer baseline: 97 diagnostics, 95 info, the original
two warnings, no errors. Inspect the delta and stop on new warnings/errors or
any failed required check. No duplicate focused/full suite or optional reruns.

From `D:\Project\NativeDevps\future-notes`, sequentially:

```powershell
$runtimePaths = @(
  'lib/main.dart',
  'lib/validation_main.dart',
  'lib/core/storage/validation_app_services.dart',
  'lib/features/dashboard/views/dashboard_screen.dart',
  'test/storage/validation_app_services_test.dart'
)
& 'C:\src\flutter\bin\dart.bat' format @runtimePaths
git diff --check
& 'C:\src\flutter\bin\flutter.bat' analyze --no-pub --no-fatal-infos --no-fatal-warnings
& 'C:\src\flutter\bin\flutter.bat' test --no-pub
if (@(Get-Process -Name flutter_application_1 -ErrorAction SilentlyContinue).Count -gt 0) {
  throw 'A project app is already running; no second instance will be launched.'
}
& 'C:\src\flutter\bin\flutter.bat' run -d windows --debug --no-pub -t lib/validation_main.dart --dart-define=FN_VALIDATION_MODE=true --dart-define=FN_VALIDATION_ROOT=D:/Project/NativeDevps/future-notes/.validation/future-notes-validation-runtime-20261013a --dart-define=FN_DATA_ROOT=D:/Project/NativeDevps/future-notes/.validation/future-notes-validation-runtime-20261013a/library --dart-define=FN_SETTINGS_PATH=D:/Project/NativeDevps/future-notes/.validation/future-notes-validation-runtime-20261013a/configuration/settings.json
```

The final command performs one Windows Debug build and one isolated launch;
there is no separate redundant build. Verify the run directory is unused before
execution; refuse unexpected existing contents rather than deleting them.
No dependency resolution, real-note access, real-library activation, automatic
app stop/relaunch, or replacement of preserved checkpoints is authorized here.

After visible startup, inspect logs and process ownership. Use synthetic note
text only for manual Save, title/body editing, autosave, navigation/reopen,
refresh/search, draft Cancel and switching between disposable sublibraries.
Observe continuous use for 30 minutes if startup and these operations succeed;
record elapsed time, resource measurements and any errors. Do not claim frame
or input targets without measurements. Cancel a normal Windows close request
while a new synthetic draft is dirty and confirm the window remains visible.
Leave the isolated app running afterward. No pending attachment/password/import/
export/Delete workflows, external transmission or original notes are involved.

GUI observations and interactions use the computer-use skill. If visible access
is unavailable or any required check fails, stop affected work and report the
limitation/failure instead of claiming runtime completion.
