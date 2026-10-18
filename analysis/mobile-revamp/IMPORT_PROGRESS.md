# Mobile package import progress and duplicate handling

## Findings and implementation

The mobile dashboard already used the owned import dialog and desktop conflict
resolver. Extraction had no progress transport, however, and duplicate lookup
could resolve an unrelated large exported backup before recognizing its type.
The dialog displayed an activity bar without byte or percentage labels.

- Add typed, throttled import progress from the retained package worker isolate.
  Binary framing, password-wrapped packages, stored ZIP and strict DEFLATE emit
  the real current file, file index/count, processed bytes and total. No new
  payload scan, encryption format or optional verification policy is introduced.
- Feed existing publication callbacks into the import job so necessary
  encrypted publication and replacement recovery work are visible.
  Keep cancellation disabled after publication starts and retain result details
  until Done.
- Opt mobile into the existing import dialog's detailed progress presentation.
  Show real stage/current file, bytes, percentage and determinate bar, with a
  narrow-screen inset. The default desktop presentation remains unchanged.
- Reuse bounded provider candidate recognition before UID lookup so a large
  unrelated backup cannot prevent reaching the duplicate resolver. Keep
  conservative rejection of unreadable actual notes during identity checks;
  discovery's silent skipping does not authorize guessing replacement targets.
- A matching UID opens Duplicate / Back up & Replace / Ignore without comparing
  incoming/existing payloads. The dialog uses neutral ID-match wording, with no
  unverified identical/different-content claim. Preserve unknown metadata, stable
  mentions and revision rechecks. No filename-based resolution or automatic overwrite.

## Design

Stitch reference `6d871f9ffb6a432a8fb417965920110f`, using the existing project
design system. The connector offers Flash/Flash Lite, not a selectable Pro model;
Flash was disclosed and used. Assets are in `.stitch/designs/mobile-import-progress`.
The reference's compact real progress and stacked conflict actions fit the
existing flow. Generated extra Open Note actions and recommended-choice styling
were not added.

## Automated validation

Initial scoped formatting/analysis passed with no errors/warnings (82 informational
notices). The initial affected suite passed 68 tests; later sections record the
additional regression coverage and final UID-only policy.

`flutter test --no-pub test/mobile_import_progress_test.dart
test/note_import_dialog_test.dart test/storage/note_import_test.dart
test/storage/streaming_pack_service_test.dart test/storage/provider_discovery_test.dart`

Coverage includes mobile file/byte/percentage readouts, finalization progress,
320 px / 200% text duplicate choices, all three duplicate decisions with
identical/different content, retained results, cancellation/finalization,
metadata/identity preservation, verified replacement recovery, encrypted binary
and ZIP round trips, desktop-compatible legacy package readers, strict DEFLATE
and framing rejection, progress delivery before completion, comparison progress,
and UID lookup beside a synthetic 3 GiB backup with no backup payload reads.

## Delivery

The preceding installed protected APK is retained in the ignored validation
directory at `mobile-import-progress-accepted` (SHA256
`585c63867e10fa4893e0f796531b9608a60180b0b7b8185d18d99d3c0ad2fe99`).
The protected Android build succeeded in 53.7 seconds. APK: 132278729 bytes,
SHA256 `75596ba8cd5cdef90d8b81953ff3098f3804beeea79f6f9f541d2cde7edeefdc`.
All 18 native libraries and the APK passed 16 KiB alignment checks. In-place
installation succeeded; cold launch took 1222 ms on LG LM-G900 / Android 12.
The app remained foreground and stable for 20 seconds with no fatal/layout log
matches; total PSS was 131843 KiB. Screenshot inspection confirmed the notes list.
No app-data wipe, real-note mutation, commit, push, tag or release publication.
Android manual large-package and repeated-import acceptance remains pending;
iOS device validation remains deferred. Windows UI/runtime is not revalidated
by the Android startup check.

## Legacy attachment-only folder correction

Manual acceptance returned `Note metadata is missing.` before the duplicate
decision. A synthetic legacy layout reproduced that exact FormatException at
`ProviderNoteFiles.inspectDiscoveryCandidate`: the new candidate recognizer
treated a `note_<id>` attachment-only directory as an independent broken note,
despite the existing resolver explicitly allowing a separate legacy note file.

Restore the resolver's absence behavior: a folder without a canonical note
envelope is not an independent note candidate. Leave its attachment payloads
untouched. A present envelope with a wrong type or malformed content still fails
the import identity check. No broad exception swallowing or guessed target.

The failing reproduction is retained in the ignored validation directory.
After the correction all 70 combined affected tests passed. Scoped analysis
passed with no errors/warnings and 24 informational notices; formatting and
whitespace checks passed. The protected Android build passed in 53.7 seconds;
APK SHA256 `933e6a093458a74faf73cf94193c56cc57317afea73390707b09ee762d1527d4`.
Native libraries and APK alignment checks passed. In-place installation returned
Success; cold launch on the LG took 1276 ms. Data was not cleared. Manual retry
of the reported package remains pending.
The replacement stayed foreground and stable for 20 seconds, with no fatal or
layout log matches and total PSS 127395 KiB. Screenshot inspection confirmed the
notes list remained visible after launch.

