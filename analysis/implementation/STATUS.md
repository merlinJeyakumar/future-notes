# Repair implementation status

## Attachment viewing and tray candidate — 2026-10-14

The unified inline attachment row, explicit file-backed Open cache, embedded video player, visible More menus, recoverable tray setting and native Windows tray lifecycle are implemented. Task-focused regressions and the single new 4 GiB/10 GiB cache gate passed, followed by one canonical Windows Release build and one prebuilt launch. Native inspection confirmed one visible responsive window and the protected cache ACL. On 2026-10-15 the user confirmed attachment addition and tray reopening worked, then authorized validation, commit and push. The final format/whitespace checks, retained analyzer exception and one full suite passed (461 tests, three opt-in skips). Remaining playback/system-opening/cache-lock/background-preparation/actual-Exit acceptance is pending; no native playback/performance claim is made. The previous 16-file Release bundle is hash-verified and retained. No ZIP or movement of `v1.0.0` belongs to this delivery. See [ATTACHMENT_VIEW_TRAY_RESULTS.md](ATTACHMENT_VIEW_TRAY_RESULTS.md) for failures/corrections, test overlap, timings and limits.

## Windows Release delivery — 2026-10-14

Canonical Windows Release `1.0.0+1` compiled successfully. The final integration suite passed 440 tests with two previously validated opt-in checks skipped. The complete 16-file ZIP was verified against build output. See [WINDOWS_RELEASE.md](WINDOWS_RELEASE.md) for commands, package hash and validation limits. Release runtime has not been exercised; no app was launched for this delivery.

## Current Windows backend delivery — 2026-10-14

This entry supersedes earlier preview restrictions and pending date/startup notes below. On `integration/recoverable-storage`, canonical `lib/main.dart` now resolves existing settings and the selected library, initializes recoverable persistence and exposes the transactional attachment/password, import/export, Delete and library-switch adapters. The preview banner and temporary unrestricted entry point are removed.

Required synthetic regressions, copied-library recovery, real 4 GiB/10 GiB streaming and independent ZIP64 reading passed. The retained original library/backup hashes match. One Windows Debug build and startup passed; native inspection confirms one visible app window in the user's desktop session. The previous executable remains retained. The user confirmed all presented full-app manual checks passed on 2026-10-14. Measured native UI performance is not claimed.

Subsequent locked-note UI report: Save/File Settings and attachment-job details are now hidden while locked, and the breadcrumb says Locked. Desktop/compact unlock/relock and standalone job-panel regressions passed; the existing session-safety tests passed. Windows Debug compilation passed after normal app closure; the previous 17-file executable bundle was retained and hash-verified. Manual runtime verification of this UI correction remains pending; the app was not restarted. See [LOCKED_NOTE_UI_RESULTS.md](LOCKED_NOTE_UI_RESULTS.md).

See [FULL_BACKEND_RESULTS.md](FULL_BACKEND_RESULTS.md) for exact gates, failures/corrections, overlapping test counts and limits, and [FULL_BACKEND_FLOW.md](FULL_BACKEND_FLOW.md) for code flow. Historical stage entries below are retained as evidence, not current feature policy. This delivery does not close unrelated findings or encryption redesign.

Baseline: development, a9f6d247d7e27322d4afe542aa27240c72af031e.

2026-10-13 integration candidate: branch `integration/recoverable-storage`, based
on preserved checkpoint `31dfe4e`. The normal entry point has opt-in owned Windows
storage wiring; default activation remains disabled. Shared settings/library
roots use one lease and queue, and unfinished workflows are guarded before draft
mutation. Code review/static lint only; tests/build/runtime and real-library
activation remain pending. See [native integration](NATIVE_STORAGE_INTEGRATION.md).

The original development analysis is baseline evidence, not verification of
subsequent patches. No finding is closed without its regression evidence.

The [finding ledger](FINDING_LEDGER.md) tracks all 50 baseline IDs, including
the separately deferred R01 migration gate.

| Stage | Implementation | Validation |
| --- | --- | --- |
| 0: isolated storage and synthetic fixtures | Implemented | Formatting, 58 tests and Windows Debug build passed; analysis accepted with explicitly approved 79-diagnostic baseline |
| 1: guarded sessions and draft transitions | Guarded sessions and decision/exit candidates passed source/test/build gates; library/export/job dependencies remain | 42 focused/100 total tests and Windows Debug compilation passed; approved analysis exception: 92 diagnostics; runtime pending |
| 2: compatible codec and recoverable persistence | Shared codec through injected note-service and shutdown/cleanup gates passed | Latest cleanup validation: 54 focused/274 total tests/build, analysis 98 diagnostics; application integration/runtime pending |
| 3: canonical saves, libraries and permanent Delete | Save coalescing and injected library coordinator passed; production activation, full mutation ordering and Delete pending | Latest library gate: 337 tests, unchanged analyzer baseline and Windows Debug build; runtime pending |
| 4: bounded attachment streaming and password transactions | Pending | Pending |
| 5: separate per-file and batch loaders | Pending | Pending |
| 6: complete streaming packages and collision-safe imports | Pending | Pending |
| 7: discovery, lifecycle, UI, performance and platforms | Readiness, scan/search ownership and watcher/library batch passed source/test/build gates | Latest: 337 tests, unchanged 97-diagnostic exception and Windows build; earlier native failure unresolved, continuous runtime/performance/platforms pending |
| 8: encryption migration specification | Deferred; new writer remains disabled | Separate acceptance gate |

## Stage 0 candidate

- Configure storage before settings initialization using explicit validation
  defines. Missing/invalid locations fail instead of selecting production.
- Validation settings and library must be separate descendants of an absolute
  disposable run root named `future-notes-validation-<run-id>`.
- Check existing path components for links before isolated I/O. This does not
  claim protection against hostile concurrent filesystem replacement.
- Ignore a copied settings file's stored library path in validation mode.
- Independent settings/file-service instances allow tests to replace production
  directory resolution with a throwing callback.
- Existing production location shapes and encryption implementations remain.
- Promote the existing path 1.9.1 dependency without changing its version.
- Generate only synthetic fixtures for current/legacy envelopes, protected
  bodies, HTML, boundary whitespace, unknown metadata and attachment/package
  ciphertext. Fixture passwords are generated in memory, never copied from
  user data.

## Approval and preservation boundary

Approved offline dependency resolution, formatting, tests, analysis and Windows
Debug build ran for Stage 0. The application has not been launched.
UserData and the existing opaque root note have not been read or modified.
The running app was not stopped or restarted. No branch/commit/push occurred.

