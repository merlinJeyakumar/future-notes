# Owned-service shutdown/cleanup gate results

Approved commands ran on Windows, 2026-10-13, from development at
`a9f6d247d7e27322d4afe542aa27240c72af031e` with the existing repairs.

| Check | Observed result |
| --- | --- |
| Dart formatter | Exit 0; four files, three changed |
| git diff --check | Exit 0; existing generated-file line-ending notices only |
| Non-mutating format check | Exit 0; four files, zero changed |
| Focused tests | Exit 0; all 54 passed, including eight new regressions |
| Full tests | Exit 0; all 274 passed |
| Analyzer with approved baseline exception | Exit 0; 16.0 seconds; 98 diagnostics: 96 info, original two warnings, no errors |
| Windows Debug build | Exit 0; 31.2 seconds; produced build/windows/x64/runner/Debug/flutter_application_1.exe |

Normalized analyzer rules/messages match the preceding Save-coalescing output
exactly: no added/removed diagnostic. Raw output:
[STAGE2_CLEANUP_ANALYSIS.txt](STAGE2_CLEANUP_ANALYSIS.txt).

The tested source/executable checkpoint is retained at
`.validation/future-notes-validation-stage2-cleanup-080a5e6fd65d48158615f428e89c9b34`.
All 78 copied Dart source/test/manifest/rules/runtime files match their source
SHA-256 hashes. The preceding Save-coalescing checkpoint remains available.

Real synthetic sidecar files forced nonrecursive temporary-directory cleanup to
fail. Successful commits retained acknowledged settings/note values; failed
commits retained conflict outcomes and external bytes. Temporary ownership and
close failure remained visible until explicit retry. Journal paths remained
retained. Injected typed/thrown release failures happened before actual release;
another root could close and failed ownership could be retried without exposing
the synthetic raw error detail. Writes after close were rejected.

The application has not enabled owned persistence. No app launch/stop, real-note
or production-settings access, dependency/encryption change, branch, commit or
push occurred. These tests do not simulate native handle-close failure, process
death, power loss or actual Windows exit. Full runtime integration and remaining
repair stages are pending; no full-plan finding is closed.
