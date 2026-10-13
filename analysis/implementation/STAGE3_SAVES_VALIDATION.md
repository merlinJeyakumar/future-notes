# First Stage 3 Save coalescing gate

Status: approved and passed on Windows, 2026-10-13. All 100 focused tests, all
266 tests, nonfatal analysis and Windows Debug build passed. Exact results:
[STAGE3_SAVES_RESULTS.md](STAGE3_SAVES_RESULTS.md).
The preceding validated checkpoint has 77 files at
`.validation/future-notes-validation-stage2-notes-741174cdc99a4a32b410cf9562c87734`.
The preceding gate passed 86 focused tests, all 252 tests, analysis with the
retained exception (99 diagnostics: 97 info, original two warnings, no errors)
and Windows Debug build. The validated coalescing source/executable has 78 files
at `.validation/future-notes-validation-stage3-saves-387e307170894b23abade3f0e29990c4`.

From `D:\Project\NativeDevps\future-notes`, sequentially:

```powershell
$stage3SavePaths = @(
  'lib/features/dashboard/viewmodels/content_viewmodel.dart',
  'test/viewmodels/save_coalescing_test.dart',
  'test/storage/owned_note_service_test.dart'
)
& 'C:\src\flutter\bin\dart.bat' format @stage3SavePaths
git diff --check
& 'C:\src\flutter\bin\dart.bat' format --output=none --set-exit-if-changed @stage3SavePaths
& 'C:\src\flutter\bin\flutter.bat' test --no-pub test/viewmodels test/storage/owned_note_service_test.dart test/storage/captured_reference_test.dart test/storage/owned_settings_test.dart test/storage/settings_isolation_test.dart
& 'C:\src\flutter\bin\flutter.bat' test --no-pub
& 'C:\src\flutter\bin\flutter.bat' analyze --no-pub --no-fatal-infos --no-fatal-warnings
& 'C:\src\flutter\bin\flutter.bat' build windows --debug --no-pub
```

Retain the original two-warning analyzer exception; inspect informational
changes. Stop on a failed required check or unexpected new warning/error.
The preceding unnecessary_import info is corrected in this candidate.

Observed passing registrations: 100 focused and 266 total, including 14 new regressions.
Tests use memory-backed synthetic note services or isolated settings/library
roots with a real owned worker; production directory resolution throws.
Check for an existing project process before building without stopping it.
No application launch/stop, real-note access or dependency resolution is included.

This gate validates pending-save coalescing, not the full note mutation queue.
Attachment publication, protection transactions, Delete and library switching
remain pending. The shared application still has not enabled owned persistence;
runtime and performance claims require their later gates.
