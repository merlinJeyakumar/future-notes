# Discovery/native diagnostic integration retry

Status: approved and passed; see STAGE7_READINESS_RESULTS.md. Analysis ran after
the already-started focused tests and before full tests/build, following the
user's latest execution-order instruction. No remediation is claimed for the earlier
native-move failure. The numeric-error diagnostic-only gate passed eight focused
native-move tests; the initial discovery-focused gate passed 73 tests. The full
suite previously failed with 283 passed and one native-move failure.
See [STAGE7_READINESS_RESULTS.md](STAGE7_READINESS_RESULTS.md).

From `D:\Project\NativeDevps\future-notes`, sequentially:

```powershell
$readinessRetryPaths = @(
  'lib/features/dashboard/services/background_service.dart',
  'lib/features/dashboard/viewmodels/content_viewmodel.dart',
  'lib/core/storage/windows_file_actions.dart',
  'test/storage/discovery_readiness_test.dart',
  'test/storage/windows_file_actions_test.dart'
)
& 'C:\src\flutter\bin\dart.bat' format @readinessRetryPaths
git diff --check
& 'C:\src\flutter\bin\dart.bat' format --output=none --set-exit-if-changed @readinessRetryPaths
& 'C:\src\flutter\bin\flutter.bat' test --no-pub test/storage/windows_file_actions_test.dart test/storage/discovery_readiness_test.dart test/storage/note_codec_test.dart test/viewmodels
& 'C:\src\flutter\bin\flutter.bat' test --no-pub
& 'C:\src\flutter\bin\flutter.bat' analyze --no-pub --no-fatal-infos --no-fatal-warnings
& 'C:\src\flutter\bin\flutter.bat' build windows --debug --no-pub
```

Stop on failed required checks or unexpected new warnings/errors; inspect
informational deltas against the retained 98-diagnostic baseline (96 info,
original two warnings, no errors). Expected registrations: 81 focused, 284 total.
These counts are expectations, not passing evidence.

Only disposable synthetic files and owned read-only test isolates are involved.
No app launch/stop, real-note access, dependency or encryption change. Check for
an existing project app before building without stopping it. The preserved
78-file cleanup source/executable checkpoint remains available and is not
replaced by this candidate. Runtime validation and the other repair stages
remain pending.
