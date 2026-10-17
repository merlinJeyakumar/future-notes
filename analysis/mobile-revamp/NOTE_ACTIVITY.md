# Mobile note-row attachment activity

17 October 2026. The user accepted the pinned attachment progress, editor bell
and Android notification correction, then requested a loading icon on its note
in the file list. Tests remain deferred; iOS validation remains held.

## Implementation

- `MobileNoteActivityController` is a mobile presentation projection over the
  existing job list and phase notifiers. It aggregates active add, open and
  protection work by the exact library identity and note storage name captured
  by the coordinator. Titles, visible filters and duplicate note UIDs are not
  used to identify the owner. Export/import are excluded because their existing
  recovery target is not a reliable per-note ownership contract.
- Composition supplies the selected library identity and typed owner resolver.
  Sidebar widgets consume an immutable activity map; they do not query files,
  call platform channels, decrypt data or change job ownership.
- The existing file/lock icon stays visible within a 32 px loading ring in its
  fixed leading slot. Tooltip and accessibility text report active job count.
  Reduced motion uses a static sync badge. Terminal phases clear the indicator.
- Byte updates do not rebuild this projection. Only changed active counts notify
  row icons. Hidden phone lists stop animation tickers; listeners are disposed
  with the dashboard. No new dependencies or worker/cache changes.

## Validation and delivery

- Four Dart files formatted; scoped analysis completed with zero errors or
  warnings and nine informational notices. Whitespace check passed.
- Eleven desktop presentation files and the desktop MyApp class still match
  v1.4.1. Existing accepted APK/source preserved in
  `.validation/mobile-note-activity-before/`.
- Stitch Flash reference saved to `.stitch/designs/mobile-note-activity.*`
  because Pro was unavailable. The reference board contains two phone frames;
  Stitch classifies the whole board as DESKTOP.
- Protected preview build passed in 62.2 seconds. APK: 131,294,681 bytes;
  SHA-256 `e3422bc246890456c325020d1d0478d33070152b11277df755816220ac755e58`.
  Eighteen native libraries present; all 64-bit ELF load segments and ZIP 16 KB
  alignment checks passed. Existing 32-bit PDFium alignment limitation unchanged.
- `adb install -r` succeeded, preserving preview data. LG LM-G900 / Android 12
  cold launch returned Status ok, TotalTime 1437 ms, WaitTime 1443 ms.
- Twenty-second startup observation: PID 27841 stayed stable, Activity resumed,
  keyguard off, zero fatal/layout-error matches in inspected logs, total PSS
  132,803 KiB. Screenshot confirmed the normal idle notes list with retained
  metadata. No note was opened or edited. Evidence:
  `.validation/mobile-note-activity-startup.json` and
  `.validation/mobile-note-activity-startup-visible.png`.
- No test suites, commit, push, tag, release, D:\tools or Windows executable
  changes. Busy-note display, multiple-note ownership and completion/cancellation
  clearing still require the user's demo check; startup is not proof of those
  runtime behaviors.
