# PDF button zoom — 16 October 2026

## Cause and change

The user reported that PDF +/− zoom moved the page toward a corner rather than
keeping the visible view centered. `_PdfSurfaceState._zoom` replaced the entire
transform with a diagonal scale matrix, dropping its translation and applying
scaling about the top-left origin. It also discarded the position after panning.

The correction reads the actual PDF viewport dimensions, captures the scene
point under its center, and applies the new scale with a translation that keeps
that point stationary. Translation is constrained to the viewer's bounds when
zooming out. Returning to minimum scale therefore recenters the fitted page.
Existing zoom limits, Fit page control, page rendering and appearance remain.
No attachment storage, decryption, file format, note data or dependency changed.

## Validation

- Formatted the changed source and test; whitespace passed.
- Scoped analysis of the two files passed with no issues. Its original server
  run was slow but continued doing work and completed; no duplicate analyzer run
  was started or treated as a pass before completion.
- One affected suite passed all nine tests:

  ```powershell
  flutter test --no-pub test/attachment_document_preview_test.dart
  ```

  The native PDF test now checks actual rendered-page centering across repeated
  zooms, a panned center preserved through +/−, maximum/minimum limits, Fit page,
  narrow/wide viewport resizing, page changes and joined native disposal. The
  same suite covers Word preview, explicit-open behavior, failures and locking.
- One protected Windows Release candidate build passed in 43.9 seconds. It uses
  canonical `lib/main.dart`, obfuscation and fresh private crash symbols/maps.
  Actual executable CFG/DEP/ASLR/stack-cookie/DLL-search checks passed. The
  existing CMake FetchContent_Populate developer deprecation warning remains.
  The candidate was launched once for manual acceptance; no rebuild was needed.
- Startup observation at 17.1 seconds: one responsive Future Notes window,
  158.8 MiB working set, and a successful protection-initialization log without
  errors. PDF interaction remains pending the user's manual acceptance. No
  automated native keyboard or mouse input was sent.

## Touchpad follow-up

The user accepted the +/- button correction, then reported that both touchpad
pinching and two-finger scrolling were still incorrect (also present before the
button fix). This is not recorded as a passing touchpad check.

Flutter's InteractiveViewer has separate paths for native pan/zoom gestures,
trackpad scroll signals, mouse-style wheel signals and discrete scale signals.
Its default mouse-style wheel path zooms, and its default scale path anchors to
the event position. The PDF viewer now explicitly routes those inputs:

- Native two-finger pan and mouse dragging retain InteractiveViewer's pan and
  pan inertia. Native trackpad scroll signals pan without scaling.
- Mouse-style scroll signals also pan, including horizontal scroll. Ctrl+wheel
  remains a zoom gesture. This covers the wheel-style format without requiring
  a trace or assumption about the user's actual device event classification.
- Discrete scale signals and cumulative native pinch use the same centered,
  bounded transform as the zoom buttons. The first attempt also retained native
  pinch translation, which caused the manual failure described below.
  Framework scaling is disabled to avoid applying a second cursor-anchored
  transform. Gesture state clears at interaction end.

The expanded native PDF regression exercises both scroll formats, horizontal
scroll, off-center discrete scaling, native pinch, native pan and Ctrl+wheel,
alongside the accepted button/Fit checks. Scoped analysis passed with no issues;
one affected suite passed all nine tests. Synthetic events establish routing
behavior, not physical hardware acceptance. Evidence uses
`.validation/pdf-touchpad-*`. One new protected build passed in 42.3 seconds;
private-symbol and executable-mitigation verification passed. It was launched
once for physical touchpad acceptance, which the user rejected. The earlier
button-fixed native bundle is preserved at
`.validation/pdf-touchpad-previous-release`. The user confirmed closing it.

## Mixed-motion pinch correction

The user reported sideways drift and supplied a screenshot. No contents or copy
of that personal document were used as a fixture. The prior test used scale-only
pinch events, while the implementation applied `focalPointDelta` as a pan after
scaling. Real pinches report both scale and centroid movement, so this could
move the page sideways even when the intended action was straight zoom.

The pinch now captures the scene point under the viewport center at gesture
start and derives each scale update from that fixed anchor. It does not add
pinch translation. Same-scale updates still restore the anchor, including when
zoom reaches a bound. Ordinary pan remains a separate gesture and preserves
its prior behavior; buttons and Fit page retain the accepted implementation.

The native regression now includes a pan-first gesture followed by simultaneous
scale and substantial sideways motion, a same-scale moving update, and reversed
zoom. It checks the anchor and scale after every update. Scoped analysis passed
with no issues and the one affected suite passed all nine tests. Evidence is
under `.validation/pdf-pinch-anchor-*`. One protected candidate build passed in
42.6 seconds; private-symbol and executable-mitigation verification passed.
The candidate was launched once. Startup reported process protections initialized,
with a responsive Future Notes window and no startup errors in captured logs.
Manual acceptance failed: straight pinch zoom was improved, but the user still
reported unwanted sideways pan during the pinch. No native input was automated.

## Single transform owner

Further review of the installed Flutter implementation found that
`InteractiveViewer` writes pan transforms before calling `onInteractionUpdate`.
It also wraps discrete pointer signals in start/update/end callbacks. The custom
handler shared its transformation controller and gesture state with those paths,
so interleaved signals could reset a native pinch and framework pan could produce
intermediate sideways transforms. The earlier fix corrected the final matrix,
without removing these competing writers.

The PDF surface now uses one gesture controller with a `GestureDetector`, a
resolved pointer-signal listener and an animated transform. No framework viewer
also mutates its matrix. Native drag/two-finger pan applies bounded deltas;
native pinch keeps its gesture-start center until end, even when scale returns
to 1. Discrete signals cannot reset native gesture state or add pan during a
pinch. No inertial transform is started after release. Buttons, Fit, rendering,
zoom limits and viewport bounds retain their prior behavior.

Scoped analysis passed with no issues. The affected suite passed nine tests.
An initial test run warned that the drag finder targeted the transformed child;
the finder was corrected to the gesture surface and the affected suite rerun
without that warning. The regression checks every intermediate transform,
mixed native movement, interleaved trackpad scroll signals, return through scale
1, subsequent separate pan, buttons and Fit. Evidence uses
`.validation/pdf-gesture-owner-*`. After normal exit of the previous candidate,
one protected build passed in 42.5 seconds. Private-symbol and PE mitigation
checks passed. The existing CMake FetchContent developer deprecation warning
remains; it did not fail compilation. The candidate was launched once for
manual checking. On 16 October 2026 the user answered "perfect now" to the
combined check of centered pinch/reversal, separate two-finger pan, +/- and Fit
page. Physical touchpad acceptance is recorded as passed for this candidate.

## Delivery boundary

The published v1.2.1 portable folder, release assets and tag are preserved.
The user authorized committing and pushing this validated correction to
`development`. This source delivery does not publish a new release or move tags.
The candidate output is `build/windows/x64/runner/Release/FutureNotes.exe` and
retains version 1.2.1+4 until a new release is explicitly requested. Evidence is
under `.validation/pdf-centered-zoom-*`. The user confirmed closing the previous
app before the candidate build. No agent keyboard/mouse input is planned.
