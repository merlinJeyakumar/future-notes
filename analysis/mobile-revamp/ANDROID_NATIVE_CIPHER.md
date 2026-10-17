# Android native cipher and device performance

17 October 2026. Implemented for Android preview; iOS validation remains held.

## Result

The observed old mobile open advanced at about 0.8 MiB/s on a 708 MiB attachment.
Android now uses the system crypto provider for bulk AES and SHA-256, while the
existing Dart coordinator retains note ownership, publication, recovery and cache
lifetime. Final synthetic LG LM-G900 / Android 12 / arm64 measurements with native
thermal/memory policy enabled:

| Operation | Payload | Elapsed |
| --- | --- | --- |
| Native encryption plus required decrypted readback verification | 700 MiB | 24,355 ms |
| Native decryption, normal viewing checks off | 700 MiB | 13,297 ms |
| Reference Dart encryption plus readback, 70% worker duty | 4 MiB | 5,110 ms |

These are synthetic runs with different payload sizes and warm storage caches,
not a guaranteed speedup for every file/device/provider. Earlier native runs
before backend thermal-policy enforcement were faster; the final numbers above
include that enforcement and are the delivery reference.

## Compatibility and ownership

- Existing AES-SIC/CTR counter behavior, PKCS7 padding, 16-byte IV prefix,
  password UTF-8 truncation/zero padding and default key remain unchanged.
  String IV/base64 layouts, legacy string fallback and the app-envelope IV are
  preserved. Format and legacy security properties are unchanged.
- AndroidCipher uses the Android system provider through javax.crypto.Cipher;
  no external crypto dependency, new native .so, Keystore key format, new
  algorithm or note migration was added.
- Native file transforms stream 1 MiB windows on a bounded executor. File
  payloads do not cross the UI channel. Polls carry stage/bytes/control only.
  Buffered metadata and package-reader cipher sessions use a separate bounded
  executor. Small synchronous session initialization acquires only cipher state.
- Dart workers initialize Flutter's background messenger using the root token.
  Each file worker/package operation has an opaque native owner group. On normal
  completion or unexpected Dart-worker exit, the root coordinator joins that
  owner's native handles before completing cancellation/cleanup. Queued native
  work can be cancelled before acquiring a handle. A transport failure cannot
  be treated as an acknowledged owner release.
- Native input is read-only; sources/destinations must resolve inside app-private
  staging locations. Output is exclusively created with O_EXCL/O_NOFOLLOW and
  never overwrites an existing object. Required source/length/padding/hash checks,
  source revision recheck, flush and write/rekey readback remain. Failed owned
  outputs are removed. Journals/generation commits and SAF publication remain
  in the existing services.
- Buffered operations above the native IPC bound retain the existing Dart path.
  If the native capability probe fails, the established Dart implementation is
  selected. Synchronous metadata-discovery helpers continue to use their existing
  Dart implementation. Windows/iOS keep the Dart backend.
- Existing notes are not rewritten on opening. Note IDs, mention IDs, timestamps,
  body whitespace and unknown metadata remain controlled by the shared codecs.
  The decrypted-file cache and its lock/exit invalidation were not changed.

## Device performance settings

The mobile App settings performance section now shows logical CPU count, detected
working-memory allowance, thermal status, native-backend status and active/queued
work. A refresh action samples capacity without creating a job or reading payloads.

| Preset | Target | Maximum files | Memory cap |
| --- | --- | --- | --- |
| Adaptive | 70% | Automatic | Automatic |
| Battery friendly | 40% | 1 | 64 MiB |
| Higher throughput | 85% | 2 | 128 MiB |

Existing persisted target/concurrency/memory fields are reused; no note or settings
schema migration. Presets preserve optional viewing-check choices. Advanced limits
remain available and setting changes publish only after the existing persistence
acknowledgement. Failed writes retain the previous value.

Native backend configuration follows these acknowledged settings, including package
transforms outside the per-file worker. It applies the lower of the root worker's
duty and its own configured device-safe duty, avoiding double multiplication of
thermal factors. It detects system/managed headroom and limits work to the app
allowance. Critical pressure pauses preparation; a bounded 15-second callback
cooldown leads to reassessment. UI_HIDDEN alone does not imply pressure.

