# Mobile focus-based panels and background tasks

Implementation: mobile presentation only. Desktop presentation, encryption,
storage protocols, worker execution and performance settings were not edited
for this task. Earlier uncommitted changes remain preserved.

## Behavior

- One editor-owned coordinator controls formatting and attachments. No idle
  timers. Pointer interaction, actual text edits, title focus, navigation,
  mode/session changes and locking collapse the applicable disclosures.
- Formatting commands preserve selection and programmatic focus restoration.
  Owned picker routes remain part of formatting. Outside dismissal is handled
  on pointer-up so the newly tapped control receives its gesture first.
- System Back and dashboard navigation explicitly collapse retained-editor
  panels. Editor instances, document controllers and scroll state are retained.
- Both mobile bell icons are replaced with Material sync icons; badges and
  pending-job visibility rules are preserved. The panel is Background tasks.
- An open task panel retains snapshots of jobs it observed until it closes.
  Reopening shows pending/interrupted work, without persistent completed history.
- Export completion returns the operation result immediately, releasing the
  initiating export lock. The presentation remains until Close/Back. Hide
  dismisses presentation without cancelling. Terminal states have no spinner
  or Cancel action. Navigation/credential invalidation removes the owned result
  route immediately. Duplicate completion snackbars are suppressed while its
  result is visible.
- Mention popup and editor share a tap-region identity; selecting a suggestion
  remains valid while outside interaction dismisses it.

## Design

Stitch Pro was unavailable through the connector. The disclosed fallback was
GEMINI_3_8_FLASH, using the existing Future Notes design system and synthetic
content. Reference screen: a6a739465e834c83901fbe1f52d7c723.
Assets: .stitch/designs/mobile-focus-results.html and .png.
Generated extra queue/share controls and verification claims were not adopted;
the implementation follows the approved interaction/result behavior.

## Automated validation

- One combined affected run covered mobile editing, exports, attachments,
  navigation, mentions, keyboard focus and motion: 49 passed; one new assertion
  failed because it used a plain key instead of the note-scoped list key.
- Focused final behavior gate: 2 passed, including a two-minute synthetic idle
  interval, owned picker retention, mutual disclosure, progress stability,
  actual text edits, controller identity and lock removal.
- Terminal task/export suite: 9 passed. Covers completion/failure/cancellation
  retained until Close, operation completion before dismissal, Hide/reopen,
  unrelated routes, native job updates and no persistent completed history.
- Existing caret/IME/keyboard/mouse tests were extended to mobile Rich text
  and HTML: both mobile cases passed, including outside dismissal and zero
  decryption/payload preparation.
- System-Back navigation gate: passed while preserving the editor instance.
- Real protected-note lock gate: passed; the result route disappears immediately
  while the underlying job remains active. Its first test fixture changed only
  the display notifier; the corrected fixture invokes the actual lock API.
- A targeted failed-start case also passed with a lagging queued worker snapshot:
  terminal presentation still exposes only Close, with no spinner or Cancel.
- Scoped analysis: no errors/warnings; 41 informational lints remain.
- Formatting and scoped Git whitespace checks passed.

## Delivery and limits

Accepted APK checkpoint: .validation/mobile-focus-accepted/app-preview-release.apk,
SHA-256 d5e0d59020e71be673bbec39771a1a02d2d2a252b57b5a035b728a8bd5a27d6f.
No uninstall, data clearing, commit, push, release publication or tag change is
included. Portable releases and notes are preserved. iOS device validation is
deferred. Final protected APK packaging, phone startup and manual acceptance
are recorded below after completion.

Final protected normal Preview built successfully (56.2 s); private symbol
assertions passed. APK: 132,098,129 bytes, SHA-256
fa88bd0f30dcaab434931f734c6372e6b2df6bb0e2e42193f6cb3152346ac44b.
Packaging inspection found 18 native libraries with 16 KiB alignment for all
64-bit ELF load segments; `zipalign -c -P 16 4` passed.

The final APK installed successfully with `adb install --no-streaming -r` and
was launched explicitly on the LG LM-G900 (Android 12). PID 8954 remained stable
for 20 seconds, was resumed with keyguard absent, and had zero fatal/layout log
matches. Total PSS was 174,512 KiB at that observation (not a peak/stress claim).
Read-only capture confirmed the mobile editor, process badge and collapsed
attachment strip. No app input or recovery/discard choice was sent by the agent.
The accepted checkpoint hash remains unchanged.

Manual acceptance was requested for Rich text/HTML, focus-driven disclosures,
picker selection, the process button and retained export results; response is
pending. iOS build/device validation remains deferred.

## Duplicate export presentation correction

The reported two Export package cards were the same job rendered by both the
shared auxiliary panel and mobile progress panel. Mobile now excludes exports
from the shared panel; its default behavior and desktop call sites are unchanged.
Password/protection jobs remain visible through the shared auxiliary panel.
No execution, storage, verification or encryption behavior was changed.

The affected four-file regression suite passed all 20 tests, including full
mobile editor composition, single export identity, changing bytes/percentage,
finalization without cancellation, completed-card removal and concurrent
protection progress. Existing export read-only, gallery progress and shared
panel tests also passed. Scoped analysis has zero errors/warnings and 17
informational lints in existing editor code. Formatting and whitespace passed.
Evidence: .validation/mobile-export-single-tests.txt and
.validation/mobile-export-single-analysis.txt.

The previously installed APK is preserved at
.validation/mobile-progress-accepted/app-preview-release.apk (SHA-256
fa88bd0f30dcaab434931f734c6372e6b2df6bb0e2e42193f6cb3152346ac44b).
Replacement protected Preview built in 60.1 seconds. SHA-256:
8030f777d0f352d65b887cb3fc58242068126a41e9ab2f7d7bc31838cf24802c.
Native-library inspection (18 libraries, 16 KiB alignment for 64-bit ELF loads)
and zipalign passed. In-place staged installation succeeded on the LG; the
launched process remained stable for 20 seconds with no fatal/layout log
matches, resumed activity and no keyguard. Observed total PSS: 172,941 KiB.
Device export-card manual acceptance remains pending. Runtime evidence:
.validation/mobile-export-single-startup.json. No application data was cleared.
