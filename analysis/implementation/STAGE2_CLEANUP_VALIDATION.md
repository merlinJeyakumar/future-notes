# Owned-service shutdown and source-cleanup gate

Status: approved and passed on Windows, 2026-10-13. All 54 focused tests and all
274 tests passed, together with analysis and Windows Debug compilation. See
[STAGE2_CLEANUP_RESULTS.md](STAGE2_CLEANUP_RESULTS.md).
The preceding Save-coalescing gate passed 100 focused tests, all 266 tests,
analysis with the retained exception (98 diagnostics: 96 info, two original
warnings, no errors) and Windows Debug build. Its 78-file source/executable
checkpoint is retained at
`.validation/future-notes-validation-stage3-saves-387e307170894b23abade3f0e29990c4`.

From `D:\Project\NativeDevps\future-notes`, sequentially:

```powershell
$stage2CleanupPaths = @(
  'lib/core/storage/owned_note_persistence.dart',
  'lib/core/storage/owned_settings_persistence.dart',
  'test/storage/owned_note_service_test.dart',
  'test/storage/owned_settings_test.dart'
)
& 'C:\src\flutter\bin\dart.bat' format @stage2CleanupPaths
git diff --check
& 'C:\src\flutter\bin\dart.bat' format --output=none --set-exit-if-changed @stage2CleanupPaths
& 'C:\src\flutter\bin\flutter.bat' test --no-pub test/storage/owned_note_service_test.dart test/storage/owned_settings_test.dart test/storage/settings_isolation_test.dart
& 'C:\src\flutter\bin\flutter.bat' test --no-pub
& 'C:\src\flutter\bin\flutter.bat' analyze --no-pub --no-fatal-infos --no-fatal-warnings
& 'C:\src\flutter\bin\flutter.bat' build windows --debug --no-pub
```

Stop on a failed required check or unexpected new warning/error; retain the
original two-warning exception and inspect informational deltas. Expected
passing registrations: 54 focused and 274 total, including eight new regressions.

Tests use disposable synthetic settings/library roots and a gracefully closed
owned worker. They create local sidecars to obstruct nonrecursive temporary
directory removal; injected release failures happen before actual release.
Teardown removes only those verified test obstructions and clears injected
faults before service/worker shutdown. No real notes, app launch/stop, production
activation, encryption change or dependency resolution. Check for an existing
project process before building without stopping it.

This gate does not establish native handle-close failure recovery, actual worker
death, process/power interruption, visible Windows exit cancellation or measured
continuous-use performance. The application has not enabled owned persistence;
full mutation ordering and runtime integration remain pending.
