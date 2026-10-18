# Processing speed work, 18 October 2026

Scope: improve saving, package import/export and encryption/decryption throughput.
Preserve accepted saving progress, designs, encryption formats, optional-check
settings, native resource/thermal limits, cancellation and recovery.

## Implementation

- Do not hash every package source byte when no expected source checksum exists.
  Captured source checksums still require and receive the existing validation.
- Copy unencrypted bounded binary-package records with the owned Android native
  transform rather than moving every payload chunk through Dart. Preserve
  sequential reading for encrypted packages and captured whole-source checksums.
  Records below 4 MiB retain sequential copying: phone measurements showed that
  dispatch/polling overhead could outweigh native-copy savings on small records.
- Calculate existing output SHA-256 and ZIP-entry CRC32 in bounded Android native
  sessions while writing. CRC reset leaves the package SHA state intact. Native
  session ownership, release, cancellation and budget pacing remain enforced.
  Other platforms and older adapters retain the Dart checksum implementation.
- Preserve direct native encryption/decryption/rekey and the already accepted
  native saving transfer. No cipher, padding, key derivation or package format
  changes. No optional verification pass added or enabled.

## Validation

The combined affected host suite passed 144 tests. The subsequent measured
small-file threshold passed the 50 cipher/package tests. Scoped production Dart
analysis passed with no errors/warnings (15 informational style notices;
the explicit diagnostic target has three additional style/print notices).
Expected source-hash rejection remains covered for plain/encrypted readers,
including non-block-aligned reads before copying the remaining record.

Protected Android probe builds passed. The initial collector failed because the
Android Flutter log sink truncated a long diagnostic summary. It restored the
accepted normal app. Short separate summaries fixed collection; no application
processing failure was observed.

The final LG LM-G900 / Android 12 synthetic probe passed SHA-256/CRC vectors,
CRC reset, encryption/decryption/rekey plaintext hashes, all eight binary/ZIP,
plain/password-protected, native/Dart producer/consumer combinations, first
provider import and all three UID conflict outcomes. Existing payload-read
attempts remained zero. Saving stayed monotonic and used native transfers;
temporary provider/private objects were cleaned. Probe-only fixture reads used
to compare known outputs are development checks, not normal-job rescans.

Measurements are single sequential synthetic runs, affected by CPU/thermal/I/O
state, not sustained large-file benchmarks. The exact 16 MiB checksum writer
comparison took 0.469 / 0.186 seconds (Dart/native) before the small-copy threshold
adjustment and 1.823 / 0.321 seconds afterward. Plain binary 2 MiB export took
0.239 / 0.069 seconds in the final run. Small ZIP export did not show a consistent
benefit. Native encryption, decryption and rekey of 2 MiB took approximately
0.218 / 0.218 / 0.226 seconds in that run; those native algorithms were already
present and were preserved, not introduced by this task. The accepted native
saving transfer saved the two-file 16 MiB batch in 1.204 seconds.

Import timing keys identify the exporting backend; the consumer is the opposite
backend. For example `import-binary-plain-dart` means Dart-produced/native-read.
The final small 2 MiB native-reader import took 0.071 seconds vs 0.241 seconds for
the Dart reader; the larger 8 MiB records in provider-import validation exercised
the native direct-copy branch. Full timing/flags:
`.validation/processing-speed-probe.json`.

The final normal `lib/main.dart` protected Preview build passed in 95.6 seconds.
APK SHA-256:
`691b56f56a1bf3510b418c81668067d313d870c3ba8144e988c498c0f763848f`.
All 18 native libraries and 16 KiB APK alignment checks passed. Streaming update
installation succeeded without clearing data. Launch was accepted, and the PID
was stable for 20 seconds with zero fatal/layout log matches and PSS 53,709 KiB.
The initial observation was behind the lock screen. After the user unlocked the
phone, a second 20-second observation confirmed the same stable PID, foreground
resumption, no keyguard, zero fatal/layout matches and PSS 158,792 KiB. Screenshot
inspection confirmed the normal notes list with no discovery error. The
diagnostic entry point is not installed. Large-file manual acceptance is pending.
Evidence: `.validation/processing-speed-startup.json` and
`.validation/processing-speed-packaging.json`, and
`.validation/processing-speed-unlocked-startup.json`.

This task changes no desktop/mobile presentation files. iOS/macOS runtime and
sustained 700 MiB timing remain unvalidated; optional verification remains off
unless the user explicitly saved an enabled setting.

The prior accepted normal APK is preserved under
`.validation/processing-speed-accepted/`, SHA-256
`b930e1f5eadabccb887741a2c26ebdac32ca26a719bc628702bbab8d6c6a9053`.
No notes, portable releases, Git tags, commits or remote branches are modified by
this delivery. iOS/macOS builds and device validation remain deferred.
