# Fast processing defaults and Git compatibility review

Status: integration, focused automated gates and protected delivery completed for Windows/Android. Normal protected Preview installed and running on the LG; user reported the requested demo attachment/export check done. Other-platform runtime limits remain explicit below.

## Comparison boundary

Base: development `74300ece819758cffad7d830d9dcd2bc577273b7`.
The worktree already contained accepted, uncommitted mobile export UI changes before this task. Those changes and unrelated files have been preserved.

`.validation/fast-processing-git-compatibility.json` records normalized source hashes and comparisons with Git HEAD and v1.4.1. Note models, note codec, legacy package service and pinned dependencies are unchanged from both. Journal record definitions are unchanged from HEAD. The provider journal adapter was introduced before this task and is not present in v1.4.1.

No note-format, package-version, key derivation, IV layout, SIC mode, padding, mention identity or journal-format migration is introduced. Desktop presentation changes in this task are limited to the requested settings controls and descriptions. Existing uncommitted Android drop/export presentation changes are not attributed to this task.

## Implemented behavior

- Source checking, plaintext read-back, exported-backup validation and extra large-write verification are independent, off by default, with missing legacy fields and Reset defaults also off. Explicit saved choices survive. Desktop no longer forces export checks on.
- Jobs capture a settings snapshot. Attachment addition and protection changes use owned candidates; rekeying streams decrypted bytes into encryption without plaintext staging.
- Sealed receipts carry streamed SHA-256, lengths and final metadata. A receipt requires an exclusively acquired new-output lease. Picked inputs cannot be adopted as owned outputs. Stale receipts are rejected.
- Windows owned candidates move into the existing journal publication path without another payload copy or checksum scan. Existing checked internal APIs remain checked.
- Android provider output leases bind a new pending document to its open descriptor. Native cipher writes directly to this candidate; the provider transaction adopts it using the existing attachment-first journal. Dart fallback honors the same policy. Apple coordinated transfers retain the one encrypted-copy fallback; direct Apple output leases are not advertised.
- Fallback provider copying hashes during the necessary transfer, checks the closed length and requires a current owned source receipt before unchecked publication. Extra read-back remains opt-in. Ambiguous interrupted recovery remains checked.
- Default binary/password-protected package export streams framing and encryption into its owned output. ZIP export calculates CRC while packing and writes compatible data descriptors. Explicit extra-write verification retains the checked export path.
- Import performs strict DEFLATE grammar validation, CRC, size checks, extraction and output hashing in one extraction pass. Fingerprints reuse current owned receipts; genuine comparisons with existing data can still read existing payloads.
- Basic path/bounds, exclusive-create, capacity, short-write, source-change, padding, flush/close and destination-conflict checks remain. Journals, retained predecessors, cancellation, foreground ownership and cache teardown remain operational requirements.
- Diagnostics contain numeric operation timing/read/write/read-back counters without filenames, paths, content or credentials. Checked export accounting includes intermediate payload passes.

Skipping read-back reduces immediate detection of storage corruption acknowledged as a successful write. Such faults may be detected only on a later read. Existing SIC/PKCS7 compatibility does not provide authenticated encryption.

## Automated evidence

- `.validation/fast-processing-combined-final-tests.txt`: 312 passed. Covers existing crypto and package compatibility, malformed archives, opt-in/default policies, settings persistence/reset, recovery faults, provider guards, source cancellation, imports/replacement, cache lifetime, mentions, mobile editing and export UI.
- The combined run includes a host sleep gap; its total elapsed time is not a latency measurement.
- `.validation/fast-processing-accounting-tests-2.txt`: 22 passed after the final diagnostic-only counter correction.
- Final comparison found that native framed-stream encryption bypassed CPU pacing. This was corrected before installation: measured native CPU work is paced against current capacity/thermal feedback, with bounded cancellation and capacity refresh. `.validation/fast-processing-paced-regressions.txt`: 108 passed after the correction; `.validation/fast-processing-paced-analysis.txt`: no errors or warnings.
- `.validation/fast-processing-sink-matrix-2.txt`: 45 passed. Adopted provider sources throw if recopied; injected boundary reachability is asserted.
- `.validation/fast-processing-recovery-tests-2.txt`: 66 passed, including owned Windows publication with real predecessors at fault boundaries.
- `.validation/fast-processing-isolated-bounded-tests.txt`: 15 passed, unchanged cache/mention/batch functional assertions with a two-minute bound. Earlier concurrent runs hit 30-second test timeouts. The isolated Save status case passed without a save-code change.
- `.validation/fast-processing-complete-analysis.txt`: no errors or warnings; informational lints remain. Narrow follow-up analysis covers final diagnostic changes.
- `.validation/fast-processing-kotlin-compile.txt`: Android native Kotlin compile succeeded. Toolchain/plugin deprecation warnings remain; dependencies were not upgraded.
- Formatting and Git whitespace checks passed for the changed scope.

