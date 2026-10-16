# Note-switch flash correction — 16 October 2026

## Evidence and correction

User confirmed stable refresh but reported sudden flashing across the content when switching notes, and clarified it was present from the beginning. Source at the existing HEAD `f63d18a3c998a34ab06846f817d5da79fc3352c4` confirms `loadNote` sets the global busy flag while dashboard paints a `Colors.black54` overlay with “Processing...”. Fast reads therefore briefly darken the dashboard. The new motion implementation separately faded incoming editor opacity to zero on identity changes; this also needed removal.

Expose the existing `_loading` state through a read-only `isOpeningNote` getter, without changing load, save, session, decryption or publication logic. Dashboard note-opening feedback now blocks pointer actions immediately without a dimming scrim. A thin overlaid progress line appears only after 150 ms; it occupies no layout space, uses one cancellable timer and is disposed as soon as opening finishes. Other busy operations retain their existing feedback. Incoming note identity changes snap to fully visible content, while same-note mode/unlock animations remain. Existing failure retention, stale-request checks, busy/drop/Save guards, locked-content removal and accepted sidebar/media changes are preserved.

This reuses the existing progress styling, without a layout redesign, dependency or storage change. No real notes were used for destructive validation. Prior accepted and partially accepted candidates and the published portable version remain preserved. The final user response authorizes validating, committing and pushing the related source; no tag, ZIP or release publication is included.

## Automated validation

The new dashboard fixture initially used a StatefulWidget lookup on stateless Sidebar; corrected it to retain its Element before testing the behavior. The corrected pre-change regression found the unwanted “Processing...” overlay. The existing geometry regression, extended to check opacity, found editor opacity 0 instead of 1 on note selection. Evidence: `.validation/note-switch-flash-reproduction.txt`, `note-switch-overlay-reproduction.txt`.

Formatted the six affected files and passed whitespace checking. Scoped static analysis completed with 29 pre-existing informational notices, no errors or warnings. After the test-fixture correction, narrow test-file analysis passed cleanly. Evidence: `.validation/note-switch-flash-analysis.txt`, `note-switch-flash-test-analysis.txt`.

One combined suite over ten files (`.validation/note-switch-flash-test-files.json`) passed 75 regressions, then stalled on the new damaged-envelope UI test: unrecognized plaintext invoked the real decrypt worker inside the simulated widget clock. Stopped that run rather than treating it as passed. Replaced only that fixture with valid JSON containing an invalid note schema, exercising the intended load failure without a real crypto isolate. The narrow dashboard file then passed both cases. All 76 distinct affected regressions pass across those runs; no second combined suite was run. Evidence: `.validation/note-switch-flash-tests.txt`, `note-switch-flash-test-final.txt`.

Coverage includes undimmed busy note reads, immediate action blocking, delayed progress with unchanged geometry, successful and failed admission, previous-draft retention, ordinary busy feedback, full editor opacity during selection, stable refresh/scroll, session races, lock state, focus/keyboard, window controls, safe exit and attachment drops/rows. Metadata fixtures and synthetic notes were used; compatibility/encryption/large-file suites were not redundantly repeated.

## Build and runtime

User saved and exited the previous candidate normally. Its executable/AOT matched `.validation/navigation-media-build-receipt.json` and were preserved in `.validation/note-switch-flash-previous-candidate`, separately from the accepted pre-motion executable. Preservation hashes were verified again after building.

Ran `.validation/note-switch-flash-build.ps1` once: canonical `lib/main.dart`, Windows Release, obfuscation and fresh private split-debug symbols/map, numeric motion diagnostics enabled. Build passed in 41.8 seconds. Runner ASLR/high-entropy ASLR/DEP/CFG/stack-cookie/dependent-load checks passed. The existing office FetchContent CMake developer warning remains. Source/executable/AOT hashes are bound in `.validation/note-switch-flash-build-receipt.json`.

Verified all receipt-bound inputs and zero app instances before one launch. PID 66872 started at 11:51:42 UTC. Read-only Computer Use showed one normal editor window; no automated app input was sent. Two process samples across 24.9 seconds were responsive. Working set rose from 149.0 to 177.8 MiB, private memory from 146.5 to 180.6 MiB, handles 576–710 and CPU time by 5.73 seconds during startup/manual activity. The last six 60-frame batches at that sample had build/raster p95 at most 1.84/2.18 ms against the 6.94 ms stage budget, with one over-budget stage report. This mixed observation is not idle/leak/sustained-load proof or a dropped-frame count.

Runtime stderr exposed repeated Flutter Windows `accessibility_bridge.cc(114)` errors: `Failed to update ui::AXTree ... will not be in the tree and is not the new root`. Stopped completion reporting and compared historical logs before making further changes. Both `.validation/window-chrome-runtime.stderr.txt` (accepted pre-motion candidate) and `.validation/navigation-media-runtime.stderr.txt` contain the same error class. It therefore predates this correction; its frequency across unequal sessions cannot be compared. No crash was observed, but runtime logs are not clean and accessibility correctness is not claimed. An extra close request made during diagnosis was explicitly withdrawn after identifying this baseline issue. No speculative accessibility patch or second build was performed. Evidence: `.validation/note-switch-flash-runtime*.json`, runtime stdout/stderr, and the historical logs above.

## Manual acceptance

The user replied “its working fine, validate and commit and push” to the locked/unlocked-note switching and steady-refresh check. They also confirmed the candidate was closed normally. Refresh and note-switch flash acceptance is complete. This does not claim the separate baseline accessibility error is resolved, infer unreported media checks, or establish sustained load behavior.
