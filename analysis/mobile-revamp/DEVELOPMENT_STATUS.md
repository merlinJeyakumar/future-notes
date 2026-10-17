# Mobile development delivery

Current source validation and acceptance are summarized in
[COMMIT_VALIDATION.md](COMMIT_VALIDATION.md). Earlier dated checkpoints below are
historical; their deferred-test and pending-user statements do not override the
latest full-suite results or subsequently confirmed workflows.

The user prioritized development and Android launch, then explicitly requested
native encryption and bidirectional import/export validation. Targeted crypto
and provider/cache validation ran for that scope; broader mobile parity gates
remain deferred. This is a development preview, not an accepted
mobile parity release or a production upgrade.

Latest correction: manual video opening failed in the first native-cipher build
because registered SAF descriptors were rejected by its private-path guard.
Native workers now acquire independent read handles from the live document
registry, with private-only output and existing validation retained. The new
provider/cache integration passed on the LG; 52 affected host tests and desktop
v1.4.1/current readers passed. The user confirmed the demo video's decryption,
playback and cached reopening. See ANDROID_NATIVE_CIPHER.md; no parity claim is made.

Mobile attachment presentation now uses compact horizontal rows and a fullscreen
Back/search file list, with desktop presentation unchanged. The general count is
below search; Select/long-press enables multi-file sharing and confirmed removal.
The editor notification badge remains intact and the dock has no outer outline.
The 81-test affected suite passed, including cancellation and failed batch actions.
The final protected preview was rebuilt, installed and cold launched on the LG
in 1,573 ms; a twenty-second startup observation found no fatal/layout errors.
Manual phone selection/share-sheet/removal acceptance remains pending.
See ATTACHMENT_PRESENTATION.md.

The user's multi-file export attempt failed before the chooser. A device probe
reproduced an aliased temporary-root rejection, followed by denied hard links.
Trusted cache roots are now canonicalized; modern Android private publication
uses no-replace renameat2. Export names avoid the share plugin's flat-cache
collisions. The 26-test focused suite and synthetic LG native chooser, payload,
conflict, backup and cleanup checks passed. The corrected normal protected
preview is installed and launched; user acceptance of gallery export is pending.

The export gallery now shows the current File N of M / filename, separate
processing stage, live stage bytes, percentage/bar and safe cancellation. It
reuses the existing mobile job progress listener without recreating workers or
changing encryption. The 50-test affected suite passed, including 200% text
layout and actual worker captions/bytes; analysis has no errors/warnings.
The normal protected preview has been rebuilt, installed and launched on the LG.
The user confirmed large-file progress works as expected; iOS validation remains held.

Mobile attachment exports now honor the existing off-by-default optional source
checking and decrypted-output readback preferences, with opening/exporting labels
in mobile settings. Required framing/padding/known-size checks and publication
verification remain. Desktop export policy is unchanged. The 65-test affected
suite passed; the protected normal preview is rebuilt, installed and launched.
Manual export-check acceptance is pending. Existing saved opt-ins are preserved,
with no new settings/note format.

## Preservation

- Original Android ID: `com.nativedevps.futurenotes` (installed 1.0.0). Not updated,
  uninstalled, cleared or used for validation by this work. The user subsequently
  confirmed they removed that original installation themselves.
- Development ID: `com.nativedevps.futurenotes.preview`, Future Notes Preview.
- Desktop portable `D:\tools`, real notes and existing release tags are untouched.
- No commit, push, store upload or release publication.
- First preview and first successfully launched provider preview APKs are retained
  in `.validation/mobile-baseline/`. The previously delivered preview is also
  retained in `.validation/mobile-accepted-before-remaining/`.

## Implemented development paths

- Phone notes/search list and full-screen editor, retained editor controllers,
  tablet split view, touch formatting expansion, readable mobile typography and
  keyboard-aware attachment mentions. Windows hover/window behavior stays separate.
- Shared inline unlocking and per-note session credentials, stable IDs and mention
  IDs, collapsed attachment rows, searchable full-screen attachment gallery and
  touch-sized attachment actions.
- Full-screen media/document viewers, explicit mobile Info, background media pause,
  protected app snapshots and decrypted-cache reuse with lock/credential teardown.
- Native bounded SAF documents and persisted local/SD folder grants. Reads/writes
  stay in the selected folder, never a URI-derived guessed filesystem path or
  private note mirror. File sources retain actual opened native descriptor leases.
