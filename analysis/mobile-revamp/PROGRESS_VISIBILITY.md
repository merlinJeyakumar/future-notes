# Mobile attachment progress visibility

17 October 2026. User reports missing attaching progress and notifications.

## Findings

- Pending attachment cards follow saved attachments in a bounded, scrolling
  mobile dock. At two columns, a third card can be below the visible row.
- On publication, an add job adopts the attachment ID, but the presentation
  map previously only considered originalAttachmentId. Its inline progress
  could disappear while the job was still finishing cleanup.
- The notification bell was exposed on the notes list, not the editor.
- Read-only inspection of the LG showed one active foreground service, one
  per-job notification (24084), and one service summary (24082). Channel
  importance is 2, user-lock fields 0, not deleted; notification app-op allows
  posting. Thus records were posted on the quiet channel; this does not prove
  their actual System UI appearance. No notification settings were changed.
- User clarified that both Android and in-app notifications were missing.
  A brief notification-panel inspection could not reach UIAutomator's idle
  state while updates were running. The panel was closed and temporary dump
  removed. Actual System UI appearance remains unconfirmed.

## Implemented

- MobileAttachmentProgress presents active current-note add/open stages,
  bytes, percentage and safe Cancel outside the attachment scroll area. It is
  bounded with visible scrolling for multiple jobs. Byte updates rebuild only
  each row; job state, workers, attachment order and cache ownership are reused.
- Add jobs remain associated with their committed attachment IDs through
  finalization. No attachment metadata or storage format is modified.
- The editor now has the same conditional notification bell and per-job
  details as the notes list. Accepted Save/Attach/Lock placement is unchanged.
- Lock drops the progress subtree immediately; panel sizing uses existing
  motion/reduced-motion settings. Scroll/animation controllers are disposed.
- On Android 12+, the notification builder now explicitly requests immediate
  foreground-service display instead of the platform's default deferral.
  Quiet channel/user permission choices remain untouched. This addresses a
  possible delay; it is not proof of the user's particular System UI symptom.
- Changes are confined to mobile presentation and Android notification display.
  Job ownership, foreground lifetime, encryption and desktop UI are unchanged.

## Checks and delivery

- Initial analysis caught an omitted ValueListenable foundation import; it
  was corrected before building. Final scoped analysis: zero errors/warnings,
  23 informational notices. Four files formatted; whitespace check passed.
- Tests remain deferred by the user. The user then confirmed the active work
  was entirely a demo run and cleared replacement without waiting. The APK
  was updated with install -r, retaining application data; no clear/uninstall,
  note editing, retry or discard action was performed.
- Presentation-only build passed in 62.2 seconds. Final protected build including
  Android immediate-display behavior passed in 40.6 seconds. Current APK:
  build/app/outputs/flutter-apk/app-preview-release.apk; 131,294,681 bytes;
  SHA-256 c9e052d91f3dcf4c9b4c01cf9769d39d831af4d22ed69ba26896926494a2e6fd.
- Eighteen native libraries present; all 64-bit ELF and ZIP 16 KB alignment
  checks passed. Eleven desktop presentation files and MyApp match v1.4.1.
- Previous APK and editor/dashboard source preserved under
  .validation/mobile-progress-before/. Stitch reference and assets recorded
  in .stitch/metadata.json and .stitch/designs/mobile-progress-visibility.*;
  Flash used because Pro was unavailable.
- Installation succeeded after the user's demo-run clarification. LG LM-G900
  Android 12 COLD launch: TotalTime 1371 ms, WaitTime 1380 ms. PID 26882 stayed
  stable for 20 seconds, Activity resumed, keyguard off; inspected logs had
  zero fatal/layout-error matches. PSS was 184,638 KiB. Screenshot confirmed
  the normal notes list and retained note metadata; no note was opened.
- Post-update inspection found zero active job notifications, consistent with
  the idle UI. A repeated panel inspection reached idle and also found no app
  entry; this does not validate display during a fresh active job. The earlier
  interrupted record was not claimed as independently verified recovery.
- Runtime evidence: .validation/mobile-progress-startup.json,
  .validation/mobile-progress-observation.json and
  .validation/mobile-progress-startup-visible.png. Active progress/bell and
  native appearance, multiple-job cancellation and immediate lock teardown
  remain pending the user's next demo check. iOS validation remains held.
- No commit, push, tag, release, D:\tools or desktop executable changes.
