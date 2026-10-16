# Natural collapsed toolbar height — 16 October 2026

Removed the collapsed toolbar's fixed 56 px height/cap. OverflowBox now defers its vertical size to the actual controls while horizontal overflow remains clipped. The card keeps its full available width and existing 4 px inner gutters, border, hover wrapping and keyboard access. No guessed replacement height or asynchronous size measurement was introduced. Editor margins and expanded layout remain unchanged.

Initial scoped analysis stopped on an undefined OverflowBoxFit symbol; adding the explicit Flutter rendering import corrected it. Final analysis reports No issues found. Formatting and whitespace passed. The combined five-file suite passed all 23 tests, including natural-height fixtures at 32/48/72 px, hover/reversal, reduced motion, fixed width, dropdown/focus, Home/End, mentions, attachment collapse and navigation stability. Evidence: .validation/natural-formatting-height-analysis-corrected.txt and natural-formatting-height-tests.txt.

One protected Windows Release build passed in 41.0 s. Private-symbol/obfuscation and PE hardening checks passed (ASLR, high-entropy ASLR, DEP, CFG, stack cookie and dependent-load flags 0xA00); existing CMake FetchContent deprecation remains. The previous executable/AOT were copied and hash-checked before compilation. Source and artifact hashes matched the build receipt before one launch, PID 80840. Runtime observations/logs are under .validation/natural-formatting-height-runtime-*. Manual visual acceptance passed: the user confirmed “perfect” and requested commit/push.

The published 1.4.0 portable folder verified all 59 files unchanged. Notes, tags, dependencies and unrelated work remain preserved. Commit and push to development are authorized. No release publication or tag changes are included.

Before commit, whitespace and build-receipt input/executable/AOT hash checks passed. The prior 23-test passing run and clean scoped analysis apply to the unchanged accepted source; no redundant build or suite was repeated.