- Disposable provider admission probes, streamed encrypted candidates, verified
  predecessor copies, revision rechecks, attachment-first generation publication,
  readback verification, version-2 pending guards and idempotent provider recovery.
- Reviewed permanent deletion with exact revision inventories, retained deletion
  tombstones, interrupted cleanup recovery and purging of captured provider and
  acknowledged desktop recovery objects. This new path has not had fault tests.
- Completed Windows v1 journals are validated as historical receipts without
  rewriting them. Interrupted v1 transactions now use a provider recovery guard,
  verified restoration and the original v1 resolution receipt; unknown revisions
  and multiple pending versions of the same object fail closed. Case-insensitive Windows object hashes are read portably while
  preserving the original target names and encoded records.
- Shared import/replacement and export pipelines are connected to native picking,
  private streamed export candidates, sharing/Save-to-Files and scoped external
  opening. Desktop canonical encryption/package formats remain unchanged.
- One retained Android engine/storage runtime, an application-owned dataSync
  foreground service, notification progress/cancellation, durable job identities,
  input fingerprints and a safe retry-from-source state. No persisted passwords.
- Native document re-opening for Retry avoids reusing an already closed descriptor
  path. Captured length, modification time and available input hash are rechecked.
- Private AES-GCM Android Keystore draft journals, explicit Recover/Discard,
  protected-draft password verification and base-revision checks. New recovery
  drafts still require their first explicit Save.
- Unfinished work remains available from the notes list after Done. Per-job Open
  note, Retry and Discard preserve other records. Attachment retry rechecks the
  source and reuses its original attachment identity, avoiding a second copy after
  an already-published commit. Missing transient input grants use native reselection.
  Known interrupted private staging is removed only on explicit Retry/Discard.
- Selected-folder identities are retained across reselection. Resolved private
  drafts are cleared before an acknowledged library handoff; failures restore the
  old selection rather than opening a second writer.
- Android provider-query notifications and resume refresh invalidate metadata.
  Android native file drops keep URI grants and real descriptor leases through
  preparation, recheck the selected editor identity and reuse attachment workers.
- Filesystem capacity is checked through actual provider descriptors before each
  candidate copy and through private-volume telemetry before attachment staging.
  A bounded wake lease follows active foreground jobs and is released on service stop.
- Preview-only screen recording/screenshots are allowed by explicit user request.
  Production retains capture protection. Android 12 preview capture protection is
  intentionally relaxed; Android 13+ still excludes recents snapshots.
- The existing 70% budget/advanced settings consume mobile memory/thermal feedback;
  unavailable system CPU telemetry retains the conservative scheduler fallback.

## Android toolchain and artifacts

Pinned Dart dependencies are unchanged. AGP 8.12.1 satisfies the existing locked
share_plus requirement; Android minimum API is explicitly 24. R8, resource
shrinking and Dart obfuscation are enabled for the preview release variant.
Development signing is deliberately separate from production signing.

Office Oxide 0.1.15 is built from upstream commit
`5d183f4de990de254f32976bf952e548bcd25972` for arm64-v8a, armeabi-v7a and x86_64,
using its lockfile and existing C ABI/parser limits. The generated libraries and
upstream license notices are packaged locally, not committed binaries.

Build command:

```powershell
$env:JAVA_TOOL_OPTIONS='-Djava.net.preferIPv4Stack=true'
flutter build apk --no-pub --flavor preview --release --obfuscate --split-debug-info=.private-release-symbols/android-preview-development
```

Output: `build/app/outputs/flutter-apk/app-preview-release.apk`.
Delivered development SHA-256:
`555b3ca0eee0888dbaa35f76a65eb664be279148ad23543b8e3c5f0369f2d875` (previous delivery; the current candidate hash is recorded below after installation).
Private Dart symbols: `.private-release-symbols/android-preview-development/`.
Generated Office inputs: `.native-deps/office-oxide/`.

## Observed evidence and pending checks

- Multiple protected Android builds completed during development.
- The provider-connected preview was installed on LG LM-G900 / Android 12 and
  reached its visible notes list. Its preview process and resumed Activity were
  observed; the inspected startup log contained no Flutter/Android fatal errors.
- Final development APK installed successfully and cold-launched on 2026-10-17.
  `am start -W` reported 941 ms, PID 24265. The preview remained the resumed Activity
  at the later check; the notes-screen accessibility elements were present and
  the fresh process-log inspection showed no listed Flutter/Android fatal errors.
  No note was opened or changed by the startup inspection. App remains running.
