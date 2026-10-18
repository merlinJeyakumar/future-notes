# Mobile read-only export browsing

## Implementation

- A tap on the exporting note now returns to the retained editor rather than
  reopening its progress dialog. The editor stays read-only, with formatting,
  attachment mutation, Save and Lock controls disabled by the existing export
  state. Back returns to the list without cancelling the job.
- A compact export action beside the Notes heading opens the existing live
  progress dialog. Its thin loading ring disappears on completion/cancellation;
  reduced motion disables the ring animation. Existing per-note activity remains.
- Starting export from the list first retains the target note's editor, before
  the worker pins its session. Standard draft decisions and load failures remain
  in force. Switching to a different note during an active job retains the
  existing session guard; returning to the exported note performs no reload.
- These changes are mobile presentation/coordinator code only. Desktop widgets,
  encryption, file formats, worker execution and payload processing are unchanged.

## Design

Stitch Pro is unavailable in the connector; Flash was disclosed and used with
the existing design system. Reference: 66281b6a6e90450da34fbc206e6d51c0,
.stitch/designs/mobile-export-browse.html and .png. Generated additional banners,
claims and controls were not adopted. Progress action is beside the Notes
heading, following the user's requested list-top placement.

## Validation

- Combined affected suite: 25 passed, one new navigation assertion failed due
  to selecting a tooltip as an IconButton. Corrected test selects the actual
  button. Extending its export-from-list fixture also required republishing its
  synthetic inventory after load (the harness has no platform discovery).
- Final navigation suite: all 3 passed. Includes list-started export preparation,
  cancelling options, same controller/session during preparing/finalizing,
  disabled attachment mutation, Back, progress-button loading ring, Hide/reopen,
  completion restoring editing and removal of the list action. Existing draft
  and tablet navigation cases also passed.
- Other passing affected cases cover Rich text/HTML export locks, terminal
  results, immediate lock teardown, cache-independent progress projection and
  single-card composition. No payload decryption was initiated by these UI tests.
- Scoped analysis: no errors/warnings, 12 informational lints in existing
  coordinator code. Formatting/whitespace passed. Desktop presentation diff empty.
- Evidence: .validation/mobile-export-browse-tests.txt,
  .validation/mobile-export-browse-navigation.txt,
  .validation/mobile-export-browse-analysis.txt.

## Delivery

Accepted APK preserved at
.validation/mobile-export-browse-accepted/app-preview-release.apk, SHA-256
8030f777d0f352d65b887cb3fc58242068126a41e9ab2f7d7bc31838cf24802c.
Protected Preview built in 55.4 seconds. APK SHA-256:
93caa9270b9e7f78d46c402badf6bbcce98864d7658c749c79dc6334b84ddae7.
Packaging inspection found 18 native libraries with 16 KiB alignment for all
64-bit ELF load segments; zipalign passed. In-place staged installation and
explicit launch on the LG succeeded. Process 11015 remained stable/resumed for
20 seconds, keyguard absent, zero fatal/layout log matches; observed total PSS
173,995 KiB (not a stress/peak measurement). Evidence:
.validation/mobile-export-browse-build.txt,
.validation/mobile-export-browse-packaging.json and
.validation/mobile-export-browse-startup.json.

Manual acceptance of read-only browsing/progress-button behavior is pending.
Notes, releases and tags remain preserved. No commit, push or publication is
included. iOS device validation remains deferred.

## Password-access correction

User feedback identified that the export guard also blocked the inline password
form. Mobile now leaves that form focusable and interactive, and enables the
locked-note shortcut to focus it. Authoring controls remain disabled.

Unlock has an explicit read-only-export option (default off). After successful
password validation, it can retain the same editor session only when all active
jobs are exports belonging to that session. This avoids cancelling export on an
access-only unlock. Foreign ownership is refused, normal unlock still advances
the session, and no encryption/storage format is changed. The revealed body
remains read-only until export completion; the password callback restores the
correct editing baseline and does not request authoring focus during export.

All 20 affected tests passed, including actual password input, wrong-password
rejection, foreign-owner rejection, unchanged controller/session, completion
restoring editing, mobile navigation and existing desktop locked-note behavior.
A real owned-storage integration paused encrypted-package export, unlocked the
protected note, resumed the same export, unpacked/decrypted its body successfully
and confirmed the original note bytes were unchanged.

Scoped analysis: zero errors/warnings; 74 informational lints remain in the
existing editor/view-model scope. Formatting and whitespace passed.
Evidence: .validation/mobile-export-unlock-tests.txt and
.validation/mobile-export-unlock-analysis.txt.
Accepted pre-correction APK retained at
.validation/mobile-export-unlock-accepted/app-preview-release.apk (SHA-256
93caa9270b9e7f78d46c402badf6bbcce98864d7658c749c79dc6334b84ddae7).
Protected replacement built in 54.8 seconds; private symbol and packaging
assertions passed (18 native libraries, 16 KiB 64-bit ELF alignment, zipalign).
APK SHA-256:
4e5f0c6b8023a0a681accf09c2f302fed841b88ab181a4953d92264827c13d3e.
Staged in-place installation succeeded. The process stayed alive for 20 seconds
without fatal/layout log matches, but the resumed activity was Android's
ChooserActivity (share sheet), not Preview. A second explicit start delivered
to the existing task and left that share sheet in front. Foreground editor
startup and manual acceptance therefore remain pending; the user was asked to
finish/dismiss the share sheet. No share target was selected by the agent.
Evidence: .validation/mobile-export-unlock-build.txt,
.validation/mobile-export-unlock-packaging.json and
.validation/mobile-export-unlock-startup.json. No app data was cleared.
