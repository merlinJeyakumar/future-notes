# Mobile attachment presentation

2026-10-17. Mobile presentation only; desktop widgets, encryption, publication,
cache ownership and worker coordination remain unchanged.

## Implemented

- Replaced fixed-height mobile attachment grid cards with readable horizontal
  rows: type/cached-image glyph, two-line filename, type/size, stored time and
  touch-sized More action. Duplicate filenames show the final five ID characters.
- Expanded editor dock has one bounded vertical list under a count/collapse
  header. Removed the outer content-area scroller which previously clipped cards.
  Collapsed icons and overflow remain; opening/unlocking/switching still collapse
  the dock and editor-focus requests still collapse it.
- All attachments uses a fullscreen app bar with Back navigation, count, search,
  lazy vertical file list and an empty-search state. No bottom Close action or
  fixed-height card grid. Overflow opens the complete searchable inventory.
- Active rows show progress/bytes and only safe cancellation. Completed rows
  regain opening/More; failed pending items retain Retry/Remove pending. The
  independently pinned progress panel and Android notifications are unchanged.
- Existing preview helper/cache reuse, metadata-only presentation and cached
  image thumbnails remain. Lock/credential/navigation guards immediately remove
  protected gallery contents. No new dependencies or file-format changes.
- Stitch Flash used because Pro is unavailable in the tool schema. Synthetic
  reference 747c3baa1922408da7b448cef36ade29 uses the existing design system;
  generated sorting/filter/batch-action suggestions were not added.

## Automated validation

- Scoped analysis: zero errors/warnings, 18 pre-existing dependency/style/async
  infos in the affected mobile files. No dependency upgrades.
- Combined suite: 38 tests passed, including four new mobile presentation tests,
  desktop attachment regressions and file-cache regressions.
- Tests cover collapsed overflow, lazy scrolling, full-width rows, readable
  filenames/duplicate IDs, case-insensitive filename filtering/empty state,
  Back navigation, large accessibility text in both themes, progress geometry,
  safe action availability and immediate lock/navigation removal. Rendering,
  expansion and search produce no payload decryptions or note writes.
- First run exposed a 31 px header overflow at 2x text scale. Narrow/large-text
  layouts now use a labelled All attachments icon action, then passed again.
- Synthetic captures were reviewed using actual SDK Roboto/Material fonts;
  no real note text or filenames were used in the design or visual fixtures.
- Eleven desktop presentation files plus desktop MyApp match v1.4.1.
  Whitespace checks passed. Accepted native-crypto APK/source preserved under
  .validation/mobile-attachments-before/ (SHA256
  087ce8e10cf15fda07469cd463fa8adba2b28a633b6c8bcb94e22272fb34ee86).

Evidence: .validation/mobile-attachments-final-analysis.txt,
.validation/mobile-attachments-final-tests.txt,
.validation/mobile-attachments-font-review.txt and synthetic dock/gallery PNGs.

## Delivery and manual acceptance

- Normal protected preview (lib/main.dart) built in 63.0 seconds, retaining Dart
  obfuscation, R8/resource shrinking and private symbols under
  .private-release-symbols/mobile-attachments-20261017/.
- APK build/app/outputs/flutter-apk/app-preview-release.apk, 131,688,393 bytes,
  SHA256 af1b7bde3f8cf5b8fbe90842b685b065d874d3544c4f04696d7da6bda08fadb2.
  Eighteen native libraries and 64-bit ELF/ZIP 16 KiB alignment checks passed.
- Installed with install -r and launched on LG LM-G900 Android 12. Cold launch
  Status ok, TotalTime 1552 ms. PID 9948 stable for twenty seconds, foreground /
  resumed with keyguard off, zero inspected fatal/layout errors, PSS 136,104 KiB.
- Evidence: .validation/mobile-attachments-release-build.txt,
  .validation/android-final-packaging.json and
  .validation/mobile-attachments-startup.json.
- User acceptance of the new attachment layout, touch actions and preview opening
  remains pending. Tests/visual fixtures do not establish phone usability.
- Desktop portable D:\tools, notes and existing tags remain preserved. No
  commit/push, release publication or iOS build/device acceptance is included.

## Follow-up polish

The initial interpretation below was corrected after the user clarified that
the general count belongs elsewhere on All attachments. The editor notification
badge is restored. The final selection/count behavior is recorded next.

- User requested removal of the top-right editor count and the white outline
  around the bottom attachment panel. Interpreted top-right editor count as the
  notification bell's numeric badge; a clarification was offered. The bell and
  its job panel remain accessible, with a simple Notifications tooltip. The
  attachment inventory counts in the dock/gallery remain distinct.
