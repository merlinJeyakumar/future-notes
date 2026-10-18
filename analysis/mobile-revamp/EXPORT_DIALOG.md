# Mobile export dialog and packing progress

## Implementation — 2026-10-17

- After export options are confirmed, the mobile note-export route mounts a
  progress dialog before starting storage preparation. Hide/Back dismiss only
  presentation. Selecting Export again, or opening its Android notification,
  reconnects to the same active job without creating another export.
- The dialog reads the existing coordinator's live state and closes when its
  operation settles. Cancellation still uses that coordinator; finalization
  removes Cancel. Completing a hidden export cannot pop an unrelated route.
- Mobile transition prompts describe export/background work and the requested
  transition. Export no longer uses “Attachment processing” or “Keep editing”.
  Desktop dialog source and cancellation decisions are unchanged.
- The package worker reports typed progress through a bounded-rate isolate port:
  assembling binary records, archive encryption and mandatory encryption readback,
  ZIP checksum calculation, and package writing. Counts come from existing
  copy/read/transform loops, with no extra payload scan. Bytes and percentages
  describe the current file/stage, not an artificial overall percentage.
- Binary-v1/ZIP64 bytes, encrypted-attachment copying, mandatory verification,
  publication and cancellation behavior are preserved. No encryption or note
  metadata format changed. Output flush/verification/publication may still show
  an indeterminate stage when no byte callback exists.
- Stitch reference: screen `398c95cc27ca4fcf9fe8842026a826fe`, existing Future Notes
  design system. Available Flash model used; Pro was unavailable. Only synthetic
  text was sent. Existing app presentation was retained.

## Validation

- Combined affected suite: **96 tests passed**, including binary/ZIP export/import
  and legacy reader compatibility, passwords, packing cancellation, modal
  lifecycle, per-file progress, owner isolation, cache reuse and desktop attachment
  regressions.
- Five dialog cases passed again with real fonts and the app's light/dark themes.
  Phone-width renders at normal/2x text were visually inspected after the entrance
  animation; controls were hit-testable, and no layout exceptions were observed.
- Scoped analysis: **zero errors and zero warnings**. Formatting and whitespace
  checks passed. Eleven desktop presentation files and desktop `MyApp` still
  match `v1.4.1`.
- Normal-entry protected Preview Release built in **62.0 seconds**. All 18 native
  libraries and 16 KB 64-bit ELF/ZIP alignment checks passed.
- APK SHA256: `b6023ec8e5a3145c9731b801cf1780aad7b0caa24c06ba6ca26dd737abceb678`.
  Size: 131885225 bytes. Previous APK preserved under
  `.validation/accepted-before-export-dialog/` with its SHA256 as the filename.

- In-place installation and launch succeeded on LG LM-G900, Android 12. The notes
  list was visibly rendered while unlocked. A 20-second startup observation kept
  the same process, with zero fatal/layout matches and 148936 KiB total PSS.
  Large-file export acceptance on the phone remains **pending**; startup evidence
  is not a sustained packing performance measurement.

No commit, push, tag, portable update or iOS validation is included.

## Follow-up: reopen after Hide

The original progress helper supported reopening through Export, but note-row
taps still attempted editor navigation. That reached the active-work transition
guard instead of the hidden export. Active export entries in the in-app
notification list also lacked a tap action.

Mobile note-row taps now reconnect to the active export before attempting a
navigation transition, including during finalization. Selecting the active export
entry in Notifications also opens that exact job's progress. The original export
continues to own its worker; reopening creates no storage job. A reopened viewer
detaches its phase listener when hidden, without cancelling the export.

Validation: **19 affected mobile tests passed**, including the real dashboard's
Hide → note tap → same progress route, repeated during finalization, normal note
navigation after completion, selectable export notifications, attachment progress,
editing controls and modal lifecycle. Final scoped analysis has zero errors and
warnings; formatting and whitespace passed. Desktop presentation still matches
`v1.4.1`. The user subsequently confirmed that reopening works on the phone.

The follow-up protected Preview build completed in **60.4 seconds**, passed all
18-library and 16 KB alignment checks, and was installed in place on the LG.
SHA256: `7cc4c90630dd1a0eb3331c39deac57b61f06eba87aa16b16b513c381d36d4c39`;
131885225 bytes. The previous APK is preserved under
`.validation/accepted-before-export-reopen/`. The notes list visibly launched;
a 20-second observation kept the same process, with zero fatal/layout matches
and 150768 KiB total PSS. This is startup evidence, not manual export acceptance.

## Editor Export entry