The pre-existing Debug runtime bundle was copied into
`.validation/future-notes-validation-baseline-860467a10d2d45acbbc656adb8263965/bundle`.
All 16 copied files match their source SHA-256 hashes; `manifest.json` records
their paths, lengths and hashes. The executable's originating source revision
and runtime behavior are unverified. This preservation is not an application
validation result. The Git baseline remains available at the revision above.

Stage 0 isolates the settings and file-service seams; the known working-directory
autosave and other unfinished workflows remain. Do not launch this intermediate
patch or enable repaired persistence against a real library. Runtime validation
starts only after the corresponding safety stages pass.

Exact command approval remains required by RULESBOOK.md. After approval, the
existing test baseline was recorded before the new isolated tests were run.
Strict analysis returned exit code 1. The user then explicitly allowed the
recorded baseline for Stage 0. Analysis with `--no-fatal-infos --no-fatal-warnings`
returned exit code 0 with the same 79 diagnostics, and Windows compilation
passed. This exception does not close those diagnostics or prove runtime safety.

The exact proposed command sequence is in [VALIDATION.md](VALIDATION.md).
Observed results and the failure are in [VALIDATION_RESULTS.md](VALIDATION_RESULTS.md).

## Stage 0 checkpoint

The tested Stage 0 Dart sources/tests, dependency manifests and Debug bundle are
preserved under
`.validation/future-notes-validation-stage0-1419f92a19554e7f81fa8f85e1d08adf`.
The manifest records 46 copied files with hashes verified against their source.
The earlier pre-existing bundle is also retained. Neither executable was launched.

## First Stage 1 candidate

This candidate brings forward captured reference and metadata-preservation
prerequisites from Stage 2 and the shared Save/autosave entry point from Stage 3.
The dependency is necessary to avoid writing a guarded session through mutable
settings or persisting a title change as a normalized body.

- Add immutable DraftSession/NoteSnapshot and typed OperationResult.
- Resolve an exact folder/legacy content object and persistent model ID before
  publishing a loaded session. Captured reads/writes do not re-resolve settings.
- Decode prospective metadata/body into temporary state. Reject damaged or
  unsupported envelopes/body schemas; retain the prior editor on failure.
- Bind loads, unlocks and conversions to owner/request generations. Reject stale
  publication and preserve edits made while another note is being read.
- Centralize document replacement and subscription ownership. Account for
  Quill's asynchronous change delivery when Save immediately follows typing.
- Save immutable snapshots through a save queue. Preserve short explicit titles,
  original IDs/timestamps, unknown metadata, unchanged body content and envelope
  kind. Loading placeholders are excluded from new durable metadata.
- Remove working-directory autosave. Use the same captured Save entry point,
  two-second debounce, explicit first Save and failure retry pause.
- Flush existing dirty drafts before note selection, reset or manual lock; keep
  drafts on failure. New dirty drafts are temporarily blocked rather than
  discarded until their decision dialogs are implemented.
- Password verification does not replace controllers; ordinary unlock publishes
  once. Reset updates lock/attachment notifiers, and late preview reads cannot
  refill cache after lock or session replacement.
- Add 22 controlled VM regressions and 4 real synthetic-file reference tests.

**Validation scope:** after approved harness setup and cleanup corrections,
26 focused regressions and all 84 tests passed. Windows Debug compilation passed.
Analysis returned 0 with the approved exception: 90 diagnostics (88 info and the
same 2 baseline warnings, no errors). Runtime behavior remains unvalidated. See
[STAGE1_RESULTS.md](STAGE1_RESULTS.md) and
[STAGE1_VALIDATION.md](STAGE1_VALIDATION.md).

**Remaining gates:** the native writer is still direct replacement and has no
expected-revision check, journal, lease, recovery or baseline copies. The save
queue does not yet order attachment publication, password jobs and Delete.
Shared discovery/export codec adoption, save coalescing, all transition decision
dialogs, first-attachment Save & Continue, library publication, normal exit
cancellation and transactional protection changes remain pending. Export retains
its preliminary selection for other notes; its load failure now blocks exporting
the wrong prior note. Password/import paths still need metadata/timestamp repair.
No app launch or real-library validation is authorized for this candidate.

## First Stage 1 checkpoint

The tested Dart source/tests, manifests and Windows Debug bundle are retained at
`.validation/future-notes-validation-stage1-587d03dd00b84c949d4966449d7d8257`.
All 52 copied files were SHA-256 verified against their source. Earlier Stage 0
and original bundles remain available. No executable was launched.

## Second Stage 1 candidate — source/test/build gate passed

- Add an injected decision handler and revision-bound transition permit. A
  Discard decision remains provisional while the destination is read/decoded;
  a failed destination retains the previous draft unchanged.
- Offer Save / Discard / Cancel for new dirty drafts and Retry / Discard / Cancel
  after existing draft flush failures. First-Save approval persists through a
  Retry, rather than asking for that decision again.
- Reject stale decisions and later revisions. Do not stack concurrent decision
  dialogs. Continue flushing edits made while Save is in progress.
- Offer Save & Continue / Cancel before the first attachment. Failed/cancelled
  Save never opens the picker. Reject a picker return owned by another session.
- Resolve normal exit through Flutter's AppLifecycleListener. Coalesce exit
  requests and return Cancel on failure or cancelled draft resolution.
- Surface typed failures through a sanitized notification. Reuse existing
  Material dialog components and theme; this is behavior wiring, not the later
  attachment-loader visual design.
- Prepare 13 additional controlled transition tests and 3 dialog tests. Test
  editor disposal happens before Flutter's pending-timer invariant.

After user approval, the redundant null assertion was removed and the gate
reran. Formatting, 42 focused tests, all 100 tests and Windows Debug compilation
passed. Analysis returned 0 with the original 2 warnings and 90 info (92 total);
the new warning is gone. Runtime did not run. See
[STAGE1_TRANSITION_RESULTS.md](STAGE1_TRANSITION_RESULTS.md) and
[STAGE1_TRANSITION_VALIDATION.md](STAGE1_TRANSITION_VALIDATION.md).

Runner inspection confirms that top-level messages are offered to Flutter before
Win32's default handler. It does not prove that Cancel keeps the actual Windows
window open. Runtime validation remains pending until safe persistence and
owned attachment jobs are implemented. Forced termination/power loss cannot
preserve edits that never reached storage.

Library switching, export without editor selection, complete attachment-job
conflict guards, protection transactions and recovery still require their later
stages. Discard cannot lock a stored plaintext note whose pending protection
change failed; that draft is retained with an explicit rejection.

The tested transition candidate is retained under
`.validation/future-notes-validation-stage1-transitions-c6830f051fdc4b10b04a2731d96889d1`.
All 56 copied source/test/manifest/bundle files match their source SHA-256 hashes.
Earlier checkpoints remain available. No notes were copied.