## Preservation and remaining delivery gates

Accepted APK and Windows runtime are checkpointed under `.validation/fast-processing-accepted`.
Accepted APK SHA-256: `92573512e48013b75a7867948c72cde4ad17174841cc98fcf2892a66560436f9`.
Accepted Windows runner SHA-256: `25a5f4e723c1ce4250196eb148df7f286216b8b497728194c1033f499fdf56ec`.

The first two protected device runs exposed scoped-storage descriptor reopening failures (write, then read). The accepted Preview was restored after each. Granted handles are now duplicated and source reads use independent positional cursors. The third run proved native direct decryption but exposed Dart path reopening and an overly broad cleanup context. The accepted Preview was restored. A bounded read-only reader now borrows the registered grant, uses pread64 with independent cursors on Android, and retains normal filesystem access elsewhere. Native source ownership is checked before/after use; the parent owns the descriptor lifetime, and temporary buffers have explicit/finalizer cleanup. Background workers initialize platform messaging independently of native crypto availability. The successful device revalidation is recorded below.

New device fixtures use a fresh scoped child library, avoiding the active library's journal namespace. The probe includes Dart fallback, actual SAF archive/strict-DEFLATE imports, simultaneous source reads and metadata larger than a cipher window. Source-reader regressions: 129 passed; focused gate: 66 passed; final reader/archive gate: 21 passed.

Windows isolated 64 MiB transform measurement after untimed JIT warm-up (two samples per mode, alternating order): fast median 5,808 ms, checked median 9,052.5 ms; the fast mode reads zero output bytes versus 67,108,896 read-back bytes when checked. Peak process RSS was about 161 MB versus 159 MB. This excludes UI/publication and is not a protected-release startup or whole-job timing. The cold run is retained separately.

The protected Android diagnostic build, normal Android build and protected Windows build succeeded after the correction. Windows runner hardening passed ASLR, high-entropy ASLR, DEP, CFG, stack-cookie and dependent-load checks. The final Windows candidate launched and its visible notes list/editor was inspected without editing notes. An earlier automatic approval review rejected closing the preceding candidate because it reported "Not saved"; the user then closed it before the final rebuild.

On-device output `output-1792300890552251` demonstrated native direct encryption/decryption, the granted-source Dart fallback, large metadata processing and independent simultaneous native reads. Numeric native observations included a 2 MiB encryption in 83 ms and decryption in 113 ms with zero read-back bytes. These are individual transformations, not whole-job benchmarks. The full probe then failed at `direct-synthetic-cleanup-recoveryRequired`: "Recover pending transactions before deleting." This is a failed recovery gate, not a successful compatibility run. Its isolated synthetic scope and recoverable transaction objects were retained. Earlier synthetic fixtures were also retained rather than deleting objects by guessed identity.

The preserved accepted APK was restored before further diagnosis. On continuation, the retained synthetic deletion journal showed that deletion read the newly created guard with its original zero-byte metadata. `ProviderDeletionStore.metadata` now returns refreshed metadata after the already verified small write; no payload reread or guard bypass was added. A focused provider-generation deletion regression passed; scoped analysis found no errors/warnings (existing informational lints remain).

Corrected device output `output-1792301249120912` passed direct provider writes with checks off/on, cleanup, Dart granted-source fallback, strict SAF archive import with native enabled/disabled, large metadata, simultaneous source cursors, cache reuse/lock invalidation, 18 cipher vectors, six failure checks, worker isolation/rekey and unexpected-worker cleanup. Eight package combinations in each direction passed. The immutable desktop v1.4.1 reader accepted the pulled Android packages and note, preserving IDs, mention metadata, body whitespace and payload hashes. The broad host suites were not repeated.

LG Android 12 synthetic 700 MiB transforms: fast native encryption 6,450 ms; checked encryption 9,159 ms; decryption 5,227 ms. Fast encryption read 734,003,200 source bytes and zero output read-back bytes. These are one-run transformation measurements at the configured 70% duty, not a whole-job guarantee or a statistically controlled thermal benchmark.

The normal protected Preview APK before the final predecessor-policy correction was 132,081,833 bytes; SHA-256 `72697a39308e5c0dc5c4d6d868ee46455437ec0887d061e904717960eb71b24d`. Its replacement is recorded below. Packaging contains 18 native libraries, all 64-bit ELF load segments align to 16 KiB, and `zipalign -c -P 16 4` passed. Dart symbols remain private. Synthetic diagnostic entry points are not the delivered app.