## Android SAF comparison worker (earlier issue)

The next manual retry failed before the duplicate selector with the generic
no-overwrite result. A protected device-only synthetic probe now exercises the
real selected-provider adapter in a new UUID-named child scope, without reading
existing note payloads. Its first setup attempt hit the validation guard on
Android's aliased cache path; the harness now canonicalizes its private run root,
keeping the guard intact. The temporary provider scope was cleaned and normal
Preview restored after that attempt.

With that setup corrected, the LG reproduced an Android-specific failure:
first import succeeded, then a fingerprint of a retained SAF attachment failed
with an uninitialized BackgroundIsolateBinaryMessenger. The Windows tests used
regular files and did not exercise the channel-backed descriptor reader.

Capture the root-isolate token and initialize the comparison worker's background
messenger before it borrows/checks SAF handles. Preserve positional bounded
reads, parent handle ownership, checksums, cancellation and revision checks.
No encryption, URI-to-path conversion, duplicate policy or UI changes.

Scoped analysis passed with no errors/warnings (two informational notices), and
all 70 affected tests passed. The corrected protected LG Android 12 probe passed:
first import succeeded, retained SAF fingerprint succeeded, all three duplicate
decisions returned their expected dispositions, and provider cleanup passed.
Before/after content-free summaries are retained in the ignored validation
directory. The probe collector
automatically restores the preserved normal APK after collecting a content-free
summary, whether the probe succeeds or fails.

The protected normal app was then built from `lib/main.dart` in 67.3 seconds,
after all native duplicate outcomes passed. APK SHA256:
`cf48c91e26c29016a4f67681d6f4dea06fac669d6f4cf4a559acd4ba6f068336`.
All 18 native libraries and APK alignment passed. In-place installation returned
Success and cold launch took 1290 ms. The normal app stayed foreground and stable
for 20 seconds, with no fatal/layout log matches and total PSS 149995 KiB.
Screenshot inspection confirmed normal notes-list startup with three notes.
Existing note payloads were not read by the synthetic probe, and app data was not
cleared. Manual acceptance of the normal dialog on the original package remains
pending; the real SAF duplicate backend now has passing device evidence.

## UID-only duplicate prompt

The user's latest decision removes content comparison from import conflict
handling entirely. Immediately after the metadata UID lookup, present the
existing three choices. Do not call the fingerprint helper or acquire existing
attachment sources before that decision. Ignore returns immediately. Duplicate
publishes the incoming version under a new identity without reading existing
attachment payloads. Replacement alone captures/rechecks predecessor payload
revisions after the user chooses it at this checkpoint; the section below
supersedes those payload scans.

Optional conflict comparison metadata is null in this flow. The same layout
shows neutral ID-match text rather than claiming identical/different content.
The standalone fingerprint helper retains its validated Android worker setup
for compatibility, but normal import no longer invokes it.

All 82 affected tests passed, including prompt/Ignore/Duplicate with a deliberately
missing synthetic existing payload, refusal to replace without the predecessor,
neutral wording, large text choices, package formats and existing recovery tests.
Scoped analysis passed without errors/warnings (58 informational notices).
The synthetic LG probe now rejects existing attachment reads before the callback
and throughout Ignore/Duplicate; only replacement releases that guard. The
protected LG Android 12 probe passed first import and all three decisions with
zero payload reads before choice. Provider cleanup passed. The protected normal
build passed in 54.8 seconds. APK SHA256:
`5692e6ce922e8efa2ec5a10bf288bfb08957c67934f0071f501a4537d6c27c0b`.
All 18 native libraries and APK alignment checks passed. In-place installation
succeeded, cold launch took 1274 ms, and normal startup stayed foreground/stable
for 20 seconds with no fatal/layout log matches (PSS 145653 KiB). Screenshot
inspection confirmed the existing three-note list. No app-data wipe or real-note
mutation was performed. Manual normal-dialog acceptance remains pending.

## Replacement without predecessor payload scans

Per the user's next decision, remove both full-file predecessor hash reads:
the initial capture and the final "Confirming existing attachment revision"
pass. Check predecessor availability through `attachmentSource(verifyContent:
false)` only. This checks the file/descriptor metadata without consuming payload
bytes. Ignore/Duplicate still never acquire predecessor attachment sources.

Keep the small note-envelope revision recheck, draft/session/cancellation guards,
fresh imported attachment storage IDs, attachment-first publication, existing
journals and retained predecessor envelope/payloads. The predecessor availability
check still refuses replacement when an old attachment is missing. These changes
do not introduce a new backup/copy pass or alter encryption/package formats.
External mutations of predecessor payload bytes are no longer detected by a
full-file comparison during replacement. Recovery of ambiguous interrupted
transactions retains its existing behavior.

The rulesbook now explicitly prohibits adding or re-enabling optional payload
verification passes without the user's request.