## First Stage 2 candidate — source/test/build gate passed

- Centralize schema validation and independent plaintext/app-envelope recognition
  in NoteCodec. Discovery, loading (and therefore stored unlock/verification),
  loose-note verification, export metadata and both package readers use it.
- Retain immutable raw note/attachment metadata, legacy string-ID representation,
  IDs, timestamps and exact body strings. Opening performs no rewrite.
- Fix discovery's unreachable plaintext fallback: it no longer depends on a
  decryption exception when the legacy decryptor returns an empty failure string.
- Reject duplicate/mixed attachment identities, malformed fields and negative
  sizes. Display basenames may still repeat; their ZIP payload repair is Stage 6.
- Pass raw metadata to package creation, reject model/metadata disagreement, and
  return raw metadata with extracted packages. This keeps binary-v1 framing and
  current ZIP mapping shape. Import publication still needs fresh identities and
  full metadata adoption in Stage 6.
- Capture the export envelope reference before asynchronous work. Attachment
  reads and export outcomes remain on their older paths until their own stages.
- Prepare 13 regressions using synthetic compatibility fixtures and operation-
  owned temp files, including shared sync/async recognition, unknown fields,
  legacy attachment representation, old model-reader compatibility, malformed
  input, exact body strings and discovery without rewriting bytes/timestamps.

The approved gate passed formatting, 74 focused tests, all 113 tests and Windows
Debug compilation. Analysis retained the original two warnings and 88 info,
with no new diagnostics. See [STAGE2_CODEC_RESULTS.md](STAGE2_CODEC_RESULTS.md).
The tested source/executable is preserved in the 61-file verified checkpoint
`.validation/future-notes-validation-stage2-codec-8c472a31d75d454898ef508322c8a35c`.

No cipher, KDF, envelope wire format or dependency version is changed. The old
decryption sentinel API still needs typed-result repair. Recoverable commits,
leases, revision conflicts and startup recovery remain pending. No app launch
or real-library activation is authorized. This candidate does not make exports
complete or memory-bounded, and it does not authorize imports into real notes.

## Second Stage 2 candidate — typed decryption source/test/build gate passed

- Add DecryptionResult with distinct success payload and sanitized failure.
  Valid empty strings/bytes remain successful. Record use of the legacy default-
  key fallback; do not retry a successful empty result with another key.
- Keep the existing AES-SIC/PKCS7 algorithm, key derivation, IV rules and wire
  layouts. Reject missing, short and misaligned ciphertext/IV framing; existing
  installed PKCS7 code checks final padding. No writer or crypto dependency changes.
- Adopt typed results in shared envelope recognition, background discovery,
  cached-password loading, unlock, password verification and preview reads.
  A plaintext body beginning `Error decrypting` is ordinary content. Failed
  preview decryption returns no payload and is not cached.
- Retain legacy adapters for buffered package and protection workflows pending
  Stages 4/6. Their callers still need typed outcomes, complete attachment
  inventory, transactions and bounded streaming; R06 remains open.
- Prepare 11 installed-cipher fixture tests and three controlled VM tests for
  empty payloads, failure-prefix content, malformed framing/padding, a fixed
  wrong-password fixture, legacy key-derived IV and mixed-key fallback, cached
  reopening, failed credentials and preview cache behavior.

The approved formatting/test/analysis/build gate passed all 88 focused and 127
total tests. Analysis has the original two warnings and 90 info, no errors.
See [STAGE2_DECRYPT_RESULTS.md](STAGE2_DECRYPT_RESULTS.md). The tested 63-file
source/executable checkpoint is retained under
`.validation/future-notes-validation-stage2-decrypt-784efd77c4084df482059b2aae0f99a6`.

Legacy ciphertext is unauthenticated: padding or decoding success does not prove
the key is correct or detect every modification. Mixed-key compatibility remains;
protection transformations must not treat ambiguous decryption as integrity proof.
The empty-payload reader repair does not yet fix the old empty encryption writer.
Recoverable writes, revision checks, owned streaming workers and runtime remain
pending. Real-library activation remains withheld; no app launch is included.

## Third Stage 2 candidate — revision and lease foundation gate passed

- Add checked SHA-256 revision capture with file length/modification time and
  1 MiB read windows. Missing targets are distinct from empty targets and I/O
  failure; only explicit OS missing-file/path errors return a missing revision.
- Reject non-files, escaped validation locations and existing path links. Detect
  changes observed across the read; this is not an atomic snapshot and cannot
  detect all adversarial concurrent replacements or forged filesystem times.
- Add nonblocking writer leases held by one file handle until explicit close.
  Prevent duplicate ownership in the coordinator's isolate; require all app lease
  work to dispatch to that owner. Retain lock files after release to avoid
  splitting filesystem identity. Settings and libraries use independent leases.
- Promote already-installed crypto 3.0.7 to a pinned direct dependency for hash
  imports. No version upgrade is requested; offline resolution must be checked
  for only this dependency classification change before continuing the gate.
- Prepare eight synthetic-file tests, including known digests, same-size external
  changes, bounded read callbacks, mid-read mutation, containment, release/reuse,
  settings/library separation and native Windows handle contention.

These primitives are not connected to existing save/settings paths. The complete
recoverable replacement, journal validation, baseline/recovery retention, startup
recovery, expected-revision integration and lease lifecycle publication are still
pending. Do not describe the current writer as recoverable or enable it on real
notes. All other platforms need actual-host validation; Unix locks are advisory
and per process, so other isolates must not acquire/close separate lock handles.
The approved gate passed offline resolution, formatting, all eight focused and
135 total tests, analysis with the retained exception and Windows Debug build.
See [STAGE2_PRIMITIVES_RESULTS.md](STAGE2_PRIMITIVES_RESULTS.md).

The tested 65-file source/executable checkpoint is retained under
`.validation/future-notes-validation-stage2-primitives-a38000de30ae4c2f885d87241c618783`.

## Fourth Stage 2 candidate — strict journal schema gate passed

- Define immutable version-1 intent/receipt schemas with opaque transaction and
  recovery identities, root-relative target paths, hashes, lengths and revisions.
  No note body/password is included. This is app-internal bookkeeping; note,
  attachment and package formats do not change.
- Derive every staging/recovery/baseline/receipt path from validated identities.
  Do not trust a journal-supplied storage path. Reject traversal, absolute paths,
  stream syntax, device names, reserved internal targets and filename aliases.
- Require exact canonical JSON, bounded record metadata, supported versions,
  valid revisions and receipt binding to the exact intent/content generation.
  Duplicate/unknown keys and damaged records fail closed for later recovery to
  retain and report, rather than silently rewriting or guessing.