- Removed the mobile dock's outer border while retaining its surface, clipping,
  row separators and safe interactions. Desktop styling remains unchanged.
- Five mobile layout/navigation checks passed with real-font synthetic captures;
  scoped analysis had zero errors/warnings and the existing 18 infos. Formatting
  and whitespace checks passed; desktop v1.4.1 presentation equality passed.
- Previous candidate APK/source preserved in
  .validation/mobile-attachment-polish-before/.
- Normal protected APK built in 60.9 seconds, preserving obfuscation and native
  protections; installed with install -r and cold launched on the LG (1528 ms).
  SHA256 53e0efc523889bb6cbe7fd1ddfe98ae989726d9ad64c5d04bd3fda6e43875d5c,
  131,688,393 bytes. Native packaging/alignment passed. Symbols retained privately
  under .private-release-symbols/mobile-attachment-polish-20261017/.
- Twenty-second phone observation passed: PID 10778 stable, resumed/foreground,
  keyguard off, zero inspected fatal/layout errors, PSS 132,441 KiB. Evidence:
  .validation/mobile-attachment-polish-startup.json. Manual appearance acceptance
  is pending.
- Evidence: .validation/mobile-attachment-polish-final-tests.txt,
  .validation/mobile-attachment-polish-final-analysis.txt,
  .validation/mobile-attachment-polish-build.txt,
  .validation/mobile-attachment-polish-packaging.json.

## Relocated count and multi-selection

- General attachment count now appears as quiet text below the search input
  (filtered results show N of M). The normal top bar has Select instead of a
  count badge. The editor notification badge is restored; the dock remains
  border-free. Desktop presentation still matches v1.4.1.
- Tap Select or long-press a committed file to enter selection. Checkboxes,
  selected-row tint, contextual selected count, filtered Select all and Back/X
  dismissal work without payload reads. Pending/processing files cannot be newly
  selected; bulk actions are disabled during other active attachment work.
- Share / Save prepares the complete selection through the existing streaming
  cipher and worker ownership path, then opens one native share sheet. Duplicate
  filenames get independent private destinations; no ZIP is introduced. The
  platform export adapter owns destinations/sharing/cleanup. Preparation failure
  or cancellation never shares a partial selection. Source-check cancellation is
  wired into the existing job coordinator. External recipient/save completion
  cannot be proved merely from opening or accepting the share sheet.
- Remove confirms the exact selected IDs, then publishes one recoverable note
  generation. Invalid/missing IDs, changed session, active jobs, locked notes or
  failed preparation abort without partial removal. Recovery attachment objects,
  body, note ID and timestamps follow the existing commit protocol. Single-file
  removal delegates to the same path; desktop regressions passed.
- Gallery/confirmation contents disappear immediately on lock/navigation. Bulk
  actions expose errors in the gallery, and native jobs retain progress and safe
  cancellation. No passwords are persisted and encryption formats are unchanged.
- Stitch Flash reference adb7fdc5126443878b694e0780035a17 uses synthetic names;
  count/selection/confirmation patterns adopted, speculative sort/cloud controls
  omitted. Actual mobile selection frames reviewed with SDK fonts.
- Automated: 81 combined tests passed, including batch export/cleanup/dismissal,
  cancellation during source checking and between files, duplicate filenames, failed/invalid/locked bulk
  removal, recovery retention, selection filtering/cancel, immediate protected
  removal, cache, desktop attachments, saves and mobile navigation. Scoped
  analysis has zero errors/warnings and 87 style/info notices across the full scoped file set. An unused test
  import warning was corrected before the passing rerun. Formatting/whitespace
  and desktop presentation equality passed.
- A cancellation regression exposed batch jobs being labelled as protection even
  when explicitly created for export. The helper now preserves explicit export
  operations; default protection batches retain their existing type. Source-read
  cancellation is reported as Cancelled for filesystem and provider exceptions.
- Evidence: .validation/mobile-selection-final-regressions.txt,
  .validation/mobile-selection-final-analysis.txt, synthetic
  .validation/mobile-attachments-gallery.png and
  .validation/mobile-attachments-selection.png. The previous installed candidate
  remains in .validation/mobile-gallery-count-before/.
- Final normal protected APK built in 73.5 seconds, preserving Dart obfuscation,
  R8/resource shrinking and private symbols. SHA256
  25089daf2b2692c5c62e390ccc2c11f2cced7ca42d09e4dffcb8ab9f7b8082bd;
  131,852,457 bytes. All 18 native libraries and 64-bit ELF/ZIP page alignment
  passed. Symbols: .private-release-symbols/mobile-attachment-selection-final-20261017/.
