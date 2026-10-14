# Date and New Note UX gate

Status: implemented and flow-reviewed; validation pending.

The isolated close-fix run used an empty disposable library. No note object was
created, so there was no stored note date. Clicking New Note on the already blank
initial draft reset it to an indistinguishable blank draft. The explicit first
Save rule remains intentional and unchanged.

The candidate now displays “Not saved” for a draft, the retained note timestamp
after Save and in sidebar rows, and separate “Note date” / “File modified” labels
in details. New Note awaits Save/Discard/Cancel resolution, closes the mobile
drawer only after success, focuses the fresh editor and explains that Save creates
the note. It does not auto-save or create empty notes. Existing timestamps and
note formats are unchanged.

The existing close candidate remains included. Eight dashboard scenarios cover
the real exit aggregation plus fresh-draft feedback and first-Save date
publication. Two sidebar scenarios cover a retained date and missing legacy date.
Tests are prepared but unrun.

Proposed exact lint-first gate from D:\Project\NativeDevps\future-notes:

```powershell
$dateNotePaths = @(
  'lib/features/dashboard/viewmodels/content_viewmodel.dart',
  'lib/features/dashboard/views/dashboard_screen.dart',
  'lib/features/dashboard/widgets/content_area.dart',
  'lib/features/dashboard/widgets/file_details_dialog.dart',
  'lib/features/dashboard/widgets/sidebar.dart',
  'test/dashboard_exit_test.dart',
  'test/sidebar_date_test.dart'
)
& 'C:\src\flutter\bin\dart.bat' format @dateNotePaths
git diff --check
& 'C:\src\flutter\bin\flutter.bat' analyze --no-pub --no-fatal-infos --no-fatal-warnings
& 'C:\src\flutter\bin\flutter.bat' test --no-pub test/dashboard_exit_test.dart test/sidebar_date_test.dart test/storage/shutdown_sequence_test.dart test/viewmodels/draft_transition_test.dart test/file_details_dialog_test.dart
if (@(Get-Process -Name flutter_application_1 -ErrorAction SilentlyContinue).Count -gt 0) {
  throw 'An app is already running; no replacement or second launch is allowed.'
}
& 'C:\src\flutter\bin\flutter.bat' run -d windows --debug --no-pub --no-hot -t lib/validation_main.dart --dart-define=FN_VALIDATION_MODE=true --dart-define=FN_VALIDATION_ROOT=D:/Project/NativeDevps/future-notes/.validation/future-notes-validation-date-new-20261013 --dart-define=FN_DATA_ROOT=D:/Project/NativeDevps/future-notes/.validation/future-notes-validation-date-new-20261013/library --dart-define=FN_SETTINGS_PATH=D:/Project/NativeDevps/future-notes/.validation/future-notes-validation-date-new-20261013/configuration/settings.json
```

Retain the established analyzer exception and stop on failures or new warnings
or errors. Run one affected suite and one compile/launch, with no duplicate full
suite or separate build. The user manually checks New Note, explicit Save/date,
reopen and one-click close. No automated input, original-note access, real-library
activation, dependency change or forced stop. Compilation alone does not prove
the new note workflow.