- Prepare 10 pure codec regressions. No filesystem recovery/save integration is
  present yet. The later reader must bound file bytes before constructing input;
  a bounded parser does not make an unbounded file read safe.

The approved gate passed all ten focused tests, all 145 tests and Windows Debug
compilation. Analysis retained the original two warnings and 95 info, no errors.
See [STAGE2_JOURNAL_RESULTS.md](STAGE2_JOURNAL_RESULTS.md). Full recoverable commit/recovery,
immutable baseline creation, lease lifecycle integration, external-change handling
and all fault boundaries remain pending. The production writer is not connected
to this journal. See [STAGE2_JOURNAL_VALIDATION.md](STAGE2_JOURNAL_VALIDATION.md).

The tested 67-file source/executable checkpoint is retained under
`.validation/future-notes-validation-stage2-journal-3a4ea054669a4e33bde8025275c954b0`.

## Fifth Stage 2 candidate — Windows file-action gate passed

- Add an injectable move interface and a Windows implementation using SDK FFI
  and MoveFileExW with flags zero. Destination replacement and cross-volume
  copy fallback are disabled. A destination conflict preserves both objects.
- Validate captured-root containment and reject traversal, links, stream/device
  paths and filename aliases before native allocation. Encode full UTF-16 names,
  including surrogate pairs, with checked allocation and cleanup.
- Report native failure, conflict and a possible completed move followed by
  allocation cleanup failure separately. Never translate a failed native return
  into success, even if its reported error code is zero.
- Prepare eight real native Windows tests using disposable synthetic files:
  successful publication, existing destinations, Unicode and long paths, retry
  after failure, missing sources, directory rejection and invalid locations.

This helper is disconnected from production writes. Native metadata work must
run in the storage owner worker when integrated; the current standalone helper
does not establish UI latency. Other platforms remain unsupported by this
implementation. No new dependency, encryption change or app launch is included.

The native no-replace operation prevents overwriting a file that appears at the
destination between a revision check and publication. It does not make the
complete transaction atomic, prevent concurrent source changes or establish
power-loss durability. Full commit/recovery and fault-boundary validation remain
pending. Microsoft documents the move flags in
[MoveFileExW](https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-movefileexw).
The approved gate passed all eight focused and 153 total tests, analysis with
the retained exception and Windows Debug build. See
[STAGE2_FILE_ACTIONS_RESULTS.md](STAGE2_FILE_ACTIONS_RESULTS.md). The verified
69-file source/executable checkpoint is retained under
`.validation/future-notes-validation-stage2-file-actions-55e631b5a8a94deb9dcfc8e0e75c0c08`.

## Sixth Stage 2 candidate — recoverable-backend gate passed

- Open only explicit disposable Windows roots; reject production before I/O.
  Acquire an owner lease and finish recovery before returning the store.
  Library and configuration roots can hold separate owners. Application services
  remain on their existing paths until this backend and integration pass gates.
- Queue commits in one owner. Validate identities, expected revisions and a
  reopenable source file before copying in 1 MiB windows. Detect changed inputs,
  source lengths, cancellation during preparation and destination conflicts.
- Exclusively create staged files and immutable intents, flush/close/verify,
  retain the first baseline with a receipt tied to its original intent, then
  retain the prior active object and publish without destination replacement.
  Verify publication and the completion receipt before returning success.
- Keep all staging, intent, baseline and recovery files. Once an intent starts,
  failures make the affected target non-writable. Cancellation stops only
  preparation; it cannot interrupt a publishing transaction.
- Recover incomplete generations to a verified prior version or prior absence.
  Retain interrupted candidates and previous files. Preserve the captured
  modification time when restoring, so another interrupted recovery can resume.
  Finish with a separate immutable restoration receipt.
- Retain and block unexpected external versions, damaged baselines/receipts and
  multiple unfinished generations. Unidentifiable intents/orphan receipts make
  the library read-only. Completed historical receipts never resurrect a later
  missing target. Bound metadata reads before JSON parsing and verify each
  object's baseline once at startup.
- Prepare 46 regressions covering 18 commit boundaries, three recovery boundaries,
  actual native moves, injected native failures before/after movement, queue and
  lease ordering, exact retention, new/empty objects, source/external mutations,
  corrupt metadata, identity collisions, cancellation and a multi-window input.

The approved gate passed formatting, all 46 focused and 199 total tests, analysis
with exactly the previous 98 diagnostics and Windows Debug compilation. See
[STAGE2_RECOVERY_RESULTS.md](STAGE2_RECOVERY_RESULTS.md). The 71-file validated
source/executable checkpoint is retained under
`.validation/future-notes-validation-stage2-recovery-b4823428c61442cc8ebdae767cc0e7cf`.

**Limits:** hooks simulate interruption with handle cleanup; they do not simulate
process death or power failure. Legacy content is copied exactly and is not
authenticated by these bookkeeping hashes. Concurrent hostile filesystem
replacement cannot be excluded by portable path checks or create/reopen pairs.
The reader currently refuses more than 30,000 transaction-directory entries;
large-history pagination/indexing remains pending before production activation.
It never deletes retained data to satisfy this bound. Corrupt receipts or
partial baselines remain non-writable for manual recovery rather than being
overwritten. Recovery can fail safely when a filesystem cannot preserve the
captured modification time.

Worker dispatch/handshake, IFileService/settings lifecycle adoption, captured
load revisions, startup discovery/watcher ordering, full mutation-queue adoption,
real process interruption, latency/resource profiling and actual app runtime
remain pending. No real-library activation, app launch, dependency or encryption
format change is included. No finding is closed by this candidate.

## Seventh Stage 2 candidate — owned persistence worker, source/test/build gate passed

- Add an injectable StorageOwner interface and a Windows validation worker.
  Reject production before spawning. Await an explicit handshake after configured
  path verification, with a deadline covering both spawn and readiness.
- Keep stores, leases, digest loops and native move calls in one actor. It can
  own separate library/settings roots; each root becomes available only after
  its recovery finishes. No attachment buffers/controllers cross its boundary.
- Tag requests/responses with worker generations and monotonically increasing
  identities. Reject foreign, released or forged root handles before submission.
  Bound pending descriptors to 128 and report overload without dropping accepted
  requests. One actor orders revision reads, commits, release and shutdown.
- Return typed revision/commit results and immutable recovery reports. Sanitize
  worker error/exit messages and invalidate outstanding acknowledgements on an
  unexpected exit. Do not automatically retry a possibly committed write.
- Graceful shutdown waits for accepted work and closes all store leases before
  its final response. Stop only an uninitialized owned worker on startup timeout;
  never kill a live writer as normal shutdown.