Native streaming jobs use a 16 MiB scheduling estimate; other backends retain
64 MiB. Actual data windows remain 1 MiB. Android automatic concurrency is
conservative; explicit limits up to four files are available, still bounded by
memory/thermal admission. The 70% target is scheduling guidance, not an OS cap or
an allocation goal. Protections cannot be disabled through these controls.

The Stitch reference used Flash because Pro was unavailable. Incorrect generated
crypto/version labels were corrected in a follow-up design; they were never
implemented. Corrected screen cf4f4cba731947079088b6879f94c51a and local reference
assets are recorded in .stitch/metadata.json. Desktop presentation is unchanged.

## Automated validation

- Formatted changed Dart files and checked whitespace. Final production-scoped
  analysis: zero errors/warnings, five existing informational notices.
- Initial affected suite: 75 passed. Final affected regression suite after owner
  cleanup/device-policy changes: **78 passed**. A separate owner-transport test
  confirms cancellation does not complete before native acknowledgement.
- Mobile settings widget test covers a narrow phone dialog, presets, successful
  acknowledgement and rejected persistence. Its first attempt failed at setup
  because a synthetic path lacked the repository's validation-run prefix; the
  fixture was corrected and the test passed. No app behavior was changed for it.
- Android synthetic validation covered eighteen default/empty/Unicode-password
  and boundary-size vectors, zero-length data, encryption/decryption, production
  worker/isolate messaging, rekey, overwrite rejection, cancellation, invalid
  padding, declared-length failure, hash failure, source revision race, and native
  cleanup after an unexpected Dart-worker exit. All final checks passed.
- **Desktop to Android:** eight binary/ZIP package combinations, protected and
  unprotected notes, optional archive passwords, stable note/mention identities,
  timestamps, whitespace and unknown fields. Native import and attachment
  decryption matched the desktop fixtures.
- **Android to desktop:** all eight final Android exports plus an encrypted note
  passed current/legacy readers on Windows. An additional test materialized the
  actual immutable v1.4.1 cipher/package sources from commit
  7a85c4812313982b64323be1b365b76cc4f7e650; those readers accepted the Android
  exports and original payload hashes. This is codec-level validation, not a
  manual import in the published Windows UI.
- The v1.4.1 package codec remains byte-for-byte unchanged. Eleven desktop
  presentation files and the desktop MyApp class still match v1.4.1.
- The synthetic compatibility target is isolated in tool/android_native_compatibility.dart
  and is not imported by the delivered app. Only its explicit validation builds
  run it; the normal delivery was rebuilt with --target lib/main.dart.

Evidence: .validation/android-native-final-host-suite.txt,
.validation/android-native-clean-analysis.txt,
.validation/android-native-ownership-regression.txt,
.validation/android-native-final-desktop-import.txt,
.validation/android-native-v141-reference-test.txt,
.validation/android-native-compat/native-final-summary.json and final exported
synthetic packages under .validation/android-native-compat/android-output/.

## Protected delivery and runtime

- Normal protected preview build passed in 60.5 seconds; package
  com.nativedevps.futurenotes.preview, version 1.4.1+8, minimum API 24, target 36.
  Dart obfuscation, R8 and resource shrinking retained; symbols private under
  .private-release-symbols/android-native-20261017/.
- APK: build/app/outputs/flutter-apk/app-preview-release.apk, 131,507,717 bytes;
  SHA-256 9911d3efe075c7379111f4d2dd1b1f4b81ab9ceddd6ac4d7249a34e07305afab.
- Eighteen native libraries present; all 64-bit ELF load segments and ZIP 16 KiB
  alignment checks passed. The existing 32-bit PDFium alignment limitation is
  unchanged; no new cross-ABI runtime claim is made.
- install -r succeeded without clear/uninstall. Normal cold launch Status ok,
  TotalTime 1605 ms, WaitTime 1622 ms. PID 6200 stayed stable for twenty seconds,
  Activity resumed and keyguard off, zero inspected fatal/layout errors; PSS
  132,113 KiB. Screenshot confirmed the existing one-note list with retained
  timestamp/ID metadata. No live note was opened or edited by validation.