All 82 affected tests passed, including retained predecessor recovery, missing
predecessor refusal, note-revision conflicts, cancellation and package formats.
Scoped analysis found zero errors/warnings and 57 informational lint notices
(the analyzer exits nonzero for infos under its existing configuration).
The protected synthetic LG Android 12 check passed first import and all three
decisions with zero existing-payload read attempts through replacement
completion. Descriptor acquisition is allowed only after the replacement choice;
payload reads remain blocked. Its private provider scope was cleaned afterward.
Evidence: `.validation/android-replace-fast-tests.txt`,
`.validation/android-replace-fast-analysis.txt`,
`.validation/android-replace-fast-probe.json`.

The normal protected `lib/main.dart` Preview build passed in 54.1 seconds.
APK SHA256:
`d08978b20f8d9dee042d6913db444f0b55fb66e87403563e6e93270a01059e97`.
All 18 native libraries and APK 16 KiB alignment checks passed. In-place install
succeeded and cold startup took 1297 ms. The normal app remained resumed/stable
for 20 seconds with zero fatal/layout log matches and total PSS 131670 KiB.
Screenshot inspection confirmed the normal existing three-note list. The previous
normal APK remains preserved in `.validation/android-replace-fast-previous/`.
No app data was cleared or real notes mutated. Manual acceptance of the new
normal replacement flow remains pending. This turn did not build/run iOS or
rebuild Windows; shared Windows storage/recovery behavior passed the host tests.

## Import saving throughput and separate file/batch progress

The saving callback previously exposed only per-document bytes, resetting for
each file while discarding its display name and batch position. Android's
bounded append adapter also reopened the provider destination on every 1 MiB
message. The package is extracted to private owned staging first; the subsequent
encrypted transfer into the selected library is real I/O, not re-encryption or
an optional verification pass.

Changes:

- Add typed publication progress carrying original filename, File N of M,
  current-file bytes and byte-weighted cumulative saving bytes. Preserve the
  existing byte callback for other callers and the desktop dialog layout.
- Mobile shows Current file and Overall saving separately. Overall is explicitly
  scoped to saving this batch, not estimated time/whole-import completion.
  Note metadata/journal work uses Finishing import with an indeterminate bar.
  Background tasks and Android's expanded notification show both metrics.
- Retain a bounded set of Android append handles until flush, closing on errors,
  rename, deletion and disposal. Retain offset/length checks and fsync.
- More importantly, reuse the existing Android owned native worker for the one
  encrypted transfer into a provider-owned candidate. Both cipher flags are
  false: payload ciphertext is copied unchanged. Carry forward the captured
  write-verification setting and streamed source checksum; do not add a scan.
  Publication adopts the receipt instead of copying again. Unsupported direct
  sinks retain the single-transfer fallback. Owner guards, resource budgeting,
  cancellation, bounds, recovery and note revision checks remain enabled.
- Keep byte-copy preparation cancellable; irreversible metadata publication
  retains the existing non-cancellable finalization boundary.

Validation: final combined affected suite passed 141 tests, including native
ownership/scheduler coverage, recovery boundaries, duplicate choices, weighted
progress and the finishing UI. Scoped analysis found no errors/warnings; existing
informational lints remain. Stitch Flash refined the synthetic dual-progress
reference (Pro unavailable); generated database claims and unsafe cancellation
during finalization were not adopted.

Real LG Android 12 evidence: the intermediate bounded-append path took 2.943119 s
for an 8 MiB encrypted file. The subsequent native path saved a two-file 16 MiB
batch in 1.296776 s. These are small synthetic observations, not a sustained
700 MiB benchmark or a guaranteed speedup on other media/thermal conditions.
The native probe passed first import, all three conflict choices, monotonic
named-file/batch progress, finishing state and unchanged-payload decryption.
No payload chunk writes crossed the document channel (largest write: 1284 bytes
of metadata); no existing payload reads occurred during conflict handling.
The temporary provider scope was cleaned. Evidence is in
`.validation/import-saving-native-probe.json` and
`.validation/import-saving-native-tests.txt`.

ADB returned `failed to read copy response: EOF` while restoring the preserved
normal app after the passing probe. This is a transport/restoration failure,
not a passing installation; reconnect and retry normal installation before
claiming delivery. No data clear/uninstall was used.

The reconnect succeeded. Streaming installation restored the preserved normal
app successfully, then installed the final protected normal build successfully.
The final `lib/main.dart` build passed in 141.8 s; APK SHA256:
`b930e1f5eadabccb887741a2c26ebdac32ca26a719bc628702bbab8d6c6a9053`.
All 18 native libraries and APK 16 KiB alignment checks passed. Cold launch took
1369 ms. Normal Preview remained foreground/stable for 20 seconds with zero
fatal/layout log matches and total PSS 125843 KiB. Screenshot inspection confirmed
the normal notes list. Existing app data, user library files, portable releases
and tags were preserved. The probe's temporary provider objects were removed;
no user note was mutated by validation.

Manual large-package progress/timing acceptance remains pending. No sustained
700 MiB test, new Windows build or iOS device/build validation was performed in
this task. Host Windows storage/recovery regression tests passed; desktop
presentation remains unchanged.
