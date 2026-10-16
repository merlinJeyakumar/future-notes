# Single-row scrolling formatting — 16 October 2026

## Implementation

Replaced the hover overlay with one fixed-height card in ordinary layout. All existing formatting controls appear in a continuous horizontally scrolling row. Vertical mouse wheel input maps to horizontal movement; native horizontal input resolves once, preventing doubled scrolling. The existing horizontal scroll view handles touchpad scrolling. Small left/right arrows scroll by part of the viewport and disable at their respective limits. Reduced motion jumps immediately; ordinary arrow movement eases briefly. The recent single-layer editor margins remain intact.

No overlay, hover expansion, disclosure timer, global Escape handler or animation controller remains. TextFieldTapRegion and existing formatting callbacks preserve selection/focus; arrow clicks restore editor focus. Keyboard Escape from toolbar focus restores the editor. Controllers are disposed. Lock and HTML mode still remove the toolbar through existing ContentArea state.

Stitch project 6056916933162144137, screen a97204805fd7441aa90c8c0dcf413077. Synthetic text only; existing styling retained. Flash used because the connected tool does not expose Pro. Source toolbar height stays at the existing 66 px including border.

## Automated validation

Formatting/whitespace passed. Scoped ContentArea analysis retains 17 existing informational notices. The new widget and tests analyze with No issues found.

The combined suite ran 22 tests: 21 passed, while the reduced-motion arrow test exposed Flutter's rejection of a zero-duration animateTo. Compilation stopped. The reduced-motion path was corrected to jumpTo. All four toolbar tests then passed; the other 18 editor keyboard/focus, mentions, attachment collapse and navigation tests passed in the combined run. Coverage includes single fixed-row geometry on hover, vertical/horizontal wheel inputs without double application, arrow limits, focus/selection, resizing, reduced motion, dropdowns and safe disposal.

Evidence: .validation/scroll-formatting-tests.txt, scroll-formatting-tests-corrected.txt and scroll-formatting-analysis-final.txt. Native physical touchpad acceptance remains a manual check.

## Build and runtime

One protected Windows Release build passed in 41.9 s. Obfuscation/private symbols and PE hardening checks passed (ASLR, high-entropy ASLR, DEP, CFG, stack cookie, dependent-load flags 0xA00). Existing CMake FetchContent deprecation remains. The previous executable/AOT was copied and hash-checked in .validation/scroll-formatting-previous-candidate. Input and artifact hashes were checked against the build receipt before one launch, PID 19768. Runtime observations are retained under .validation/scroll-formatting-runtime-*.json and logs. Manual acceptance is pending.

Notes, existing tags, dependencies, published 1.4.0 portable folder and unrelated work remain preserved. The portable bundle verified all 59 files unchanged. No commit, push or release publication is included.