- Installed with install -r and cold launched on the LG in 1,573 ms. PID 12102
  remained stable for twenty seconds, resumed with keyguard off, zero inspected
  fatal/layout errors, PSS 173,196 KiB. This is a startup observation, not a
  sustained performance benchmark or proof of native share-sheet acceptance.
- Final delivery evidence: .validation/mobile-selection-final-build.txt,
  .validation/mobile-selection-final-packaging.json,
  .validation/mobile-selection-final-zipalign.txt and
  .validation/mobile-selection-final-startup.json. An initial sandbox denied
  Dart configuration/SDK access; scoped checks were retried with SDK access.
- Manual phone selection/share-sheet/removal acceptance remains pending.
  No release/tag, commit/push or iOS validation.

## Android multi-file export correction

- User reported export failing before the native share sheet. The prior host
  batch tests did not exercise Android temporary paths or native publication.
- A synthetic LG device probe reproduced a StateError in destination review:
  the platform temporary directory contained a filesystem alias. Export now
  resolves the trusted platform root before creating fresh destinations; the
  existing no-symlink revision/publication checks remain enforced.
- The next device gate exposed Android hard-link publication returning EACCES
  (errno 13). Modern Android now uses the available API 30+ libc
  renameat2(RENAME_NOREPLACE) operation for app-private exports. It does not use
  an overwriting rename. Older Android/iOS retain their prior link/unlink path;
  that fallback has not gained device acceptance from this correction.
- The pinned share_plus Android adapter copies files into a flat cache by
  basename. Export destinations now reserve case-insensitively distinct names
  (for example duplicate.txt, duplicate (2).txt) to prevent copy collisions.
- The 26-test focused suite passed: real platform-directory alias review,
  unchanged rejection of unresolved links, distinct export names, batch
  cancellation/failure cleanup, bulk removal and cache behavior. Scoped
  analysis has no errors/warnings; formatting and whitespace checks passed.
- Corrected synthetic LG probe passed native decryption, private publication of
  two files with duplicate original names, Android chooser presentation and
  dismissal, exact verification of both plugin-cached payloads, no-overwrite
  conflict rejection, stale-revision rejection, replacement with a verified
  predecessor copy, and cleanup. No recipient was selected or files sent.
- Device evidence: .validation/android-export-probe-result.txt (alias failure),
  .validation/android-export-probe-errno-result.txt (hard-link EACCES), and
  .validation/android-export-probe-fixed-result.json (passing corrected probe).
  Test/build/static evidence: .validation/mobile-export-fix-tests.txt,
  .validation/mobile-export-fix-analysis.txt and
  .validation/android-export-probe-publication-build.txt.
- Corrected normal lib/main.dart protected preview built in 58.5 seconds and
  installed with install -r, then cold launched on the LG in 1,557 ms. APK
  SHA256 42ae22c082b5d3dacbfdd40885ef09ca776b1a778fa3c35e3449a943d8da7360;
  131,852,457 bytes. All 18 native libraries and ELF/ZIP alignment checks passed.
  Evidence: .validation/mobile-export-fix-build.txt and
  .validation/mobile-export-fix-packaging.json. Private symbols retained under
  .private-release-symbols/mobile-export-fix-20261017/.
- Restored normal startup observation: PID 13594 stable for twenty seconds,
  resumed with keyguard off, zero inspected fatal/layout errors, PSS 126,712 KiB.
  Evidence: .validation/mobile-export-fix-startup.json. Startup observation does
  not establish sustained performance or user acceptance of gallery actions.
- The temporary probe was explicit synthetic validation and has been replaced
  by the normal app. Prior normal APK retained in
  .validation/mobile-selection-export-before/; no live note reads/mutations
  during the probe. Real gallery export acceptance and iOS validation remain
  pending. No encryption-format, desktop presentation, note, tag or portable
  release changes; no commit/push/publication.

## Multi-file export progress visibility

- The gallery previously replaced the export worker's live progress with a
  static Preparing selected attachments message. It now reuses the mobile job
  progress row, subscribed directly to the job's ValueNotifier. Byte ticks do
  not rebuild the gallery/file list or create another worker.
- The batch coordinator supplies File N of M and the current filename. The
  gallery separately displays Checking attachment / Decrypting / Verifying,
  stage bytes, a determinate percentage/bar when totals are known, and safe
  Cancel export. Decryption reaching 100% does not imply overall export success.
  Cancelling/final share handoff use indeterminate status rather than a false
  percentage, and Cancel disappears when it is no longer safe.
- The progress header wraps at large accessibility sizes; byte text can wrap
  without ellipsis. A first 200% text test exposed a 69-pixel overflow, and a
  subsequent correction caught an invalid Expanded in OverflowBar. Both were
  fixed before the passing reruns; the installed APK was not replaced on failure.
