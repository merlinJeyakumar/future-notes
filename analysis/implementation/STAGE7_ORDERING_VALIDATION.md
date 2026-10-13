# Discovery/search ordering gate

Status: approved and passed; see [STAGE7_ORDERING_RESULTS.md](STAGE7_ORDERING_RESULTS.md).
Source and control-flow review are
documented in [STAGE7_ORDERING_FLOW.md](STAGE7_ORDERING_FLOW.md). Candidate is
validated through the required source/test/build checks, with runtime pending.
Prior passing baseline: 284 tests, 97 analyzer diagnostics (95
info, original two warnings, no errors) and Windows Debug build.

From `D:\Project\NativeDevps\future-notes`, sequentially:

```powershell
$discoveryOrderingPaths = @(
  'lib/features/dashboard/services/background_service.dart',
  'lib/features/dashboard/viewmodels/content_viewmodel.dart',
  'test/storage/discovery_readiness_test.dart',
  'test/storage/discovery_ordering_test.dart',
  'test/viewmodels/discovery_search_test.dart'
)
& 'C:\src\flutter\bin\dart.bat' format @discoveryOrderingPaths
git diff --check
& 'C:\src\flutter\bin\flutter.bat' analyze --no-pub --no-fatal-infos --no-fatal-warnings
& 'C:\src\flutter\bin\flutter.bat' test --no-pub
& 'C:\src\flutter\bin\flutter.bat' build windows --debug --no-pub
```

Run the suite once (new regression groups included) and the required Windows
build once. No duplicate focused/full runs or extra passing-check repetitions.
Expected total: 306 tests, including 22 new registrations; this is not evidence
that they pass. Stop on a failed check or unexpected new warning/error; inspect
informational changes against the retained exception.

Tests use explicit disposable native roots or injected in-memory services. No
app launch/stop, real-note access, dependency or encryption change. Read-only
test readers own no writer leases. Check for an existing project process before
building without stopping it. Prior source/executable checkpoints stay available.
Runtime/performance validation and other repair findings remain pending.
