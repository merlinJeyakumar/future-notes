# Discovery/search ownership gate results

Approved gate ran on Windows, 2026-10-13, from development at
`a9f6d247d7e27322d4afe542aa27240c72af031e` with the existing repairs.
The implementation's flow/async joins were reviewed before execution; format
and analyzer ran before one test suite and one required Windows build.

| Check | Observed result |
| --- | --- |
| Dart formatter | Exit 0; five files, five changed |
| git diff --check | Exit 0; existing generated-file line-ending notices only |
| Analyzer with approved baseline exception | Exit 0; 9.8 seconds; 97 diagnostics: 95 info, original two warnings, no errors |
| Single full integration suite | Exit 0; all 306 passed; final progress time 00:18 |
| Single Windows Debug build | Exit 0; 15.7 seconds; produced build/windows/x64/runner/Debug/flutter_application_1.exe |

Normalized analyzer rules/messages exactly match the readiness baseline:
no added or removed diagnostics. Raw output:
[STAGE7_ORDERING_ANALYSIS.txt](STAGE7_ORDERING_ANALYSIS.txt).

The 22 new regressions passed: 11 native/read-only scanner tests and 11
view-model widget tests. A hundred queued refresh descriptors coalesce to the
latest one; stale partial/final/failure replies cannot publish or advance a
different active request. Root generations and path-resolution guards prevent
older discovery from replacing a newer request. A real 125-note synthetic scan
published lengths 10 and 125; a ten-note scan published one final snapshot.
Query/listing races, stale failures, disposal, debounce cancellation, immutable
filter input and sanitized errors passed with zero view-model note writes.

The tested 81-file source/executable checkpoint is retained at
`.validation/future-notes-validation-stage7-ordering-2d745fdf585041c7bbfdc24e7c65352d`.
Every copied Dart source/test, manifest, rules and runtime file matches its
source SHA-256 hash. The prior readiness and cleanup checkpoints remain.

No duplicate focused/full run, extra passing-check rerun, app launch/stop,
real-note access, dependency/encryption change, production persistence activation,
branch change, commit or push occurred. Unrelated dirty/generated files and the
opaque root note folder remain preserved. Tests used disposable synthetic roots
or explicitly injected in-memory services only.

This is source/test/build validation, not application runtime or performance
evidence. Watcher rebinding, transactional library changes, full mutation
ordering, attachment/protection/package repairs and remaining platforms remain
pending. The earlier intermittent Windows native-move failure's cause remains
unresolved; this run passed that test and retains its numeric error diagnostic,
without claiming remediation. No full-plan finding is closed by this gate.