- Add 16 tests for real-isolate readiness, startup/launch timeout and late
  cleanup, startup errors/exit, unexpected root-free exit, file-backed commits,
  queue backpressure/order, generation guards, independent worker contention,
  library/settings isolation, recovery publication and graceful shutdown.

All 16 focused tests and all 215 tests passed. Windows Debug compiled in 9.8
seconds. Analysis matched the prior 98 diagnostics exactly (96 info, two original
warnings, no errors). See [STAGE2_OWNER_RESULTS.md](STAGE2_OWNER_RESULTS.md) and
[STAGE2_OWNER_VALIDATION.md](STAGE2_OWNER_VALIDATION.md). The tested 73-file
source/executable checkpoint is retained at
`.validation/future-notes-validation-stage2-owner-54a6d15bf54448d5a56dffbe76f44e9e`.
The backend's previous 71-file checkpoint remains available.

Application file/settings services do not use this worker yet. Production
activation, captured load revision adoption, discovery/watcher startup ordering,
save coalescing/full mutation queue, attachment cancellation/progress, real
process interruption and UI latency/resource/continuous-operation validation
remain pending. An unexpected isolate exit can leave lease cleanup uncertain;
fresh ownership must still pass the native lease and recovery checks. No claim
is made that this worker improves measured frame time. No app launch, dependency
change or encryption-format change is included.

## Eighth Stage 2 candidate — injected settings-service adoption, source/test/build gate passed

- Connect SettingsService.withStorage to an optional injected StorageOwner;
  require disposable Windows settings and reject production before owner or
  Documents access. The singleton/main application does not enable this path.
- Acquire the fixed configuration root and finish its recovery before reading
  settings. Compare revisions around bounded UTF-8 JSON reads (64 KiB maximum).
  Validate all known fields before publishing any values; retain unknown fields.
  Opening does not rewrite settings. Explicit validation paths override copied
  library selections.
- Serialize settings mutations. Build each candidate from the last acknowledged
  values and publish values/notifiers only after a complete recoverable commit.
  Preserve prior values on failure, with sanitized typed exceptions. Do not
  fall back to direct writes after ownership/recovery/load/commit failure.
- Stage operation-owned, bounded configuration sources, flush them and pass file
  descriptors to the worker. Remove those temporary sources after acknowledgement;
  retain failed cleanup ownership for retry on close without disguising a
  successfully acknowledged commit. Backend recovery copies remain retained.
- Close after accepted mutations and initialization, release only the settings
  root and leave the injected worker's independent library ownership intact.
- Add 19 regressions for publication timing, queue ordering, failure/retry,
  metadata/baseline preservation, external/load conflicts, invalid input, lease
  contention, recovery and close ordering, plus the seven existing isolation tests.

All 26 focused tests and all 234 tests passed. Windows Debug compiled in 12.2
seconds. Analysis reported 99 diagnostics: the original two warnings, no errors,
and one new informational unnecessary_underscores lint. Exact commands and
results: [STAGE2_SETTINGS_VALIDATION.md](STAGE2_SETTINGS_VALIDATION.md) and
[STAGE2_SETTINGS_RESULTS.md](STAGE2_SETTINGS_RESULTS.md). The tested 75-file
source/executable checkpoint is retained at
`.validation/future-notes-validation-stage2-settings-1fe9aa2f6b584b5784945c83bf7d68db`.
The previous 73-file worker checkpoint remains available.

This changes only the injected validation service path. Existing singleton
settings error swallowing/publication issues remain pending until integration
and runtime gates permit activation. File-service adoption, startup ownership,
settings-dialog error handling and transactional library switching remain pending.
Temporary source cleanup failures need a later fault/runtime gate. No real notes,
app launch, dependency change or encryption change is included. No finding closes.

## Ninth Stage 2 candidate — injected note-service adoption, source/test/build gate passed

- Add captured storage revisions and worker capabilities to NoteReference;
  preserve both when attaching a persistent model ID or advancing a revision.
- Allow FileService to receive the same injected worker as settings. Reject
  production injection before directory resolution. Prepare each captured
  library once, including recovery, before discovery or resolving its objects.
  A failed acquisition can be explicitly retried; retain earlier owned roots
  until close so in-flight references do not follow mutable settings.
- Compare revisions before and after body reads. Require the captured revision
  and live capability before committing; no read-after-edit rebase accepts an
  external writer's changes. Return the verified acknowledged reference from
  writeResolved; adapt the existing in-memory harness and editor save path.
- Rebase queued editor snapshots only onto their own acknowledged save of the
  same session/model/root/object and worker capability. Capture body/title before
  asynchronous preparation; preserve typing/controller ownership during commits.
  Propagate typed conflict/recovery results while retaining a failed draft.
- Stage operation-owned sources in the unchanged envelope format. Flush sources,
  submit file descriptors and retire only those local temporary sources. Recovery
  copies remain retained; failed local cleanup stays owned for retry on close.
  Plaintext legacy envelopes retain their existing protection, including in
  retained recovery/staged objects; protected bodies are not decrypted for storage.
- Reject unintegrated direct attachment, import and Delete mutators in injected
  mode before I/O. The app cannot select this experimental path. Use recursive
  injected-library watchers with recovery/staging events filtered and omit
  internal storage files from its discovery list. Full watcher rebinding remains
  a later lifecycle gate.
- Prepare 18 real-worker/file/editor regressions: exact folder/legacy paths,
  first/manual/autosave revision adoption, stale and foreign references,
  same-size external changes, load races, captured-root writes, startup recovery,
  ambiguous journals, lease contention/retry, shutdown, queued Save, typing during
  commit, metadata preservation, dirty conflicts and zero-write locked/failed-load
  behavior. Correct the prior informational underscore lint in settings.

The first approved focused command returned exit 1: 80 passed and six failed.
Windows-native relative separators were passed into the strict slash-separated
journal target interface. Work stopped. After explicit approval, the adapter
conversion and canonical-target assertion were corrected and the complete gate
reran: all 86 focused and 252 total tests passed, along with formatting, analysis
and Windows Debug compilation (21.7 seconds). Analysis had 99 diagnostics:
97 info, original two warnings, no errors. Exact gate/results:
[STAGE2_NOTES_VALIDATION.md](STAGE2_NOTES_VALIDATION.md) and
[STAGE2_NOTES_RESULTS.md](STAGE2_NOTES_RESULTS.md). The tested 77-file
source/executable checkpoint is retained at
`.validation/future-notes-validation-stage2-notes-741174cdc99a4a32b410cf9562c87734`.
All hashes match their sources. The 75-file settings checkpoint remains available.
No app launch, real-note/settings access, dependency
or encryption-format change is included. No finding is closed.

