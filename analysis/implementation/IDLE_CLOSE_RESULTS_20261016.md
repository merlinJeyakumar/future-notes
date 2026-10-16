# State-aware application Close — 16 October 2026

## Implementation

Removed the unconditional Exit Future Notes? dialog from the production close path. Idle empty drafts and saved notes proceed directly through prepareToExit, cache invalidation and the existing ordered shutdown. Completed job history does not prompt. Required draft, active-operation, save-failure and cleanup-failure decisions remain owned by their existing coordinator. Finalizing publications are still awaited. The optional injected confirmExit hook remains compatible for tests/hosts. The native/in-app Close lifecycle, concurrent-request coalescing and shutdown retry behavior remain unchanged.

No new dialog design or UI surface was introduced. No notes, dependencies, encryption formats or release metadata were changed. Release promotion remains paused; version remains 1.4.0+7.

## Validation

Initial affected run was stopped while a new saved-note fixture waited across Flutter fake-async/runAsync save boundaries. No build proceeded. The fixture now loads an existing synthetic plaintext note and asserts that it is clean, avoiding unrelated encryption/save scheduling. All six corrected window-control tests pass: idle empty/saved close with terminal export history, in-app Close, draft Cancel/Discard and Keep running during active work.

The first filtered lifecycle command failed with exit 255 because the Windows batch launcher interpreted the pipe characters in the name regex as shell pipelines. Rerunning with the simple name filter exit passed five relevant lifecycle cases. Forty-six additional draft-transition, cache-lifecycle, shutdown-sequence and owned-mutation integration tests passed. Total affected successful checks: 57. Tests cover cancellation, active/finalizing work, retained editors, concurrent close, cleanup failures/retries, stored-note preservation and cache cleanup. Dashboard new-note/date-display cases were outside the filtered lifecycle selection; the suite was not claimed as a full application test run.

Formatting and whitespace passed. Scoped analysis passed with --no-fatal-infos, with three existing informational notices in dashboard_screen.dart and no errors/warnings. The newly introduced test brace-style notice was corrected before final analysis.

Evidence: .validation/idle-close-tests.txt (stopped run), idle-close-window-tests-corrected.txt, idle-close-lifecycle-tests.txt (launcher failure), idle-close-lifecycle-tests-corrected.txt, idle-close-storage-tests.txt and idle-close-analysis-final.txt.

## Build and runtime

One protected Windows Release build passed in 42.2 seconds after preserving/hash-verifying the accepted executable/AOT checkpoint. Private symbols and obfuscation remained enabled; the native runner passed ASLR, high-entropy ASLR, DEP, CFG, stack-cookie and dependent-load-flag checks. The existing CMake FetchContent deprecation warning remains. Source and artifact hashes matched before launching PID 69084; startup and a 33-second follow-up were responsive with process protections initialized and no exception pattern in sampled logs. The follow-up used approximately 290 MiB working set, 6.02 accumulated CPU seconds and 1,032 handles. Recent frame samples had build/raster p95 below 1.5 ms with no over-budget frame in those samples. These are bounded startup observations, not long-duration resource claims. In response to the manual checklist, the user requested validation, commit and push; individual manual outcomes were not separately reported. The published portable 1.4.0 bundle verified all 59 files unchanged. Version remains 1.4.0+7; release promotion stays paused. Notes, existing tags and unrelated changes remain preserved. No version change, tag creation or publication is included.

Final commit gate: formatting/whitespace passed; scoped analysis of all seven changed Dart files passed with --no-fatal-infos, retaining 29 existing informational notices and no errors/warnings. Thirty-two export-panel, close-control and owned-mutation tests plus five selected dashboard lifecycle exit tests passed (37 total). All build-input and executable/AOT hashes still matched the protected-build receipt. The user authorized committing and pushing these fixes together with the accepted compact export-panel work to development. Evidence: .validation/close-export-final-analysis.txt, close-export-final-tests.txt and close-export-final-lifecycle-tests.txt.