- The first launched provider APK had SHA-256
  `DC52D8978F9413A97A94B8172BC014AC27F04F4229E225B7EC759957863B1CA4`.
  Later development APKs supersede this hash; record the delivered hash separately.
- APK package/minimum API and 16 KB ZIP alignment were checked for that candidate.
  Office ELF PT_LOAD segments were independently checked at 16 KB alignment.
- The delivered APK contains 18 native libraries. All arm64-v8a and x86_64 ELF
  load segments meet 16 KB alignment and APK ZIP alignment passes. The locked
  armeabi-v7a PDFium binary uses 4 KB ELF alignment; no 32-bit device run is claimed.
  Android's 16 KB compatibility requirement applies to 64-bit devices; see the
  [official guidance](https://developer.android.com/guide/practices/page-sizes).
  Packaging inspection is not a 16 KB runtime acceptance result.
- Earlier focused suites passed before the user deferred tests. Those results do
  not validate subsequent deletion, draft, job-host, native retry or iOS changes.
- The mobile navigation test fixture was corrected after a failed fixture setup,
  then not rerun following the user's instruction. No pass is claimed.
- The later scoped analyzer did not finish and was cancelled. Subsequent Android
  compiler/package results are the current compilation evidence. The 2026-10-17
  remaining-feature scoped analysis completed with no errors or warnings and
  informational style notices. Formatting and whitespace checks completed;
  no test suite was run following the latest instruction.
- Real editing/import/replacement/playback/recovery, screen lock/rotation/death,
  SD failure, sustained attachments, frame/resource profiling, minimum/current API
  emulators and tablet acceptance remain deferred. Do not mark ACCEPTANCE.md done.

## Remaining limitations and deferred acceptance

- Tests are explicitly skipped for this delivery. No fault-injection, workflow,
  sustained-load, frame-timing, minimum/current-API or tablet acceptance is claimed.
- Process death restarts attachment work from a checked source, not a byte offset.
  Protected notes require unlocking. Exports/protection/import operations must be
  reopened and restarted through their normal controls; passwords are not saved.
- Provider notifications are hints. Resume and manual Refresh rescan the granted
  folder; every publication still requires revision checks. Uncooperative external
  simultaneous writers are not supported, and rename is never claimed atomic.
- Recording is allowed in the development preview, including Android 12. Do not
  treat this build as providing the production capture restriction on that device.
- Native Android drops require a sender that supplies content URI drag grants;
  unsupported senders can use the native file picker. iOS drop validation is held.

## iOS source readiness

`MobilePlatform.swift` provides the matching channel contracts using scoped folder
bookmarks, NSFileCoordinator, bounded I/O, actual native source leases, private
Keychain AES-GCM drafts, external opening, snapshot cover and bounded background
task expiration/cancellation. The stale example bundle ID is corrected and the
deployment target remains 13. The shared UI uses explicit touch controls.

The pinned static Office XCFramework has a Mac build recipe, local pod integration,
C ABI retention and license packaging. No XCFramework, CocoaPods build, Swift
compile, iPhone/iPad run, signing or iOS background acceptance has been performed
on this Windows host. iOS support is not claimed as validated.

## Current Android delivery

- Final protected preview build passed on 2026-10-17 in 99.9 seconds.
- Package `com.nativedevps.futurenotes.preview`, version 1.4.1+8, minimum API 24,
  target API 36. R8 mapping was generated; Dart obfuscation and resource shrinking
  remained enabled. Dependency versions were not upgraded.
- APK size: 132,080,949 bytes. SHA-256:
  `34fcb352cf20af07feebee5f0def35b1e7f95447605e25dbecdf988442bd183e`.
- Final APK inspection found all three declared Android ABIs and 18 native libraries.
  All 64-bit ELF load segments satisfy 16 KB alignment; ZIP alignment check passed.
- Final ownership-path analysis exited successfully with 54 informational notices,
  no errors or warnings. Earlier scoped remaining-feature analysis also completed.
  One build was cancelled after an overnight pause stalled its command; its rerun
  and final build succeeded. No test suite was run.
- `adb install -r` succeeded on LG LM-G900 / Android 12 / arm64-v8a, retaining
  preview data. `am start -W` returned Status ok (WaitTime 3038 ms), PID 11780;
  the resumed Activity is the preview MainActivity. Inspected process startup logs
  contain no listed Flutter/Android fatal errors.
- Runtime window attributes omit SECURE in this preview. The initial screenshot
  was black because the phone display was asleep/locked; UI accessibility labels
  were unavailable. The display was woken and the user was asked to unlock it.
  After the user confirmed unlocking, the 2026-10-17 follow-up screenshot visibly
  showed the normal dark notes list with New Note, Import Note, Unfinished work,
  search and the existing locked note. Screenshot capture was successful and the
  runtime window still omitted SECURE. PID 11780 remained resumed with no listed
  Flutter/Android fatal log errors. No note was opened or changed by this check.
  This confirms visible startup and screenshot capture, not a recorded-video run
  or complete workflow acceptance. One earlier idle sample was 57,076 KiB total
  PSS and 168,684 KiB RSS; no sustained-load profiling is claimed.
iOS validation is on hold by explicit user instruction because no Mac or iOS device
is available. No iOS validation is attempted as part of this Android delivery.

## Mobile presentation isolation revision (2026-10-17)

The Android phone/tablet presentation now lives under
`lib/features/dashboard/mobile/`, including its own app theme, notes list, editor
header/formatting and preview UI. Desktop presentation files and the MyApp class
match v1.4.1 exactly; main selects MobileApp only on Android/iOS. Business behavior
and storage remain shared. Details, hashes and acceptance limits are recorded in
[UI_ISOLATION.md](UI_ISOLATION.md). The rebuilt preview is installed and launched;
the unlocked notes list was visually confirmed after the phone initially auto-locked.
The redesigned editor and subjective layout acceptance still await user review.
# Attachment progress visibility correction

17 October: corrected mobile add-job association through cleanup, added a pinned
current-note progress surface and editor notification access. Android 12+ requests
immediate foreground-notification display; quiet channel preferences stay intact.
Protected candidate build/checks passed. **Installed and launched** after the
user confirmed the active work was entirely demo content and cleared updating
without waiting. Normal notes list and retained metadata visibly confirmed;
20-second startup observation had no fatal/layout errors. Active progress and
notification acceptance pending. Details: [PROGRESS_VISIBILITY.md](PROGRESS_VISIBILITY.md).

# Latest mobile list revision

17 October: direct Import action beside the Notes heading; separate count
badge; permanent Unfinished work menu replaced with per-job Android
notifications and conditional in-app notification access. Recovery remains
coordinator-controlled. Protected preview rebuilt, installed and visibly
launched on LG Android 12. Per-job cancellation/recovery acceptance pending;
tests and iOS validation remain deferred. See [LIST_NOTIFICATIONS.md](LIST_NOTIFICATIONS.md).

## Note-row loading indicator (17 October)

The user confirmed pinned attachment progress, the editor bell and native
notifications work. A mobile-only typed activity projection now supplies a
loading ring around the owning note's existing lock/file icon. Exact selected
library and note storage identity are used; byte updates do not rebuild the
list. Protected APK built, packaging checked, installed and launched on the LG.
Busy-row manual acceptance remains pending. Tests and iOS validation remain
deferred. See [NOTE_ACTIVITY.md](NOTE_ACTIVITY.md).

## Orientation, memory and logging (17 October)

Added Android app-scoped worker memory admission, bounded pressure cooldown and
content-free structured lifecycle/job/recovery diagnostics. Protected preview
rebuilt and installed. Rotation, actual Activity destruction/recreation with
one retained engine, and pressure-callback propagation passed on LG Android 12;
zero inspected fatal/layout errors. An isolated partially black rotation capture
was not reproduced in sixteen follow-up samples; active editor/job rotation
acceptance remains pending. Tests and iOS validation remain deferred. Evidence
and limitations: [RESILIENCE_DIAGNOSTICS.md](RESILIENCE_DIAGNOSTICS.md).

## Android native cipher and device settings (17 October)

Implemented Android system-provider encryption/decryption with the unchanged
desktop-compatible format, scoped native-handle ownership and device/thermal
resource policy. Mobile settings now expose device telemetry, presets and
persisted advanced controls. Final 78-test regression suite passed. Physical LG
validation passed eighteen vectors, eight package cases in each direction,
worker/rekey and failure cleanup, including unexpected worker exit. Immutable
desktop v1.4.1 readers accepted the Android exports. Final 700 MiB synthetic
decryption: 13.3 seconds; encryption plus readback: 24.4 seconds with safety policy.
Normal protected preview rebuilt, installed and visibly launched; settings native
status verified read-only. User acceptance and iOS validation remain pending/held.
Details: [ANDROID_NATIVE_CIPHER.md](ANDROID_NATIVE_CIPHER.md).
