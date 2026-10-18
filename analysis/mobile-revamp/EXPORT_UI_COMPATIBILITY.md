# Export result UI, filenames and compatibility

The user accepted native Save/Share and cached replay on the LG, then requested
a more polished result and proper filenames. This correction preserves that
accepted behavior and changes only the mobile result presentation/suggested name.

## Implementation

- One success header and one file-summary tile replace the repeated note title,
  explanatory paragraph, Export complete text and separate checkmark. Save is
  full width; Share/Close share a row or stack for narrow/enlarged-text layouts.
- Explicit system-safe insets and standard visual density preserve at least
  48-pixel action targets under platform theme differences. No auto-dismissal.
  Progress, file reuse, native actions and explicit Close remain operational.
- Suggested names come from the note title: Ave maria.fnote or Ave maria.zip.
  The shared pure filename helper preserves Unicode, replaces cross-platform
  forbidden characters, strips controls/bidi overrides, handles reserved Windows
  device names, avoids duplicate format extensions and bounds UTF-8 name length.
  Native pickers still let the user rename; no existing external files are renamed.
- Saved/cancelled/error feedback is a short inline status rather than a paragraph.
  Cached output ownership/lifetime, encryption and package formats are unchanged.

## Validation

- Initial affected suite: 18 passed, 3 layout cases failed. Large text reached
  the system navigation area; desktop theme density shrank buttons to 40 px.
- Corrected layout gate: all 8 passed, including 280/320/390 dp, landscape,
  tablets, light/dark, 2x text, Android/iOS/Windows/macOS theme settings and
  navigation/safe-area padding. Real-font/app-theme rendering rerun: all 8 passed.
  Dark and narrow-light renders were visually inspected under .validation/
  mobile-attachments-ready-polished-dark.png and ready-polished-narrow.png.
- Portable filename cases passed; actual owned-storage export uses the title
  and still reuses/invalidates prepared files correctly. Native action retry and
  retained-result regressions passed. Scoped analysis: no errors/warnings;
  58 informational lints remain in the inspected existing scope.
- Evidence: .validation/mobile-export-polish-tests.txt,
  .validation/mobile-export-polish-layout-final.txt,
  .validation/mobile-export-polish-render.txt,
  .validation/mobile-export-polish-analysis.txt.

## Compatibility scope

- Current Android configuration: minSdk 24, compileSdk/targetSdk 36. App API lint
  is scoped to NewApi, InlinedApi and ObsoleteSdkInt, with dependency tests excluded
  from this isolated invocation. Initial lint hit a Windows C:/D: plugin unit-test
  path error; the temporary init script disables those unrelated unit-test variants
  only for lint. No dependency or production Gradle settings were changed.
- That run then found genuine existing API gaps: three API-26 Path calls in
  AndroidCipher and an API-29 DocumentsContract.isChildDocument call. Cipher
  containment now uses canonical separator-bounded paths. API 24-28 uses a
  single tree-scoped document-ID query, whose trusted provider enforces subtree
  membership; API 29+ retains isChildDocument. Authority, exact tree identity
  and persisted read/write grant checks remain unchanged. No opaque ID is
  interpreted as a filesystem path and no payload is scanned for containment.
  Provider enforcement was checked against the
  [Android 7 AOSP DocumentsProvider source](https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/android-7.0.0_r1/core/java/android/provider/DocumentsProvider.java).
- Final API lint passed after those corrections: zero NewApi/InlinedApi errors,
  one existing ObsoleteSdkInt resource-directory warning (drawable-v21 below
  the app's minSdk 24). Evidence: .validation/mobile-export-api-lint-final.txt
  and .validation/export-api-lint.xml. This is API-source validation, not proof
  of runtime operation on every device/provider or Android version.
- Save uses Android's Storage Access Framework ACTION_CREATE_DOCUMENT and Share
  uses read-only FileProvider content grants. These APIs predate minSdk 24.
  Source: [Android document picker](https://developer.android.com/training/data-storage/shared/documents-files).
- System-safe dialog geometry is covered by widget tests, including navigation
  bars and gesture insets required by newer edge-to-edge behavior. Source:
  [Android 16 changes](https://developer.android.com/about/versions/16/behavior-changes-16).
- Real runtime/functional acceptance is on Android 12/API 31 LG LM-G900. API 24
  and 36 emulator images are absent; the configured AVD is API 33. No claim is
  made that every Android API/OEM or provider has been device-tested.
- iOS source retains its iOS 13 baseline/availability-guarded Files picker.
  UI theme tests are not an iPhone/iPad or Mac build. Those checks remain pending.
  Desktop/browser native export paths and desktop presentation are unchanged.

## Design and delivery

Stitch Pro unavailable; disclosed Flash fallback. Reference screen
db0490b6056347adba9ec34da39df10e is saved at
.stitch/designs/mobile-export-polished.html and .png. Generated additional
cancel-write/Save-again controls were not adopted.

Accepted APK preserved at .validation/mobile-export-polish-accepted/
app-preview-release.apk, SHA-256
b9da4430bdc04d6abe44e7d9a0a36ab0954892aaf5638d1d8c9a5b1d755cc44c.
Protected build passed in 71.6 seconds. APK SHA-256:
3e6e935597cf0857f54655898bb7479c48b40be68af59489e50a24e30c1197d3.
Packaging inspection passed for 18 native libraries and 16 KiB alignment of
64-bit ELF load segments; zipalign passed. Actual APK badging confirms minSdk
24 and target/compile SDK 36. Private symbols assertions passed.

In-place staged installation succeeded on the LG. Cold activity launch took
1,172 ms. Process 17141 remained stable/resumed for 20 seconds with no fatal
or layout log matches and no keyguard. Observed total PSS: 184,963 KiB; this
is not a stress/peak measurement. Evidence:
.validation/mobile-export-polish-build.txt,
.validation/mobile-export-polish-packaging.json,
.validation/mobile-export-polish-startup.json.

The new visual/filename acceptance and a small attachment open remain manual
LG checks. API 24/36 and iOS device validation remain pending as described above.
No notes, portable builds, tags or Git history are changed; no commit/push/release
publication is included. The accepted APK checkpoint hash remains unchanged.
