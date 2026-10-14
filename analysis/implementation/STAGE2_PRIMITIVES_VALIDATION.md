# Third Stage 2 revision/lease primitives gate

Status: approved and passed on 2026-10-13. All eight focused tests, all 135 tests
and Windows Debug compilation passed. Analysis retained the original warnings
with three new informational constructor-style lints. These primitives remain
disconnected from production writes. See [STAGE2_PRIMITIVES_RESULTS.md](STAGE2_PRIMITIVES_RESULTS.md).

Run sequentially from `D:\Project\NativeDevps\future-notes`:

```powershell
& 'C:\src\flutter\bin\flutter.bat' pub get --offline
& 'C:\src\flutter\bin\dart.bat' format lib/core/storage/native_storage_primitives.dart test/storage/native_storage_primitives_test.dart
git diff --check
& 'C:\src\flutter\bin\dart.bat' format --output=none --set-exit-if-changed lib/core/storage/native_storage_primitives.dart test/storage/native_storage_primitives_test.dart
& 'C:\src\flutter\bin\flutter.bat' test --no-pub test/storage/native_storage_primitives_test.dart
& 'C:\src\flutter\bin\flutter.bat' test --no-pub
& 'C:\src\flutter\bin\flutter.bat' analyze --no-pub --no-fatal-infos --no-fatal-warnings
& 'C:\src\flutter\bin\flutter.bat' build windows --debug --no-pub
```

Inspect lockfile changes immediately after offline resolution: crypto remains
3.0.7 and only moves from transitive to direct. Stop on incidental version changes,
failed required checks or unexpected new warnings/errors; inspect informational
deltas. Retaining the accepted analyzer exception requires this candidate's
approval: 92 diagnostics (90 info, original two warnings, no errors).

Eight new registrations imply 135 full-suite tests on Windows; those are expected
counts, not passing results. The native handle contention test is Windows-only;
other hosts require separate process-lock verification. All files are synthetic
and isolated; no real library/settings, app launch or editor runtime is included.
Check for an existing project app before build; do not launch or terminate one.

Known hashes and 3 MiB synthetic reads validate revision logic, not 4/10 GiB memory
profiles. Complete transaction/recovery, lease lifecycle wiring, all boundary
fault tests and real-library activation remain pending. Keep earlier validated
source/executable checkpoints available.
