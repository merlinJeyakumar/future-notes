# Ninth Stage 2 note-service adoption gate

Status: approved correction and complete rerun passed on 2026-10-13: 86 focused
tests, all 252 tests, analyzer with the retained exception and Windows Debug
build. The first focused attempt failed with 80 passed/six failed and stopped;
the user then approved the separator correction and rerun. See
[STAGE2_NOTES_RESULTS.md](STAGE2_NOTES_RESULTS.md).
The settings gate passed all 26 focused
tests, all 234 tests and Windows Debug compilation. Analysis had 99 diagnostics:
97 info, the original two warnings, no errors. Its 75-file checkpoint is retained.

From `D:\Project\NativeDevps\future-notes`:

```powershell
$stage2NotePaths = @(
  'lib/core/storage/note_reference.dart',
  'lib/core/storage/owned_note_persistence.dart',
  'lib/features/dashboard/services/file_service.dart',
  'lib/features/dashboard/services/settings_service.dart',
  'lib/features/dashboard/viewmodels/content_viewmodel.dart',
  'test/support/editor_harness.dart',
  'test/storage/owned_note_service_test.dart'
)
& 'C:\src\flutter\bin\dart.bat' format @stage2NotePaths
git diff --check
& 'C:\src\flutter\bin\dart.bat' format --output=none --set-exit-if-changed @stage2NotePaths
& 'C:\src\flutter\bin\flutter.bat' test --no-pub test/storage/owned_note_service_test.dart test/storage/captured_reference_test.dart test/storage/owned_settings_test.dart test/storage/settings_isolation_test.dart test/viewmodels
& 'C:\src\flutter\bin\flutter.bat' test --no-pub
& 'C:\src\flutter\bin\flutter.bat' analyze --no-pub --no-fatal-infos --no-fatal-warnings
& 'C:\src\flutter\bin\flutter.bat' build windows --debug --no-pub
```

Sequential checks; stop at the first failed required check or unexpected new
warning/error. Inspect informational deltas against the prior 99 diagnostics.
The settings unnecessary_underscores info is corrected in this candidate.
Check for an existing project process before building without launching/stopping
it. No dependency resolution or change.

Observed passing registrations: 18 new native service/editor tests and 252 total
tests. Focused validation also includes the existing
captured-reference, settings and view-model regressions because writeResolved now
returns an acknowledged NoteReference. Tests use disposable roots and injected
workers; Documents resolution throws. Synthetic cipher tests establish ordering
and metadata behavior; earlier real-format compatibility tests remain in the suite.

The candidate acquires and recovers an injected library before discovery or
resolution; captures worker capabilities and revisions; checks body reads;
commits through the recoverable worker; and publishes its acknowledged revision
to the editor. Queued saves rebase only onto their own earlier acknowledgement
of the identical captured object, never onto a fresh external read.

The singleton/main application does not enable this path. Unintegrated direct
attachment/import/delete/password-storage mutators are rejected in injected mode.
Runtime startup/UI feedback, the full mutation queue, transactional library
switching, process-death recovery, cleanup-failure injection, coalescing,
serialization/encryption offloading and bounded preview/attachment/package work
remain pending. Note body serialization still materializes the existing body;
this gate does not establish attachment streaming or measured UI improvement.
