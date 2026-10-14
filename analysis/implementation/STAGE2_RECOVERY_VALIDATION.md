# Sixth Stage 2 recoverable backend validation

Status: approved and passed on 2026-10-13. All 46 focused and 199 total tests,
formatting and Windows Debug compilation passed. Analysis retained exactly 98
diagnostics, with no additions/removals. The backend remains validation-only and
disconnected from application persistence. See [STAGE2_RECOVERY_RESULTS.md](STAGE2_RECOVERY_RESULTS.md).

Run from `D:\Project\NativeDevps\future-notes`:

```powershell
& 'C:\src\flutter\bin\dart.bat' format lib/core/storage/recoverable_store.dart test/storage/recoverable_store_test.dart
git diff --check
& 'C:\src\flutter\bin\dart.bat' format --output=none --set-exit-if-changed lib/core/storage/recoverable_store.dart test/storage/recoverable_store_test.dart
& 'C:\src\flutter\bin\flutter.bat' test --no-pub test/storage/recoverable_store_test.dart
& 'C:\src\flutter\bin\flutter.bat' test --no-pub
& 'C:\src\flutter\bin\flutter.bat' analyze --no-pub --no-fatal-infos --no-fatal-warnings
& 'C:\src\flutter\bin\flutter.bat' build windows --debug --no-pub
```

Run sequentially and stop at the first failed required check or unexpected new
warning/error. Inspect informational changes against 98 diagnostics: 96 info,
the original two warnings, no errors. Check for an existing project app before
building; do not launch or stop one. No dependency resolution/change is needed.

Expected registrations on Windows: 46 focused and 199 full-suite tests. These
counts do not establish passing results. All file operations use disposable
synthetic roots with explicit separate settings/library paths. The focused
tests call native Windows metadata APIs; they do not launch the project app or
access real notes/settings.

The gate tests 18 injected commit boundaries and three recovery boundaries,
three native move failure scenarios, queue/lease ordering, retained baseline
and revisions, empty/new objects, source changes, external publication races,
corrupt/oversized/orphan metadata, cancellation, identity collisions, repeated
recovery and bounded multi-window hash round trips.

It does not prove process-death/power-loss durability, hostile filesystem-race
protection, worker/UI latency, large retained-history operation, application
service integration, other platforms or 4/10 GiB attachment/package behavior.
Those remain later gates. Preserve the last validated path and keep production
activation disabled. Source risks and limits are recorded in [STATUS.md](STATUS.md).
