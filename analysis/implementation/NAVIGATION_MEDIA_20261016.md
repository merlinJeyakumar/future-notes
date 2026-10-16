# Navigation stability and media controls — 16 October 2026

## Scope and implementation

User reported sidebar jumps on refresh and content movement on note selection, after accepting other in-app animations. They also requested removal of the image-wide “Pause GIF” tooltip, a subtle visible playback control, and media/attachment information initially and on hover.

Refresh now changes status within the existing FILES header footprint; its thin progress bar overlays the header instead of inserting a 24 px block above note rows. The sidebar uses its own non-primary scrollable and supplies keyed row lookup for inventory changes. No sort order or library operations changed.

Note identity changes publish incoming content without a lift or blank frame (the subsequent flash correction removed the initial incoming fade). Toolbar and attachment/operation size transitions start with the new note's acknowledged geometry instead of interpolating across two note identities. Within the same note, the accepted toggle/mode transitions remain. No outgoing editor or protected content is retained. Existing controllers, selection, keyboard behavior, attachment cache, processing and persistence contracts are preserved.

GIF keeps image-click playback toggle and receives a small bottom-right play/pause button. The full-image hover tooltip and large paused icon are removed. Media viewers overlay filename, format, completed cache length and available stored date for three seconds, and while hovered or keyboard-focused. The ribbon ignores pointer input and does not change preview dimensions. No media path is displayed and no extra payload decryption or media probing is introduced. Native video/audio controls and document viewers retain their existing behavior.

Stitch project `6056916933162144137` returned a textual refinement in session `10871734945830681749`, retained at `.stitch/designs/navigation-media-20261016.json`; no new screenshot or screen was returned. The available Flash model was used; Pro was unavailable. Only synthetic filenames were supplied.

## Automated validation

Before changes, `flutter test --no-pub test/navigation_layout_stability_test.dart` reproduced both reported movements: refresh moved a row from y=282 to y=306, and note selection applied a 6 px lift. Evidence: `.validation/navigation-layout-reproduction.txt`.

Formatting and `git diff --check` passed. Scoped analysis of ten affected files completed with no errors/warnings, 27 informational notices; one newly introduced brace notice was corrected. Narrow viewer reanalysis left only its two existing informational notices. The scoped baseline therefore has 26 existing informational notices. Evidence: `.validation/navigation-media-analysis.txt` and `navigation-media-analysis-correction.txt`.

One combined affected suite used 15 files listed in `.validation/navigation-media-test-files.json`. It passed 72 tests but was interrupted when the newly extended navigation test awaited isolate conversion inside the simulated widget clock. Corrected that harness to use `tester.runAsync`, matching existing converter tests. Its first narrow rerun then caught an incorrect zero-write assertion: editor-mode conversion is an actual edit and existing navigation saves it. Corrected the assertion to verify zero writes before conversion and no further writes during animation frames after that legitimate save. The final narrow run passed both navigation tests. All 73 distinct affected tests now pass across these runs; no duplicate full suite ran.

Coverage includes refresh offset/row geometry, note selection with differing docks and HTML/rich toolbar geometry at intermediate frames, stable Quill state during note changes, ribbon timing/hover/focus/reduced motion/disposal and click-through, real decoded GIF frames and paused thumbnails, cache retention/revocation, immediate security teardown during viewer dismissal, keyboard focus, lock state, processing UI, window controls and file drops. Evidence: `.validation/navigation-media-tests.txt`, `navigation-media-test-correction.txt`, `navigation-media-test-final.txt`.

## Build and runtime

Ran `.validation/navigation-media-build.ps1`: verified zero project instances, preserved the previous candidate with matching executable/AOT hashes, then built canonical `lib/main.dart` once using `flutter build windows --release --no-pub --dart-define=FN_MOTION_DIAGNOSTICS=true -t lib/main.dart --obfuscate`, fresh private split-debug symbols and an obfuscation map. Build passed in 42.0 seconds. The existing office FetchContent CMake developer deprecation warning remains. Runner ASLR/high-entropy ASLR/DEP/CFG/stack-cookie/dependent-load checks passed. Evidence: `.validation/navigation-media-build.txt`, `navigation-media-build-receipt.json`.

Rechecked all receipt-bound source, executable and AOT hashes and zero instances before one launch. PID 23520 started at 11:44:36 UTC. Read-only Computer Use showed one normal editor window and existing library navigation; no app input was sent. Startup logs contained expected media/protection initialization, with no application error observed.

Two read-only process samples over 20.8 seconds were responsive. Working set rose from 149.4 to 184.2 MiB, private memory from 147.1 to 183.1 MiB, handles from 570 to 747, and CPU time by 4.98 seconds during startup/manual activity. This short mixed sample does not establish idle stability, absence of leaks or sustained load behavior. The last eight 60-frame diagnostic batches observed then had build p95 0.50–1.61 ms and raster p95 1.12–1.95 ms against the 6.94 ms stage budget, with one reported over-budget frame. These numeric samples are not a dropped-frame count or proof of all interactions. Evidence: `.validation/navigation-media-runtime*.json` and runtime stdout/stderr logs.

The accepted pre-motion executable remains in `.validation/app-motion-previous-release`. The partially accepted motion candidate is retained with verified hashes in `.validation/navigation-media-previous-candidate`. Published portable files and notes were not modified. Existing `v1.3.0` still resolves to `4a8d1a2cfd4a2f9a22d577e465ee3c108b0fb636`. No commit, push, release publication or ZIP is included.

## Manual acceptance

Pending user checks of refresh/selection stability, GIF controls, and initial/hover media information. Automated evidence does not substitute for these physical interactions or sustained attachment-load performance.

The user subsequently confirmed refresh is fixed, but reported a whole-content flash on note selection that predated the motion work. That remaining issue is addressed separately in `NOTE_SWITCH_FLASH_20261016.md`; note-selection visual acceptance is not claimed here. GIF/ribbon acceptance has not yet been reported separately.

Final follow-up: the user confirmed the flash correction works and authorized validation, commit and push of the related source. Unreported individual media checks and sustained load behavior are not inferred from that response. No tag, portable publication or ZIP is authorized by this source-delivery request.
