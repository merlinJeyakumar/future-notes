# First Stage 1 candidate validation

Status: completed for the first candidate after the user approved the harness
setup and two test-cleanup corrections. All required commands returned exit 0.
Focused tests: 26 passed. Full suite: 84 passed. Analysis used the approved
exception and reported 90 diagnostics (88 info, the same 2 warnings, no errors).
Windows Debug compilation passed. See [STAGE1_RESULTS.md](STAGE1_RESULTS.md).
Keep baseline diagnostics visible and inspect the current delta.
Stop on any failed required command or unexpected new analyzer warning/error.
No application launch is included.

Run from `D:\Project\NativeDevps\future-notes`. No dependency resolution or
upgrade is needed. Only changed/new Dart files are formatted. The tests use
operation-owned disposable settings/libraries and controllable memory-backed
services; background initialization and production directory resolution are
disabled for the VM race tests. The existing real-encryption fixtures remain in
the complete suite.

```powershell
$stage1FormatPaths = @(
  'lib/core/operations',
  'lib/core/storage/note_reference.dart',
  'lib/features/dashboard/models/draft_session.dart',
  'lib/features/dashboard/services/file_service.dart',
  'lib/features/dashboard/services/settings_service.dart',
  'lib/features/dashboard/viewmodels/content_viewmodel.dart',
  'lib/features/dashboard/views/dashboard_screen.dart',
  'lib/features/dashboard/widgets/content_area.dart',
  'test/storage/captured_reference_test.dart',
  'test/support/editor_harness.dart',
  'test/viewmodels'
)
& 'C:\src\flutter\bin\dart.bat' format @stage1FormatPaths
git diff --check
& 'C:\src\flutter\bin\dart.bat' format --output=none --set-exit-if-changed @stage1FormatPaths
& 'C:\src\flutter\bin\flutter.bat' test --no-pub test/viewmodels/session_safety_test.dart test/storage/captured_reference_test.dart
& 'C:\src\flutter\bin\flutter.bat' test --no-pub
& 'C:\src\flutter\bin\flutter.bat' analyze --no-pub --no-fatal-infos --no-fatal-warnings
& 'C:\src\flutter\bin\flutter.bat' build windows --debug --no-pub
```

Execute sequentially and inspect each exit code. Inspect analysis output before
the build. Check for a project application process before building; do not launch
or terminate one. The Stage 0 source/build checkpoint and the original executable
remain available at the locations recorded in [STATUS.md](STATUS.md).

Acceptance is bounded to the tested VM behavior, synthetic native file-reference
handling and Windows compilation. UI workflows, exit cancellation, recoverable
writes, attachment jobs, other platforms and measured performance remain pending.
