# Remove the shutdown screen and preserve exit listeners

Status: implemented and flow-reviewed, full validation pending. The user first
selected “Code changes only”, then requested a run and approved the exact
launch-only command. Formatting, analysis and test commands below remain
unapproved and were not executed for this candidate. One compilation/isolated
launch ran; no app input was sent.
The user's request
to fix closing and remove the screen authorizes this candidate after the prior
analysis-only boundary. Execution evidence appears below.

The dashboard now keeps its existing editor subtree mounted through closing.
AbsorbPointer and ExcludeFocus remain stable ancestors before and during the
request, disabling interaction without disposing text-field listeners that are
still in Flutter's exit-observer snapshot. No shutdown screen or success notice
is shown. Slow cleanup and genuine failures use snackbars. The original exit
request awaits cleanup; no forced exit or observer-cancellation bypass exists.

Dirty drafts still resolve before cleanup begins. Cancellation leaves editing
enabled. Once storage cleanup begins, editing stays disabled, including after
partial failure; a deliberate Close retries the owned cleanup. Watcher/service
closure and retained note/recovery data are unchanged. The original library and
retained backup/executable are outside the proposed test/run locations.

DashboardScreen passes its existing view-model background-start option through
an optional parameter, default true. The new tests disable background bootstrap
and use injected in-memory notes with disposable settings paths. No Documents
resolver or original library is used. Six tests exercise the actual binding
aggregation with mounted text fields, including successful cleanup, a slow
request, concurrent requests, another observer's cancellation, cleanup failure
and retry, and a cancelled unsaved draft. They assert retained mounted editor
states rather than testing only the cleanup helper. None has run yet.

Proposed exact single lint-first gate from D:\Project\NativeDevps\future-notes,
sequentially, stopping on failures or new warnings/errors. Retain the established
101-diagnostic baseline (99 info, original two warnings, no errors):

```powershell
& 'C:\src\flutter\bin\dart.bat' format lib/features/dashboard/views/dashboard_screen.dart test/dashboard_exit_test.dart
git diff --check
& 'C:\src\flutter\bin\flutter.bat' analyze --no-pub --no-fatal-infos --no-fatal-warnings
& 'C:\src\flutter\bin\flutter.bat' test --no-pub test/dashboard_exit_test.dart test/storage/shutdown_sequence_test.dart test/viewmodels/draft_transition_test.dart
if (@(Get-Process -Name flutter_application_1 -ErrorAction SilentlyContinue).Count -gt 0) {
  throw 'An app is already running; no replacement or second launch is allowed.'
}
& 'C:\src\flutter\bin\flutter.bat' run -d windows --debug --no-pub --no-hot -t lib/validation_main.dart --dart-define=FN_VALIDATION_MODE=true --dart-define=FN_VALIDATION_ROOT=D:/Project/NativeDevps/future-notes/.validation/future-notes-validation-close-fix-20261013 --dart-define=FN_DATA_ROOT=D:/Project/NativeDevps/future-notes/.validation/future-notes-validation-close-fix-20261013/library --dart-define=FN_SETTINGS_PATH=D:/Project/NativeDevps/future-notes/.validation/future-notes-validation-close-fix-20261013/configuration/settings.json
```

One affected suite and one compile/launch; no duplicate full suite or separate
build. The user will test typing and one-click close manually on synthetic data;
the agent only reads logs. No automated input, forced termination, dependency
change, original-note test or real-library reactivation. A new source change
invalidates the earlier activation receipt; do not reuse it for activation.

The regression/build gate and isolated manual close are required to claim the
repair validated. The prior diagnostic binding proposal is superseded by this
direct candidate. RULESBOOK requires exact-command approval before execution.

## Approved launch-only result

The exact isolated flutter run command above was separately approved and
executed once, after checking that no project app was running. Windows Debug
compilation succeeded in 31.2 seconds. Session 14099 remains live at handoff;
process metadata showed exactly one responding Future Notes window, PID 41264,
with a nonzero window handle and the expected executable path. Captured startup
logs contained no errors at inspection. The disposable close-fix library is
separate from original notes. No tests, analyzer, automated input, forced stop
or original-library activation was performed. Visible dashboard and one-click
close acceptance require the user's manual confirmation; no closing success
is claimed from compilation alone.