Singleton/main startup adoption, full mutation ordering, library-switch
transactions, settings/dialog failure UX, save coalescing, serialization/cipher
worker dispatch, bounded attachments/previews/packages, cleanup-failure injection,
actual interruption and continuous-operation/performance validation remain pending.
The existing note body is still materialized during serialization; this candidate
does not claim attachment streaming or measured frame-time improvements.

## First Stage 3 candidate — Save coalescing, source/test/build gate passed

The validated note-service checkpoint above remains retained. The subsequent
Save-coalescing source/test/build gate also passed.

- Replace pending saves for the same session, credentials and captured object
  with the latest synchronously captured snapshot. Leave active encryption and
  commits on their original immutable snapshot. All coalesced callers receive
  the actual latest transaction outcome; no Save succeeds before acknowledgement.
- Preserve explicit Save when automatic requests join it. Continue rejecting
  automatic first Save for never-saved drafts.
- Skip duplicate queued requests already covered by this session's acknowledged
  revision, without rebasing onto an external read.
- Cancel pending stale ownership on new submission, settle pending callers on
  disposal, and keep exit waiting for the complete drain. Preserve controllers
  and edits made after the latest snapshot capture.
- Prepare 12 controlled view-model tests and two native worker/file integration
  tests. They cover burst/duplicate/mixed saves, dirty edits during work,
  truthful failure, disposal/session/credential boundaries, first-Save rules,
  exit waiting, HTML/metadata retention, native acknowledgements and conflicts.
- Remove the note-test unnecessary dart:async import identified in the preceding
  analyzer gate. No dependency, encryption format or application activation change.

Exact gate: [STAGE3_SAVES_VALIDATION.md](STAGE3_SAVES_VALIDATION.md).
All 100 focused tests and all 266 tests passed. Analysis returned 0 with 98
diagnostics: 96 info, original two warnings, no errors and no new diagnostics.
Windows Debug compiled in 21.7 seconds. Observed results:
[STAGE3_SAVES_RESULTS.md](STAGE3_SAVES_RESULTS.md). The tested 78-file
source/executable checkpoint is preserved at
`.validation/future-notes-validation-stage3-saves-387e307170894b23abade3f0e29990c4`.
All hashes match their sources. Neither the current nor preserved executable ran.
Full mutation ordering for attachment/password/Delete, transactional libraries,
application startup adoption and runtime/performance evidence remain pending.

## Tenth Stage 2 candidate — shutdown and source-cleanup failures, source/test/build gate passed

This prerequisite is brought forward before application startup adoption. The
78-file Save-coalescing source/executable checkpoint remains available. The
subsequent shutdown/cleanup source/test/build gate also passed.

- Catch thrown root-release errors in OwnedNotePersistence, keep that root for
  explicit retry, and continue releasing other roots and cleaning local sources.
  Previously, a thrown release left the cached failed close Future permanently
  set and prevented further cleanup/retry.
- Sanitize thrown settings-root release errors into recoveryRequired, retaining
  the root for retry. Typed settings-release failures retain their outcome.
- Prepare four note and four settings regressions. Real synthetic sidecar files
  make nonrecursive operation-directory cleanup fail after source deletion;
  tests then remove only their own obstruction and retry close. They check
  successful acknowledgement/publication, original conflict outcomes, retained
  source ownership, refusal of writes after close, independent leases, retained
  journal paths, typed/thrown release failures and sanitized errors.
- Test teardown clears injected release faults and removes only verified,
  operation-owned synthetic obstructions before draining normal service close.
  No new dependency, recursive production cleanup or runtime activation.

Exact proposed gate:
[STAGE2_CLEANUP_VALIDATION.md](STAGE2_CLEANUP_VALIDATION.md). All 54 focused
and 274 total tests passed. Formatting and Windows Debug compilation passed
(31.2 seconds), and analysis matched the preceding 98 diagnostics exactly:
96 info, original two warnings, no errors. Observed results:
[STAGE2_CLEANUP_RESULTS.md](STAGE2_CLEANUP_RESULTS.md). Unexpected worker death,
power-loss behavior, native handle-close fault injection and actual application
exit remain outside these tests and pending. Full note mutation ordering,
libraries, attachment/protection/package work and performance evidence remain.

The tested shutdown/cleanup checkpoint is retained at
`.validation/future-notes-validation-stage2-cleanup-080a5e6fd65d48158615f428e89c9b34`.
All 78 copied source/test/manifest/rules/runtime hashes match their sources.

## First Stage 7 candidate — discovery readiness, source/test/build retry passed

This discovery prerequisite is brought forward before application persistence
integration. The prior 78-file cleanup source/executable remains preserved.
The discovery candidate has source/test/build validation described below;
no application runtime validation is claimed.

- Subscribe before spawning and await the reader's SendPort handshake, including
  launch and handshake in a ten-second deadline. Cache initialization so repeated
  calls cannot spawn readers/listen twice. Reject scans before readiness instead
  of silently losing the first request.
- Track read-only reader errors/exits, clear readiness, settle startup failure
  and expose sanitized error outcomes. Never forward raw legacy scan messages,
  which may contain paths. A scan failure can be explicitly refreshed while the
  reader is alive; a dead reader cannot accept further scans.
- Bind scanner startup to the configured StorageEnvironment before reads. Owned
  test environments verify explicit disposable paths. This reader owns no
  writer lease, mutations or commits; cancellation stops only this read-only
  isolate. Native browser guards remain a later platform repair.
- Make ContentViewModel await readiness before its first list request. Observe
  and dispose scanner-error subscriptions, and contain watcher/refresh failures.
  Returned lists are immutable. Existing codec and listing batch logic remain.
- Prepare ten native/read-only regressions: first actual synthetic scan,
  initialization reuse, pre-ready rejection, deadline, sanitized launch/scan
  failures, pre/post-handshake exits, disposed requests and invalid deadline.

Exact proposed gate:
[STAGE7_READINESS_VALIDATION.md](STAGE7_READINESS_VALIDATION.md). Approved
formatting/whitespace checks and all 73 focused tests passed, including ten new
readiness regressions. Full tests returned exit 1: 283 passed and one existing
Windows native destination-conflict test failed, receiving ioFailure instead of
conflict. Analyzer and build did not run. The cause is unconfirmed; no correction
or rerun followed the failure. See
[STAGE7_READINESS_RESULTS.md](STAGE7_READINESS_RESULTS.md). The prior cleanup
checkpoint remains preserved. No app launch or real-note access.