- Read-only App settings inspection confirmed native cipher status, device card
  and performance section on the phone, then closed the dialog without changing
  settings. Evidence: .validation/android-native-settings-visible.json and
  .validation/android-native-final-startup.json.
- Only the guarded app-private synthetic crypto-validation folder and temporary
  UI dump were removed from the phone after retaining final results locally.
  Notes, interrupted-demo recovery records and selected-library settings were
  not deleted or replaced.
- Accepted prior APK/source preserved in .validation/android-native-before/.
  Rollback can reinstall that APK without converting notes; no automatic rollback
  was performed. Published portable folder D:\tools, Windows executable, branch,
  existing release tags and production signing configuration were untouched.
- No commit, push, release publication or new tag.

## Manual acceptance and remaining limits

The first normal preview failed manual video opening: both attempts failed before
decryption progress (606 ms and 434 ms). The native input guard accepted private
files but rejected the registered /proc/self/fd handles supplied by Android SAF.
The original compatibility harness used private files, so it missed this path.
The failed candidate is preserved in .validation/android-native-failure-before/;
the previously accepted Dart-path APK remains in .validation/android-native-before/.

Correction: acquire a read-only independent input handle on LocalDocuments' serial
executor only when its exact descriptor is registered in the live source map.
Do not canonicalize a provider handle into a filesystem path or admit arbitrary
external files. Output remains exclusively created within app-owned roots; input
bounds, revision checks, padding, hashes, worker joining and cache revocation stay
in place. Content-free CIPHER_FAILED stage/kind diagnostics were added.
The harness now also exercises ProviderNoteFiles -> AttachmentOpenCache -> worker
-> native cipher using a disposable UUID-named provider note, verifies cached
reopening, immediate lock cleanup, checked rekey and rejected released handles,
and removes only its own provider objects in reverse creation order.

Correction validation passed on the LG Android 12 phone. The new 16 MiB SAF/cache
integration exercised first open, cached reopen without another transform,
plaintext removal on lock, checked rekey and released-handle rejection. The
first fixture run failed because its cache directory did not exist; the fixture
was corrected to create a canonical private root before repeating successfully.
The complete device suite then passed eight packages in each direction, eighteen
vectors, six intentional failure checks, worker/owner cleanup and a 700 MiB
transform (24,065 ms encryption with verification; 13,384 ms decryption). The
fresh outputs passed both current and immutable v1.4.1 desktop readers. Fifty-two
focused host cache/cipher/scheduler/ownership tests passed. Scoped analysis had no
errors or warnings (two existing infos in the explicit validation target).
Evidence: .validation/android-provider-host-regression.txt,
.validation/android-provider-desktop-compat.txt,
.validation/android-provider-fix-analysis.txt and
.validation/android-native-compat/native-final-summary.json.

The normal protected replacement (lib/main.dart) was built in 60.5 seconds,
installed with install -r and launched successfully (TotalTime 1651 ms). APK SHA256
087ce8e10cf15fda07469cd463fa8adba2b28a633b6c8bcb94e22272fb34ee86;
131,524,101 bytes. Symbols are retained privately under
.private-release-symbols/android-provider-fix-20261017/. Eighteen native libraries
and 64-bit ELF/ZIP 16 KiB alignment checks passed. PID 8996 remained stable for
20 seconds, foreground/resumed with keyguard off; no inspected fatal/layout
errors, PSS 172,369 KiB. UI hierarchy confirmed visible preview nodes and no
synthetic-harness label; it did not independently establish editor interaction.
Synthetic provider children and private phone validation files were removed.
Evidence: .validation/android-provider-normal-build.txt,
.validation/android-provider-normal-startup.json and
.validation/android-final-packaging.json.

The user subsequently confirmed that the same demo video decrypts/plays and
reopens immediately from cache ("it was working nice"). That manual decryption
and cache acceptance passed. Separate settings interaction acceptance remains
pending.
No validation imported into or
replaced the user's real library. Sustained multi-hour/SD-card sessions, real
low-memory process kills, other Android devices/API levels and iOS build/device
acceptance remain unvalidated. Orientation manual acceptance remains deferred by
the user, independently of this change.
