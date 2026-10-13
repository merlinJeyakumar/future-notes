# Injected note-service gate results

Approved gate started on Windows on 2026-10-13 from development at
`a9f6d247d7e27322d4afe542aa27240c72af031e` with the existing repairs.
The first attempt failed and stopped. After explicit approval, the narrow
separator correction and the complete gate rerun passed. The injected candidate
is validated at source/test/build level and is not enabled by the application.

| Check | Observed result |
| --- | --- |
| Dart formatter | Exit 0; seven files, five changed |
| git diff --check | Exit 0; existing generated-file line-ending notices only |
| Non-mutating format check | Exit 0; seven files, zero changed |
| Focused tests | Exit 1; 80 passed, six failed |
| Full tests, analyzer, Windows build | Not run after focused failure |

Exact failed command:

```powershell
& 'C:\src\flutter\bin\flutter.bat' test --no-pub test/storage/owned_note_service_test.dart test/storage/captured_reference_test.dart test/storage/owned_settings_test.dart test/storage/settings_isolation_test.dart test/viewmodels
```

Five tests failed with `Note persistence failed (rejectedInput).` at
OwnedNotePersistence.capture, owned_note_persistence.dart:130:7:

- Folder/legacy reference resolution and acknowledged revision updates.
- New identity admission and first publication.
- Plain/foreign capability rejection setup.
- Closing after accepted commits.
- Lease release followed by explicit retry.

The new-editor first-manual-Save test failed at its success assertion
(owned_note_service_test.dart:417): expected true, actual false.

Static diagnosis: the adapter's _target returns Windows-native `p.relative()`,
so folder identities contain backslashes. CommitRecord._validateTarget explicitly
rejects backslashes and requires canonical `/` components. Revision requests for
single-component legacy files passed. The first manual Save failure is consistent
with the same folder-target issue, but its correction remains untested.

Proposed correction: derive the journal target with
`p.posix.joinAll(p.split(p.relative(path, from: reference.binding.root)))` after
existing captured-root containment checks; assert the canonical folder target
in the existing new-reference test. Retain the strict backend schema and native
paths. This diagnosis and proposed correction were reported before requesting
approval; no affected work continued until the user approved correction and rerun.

## Approved correction and rerun

The adapter now derives slash-separated targets from native path components,
after the existing root-containment check. The existing new-reference test
asserts `note_fresh/note_content_fresh.enc`. The strict journal schema, native
file paths and encryption implementation remain unchanged.

| Check | Observed rerun result |
| --- | --- |
| Dart formatter | Exit 0; seven files, one changed |
| git diff --check | Exit 0; existing generated-file line-ending notices only |
| Non-mutating format check | Exit 0; seven files, zero changed |
| Focused tests | Exit 0; all 86 passed, including the six previously failing cases |
| Full tests | Exit 0; all 252 passed |
| Analyzer with approved baseline exception | Exit 0; 99 diagnostics: 97 info, original two warnings, no errors |
| Windows Debug build | Exit 0; 21.7 seconds; produced build/windows/x64/runner/Debug/flutter_application_1.exe |

Analysis removed the prior settings `unnecessary_underscores` info and added an
informational `unnecessary_import` for dart:async in owned_note_service_test.dart.
No new warning/error appeared. See [STAGE2_NOTES_ANALYSIS.md](STAGE2_NOTES_ANALYSIS.md).

The tested source/executable checkpoint is retained at
`.validation/future-notes-validation-stage2-notes-741174cdc99a4a32b410cf9562c87734`.
All 77 copied files match their source SHA-256 hashes. Checkpoint contents are
limited to Dart sources/tests, dependency manifests, RULESBOOK and the Debug
runtime bundle; notes were not copied.

The 75-file validated settings source/executable checkpoint remains retained at
`.validation/future-notes-validation-stage2-settings-1fe9aa2f6b584b5784945c83bf7d68db`.
No app launch/stop, real-note/settings access, dependency/encryption change,
branch, commit or push occurred. Runtime startup/continuous use, complete mutation
ordering, library switching, cleanup-failure injection and production integration
remain pending. Passing this gate does not close any full-plan finding.