An approved isolated native-move reproduction also failed (seven passed, one
failed). A subsequent approved numeric-error diagnostic preserved move flags
and classification, reordered byte-preservation assertions before the outcome
check, and passed all eight focused native-move tests. The earlier failure's
cause remains unconfirmed; no remediation is claimed. The approved integration
retry then passed 81 focused tests, all 284 tests, analysis (97 diagnostics:
95 info, original two warnings, no errors) and Windows Debug compilation
(35.0 seconds). There were no new diagnostic rules/messages; the scanner print
lint was removed. The native failure's cause remains open.

The new tested source/executable checkpoint is retained at
`.validation/future-notes-validation-stage7-readiness-8fd98d0b852a4d62ac70fb61964f2bf0`.
All 79 copied files match their source hashes. The earlier checkpoint remains.
The user requested code-flow/async coordination and lint checks first, then
only required tests/builds. Analysis was moved before the remaining full tests
and build; subsequent changes will follow that order from the start and avoid
optional/redundant reruns. No app was launched or production persistence enabled.

Root/request generations, one-active/latest-pending scans, reduced batch
publication, watcher rebinding, stale search/list suppression and application
runtime/performance validation remain pending. UI startup/continuous behavior,
late-spawn cancellation and native-reader handle cleanup need further evidence.
The owned writer is independent and remains disabled in the singleton app.

## Second Stage 7 batch — discovery/search ownership, source/test/build passed

The user approved continued repairs with flow/async coordination and lint first,
then only required execution checks. The current batch captures root/request
ownership, coalesces scan descriptors to one active and latest pending, rejects
stale replies/terminal events, reduces publication to an initial/final snapshot,
and guards search success/failure by both query and inventory revisions. Older
async path resolution cannot redirect newer discovery. Disposal invalidates
publication. No writer/encryption/dependency activation belongs to this batch.

All 11 scanner/native/read-only and 11 widget regressions passed in the single
306-test integration suite. Existing readiness fixtures use
the tagged protocol. Injection follows existing service/test patterns.
The control-flow joins and limits are reviewed in
[STAGE7_ORDERING_FLOW.md](STAGE7_ORDERING_FLOW.md). The proposed lint-first gate
is [STAGE7_ORDERING_VALIDATION.md](STAGE7_ORDERING_VALIDATION.md): format once,
analyze once, full suite once and required Windows build once, with no duplicate
focused/full reruns. The approved gate passed all commands, with exactly the
prior 97 diagnostics and Windows Debug compilation in 15.7 seconds. Evidence:
[STAGE7_ORDERING_RESULTS.md](STAGE7_ORDERING_RESULTS.md).

The new 81-file source/executable checkpoint is retained at
`.validation/future-notes-validation-stage7-ordering-2d745fdf585041c7bbfdc24e7c65352d`.
All copied hashes match their sources; previous checkpoints remain. The earlier
native-move failure's cause is still unresolved, without a remediation claim.
Runtime/performance and the remaining repair stages are pending.

## Third Stage 7 batch — watcher rebinding and library switching

The candidate prepares root-bound recursive watching with a shallow ancestor
sentinel for creation/recreation. Library switching resolves the draft, acquires
and recovers the candidate root, prepares watching, commits fixed-location
settings, then publishes the new binding. Old events are rejected. Candidate
abort and post-commit cleanup have distinct truthful outcomes and retained retry
ownership. Existing notes are not moved or deleted.

The default app has not enabled owned persistence. Its folder action now
refuses unsafe switching rather than invoking the old direct settings writer.
The complete coordinator remains restricted to injected disposable Windows
storage. A late programmatic edit during commit keeps the previous draft and
its captured reference/lease, with a typed published-library conflict.

Source/async join review: [STAGE7_LIBRARIES_FLOW.md](STAGE7_LIBRARIES_FLOW.md).
Approved lint-first gate: [STAGE7_LIBRARIES_VALIDATION.md](STAGE7_LIBRARIES_VALIDATION.md).
The final gate passed formatting, whitespace, exactly the prior 97 diagnostics
(95 info, original two warnings, no errors), all 337 tests and Windows Debug build
(12.5 seconds reported). All 31 additions passed: eight controlled watcher,
nineteen widget coordinator and four native synthetic-storage regressions.

Earlier interface/brace and fake-async harness failures stopped affected work;
each correction/resumption was explicitly approved. Their evidence remains in
[STAGE7_LIBRARIES_DIAGNOSTIC.md](STAGE7_LIBRARIES_DIAGNOSTIC.md) and
[STAGE7_LIBRARIES_RESULTS.md](STAGE7_LIBRARIES_RESULTS.md). The final harness
keeps operation creation/race/debounce timing in fake async, permits root-zone
cancellation continuations through bounded joins, and acknowledges resource close
inside the active test body before registered teardown. No acceptance assertion
was removed to obtain a pass.

Final checkpoint:
`.validation/future-notes-validation-stage7-libraries-acd44f557c3f4b049b6d0039176baf38`.
All 67 allowlisted source and 17 runtime files have matching copied SHA-256 hashes.
The preceding 81-file checkpoint remains intact. No app launch/stop, real-note
access, dependency or encryption change. Continuous native runtime, performance,
other platform checks, common mutation ordering and real-library activation remain
pending. The earlier intermittent native-move failure remains unexplained;
this gate passed that regression without changing native move classification.

## Isolated application runtime integration — prepared, unvalidated

The user requested the pending launch/runtime and real-library activation work.
A separate `validation_main.dart` now composes one owned worker with independent
settings/files, recovers roots before UI discovery, and injects them into the
dashboard. Validation exit resolves the draft, joins watcher and persistence
cleanup and keeps the editor non-writable on a retryable cleanup failure.
Normal application persistence remains unchanged. Nine regressions are prepared.

Flow/limits: [VALIDATION_APP_FLOW.md](VALIDATION_APP_FLOW.md).
One lint-first suite/build/isolated-launch gate is prepared in
[VALIDATION_APP_GATE.md](VALIDATION_APP_GATE.md), awaiting exact-command approval.
The approved gate passed formatting/whitespace, the exact prior 97-diagnostic
analysis baseline, all 346 tests and one Windows Debug build (24.2 seconds).
One isolated app window was visibly opened. Runtime workflow validation stopped
because synthetic title typing did not change the observed value after a bounded
refocus/retry; application versus automation cause is unconfirmed. No Save or
real-note access occurred. The isolated app remains running, and no second
instance or duplicate suite/build was launched. Evidence:
[VALIDATION_APP_RESULTS.md](VALIDATION_APP_RESULTS.md).

The previous 84-file validated checkpoint remains preserved. This candidate is
source/test/build validated, with runtime blocked, and is not promoted over that
checkpoint. Production activation requires the unfinished mutation integrations
and a verified compatibility/recovery rehearsal; runtime/performance completion
is not claimed.

