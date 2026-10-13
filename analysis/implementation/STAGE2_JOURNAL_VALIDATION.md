# Fourth Stage 2 journal schema validation

Status: approved and passed on 2026-10-13. All ten focused tests, all 145 tests
and Windows Debug compilation passed. Analysis retained the original warnings
with two informational style additions. The schema remains disconnected from
production storage. See [STAGE2_JOURNAL_RESULTS.md](STAGE2_JOURNAL_RESULTS.md).

Run from `D:\Project\NativeDevps\future-notes`:

```powershell
& 'C:\src\flutter\bin\dart.bat' format lib/core/storage/commit_record.dart test/storage/commit_record_test.dart
git diff --check
& 'C:\src\flutter\bin\dart.bat' format --output=none --set-exit-if-changed lib/core/storage/commit_record.dart test/storage/commit_record_test.dart
& 'C:\src\flutter\bin\flutter.bat' test --no-pub test/storage/commit_record_test.dart
& 'C:\src\flutter\bin\flutter.bat' test --no-pub
& 'C:\src\flutter\bin\flutter.bat' analyze --no-pub --no-fatal-infos --no-fatal-warnings
& 'C:\src\flutter\bin\flutter.bat' build windows --debug --no-pub
```

Run sequentially, stopping at the first failed check or unexpected new warning/
error. Inspect informational deltas. The proposed retained exception is the
95-diagnostic baseline: 93 info, original two warnings, no errors. No dependency
resolution, version change or app launch is needed. Check for an existing project
app before building; do not launch or stop one.

Expected counts: 10 focused, 145 full-suite tests on Windows. These are registration
counts, not passing results. Schema tests perform no note/file I/O. Existing
isolation and native foundation tests remain in the full suite.

These checks cannot prove interrupted-write recovery, receipt durability,
non-writable ambiguous objects, baseline retention or runtime behavior. The
complete protocol and integration require later fault-boundary tests and gates.
Preserve earlier tested source/executable checkpoints; real-library activation
remains withheld.
