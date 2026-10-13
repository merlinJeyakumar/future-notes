# Seventh Stage 2 owned persistence worker validation

Status: approved and passed on 2026-10-13. The backend gate passed all 199 tests,
Windows Debug compilation and the unchanged 98-diagnostic analyzer baseline.
Its 71-file source/executable checkpoint remains available. This new worker
candidate is disconnected from application file/settings services and rejects
production environments.

Run from `D:\Project\NativeDevps\future-notes`:

```powershell
& 'C:\src\flutter\bin\dart.bat' format lib/core/storage/storage_owner_worker.dart test/storage/storage_owner_worker_test.dart
git diff --check
& 'C:\src\flutter\bin\dart.bat' format --output=none --set-exit-if-changed lib/core/storage/storage_owner_worker.dart test/storage/storage_owner_worker_test.dart
& 'C:\src\flutter\bin\flutter.bat' test --no-pub test/storage/storage_owner_worker_test.dart
& 'C:\src\flutter\bin\flutter.bat' test --no-pub
& 'C:\src\flutter\bin\flutter.bat' analyze --no-pub --no-fatal-infos --no-fatal-warnings
& 'C:\src\flutter\bin\flutter.bat' build windows --debug --no-pub
```

Run sequentially, stopping at the first failed required check or unexpected new
warning/error. Inspect informational deltas against 98 diagnostics: 96 info,
the original two warnings, no errors. Check for an existing project app before
building; do not launch or stop one. No dependency resolution/change is needed.

Observed on Windows: all 16 focused and all 215 full-suite tests passed.
Analysis matched all 98 prior diagnostics exactly; Windows Debug compiled in
9.8 seconds. See [STAGE2_OWNER_RESULTS.md](STAGE2_OWNER_RESULTS.md).
The tests create/close owned Dart
isolates and use disposable synthetic files with separate library/settings
locations. Startup/exit tests stop only uninitialized or explicitly root-free
test isolates, never an active writer or the project app. Native file operations
remain inside disposable roots. Real notes/settings are not accessed.

The gate covers readiness and launch deadlines, error/exit outcomes, root and
request generations, bounded descriptor queues, actor ordering, native lease
contention, immutable recovery reports, file-backed publication and graceful
shutdown. It does not establish application adoption, abrupt writer death,
power-loss atomicity, attachment job cancellation/progress, matched UI profiling,
continuous app operation or other-platform support. Those remain later gates.
Source risks and limits are recorded in [STATUS.md](STATUS.md).
