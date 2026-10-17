# Mobile notes header and job notifications

17 October 2026. Android preview only; desktop presentation remains v1.4.1.

## Implemented

- Notes/Results heading with a separate subdued count badge. Import is a
  visible labelled button beside Refresh on the right of that heading.
- Removed the app overflow menu and its permanent Unfinished work entry.
  Settings remains directly available. There is no automatic job-recovery
  dialog at startup.
- Active and interrupted jobs have individual Android notifications, grouped
  under the required summary. Stable string tags avoid notification-ID hash
  collisions. Progress updates reuse existing identities and the existing
  retained engine/service; there is no second writer or new dependency.
- Each Cancel action targets only its job and rechecks cancellability in both
  native and Dart code. Finalization keeps its existing non-cancellable rules.
- Tapping an interrupted job opens that job's existing Open note / Retry /
  Discard recovery controls. Notification payloads select job IDs, never
  filesystem paths. Library, credential, source and revision checks remain
  in the existing coordinator. No automatic retry/discard/unlock is added.
- A conditional in-app bell lists one entry per pending job, retaining recovery
  access if Android notifications are disabled. Native notifications hide
  contents on the lock screen. Resolved records remove their notifications;
  recovery objects are not removed merely by dismissing a notification.
- iOS can use the shared in-app presentation, but native iOS notification and
  device acceptance are deferred along with the user's existing iOS hold.

## Automated/static delivery evidence

- Five changed Dart files formatted; scoped analysis: zero errors/warnings,
  twelve informational notices. No test suites run, per user deferral.
- Whitespace check passed. Fresh comparison confirms eleven desktop UI files
  and desktop MyApp remain identical to v1.4.1. D:\tools is untouched.
- Android/Kotlin and obfuscated preview release build passed in 124.9 seconds.
  APK: build/app/outputs/flutter-apk/app-preview-release.apk.
  Size: 131,294,681 bytes. SHA-256:
  d4b776df23ac053ab375c38cecaa4be38229f5749b9ed6276354f97a2367b369.
- All 18 native libraries present; all 64-bit ELF load segments and APK ZIP
  alignment pass 16 KB checks. Existing 32-bit PDFium limitation unchanged.
- Previous APK and affected sources are retained in
  .validation/mobile-list-jobs-before/.
- adb install -r succeeded after checking that no attachment service was
  active. LG LM-G900 / Android 12 launch: COLD, TotalTime 1008 ms,
  WaitTime 1016 ms. PID 18784 stayed stable for 20 seconds, Activity resumed,
  keyguard off; inspected startup logs contained zero fatal/layout matches.
  Total PSS: 133,188 KiB. Screenshot confirms the Notes badge, direct Import,
  retained note row and no idle notification bell/overflow menu. No note was
  opened or edited during inspection. Per-job interactions remain pending.
- Runtime evidence: .validation/mobile-list-jobs-startup.json and
  .validation/mobile-list-jobs-visible.png. These are startup evidence, not
  sustained background-processing or recovery acceptance.
- Stitch refinement: screen 561aa50459c944b4b9d68819fe3b04dd;
  Flash used because Pro was unavailable. Local
  reference: .stitch/designs/mobile-list-job-notifications.html/png.

## Pending manual acceptance

- Header/count presentation; Import opens its existing picker and can cancel.
- Two synthetic attachment jobs show distinct notifications/progress. Cancel
  one safely while the other continues; finalizing jobs have no Cancel action.
- Notification taps (warm/cold activity) select the intended job; interrupted
  recovery still requires opening/unlocking the original note.
- Notification permission denial, process-death recovery and minimum/current
  API device coverage have not been rerun for this change. No parity claim.
- No commit, push, tag, publication or production-package change.