The mobile editor's top-right Note actions menu now includes Export. Its callback
uses the dashboard's existing capture, credential verification, options and
progress route; it does not switch to the notes list or create another export
implementation. An active export reconnects to its progress instead.

New drafts first ask Save & Export / Cancel. Only explicit approval saves the
draft, with existing save-failure handling and a session-identity recheck before
continuing. Cancelling retains the draft. The action menu can scroll on short
screens. Desktop editor/menu source is unchanged.

Validation: **24 affected tests passed**, including the locked/unlocked editor
menu, unchanged editor/note state, new-draft cancellation, editor access to an
active export, navigation, dialog lifecycle and export options. Scoped analysis
has zero errors/warnings; formatting and whitespace pass. Eleven desktop
presentation files and desktop `MyApp` still match `v1.4.1`. Manual phone
acceptance of the new editor entry remains pending.

The editor-entry protected Preview build completed in **56.8 seconds** and passed
all 18-native-library / 16 KB alignment checks. SHA256:
`a8e6a979cde62577ae5c5f4825b29d8da8e538360c70b12d5dbe2f397c74eb25`;
131885225 bytes. Previous APK preserved under
`.validation/accepted-before-editor-export/`.

In-place installation and launch succeeded on the LG. The notes list was visibly
rendered while unlocked; the 20-second startup check kept the same process,
reported zero fatal/layout log matches and 153389 KiB total PSS. Editor Export
acceptance on the phone remains pending.

## Read-only mobile editor during export

Export now disables the mobile editor from the initial action through options,
packing and completion. A small dashboard request counter covers preparation
before an export job exists; the active job keeps the editor read-only after
Hide or reopening progress. Nested/reopened routes do not create another worker.
Cancelling options, success, cancellation and failure restore the prior editing
state. Existing independent read-only guards remain in effect.

Rich text, HTML and title editing, mode changes, formatting, attachment actions,
mention insertion/opening, password changes, deletion and save/new-note shortcuts
are disabled. Android native file drops revoke their target while exporting and
still close any delivered native leases. Progress, notifications, Hide, navigation
and safe cancellation remain accessible. Editor controllers/documents stay mounted;
no persistence, package or encryption formats change. Desktop UI is unchanged.

Automated validation: 47 combined affected tests passed (editor controls,
navigation, progress routes, attachment rows, export options, mentions and toolbar).
Coverage includes both editor modes through preparation, hidden active work and
all three terminal outcomes, restoring an already-open actions menu, preserving
pre-existing read-only state, disabled keyboard formatting/focus and cancelled
new-draft preparation. Tests assert unchanged controllers/documents and zero
payload decryptions/writes in these UI-only scenarios. Initial new-test import
and tooltip-finder errors were corrected before this passing run. Scoped analysis
reports zero errors/warnings, formatting has zero changes and whitespace passes.
Eleven desktop presentation files and desktop MyApp still match v1.4.1.

The protected Preview build completed in 55.4 seconds and passed the 18-library
and 16 KB ELF/APK alignment checks. SHA256:
`33c3e682e2586b175b16ce0b28514d2d4b0de11b2295713b0f5e23148d06720d`;
131885225 bytes. The accepted a8e6a979 build is preserved under
`.validation/accepted-before-export-readonly/`. In-place installation succeeded
and Android acknowledged activity launch. During the 20-second observation PID
20888 remained stable, with zero fatal/layout log matches and 63692 KiB total PSS.
The phone was locked (keyguard showing; activity not resumed); captured display
was black, so this does not establish visible UI startup. User unlock, visible
startup and manual phone read-only acceptance remain pending. No notes/data were
cleared; desktop/portable releases and tags were not changed.

## Optional scan settings versus required backup validation

The user reported Checking/Verifying despite both advanced viewing/export scan
switches being off. Investigation found opening and plaintext attachment exports
already obeyed both switches, including the Android native cipher `verify` flag.
Whole-note package export, however, requested checked attachment sources
unconditionally. It also reparses the completed candidate to validate the backup;
archive-password encryption retains mandatory output readback. Those latter
checks protect a newly written backup and are separate from optional plaintext
viewing/export readback.

Mobile whole-note export now uses the existing source-scan setting. Off obtains
bounded metadata/revision descriptors without a full source pre-scan; source
length/revision/reader checks, package CRC/framing and final backup validation
remain enabled. Desktop source policy is unchanged. Required stages explicitly
say `Validating backup encryption (required)` / `Validating exported backup
(required)`. Mobile settings now explain the scope. In-app notifications and the
Android job-host/notification adapters carry the specific stage detail instead of
displaying only the ambiguous phase. No encryption, package or note formats change.

