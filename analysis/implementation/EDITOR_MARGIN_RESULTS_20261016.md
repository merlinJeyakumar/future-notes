# Editor margins — 16 October 2026

Removed the duplicated 16 px rich-text padding. One shared outer inset now supplies 20 px horizontal on desktop, 12 px for content widths below 900 px, and 8 px vertical. Rich text previously accumulated 32 px on every side. HTML shares the outer inset; its source-editor controls remain unchanged. No note content, typography or toolbar behavior changed.

Stitch reference: project 6056916933162144137, screen e76a83bcf906490da7f1db19dada92b1. Synthetic text only; the connected tool offers Flash, not Pro.

Formatting and whitespace passed. Scoped ContentArea analysis exited 0 with 17 existing informational notices, no errors or warnings. The combined hover toolbar, keyboard/focus, mentions, attachment collapse and navigation suite passed all 23 tests. Evidence: .validation/editor-margin-analysis.txt and editor-margin-tests.txt.

One protected Windows Release build passed in 41.7 s, including private symbols and native hardening checks (ASLR, high-entropy ASLR, DEP, CFG, stack cookie and dependent-load flags 0xA00). The existing CMake FetchContent deprecation remains. The accepted executable/AOT was copied and hash-checked in .validation/editor-margin-previous-candidate. Source and artifact hashes were verified before one launch, PID 76944. Startup observations are in .validation/editor-margin-runtime-start.json and editor-margin-runtime-end.json. Manual spacing acceptance is pending.

The published 1.4.0 portable folder verified all 59 files unchanged. Notes, existing tags, dependencies and unrelated work remain preserved. No commit, push or release publication is included in this adjustment.