- Stitch Flash reference 35d3916deb0a4687ac0d68771154abce and synthetic
  .stitch/designs/mobile-export-progress.html/.png guided the compact footer.
  Pro was unavailable in the exposed model choices. Adopted per-file/stage/byte
  separation; no new Cancel confirmation or ETA estimate was introduced.
- Automated: 50 affected tests passed, including actual worker captions and
  byte updates, real gallery binding, first/second file progress, cancellation,
  200% text, sharing cleanup, cache and desktop attachment regression coverage.
  Scoped analysis: no errors/warnings, 68 informational/style notices. Final
  formatting/whitespace and desktop v1.4.1 presentation equality checks passed.
  Synthetic normal/200% screenshots were inspected with SDK fonts.
- Evidence: .validation/mobile-export-progress-regressions.txt,
  .validation/mobile-export-progress-analysis.txt,
  .validation/mobile-attachments-export-progress-1x.png and
  .validation/mobile-attachments-export-progress-2x.png. Previous normal protected
  APK is retained in .validation/mobile-export-progress-before/.
- Normal lib/main.dart protected preview built in 62.3 seconds and installed
  with install -r, then cold launched on the LG in 1,871 ms. APK SHA256
  b23ec8c1394ebd8331308c80390fee02409be6b21f87a2fa9e5f20f4c255d7f5;
  131,852,457 bytes. All 18 native libraries and 64-bit ELF/ZIP alignment checks
  passed. Evidence: .validation/mobile-export-progress-build.txt and
  .validation/mobile-export-progress-packaging.json. Private symbols retained
  under .private-release-symbols/mobile-export-progress-20261017/.
- Twenty-second phone startup observation passed: PID 15076 stable, resumed
  with keyguard off, zero inspected fatal/layout errors, PSS 149,214 KiB.
  Evidence: .validation/mobile-export-progress-startup.json. This is startup
  verification; it does not establish sustained large-file export performance.
- User confirmed the large-file progress display works as expected. Notes, encryption formats,
  desktop presentation, D:\tools and release tags remain preserved; no
  commit/push/publication or iOS device/build validation is included.

## Optional mobile export scans

- User accepted the current-file/decryption/byte/percentage progress display,
  then requested Checking attachment and Verifying off by default for export.
- The existing persisted checkBeforeOpen / verifyAfterOpen preferences were
  already false by default, but export ignored them. Mobile attachment export
  now honors them for the optional source hash scan and decrypted-output
  readback. Mobile settings labels explicitly cover opening/exporting. No new
  metadata keys, note migration or forced reset of saved opt-ins is introduced.
- Desktop attachment exports retain their existing checked-source/readback
  behavior. Mobile exports require whole-source framing and match known positive
  metadata sizes on both password and legacy app-key fallback paths. Required
  padding, source revision, no-overwrite publication and publication readback
  checks remain; this change does not remove every export I/O pass or change
  encryption formats, note/package import checks, backups or recovery commits.
- Automated: 65 affected tests passed, including false/missing defaults,
  independent saved opt-ins, mobile settings controls, unchanged desktop policy,
  decryption without output readback, wrong-key/framing rejection, cancellation,
  batch exports, cache and progress. Scoped analysis has no errors/warnings and
  57 informational/style notices. Formatting, whitespace and desktop v1.4.1
  presentation equality checks passed.
- Evidence: .validation/mobile-export-checks-tests.txt and
  .validation/mobile-export-checks-analysis.txt. Accepted progress APK retained
  in .validation/mobile-export-checks-before/ (SHA256
  b23ec8c1394ebd8331308c80390fee02409be6b21f87a2fa9e5f20f4c255d7f5).
- Normal protected lib/main.dart preview built in 64.0 seconds, installed with
  install -r, and cold launched on the LG in 2,092 ms. SHA256
  15edffa96728b0905d2cdf3b31868b7a5322e220a068ce120f6f34ac0550b8da;
  131,852,457 bytes. All 18 native libraries and 64-bit ELF/ZIP alignment checks
  passed. Evidence: .validation/mobile-export-checks-build.txt and
  .validation/mobile-export-checks-packaging.json. Symbols retained privately
  under .private-release-symbols/mobile-export-checks-20261017/.
- Twenty-second startup observation passed: PID 15766 stable, resumed with
  keyguard off, zero inspected fatal/layout errors, PSS 151,554 KiB. Evidence:
  .validation/mobile-export-checks-startup.json. Large-file acceptance with the
  optional scans disabled remains a separate manual check.
- User confirmed mobile export with both optional checks disabled works perfectly.
  iOS validation remains held. Source commit/push is now authorized; no release.