Automated validation: 102 affected tests passed, including binary and ZIP
password-protected backups under all four optional-switch combinations, exact
encrypted attachment bytes after round trip, retained required validations,
desktop checked-source cancellation, preview scan settings/cache reuse, plaintext
batch export, mobile settings, notification detail forwarding, editor read-only
and progress-route/navigation regressions. The first run caught a Flutter
UI-platform default being used for host policy; native OS selection was restored
before the passing run. Synthetic fixture ID/type assertions were corrected too.
Scoped analysis has zero errors/warnings; formatting and whitespace pass. Eleven
desktop presentation files and desktop MyApp still match v1.4.1.

The protected Preview build completed in 72.0 seconds; 18 native libraries and
all applicable 16 KB ELF/APK alignment checks passed. SHA256:
`1ce87386106dd72da2ac8aebcf8c8db0ac8ebd5c36a96d495a37b96d896c2627`;
131885225 bytes. Previous build 33c3e682 is preserved under
`.validation/accepted-before-export-checks/`. In-place installation succeeded.
The launch request was acknowledged but reported Android ChooserActivity; no
visible editor startup is claimed. The phone subsequently auto-locked and its
capture was black. During a 20-second observation PID 21849 remained stable,
with zero fatal/layout matches and 9221 KiB total PSS; the app was not resumed.
These are background-process observations only. User unlock, visible editor
startup and manual operation acceptance remain pending. No app data was cleared;
portable builds and tags were preserved.

Follow-up: the user replied `done` to the new-operation/settings check and
reported no further failure. A fresh 20-second observation found Preview resumed
with keyguard hidden, stable PID 25731, zero fatal/layout matches and 161387 KiB
total PSS. The visible editor was confirmed with an active Export note dialog
showing `Preparing export files (1/7)`, progress and Hide/Cancel controls. Editing
actions were visibly disabled beneath it. This confirms foreground startup and
the running export presentation; the capture alone does not establish terminal
export completion or every optional-check combination. Automated coverage above
provides the settings/round-trip validation.

## Optional backup readback (latest user decision)

The latest request supersedes the earlier mandatory full-backup reparse policy
for mobile exports. Advanced configuration now includes `Validate exported
backups`, persisted as `validateExportedBackup` and defaulting to false, including
when opening an older settings file without that field. The switch is independent
of source scanning and plaintext output verification. Enabling it restores the
extra completed-package import/readback before publication; its progress says
`Validating exported backup` without the previous required label. The choice is
captured for each export rather than changing a running job midway.

Off skips that full-package import/readback. Existing metadata/entry/name/size
bounds, bounded exact source copying, source revision checks, ZIP checksum
generation, flushing/closing and destination revision/retained-copy publication
remain. Newly encrypted output retains its existing write verification; import
validation remains unchanged. No encryption, note or package format changes.
Desktop exports retain their accepted validation policy and presentation.

Automated validation: 130 affected tests passed, including independent source /
plaintext / backup-check combinations for binary and ZIP packages, exact encrypted
attachment bytes after round trip, default-off legacy settings, boolean type
validation, acknowledged settings writes and restart, narrow mobile settings UI,
export destination safety, package limits/cancellation, cache reuse, editor
read-only and progress/navigation lifecycle. Scoped analysis has zero errors or
warnings. Formatting and whitespace pass; desktop presentation still matches
v1.4.1. The installed 1ce87386 APK was hash-verified and preserved under
`.validation/accepted-before-optional-backup/` before rebuilding.

The protected Preview build completed in 62.1 seconds; all 18 native libraries
and applicable 16 KB ELF/APK alignment checks passed. SHA256:
`92573512e48013b75a7867948c72cde4ad17174841cc98fcf2892a66560436f9`;
131885225 bytes. In-place installation succeeded and Android acknowledged the
MainActivity launch. The phone auto-locked; its capture was black. A 20-second
background observation kept PID 29724 stable, with zero fatal/layout log matches
and 66669 KiB total PSS, but the activity was not resumed. Visible startup and
manual confirmation of the new setting/export behavior await user unlock. No
app data was cleared. No commit, push, tag or portable release publication is
included in this change.

Foreground follow-up: after user unlock, Preview was visibly open on the LG in
Attachment performance settings. A fresh 20-second foreground observation kept
the same PID 29724, with keyguard hidden, zero fatal/layout matches and 207297 KiB
total PSS. Visible launch is confirmed. The captured settings screen had Advanced
configuration collapsed; manual new-switch/export acceptance remains pending.

Manual acceptance: the user replied `perfect` to the check that Validate exported
backups is off by default and a new demo export skips Validating exported backup.
The requested mobile setting/export behavior is accepted on the connected LG.
