# Android preview source validation - 17 October 2026

This development change brings the Android-first work since desktop v1.4.1 into
one source commit. It is not a mobile parity release or production upgrade.
This report supersedes earlier checkpoint statements that all tests were deferred.

## Included scope

- Separate mobile notes/editor/toolbar/mentions/viewer presentation; desktop
  presentation and desktop MyApp still match v1.4.1 exactly.
- Typed local-document access, recoverable provider publication, private draft
  recovery, retained Android runtime and per-job foreground notifications.
- Android native compatible encryption/decryption, bounded ownership and
  cancellation, adaptive memory/thermal limits and device settings.
- Compact attachment rows/gallery, multi-selection, native sharing, safe bulk
  removal, current-file export progress and off-by-default optional mobile scans.
- Android preview package/signing isolation and pinned Office native build tools.
- Shared interfaces and prepared iOS adapters/build inputs; iOS validation held.

Real notes, private symbols, native build outputs, APKs, unrelated older analysis,
generated-header line-ending noise and an unrelated older design are excluded.
The accepted protected APK is preserved. D:\tools and existing tags are untouched.

## Automated validation

- Full `flutter test --no-pub`: **749 passed, 3 skipped**. The skips require
  opt-in disposable fixtures: activation rehearsal, large attachment cache and
  large streaming tests. No real note was supplied to those tests.
- All 73 changed/new Dart files passed formatting. Whitespace checks passed.
- Exact commit-scope analysis: **0 errors, 0 warnings**, 232 informational/style
  notices. Full lib/test/tool analysis: 0 errors, one pre-existing unused-import
  warning in unchanged test/file_details_dialog_test.dart, and 299 infos. The
  unchanged starting-commit import was verified; unrelated test code is retained.
- Existing Windows UI/storage/import/cache regressions are part of the full suite.
  The 11 desktop presentation files and desktop MyApp match v1.4.1 byte-for-byte
  after line-ending normalization. No new Windows executable is promoted.
- Evidence retained locally in .validation/mobile-commit-full-tests.txt,
  mobile-commit-format.txt, mobile-commit-analysis.txt and
  mobile-commit-scoped-analysis.txt. The final protected Android preview build
  passed in 50.5 seconds; all 18 native libraries and 64-bit ELF/ZIP alignment
  checks passed. Evidence: .validation/mobile-commit-build.txt and
  mobile-commit-packaging.json. No iOS compilation is implied.

## Android runtime and user acceptance

The installed normal protected preview is package
com.nativedevps.futurenotes.preview, version 1.4.1+8 on LG LM-G900 / Android 12.
The last accepted APK has SHA256
15edffa96728b0905d2cdf3b31868b7a5322e220a068ce120f6f34ac0550b8da.
Its native libraries/64-bit ELF and ZIP alignment passed; cold launch was
2,092 ms and a twenty-second observation found no fatal/layout errors.
The final rebuild produced exactly the same APK SHA256 as this accepted app.
No reinstall or interruption of the running preview was needed for source commit.

The user confirmed native video decryption/playback and immediate cached reopen;
mobile progress/notifications and the note-row loading indicator; current-file,
byte and percentage export progress; and successful export with Checking and
Verifying disabled. Existing optional scan opt-ins remain respected. Required
decryption framing/padding/known-size and publication checks remain enforced.
Native synthetic sharing additionally verified both distinct payloads, chooser
dismissal, conflict rejection, predecessor backup and cleanup. See
ANDROID_NATIVE_CIPHER.md and ATTACHMENT_PRESENTATION.md for bounded evidence.

## Remaining acceptance limits

No Mac/Xcode or iPhone/iPad acceptance is available. Orientation editing/job
acceptance remains explicitly deferred. Minimum/current API emulators, tablets,
SD removal/full-disk/provider fault matrices, sustained multi-hour memory/thermal
profiling and all process-death/recovery workflows remain pending. Existing
automatic/runtime evidence does not close the complete ACCEPTANCE.md checklist.

This request authorizes source commit/push to development only. No tag, store
publication, production-package replacement or release publication is included.

## Rebuilding from a fresh checkout

Native Office binaries and licenses are generated locally, not committed. With
the pinned Android NDK 28.2.13676358 and Rust toolchain installed, run the native
build script before the APK build; it verifies the upstream commit and lockfile.

```powershell
pwsh -File tools/build-mobile-office.ps1
flutter build apk --no-pub --flavor preview --release --obfuscate --split-debug-info=.private-release-symbols/android-preview --target lib/main.dart
```

Resolve the pinned Flutter packages first with flutter pub get on a fresh clone.
iOS Office generation uses tools/build-ios-office.sh on a Mac and remains
unvalidated here. Do not replace a production app to work around signing errors.