Manual acceptance remains separate from automated tests. iOS/macOS build/device validation requires a Mac and remains pending; Linux/browser runtime parity is not established by Windows tests. No full sustained thermal, lifecycle or manual workflow acceptance is inferred from these focused checks.

No commit, push, tag, release publication or portable-folder replacement is included. Existing notes, tags and D:\tools are preserved.

Rollback startup observation: stable process for 20 seconds, no fatal/layout log matches, approximately 51 MiB total PSS. The phone was on its lock screen, so resumed/visible-editor acceptance is pending. The temporary host keep-awake request was released.

Final normal Preview installation used `adb install --no-streaming -r` successfully, followed by explicit activity launch. The normal app remained at PID 4448 for the 20-second startup observation, was resumed with keyguard absent, and had zero fatal/layout error matches; total PSS was 153,435 KiB. Windows PID 62272 was responsive with a visible normal editor; a later sample showed 186,945,536 bytes working set. These are point observations, not peak-memory or sustained-load guarantees. Accepted APK/Windows runner hashes were rechecked and still match their preserved checkpoints. The user was asked to check a demo attachment open and export with checks off; that manual result is pending.

Read-only phone capture confirmed the normal notes list and an existing "Recover unsaved draft?" prompt. No Recover/Discard choice was sent, and no existing draft was changed. The user was informed to handle that prompt before manual acceptance.

Final policy audit found that provider predecessor copies still used the checked write default. The exclusively created journal copy now uses the mutation's captured `verifyReadback` setting and compares its checksum during the necessary transfer against the captured predecessor hash. Revision rechecks and checked ambiguous recovery remain. Two focused off/on tests passed, asserting zero predecessor read-back bytes when off and positive read-back when enabled. Scoped analysis found no errors or warnings; the normal protected Android candidate rebuilt successfully in 58 seconds for this mobile-provider correction. The prior normal APK was checkpointed before replacement. No broad test suite or native benchmark was repeated for this two-line policy change.

Final Android APK SHA-256: `d5e0d59020e71be673bbec39771a1a02d2d2a252b57b5a035b728a8bd5a27d6f`, 132,081,833 bytes. The replacement passed the 18-library ELF inspection and `zipalign -c -P 16 4` again.

## Completion audit

| Requirement | Evidence and limit |
| --- | --- |
| Shared off defaults, old settings, Reset, saved opt-in | Shared policy source and settings regressions in the 312-test combined run; matching desktop/mobile controls. |
| Owned candidates, identity revocation, no picked-file adoption | Owned-write and provider sink tests; direct SAF device checks and source ownership failures. |
| One transform pass / one necessary fallback transfer | Worker byte counters, owned-sink no-copy tests and the 700 MiB device fast-path read/read-back counts. Provider predecessor-copy policy has its own off/on regression. |
| Attach, rekey, open/cache, plaintext export | Combined storage tests; actual native/Dart provider, rekey and cache/lock device checks. |
| Binary/password and ZIP export/import compatibility | Eight real device package combinations each way and immutable desktop 1.4.1 import; strict DEFLATE/CRC/bounds regressions. |
| Basic safety, journals, predecessors and recovery | 66 focused recovery tests, provider boundary matrix, cancellation/source-change failures and corrected real-device deletion cleanup. |
| Progress and private diagnostics | Existing affected UI tests and numeric payload diagnostics; user replied "done" to the requested demo attachment/export progress and completion check. |
| Git compatibility and design preservation | Recorded HEAD/v1.4.1 hashes; unchanged note codec/models/legacy package formats and dependencies; desktop settings-only presentation scope. |
| Protected artifacts | Windows hardening result, private Dart symbol assertions, Android ELF/ZIP alignment inspection. Current Android delivery must match the final packaging hash. |
| Runtime and acceptance | Visible Windows startup and normal Android startup/log/resource observations passed. User reported the requested demo attachment/export check done; this does not imply acceptance of every workflow on every platform. |
| Other platforms | Shared source/adapters only; no iOS/macOS build/device claim, no Linux/browser runtime claim. iOS device validation remains held per user direction. |
| Preservation / publication limits | Accepted artifact hashes unchanged; no uninstall/clear-data, no portable replacement, no commit/push/tag. Retained ambiguous synthetic recovery fixtures are identified separately. |

Final corrected normal Preview installation succeeded without clearing data. After launch, PID 5345 remained stable during the 20-second observation, resumed with keyguard absent and zero fatal/layout log matches. Total PSS was 190,720 KiB (point observation). The user answered "done" to: "check one demo attachment open and one export with optional checks off. Do they show the transformation progress and finish normally?" This records acceptance of those requested checks only. The earlier pending manual-acceptance entries describe prior observations, not an outstanding request.
