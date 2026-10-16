# Attachment viewing checks: default off

## Requested behavior and code flow

The note envelope already contains attachment ID, display filename, declared
size and MIME type. It does not contain a trusted payload digest. The shared
NoteCodec validates attachment declarations at load; unlocking now explicitly
uses the same metadata-only validation before admitting the decrypted body.
Unlock does not scan multi-GiB payloads or prevent reading a note merely because
an attachment is unavailable.

App settings > Attachment performance > Advanced configuration adds two
persisted switches, both false for absent/legacy settings:

- Check encrypted file before opening: capture a complete source hash before
  decryption, then compare that capture during the decrypt stream.
- Verify decrypted output: read back the prepared plaintext and compare its
  digest with the digest computed during decryption.

With both off, the owned source admission checks path containment, links,
ownership and regular-file metadata without reading the payload. One worker
then streams decryption in existing 1 MiB windows. Required ciphertext framing,
padding, source revision/change checks, the 10 GiB limit and known nonzero
declared plaintext length remain enforced. Plaintext is hashed within that
same decrypt stream; there is no additional payload pass. Legacy size=0 may
mean unknown and is not retroactively interpreted as an exact empty-file size.

The settings only affect viewing. Writes, password changes, imports/exports
and recoverable journal commits retain their existing verification defaults.
The cipher refuses a readback opt-out for writes or rekeying. Encryption formats
and notes are unchanged. These optional scans offer extra readback/source-change
assurance; neither setting authenticates the existing legacy encryption format.

Completed cache entries are reused without another decryption. Enabling a check
after an unchecked cache entry exists forces preparation with the new policy.
Cancellation/invalidation waits for the owned worker to close handles and removes
partial plaintext before settling. Settings publish only after their existing
recoverable writer acknowledges them.

## Design and validation

Stitch screen `0b616520f4f44469a97f6fbfc59226cb` refines the existing settings
layout with the two switches; generated HTML/PNG are retained. The requested Pro
model was unavailable; the available GEMINI_3_8_FLASH model was used, as disclosed.
No unrelated visual redesign was implemented.

Formatting and whitespace checks passed. The first non-escalated formatter was
blocked by Dart's user analytics directory permissions; it then passed with the
required access. Flutter analysis completed in 15 seconds with 108 informational
diagnostics, zero warnings and zero errors. Existing informational diagnostics
remain; analysis is not a clean-lint claim.

The combined affected test command initially finished with 115 passes and two
failures: one newly written cancellation probe relied on throttled progress,
and one listed test path did not exist. The probe was changed to deterministic
between-window cancellation; its single rerun passed. The correct cache/tray
lifecycle files passed six tests. Total distinct passing tests: 122. The enhanced
metadata/unlock regression was then rerun alone and passed, directly exercising
the real owned-storage metadata-only source path.

Coverage includes all four switch combinations, exact decrypted fixture bytes
(empty, block boundaries, multi-window, app-key and protected files), wrong keys,
declared-length mismatch, framing rejection, cancellation cleanup, cache reuse,
stricter-policy re-preparation, settings persistence/failure, metadata admission,
unlock without payload reads, mutation publication and cache/Exit lifecycle.

Evidence: `.validation/attachment-open-options-*`. Earlier HTML/drop, adaptive
scheduling and resume-progress gates are recorded in their separate reports;
they were not repeated for this viewing-only change. Real notes, published
portable folders, existing tags and previous executable checkpoints are retained.

## Delivery status

The accepted bundle was copied to
`.validation/attachment-open-options-previous-release`, with matching EXE/AOT
hashes, before compilation. One protected canonical Windows Release build passed
in 185.9 seconds. Private symbol/map validation and the runner's ASLR,
high-entropy ASLR, DEP, CFG, stack cookie and restricted DLL-loading checks passed.
The existing CMake FetchContent deprecation was the only build warning.

The candidate launched once as PID 80616. Its window was visible and responsive
after input-idle startup. Initial working set was 151.4 MiB; protection and media
registration logs were clean. A separate observation file records continuous
startup/resource samples: all seven samples across 30 seconds were responsive,
working set remained 151.3-151.4 MiB, and process CPU increased by 0.25 seconds.
No automated input, forced shutdown, note mutation or
release/tag publication was performed. Manual acceptance of the two new viewing
switches was requested and remains pending. Test/startup results do not establish
physical disk throughput or suspend/wake performance.
