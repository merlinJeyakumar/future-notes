# Save-coalescing gate results

Approved commands ran on Windows, 2026-10-13, from development at
`a9f6d247d7e27322d4afe542aa27240c72af031e` with the staged repairs.

| Check | Observed result |
| --- | --- |
| Dart formatter | Exit 0; three files, three changed |
| git diff --check | Exit 0; existing generated-file line-ending notices only |
| Non-mutating format check | Exit 0; three files, zero changed |
| Focused tests | Exit 0; all 100 passed, including 14 new regressions |
| Full tests | Exit 0; all 266 passed |
| Analyzer with approved baseline exception | Exit 0; 16.8 seconds; 98 diagnostics: 96 info, original two warnings, no errors |
| Windows Debug build | Exit 0; 21.7 seconds; produced build/windows/x64/runner/Debug/flutter_application_1.exe |

The unnecessary dart:async test import from the preceding 99-diagnostic gate
is removed. No new diagnostic appeared. Rules/messages match the prior settings
baseline after removing its previously corrected underscore info and accounting
for shifted source locations. Raw output: [STAGE3_SAVES_ANALYSIS.txt](STAGE3_SAVES_ANALYSIS.txt).

Observed controlled burst: an active Save followed by 32 requested revisions
published two writes, retaining the latest title. Already-covered duplicates
caused one write. Native worker tests published the active plus latest revision
and preserved synthetic external changes on conflict. Failure/cancellation
settled waiting callers, and typing after capture remained dirty. These are
regression results, not measured app frame-time or continuous-use evidence.

The tested source/executable checkpoint is retained at
`.validation/future-notes-validation-stage3-saves-387e307170894b23abade3f0e29990c4`.
All 78 copied Dart/source/test/manifest/rules/runtime files match source SHA-256
hashes. The preceding 77-file note-service checkpoint remains available.

No application launch/stop, real notes/settings access, dependency resolution,
encryption format change, branch, commit or push occurred. Tests used synthetic
memory-backed notes and disposable native settings/library roots. The singleton
application has not enabled owned persistence. Full mutation ordering, libraries,
Delete, attachments/password transactions and runtime validation remain pending.
No full-plan finding is closed by this gate.
