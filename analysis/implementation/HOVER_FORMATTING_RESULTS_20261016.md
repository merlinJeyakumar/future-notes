# Hover formatting — 16 October 2026

## Final requested implementation

One actual card contains both formatting rows. The primary row remains visible. Hover reveals the secondary controls within that same card; there are no separate row cards or expansion button. Keyboard focus retains access. The card expands over the editor and reserves a constant 66 px resting footprint, preserving editor geometry, selection and focus. Hidden secondary controls are excluded from interaction and semantics. Existing locking/mode/navigation removal and reduced-motion behavior remain.

Stitch reference: project 6056916933162144137, screen 1f9f7a475e5243ce83a567e039362ff5. Synthetic content only; existing styling retained. The connected tool exposes Flash, not Pro.

## Validation

Formatting and whitespace passed. Final scoped analysis of the widget, toolbar tests and editor keyboard/focus tests reports No issues found.

The first single-card combined run had 21 passes and two failures: a dropdown test needed to await overlay layout; delayed primary-row measurement caused a 16 px navigation bounce. Compilation was stopped. Replacing delayed measurement with the existing fixed row footprint and attaching the portal before the first frame corrected the bounce; no runtime candidate containing this regression was built.

- Original combined suite: mentions, attachment focus and editor focus passed; toolbar and navigation failures were corrected.
- Corrected hover-only toolbar and editor keyboard/focus suite: 11 passed.
- Final first-frame toolbar and navigation suite: 7 passed.
- Coverage includes a single common card ancestor, hover entry/exit, rapid reversal, reduced motion, keyboard access/Escape, dropdown selection, immediate removal, stable editor geometry/selection/focus, Home/End, formatting focus, and navigation without bounce.

Evidence: .validation/same-card-formatting-analysis-final.txt, same-card-formatting-tests-final.txt, same-card-formatting-initial-frame-tests.txt. The initial failed log is retained in same-card-formatting-tests.txt.

## Build and manual acceptance

The final single-card protected Windows Release build passed in 52.8 s, with obfuscation/private-symbol validation and native hardening checks (ASLR, high-entropy ASLR, DEP, CFG, stack cookie and dependent-load flags 0xA00). The existing CMake FetchContent deprecation remains.

Before compilation, the previous executable and AOT payload were copied and hash-checked in .validation/same-card-formatting-previous-candidate. Build inputs and artifact hashes were validated against .validation/same-card-formatting-build-receipt.json before one launch of PID 11904. The user manually accepted the final single-card candidate with “its perfect” and requested validation, commit and push. Process observation at 11 s showed responsive startup, about 154 MiB RSS and 566 handles, with native protections initialized and no reported startup exception. A second observation is retained in .validation/same-card-formatting-runtime-end.json; these short observations do not establish prolonged operation or manual visual acceptance.

The published FutureNotes-1.4.0-windows-x64 folder verified unchanged after the preceding build. Notes, tags, dependencies and unrelated files remain preserved. Commit and push to development are authorized after manual acceptance; no release publication or tag changes are included.

Earlier automatic approval review blocked native screen capture because its target was uncertain. No capture workaround was attempted. The user provided manual visual confirmation; the blocked capture is not used as evidence.

## Final commit gate

After manual acceptance, formatting and whitespace passed again. The combined five-file suite passed all 23 tests on the final source. Scoped analysis including ContentArea returned exit 0 with no errors/warnings and 17 existing informational notices. Logs show initialized native protections without a startup exception. Build-input and executable/AOT hashes still match the accepted protected candidate; an unchanged build was not repeated. The published portable folder again verified all 59 files unchanged. Evidence: .validation/hover-formatting-commit-analysis.txt and hover-formatting-commit-tests.txt.
