# Collapse attachments when returning to the editor — 16 October 2026

## Implementation

The user requested collapsing an expanded attachment row when the editor receives focus. ContentArea sends a local UI collapse request when its existing rich-text or HTML focus node gains focus. Editor pointer-down also sends that request, covering clicks when the editor already has focus. AttachmentStrip listens to the optional signal and collapses only when expanded, using its accepted height animation. Manual expansion still works; typing, autosave and progress notifications do not continuously force collapse.

No view-model state, persistence, attachment worker, viewer or cache contract changed. Editor controllers and focus nodes remain mounted. Focus and signal listeners are detached on update/disposal; the ContentArea-owned notifier is disposed. This is an interaction correction using the current layout/motion, with no new design, dependency or storage action.

## Validation

Formatted the three affected Dart files and passed whitespace checking. Scoped analysis passed without errors/warnings. Expanded the focus condition into braces during review and reanalyzed that file; remaining informational notices are in existing code. Evidence: `.validation/editor-focus-collapse-analysis.txt`, `editor-focus-collapse-analysis-correction.txt`.

One combined affected suite passed all 32 tests in `attachment_editor_focus_test.dart`, `attachment_strip_test.dart`, `editor_keyboard_focus_test.dart`, `content_area_locked_test.dart`, `navigation_layout_stability_test.dart` and `attachment_job_panel_test.dart`. New rich-text and HTML scenarios verify focus gain and clicking an already-focused editor both collapse the row, manual expansion remains possible, ordinary cache updates preserve expansion, editor/controller state and body/source remain unchanged, and folding performs no writes, cache invalidations or decryptions. Existing tests cover attachment processing, lock transitions, keyboard/focus behavior, stable note navigation, rendering and cache reuse. All fixtures are synthetic. Evidence: `.validation/editor-focus-collapse-tests.txt`.

## Build and manual acceptance

User saved and exited normally. The accepted Info/ribbon candidate executable/AOT matched its receipt before checkpointing in `.validation/editor-focus-collapse-previous-candidate`. Ran `.validation/editor-focus-collapse-build.ps1` once: canonical `lib/main.dart`, Windows Release, obfuscation, fresh private symbols/map and opt-in numeric motion diagnostics. Build passed in 42.0 seconds. Runner ASLR/high-entropy ASLR/DEP/CFG/stack-cookie/dependent-load checks passed. The existing Office FetchContent CMake developer warning remains. Evidence: `.validation/editor-focus-collapse-build.txt`, `editor-focus-collapse-build-receipt.json`.

Verified every receipt-bound production input and executable/AOT hash and zero instances before one launch. PID 69668 started at 12:12:08 UTC. Read-only Computer Use showed one normal editor window; no app input was sent. Initial logs contained expected initialization. Notes, existing tags, portable releases and unrelated edits are preserved. No publication or ZIP is included.

Two process samples across 24.7 seconds remained responsive during startup/manual activity. Working set was 149.4–175.7 MiB, private memory 146.5–187.9 MiB, handles 603–756 and CPU time increased by 3.19 seconds. The last four 60-frame batches sampled then reported build p95 0.87–1.06 ms and raster p95 1.31–7.97 ms against a 6.94 ms stage budget, including seven over-budget reports; these are not dropped-frame counts or sustained-load/leak proof. The previously documented Flutter Windows AXTree/accessibility bridge error reappeared during interaction. It also occurs in accepted pre-change builds and is not claimed fixed here. Evidence: `.validation/editor-focus-collapse-runtime-observation.json` and runtime stdout/stderr logs.

The user replied “perfect validate and commit push” to the manual rich-text/HTML focus-collapse and manual re-expansion check. Acceptance of the requested interaction is complete; source validation, commit and push are authorized. The accepted hover/Info changes remain part of the related source delivery. No further application rebuild or duplicate regression suite is required when receipt-bound inputs remain identical.