The subsequently approved single-key probe succeeded, allowing the original
isolated runtime checks to resume without code changes or repeated SDK checks.
Synthetic first Save, body/title autosave, reopen, Windows close cancellation
and switching to a second disposable library were observed. The next log check
revealed Flutter `HardwareKeyboard` physical/logical key assertions and empty
JSON-message diagnostics. Runtime work stopped; their origin is unconfirmed.
The same app remains running with original notes untouched. Roughly nine minutes
of resumed interaction occurred, not a completed 30-minute acceptance run.
Updated evidence: [VALIDATION_APP_RESULTS.md](VALIDATION_APP_RESULTS.md).

## Slow shutdown repair — implemented, pending validation

The user reported the prolonged “Finishing storage operations…” screen.
The latest old-binary close eventually completed normally. Its delayed native
stage was not instrumented. The unchanged binary was recovered into one visible
isolated window; no force termination or original-note access occurred.

The candidate quiesces read-only discovery/search before cleanup, retains a
single owned cleanup attempt across ten-second exit-response timeouts, reports
phases and resumes cancelable exit only after acknowledgement. Seven regressions
are prepared. The exact latency fix and Flutter window behavior remain unproven.
Flow: [SHUTDOWN_FIX_FLOW.md](SHUTDOWN_FIX_FLOW.md). The single lint-first suite/
build/runtime gate was approved: [SHUTDOWN_FIX_GATE.md](SHUTDOWN_FIX_GATE.md).
The prior 84-file source/executable checkpoint remains preserved, plus a hash-
verified copy of the unchanged 346-test runtime binary/kernel. No new SDK checks
or candidate application launch had run at preparation time. The approved
formatter and whitespace checks have now passed. Analysis stopped with one
undefined test getter (`saved.ownerRoot`); the suite and runtime remain unrun.
See [SHUTDOWN_FIX_RESULTS.md](SHUTDOWN_FIX_RESULTS.md). Correction and gate
resumption await confirmation; no production change or further validation has
followed the failure at that point. The user subsequently approved the test-only
correction and resumption. Analysis now passes with the original two warnings
and two additional informational brace lints exposed by test formatting; all
353 tests pass. Candidate runtime remains pending because the old isolated app
has not completed its normal close. The same process/session remains owned;
no force termination or second instance has occurred. Updated evidence:
[SHUTDOWN_FIX_RESULTS.md](SHUTDOWN_FIX_RESULTS.md).

The approved candidate subsequently built and visibly started. Runtime exit
FAILED: watchers and storage acknowledged completion in 53 ms, but the Windows
window remained open past ten seconds at “Storage closed.” The remaining
exit-response/window-destruction path needs diagnosis. Candidate shutdown is
partially working, not validated as complete. Runtime stopped; no reopen or
candidate force termination followed the failure. See the same results record.

Subsequently the session ended and zero project processes were observed before
the exit-trace work began. The user stopped agent testing, then confirmed that
typing and closing work perfectly in the normal run. Manual functionality is
accepted on that report; the automated-run discrepancy remains unexplained.
No diagnostic source patch or speculative native exit fix was applied. The
user's sandbox hypothesis is recorded as unconfirmed. Automated validation is
stopped at the user's request; broader runtime/performance and real-library
activation remain pending. See SHUTDOWN_FIX_RESULTS.md for the evidence boundary.
# Current activation preparation — 2026-10-13

On `integration/recoverable-storage`, the user requested verified backups,
recovery rehearsal on a copy and explicit activation for existing notes, with
manual app testing. Native discovery and the user's normal close are verified;
zero project processes were observed afterward. No original-note payload was
read or written in preparation. Two note objects were discovered; settings and
recovery directories were absent.

The manual two-click close report is open. A candidate keeps the original exit
request waiting through slow cleanup instead of cancelling and issuing another
request. Three close-wait regressions and Debug handoff labels are prepared.
This is not a confirmed fix for the historical fast-cleanup/window-retention
failure. No agent-driven application interaction is proposed.

Backup scripts and an opt-in copied-note recovery rehearsal are prepared.
Formatting, script parsing, whitespace and static analysis passed (101 existing
diagnostics: 99 info, two warnings, no errors). Backup execution, tests,
rehearsal, Windows build/launch and manual close acceptance remain pending.
Real-note activation remains off until the exact execution gate is approved
and its preceding checks pass. See [STORAGE_ACTIVATION_GATE.md](STORAGE_ACTIVATION_GATE.md).

## Activation evidence after approval

The retained backup verified three library files and 17 prior-executable files.
Both notes passed compatible worker commits and four interruption/recovery
checks on the separate disposable copy. The initial required suite stopped at
317 passed/eight failed. After user-approved native error-capture and independent
lease-probe corrections, the single affected suite passed all 130 tests; static
analysis retained the 101-diagnostic baseline. Original failure evidence is
preserved in [STORAGE_ACTIVATION_RESULTS.md](STORAGE_ACTIVATION_RESULTS.md).

Original/backup inventories still matched immediately before the approved
single build/launch. Windows Debug compilation passed (37.3 seconds). Exactly
one owned process/window was observed, with clean startup logs and the original
library writer-lock object present. The admitted executable enables the new
backend; unconfigured builds retain the old writer. No agent-driven edits or
destructive tests on original notes occurred. Backup and previous executable
remain retained.

Existing-note visibility, editing/Save/reopen and one-click Close await the user's
manual confirmation. No runtime performance or continuous-use claim is made.
Extended workflow guards and the separate R01 migration limit remain in place.
## Closing-screen removal candidate

After the manual close failure and read-only lifetime analysis, the user asked
to fix closing and remove the screen. DashboardScreen now retains its mounted
editor/listeners while blocking input during cleanup, with no replacement
shutdown screen. Six real-binding widget regressions are prepared but unrun.
The user approved a launch-only check: Windows Debug compiled in 31.2 seconds,
and the user confirmed one-click closing without the shutdown screen. Captured
logs show cleanup in 51 ms followed by WM_DESTROY. The run used a disposable
empty library; original notes were not enabled. Formatting, lint and automated
tests remain pending. Existing backups and the prior executable remain retained;
no storage or encryption format changed.

The same manual run exposed unclear blank-draft UX and absent visible dates.
The disposable library contained no saved note. A follow-up code candidate shows
“Not saved” until first Save, renders retained note dates after Save and in the
sidebar, labels filesystem modification separately, and makes New Note await its
draft transition before focusing the editor and explaining the explicit first
Save. Eight dashboard/exit tests and two sidebar-date tests are prepared but
unrun. These follow-up changes have not been compiled or launched.
