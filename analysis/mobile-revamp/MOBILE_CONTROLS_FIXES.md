# Mobile task indicators, formatting disclosure and HTML structure

18 October 2026. No commit, push, tag or release publication.

## Implemented

- An open Background tasks panel previously retained an active snapshot after
  its coordinator removed the job. Remove orphaned active snapshots; keep
  acknowledged terminal results until the panel closes.
- Separate active count from interrupted recovery count. Mobile list/editor
  badges count actual active work only. Interrupted work uses a quiet history
  control without a processing badge or spinner.
- Android interrupted notifications have Dismiss and swipe handling. Persist
  notification dismissal in bounded private job records so it survives restart;
  retain recovery metadata, picked-source information and library recovery
  objects. Dismissal creates no Flutter engine or extra writer when the process
  is absent. Existing explicit recovery acknowledgement removes only the chosen
  ID from both ledgers. Active IDs cannot be dismissed by this path.
- In-app Dismiss notification preserves the reviewable interrupted entry. Native
  dismissal updates an open panel through the existing job channel. Cancel for
  actual work continues through the existing coordinator; no forced termination.
- Replace mobile Format/Less text with 48 dp expand/collapse chevrons and
  accessible tooltips. Preserve focus, normal layout and reduced motion.
- Mobile HTML mode/Format HTML requests expanded text-block structure, including
  plain and mixed inline text. The established formatter's desktop default stays
  unchanged. Preserve whitespace-sensitive elements, literal edge spaces, tags,
  entities and links. Use a compact monospaced code view with line numbers,
  horizontal scrolling and disabled smart quotes.
- iOS source supports the corresponding scoped job-record dismissal/acknowledge
  calls. No Mac build or iOS device validation is claimed.

## Validation

Preserved accepted APK SHA-256:
`691b56f56a1bf3510b418c81668067d313d870c3ba8144e988c498c0f763848f`
under `.validation/mobile-controls-accepted/`.

Combined affected suite passed 44 tests. Subsequent focused presentation/HTML
gate passed 14 tests after the orphaned snapshot and recovery-preserving
dismissal corrections. These include duplicate executions of relevant cases;
they are not 58 unique tests. Scoped analysis passed without errors/warnings;
existing informational style notices remain. Desktop presentation file hashes
match their pre-task snapshot. Whitespace checks passed.

The new mobile HTML widget fixture initially omitted the production dashboard's
model listener, so its mode-switch assertion could not locate the rebuilt code
field. Correcting the fixture to reproduce production wiring passed the UI
structure and unchanged rich-text round trip. The accepted APK was not replaced
during this failed gate.

Stitch Flash refined synthetic mobile states; Pro was unavailable through the
connector. Reference screen `e86564adc301484f869f73493d1145a4`, project
`6056916933162144137`. Generated encoding/line-count telemetry and extra recovery
screens are reference-only and were not added.

Protected normal `lib/main.dart` Android Release build passed (1169.3 seconds on
this host). APK SHA-256:
`a01c7714f390b1e7476dd2c6834c72105e61752400d0eff81afad7ba7706cade`.
All 18 native libraries, 16 KiB APK alignment and packaged notification receiver
checks passed. Streaming update installation succeeded without clearing data.
Cold launch took 1855 ms. The app stayed foreground on the unlocked LG for
20 seconds with a stable PID, zero fatal/layout log matches and PSS 164,477 KiB.
Screenshot inspection confirmed the normal notes list with a quiet history icon,
no stale processing badge and no note-row loading indicators while idle.

Android notification inspection found three app records, zero ongoing
notifications, zero progress notifications, and Dismiss action mentions. This
validates idle notification generation/flags. Native notification swipe/cancel
dispatch, persistence across a real restart and final visual acceptance remain
manual checks; Dart tests validate channel/state behavior, not those Android OS
interactions. No app input or real-note edits were sent during validation.

Evidence: `.validation/mobile-controls-packaging.json`,
`.validation/mobile-controls-startup.json`,
`.validation/mobile-controls-native-notifications.json`, and
`.validation/mobile-controls-final-tests.txt`.

Notes, encryption formats, optional verification defaults, portable releases
and existing tags are preserved. iOS source changes remain unbuilt/unvalidated
without Mac/Xcode and device access.

## Manual acceptance and icon correction

The user confirmed the phone checks worked, including the chevron, HTML structure,
Cancel and notification dismissal. The follow-up changes the mobile header's
history glyph to the same outlined pause indicator used by interrupted task rows.
The tooltip remains Review interrupted tasks. Running jobs retain their sync
indicator and count badge; there are no desktop or task-execution changes.
The accepted APK above was preserved before replacement. Scoped analysis and
all three task-state tests passed. The protected normal build passed in 69.8 s;
APK SHA-256:
`b10eacc313c37f58cb44fefb6b651c0253507810322a72091b6fffc1d343e0af`.
16 KiB APK alignment, data-preserving installation and cold launch (1673 ms)
passed. Foreground observation lasted 20 seconds, with no fatal/layout matches
and PSS 167,659 KiB. Screenshot inspection confirmed the outlined pause icon
without a processing badge. Desktop presentation and job execution were not
changed by this follow-up. Evidence: `.validation/interrupted-icon-tests.txt`
and `.validation/interrupted-icon-startup.json`.
