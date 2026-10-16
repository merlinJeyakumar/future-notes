# In-app motion — 16 October 2026

## Implemented behavior

Shared `AppMotion` definitions provide cubic ease-out entrances and the paired ease-in exit, with no bounce or continuous decorative animation. App-owned dialogs use a typed `AppDialogRoute`/`showAppDialog<T>` helper: fade and scale 0.97–1 over 220 ms, reversing over 160 ms. Existing modal results, barriers, focus behavior and Navigator ownership remain.

The sidebar retains its 280 px content width during a clipped horizontal reveal. Its mounted content and search state survive reversals; closing immediately excludes pointer, focus and semantics. Attachment rows animate height at their full-width boundary, avoiding unintended width growth or clipped controls. Auxiliary operation panels and disclosure icons animate expansion/collapse. Menus use 120/90 ms timing, and explicit app tooltips retain Material styling, positioning and semantics with the shared short motion.

Incoming acknowledged note identities publish at full opacity without moving the viewport. Same-note editor-mode/unlock changes fade and lift 6 px over 160 ms. One child is retained, rather than crossfading two editor instances. Session/path/access/mode identify the transition; typing and autosave do not restart it. Locked content, toolbar and attachment access are removed immediately. System reduced-motion changes snap active custom panel/dialog transitions to their endpoint. Hidden child tickers are disabled; owned controllers are disposed.

Ordinary preview dismissal pauses playback immediately, reverses the route, then disposes resources once. Lock/cache invalidation/removal/shutdown use the existing registered close callback to blank the preview immediately and join cleanup. Already-popping routes are handled without attempting an invalid second removal. Native pause failure falls back to immediate resource closure. Existing decryption, file-backed cache retention, attachment worker state and storage contracts are unchanged.

Windows caption controls, minimize/maximize, actual application exit and native file dialogs retain their existing behavior. No layout/text-size redesign or dependency change is included. The user subsequently authorized validating, committing and pushing the related source changes; tags and release publication remain outside scope.

## Design reference

Stitch project `6056916933162144137`, screen `6687591b37184ef785cc968e886eba36`. The available Flash model was used after disclosing that Pro was not selectable. Synthetic interactive reference: `.stitch/designs/app-motion-20261016.html` and `.png`. Its representative panel/dialog/viewer transitions informed the Flutter implementation; generated unrelated shortcuts/layout were not substituted.

## Automated validation

- Formatting and whitespace checks passed. Scoped analysis initially ran slowly but continued CPU/I/O work; the original run was awaited rather than duplicated or treated as a pass.
- The first scoped analysis found two missing tooltip-wrapper parameters. These and new style notices were corrected. Narrow corrected-file analysis passed; remaining informational notices are in existing code. Evidence: `.validation/app-motion-analysis*.txt`, `app-motion-final-analysis.txt`, `app-motion-frame-log-analysis.txt`.
- One combined affected suite used the 23 files recorded in `.validation/app-motion-test-files.json`. It completed with 140 passing and six failing tests. Failures identified security cleanup of an already-popping viewer, unintended attachment width animation, and assertions measuring transient rather than finished layouts.
- Corrected immediate viewer removal, moved attachment size animation to the full-width row, and updated collapse/expansion/geometry checks to wait for their intended endpoint. Expanded failed-pending items are checked for their direct Retry action; only the committed item has More. The six affected files reran with 32 passing and one remaining timing assertion in the window-drop test. That file then passed both tests after waiting for the dock reveal before measuring its geometry. No second full suite ran.
- All 146 distinct affected regressions now pass across those runs. A further frame-log test passed, bringing the total to 147 distinct passing tests. This covers intermediate motion frames, reversal continuity, dynamic reduced motion, dialog results, immediate preview revocation, focus/keyboard behavior, lock/unlock, media/GIF/document disposal, attachment cache lifecycle, import/export dialogs, safe exit and window-wide drops.
- One protected Windows Release build through canonical `lib/main.dart` passed in 49.5 seconds, with obfuscation and private symbols/maps. The existing office FetchContent deprecation warning remains. Runner ASLR/high-entropy ASLR/DEP/CFG/stack-cookie/dependent-load checks passed. Evidence and source/executable/AOT hashes: `.validation/app-motion-build.txt` and `app-motion-build-receipt.json`.

## Runtime observation and preservation

Verified zero project instances and matching build-receipt hashes before one launch. PID 37140 started at 11:26:43 UTC. Computer Use showed one normal editor window with existing library navigation and the unchanged final layout; no keyboard/mouse input was sent and no real-note mutations were performed as validation.

Three read-only samples over 20.1 seconds were responsive throughout. Working set stayed approximately 150 MiB, private memory approximately 146 MiB, handles 596–594; CPU time increased by 0.016 seconds. Logs contained expected media/protection initialization and no error output.

This candidate was compiled with `FN_MOTION_DIAGNOSTICS=true`. The opt-in frame callback stores at most 60 build/raster samples per batch, emits numeric aggregate timing only, creates no timer/idle animation and unregisters on disposal. The define defaults false. An observed 60-frame batch reported build/raster p95 of 0.83/5.18 ms against the initial display's 6.94 ms stage budget; two frames exceeded the stage budget. This mixed runtime sample does not establish sustained under-load performance or dropped-frame counts. Additional batches can be inspected during manual exercise without automatic app input.

The accepted executable and AOT are preserved at `.validation/app-motion-previous-release` and match the previous accepted receipt. Published `build/releases/FutureNotes-1.3.0-windows-x64` remains unchanged. Existing release tag `v1.3.0` still resolves to `4a8d1a2cfd4a2f9a22d577e465ee3c108b0fb636`. Notes, unrelated edits and loose files are preserved.

## Manual acceptance and correction

The user reported “everything perfect” except movement when selecting notes. They subsequently identified sidebar movement during refresh and movement inside the content area on selection, and requested subtle GIF controls and a transient media-information ribbon. Those specific corrections are tracked in `NAVIGATION_MEDIA_20261016.md`. The original motion candidate is therefore partially accepted, not a fully accepted replacement. Sustained performance under attachment load and any unreported individual manual checks remain unproven.

After the later corrections, the user confirmed steady refresh and note switching, including the locked/unlocked-note check, and requested validation, commit and push. Final production input and executable/AOT hashes match the tested protected candidate. The pre-existing Windows accessibility-tree log error remains documented in `NOTE_SWITCH_FLASH_20261016.md`; it is not claimed fixed. No further source rebuild or duplicate suite is required for this documentation-only acceptance update.
