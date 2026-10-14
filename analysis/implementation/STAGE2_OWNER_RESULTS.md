# Owned persistence worker gate results

Approved gate executed on Windows on 2026-10-13, from development at
`a9f6d247d7e27322d4afe542aa27240c72af031e` with the existing repair changes.
Exact commands are in [STAGE2_OWNER_VALIDATION.md](STAGE2_OWNER_VALIDATION.md).

| Check | Observed result |
| --- | --- |
| Dart formatter | Exit 0; two files formatted |
| git diff --check | Exit 0; existing generated-file line-ending notices only |
| Non-mutating format check | Exit 0; two files, zero changes |
| Focused worker tests | Exit 0; all 16 passed |
| Full test suite | Exit 0; all 215 passed |
| Analyzer with approved baseline exception | Exit 0; 98 diagnostics, 96 info, original two warnings, no errors; no added or removed diagnostics |
| Windows Debug compilation | Exit 0; 9.8 seconds |

Analyzer output is retained in [STAGE2_OWNER_ANALYSIS.txt](STAGE2_OWNER_ANALYSIS.txt).
The worker tests use disposable settings/library roots. They cover real-isolate
readiness, launch/readiness deadlines, startup and idle-exit failures, bounded
descriptor queues, stale/foreign ownership, file-backed commits, contention
between native workers, recovery before publication and orderly shutdown.
Only uninitialized or explicitly root-free owned test isolates were stopped.

No project app instance was found before building. No app was launched or
stopped; real notes/settings and the opaque untracked root note were not used.
No dependency or encryption-format change was made. No branch/commit/push.

The tested sources, tests, manifests and Debug bundle are retained at
`.validation/future-notes-validation-stage2-owner-54a6d15bf54448d5a56dffbe76f44e9e`.
All 73 copied files matched their source SHA-256 hashes. The previous 71-file
backend checkpoint remains available.

This passes the worker foundation's source/test/build gate. Application
file/settings adoption, production activation, full mutation ordering, real
writer interruption, UI latency/resource profiling and continuous app operation
remain pending. Tests and compilation do not prove app runtime safety or
other-platform support. No baseline finding is closed by this gate.
