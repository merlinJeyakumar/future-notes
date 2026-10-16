# Windows release hardening — 16 October 2026

## State

Implemented and manually accepted as a candidate. The user then authorized
commit/push to development and publication under a fresh tag. Version 1.2.1+4
is prepared for that promotion; publication is not established by this source
report. The final publication receipt is kept in `.validation` after delivery.
Published v1.2.0 and its portable folder remain unchanged. The previously built
executable is retained at `.validation/windows-hardening-previous-release`.

The candidate is `build/windows/x64/runner/Release/FutureNotes.exe`, built from
canonical `lib/main.dart` without validation defines or storage restrictions.
After the user confirmed closing the previous portable app, zero running
instances and the candidate EXE/AOT hashes were verified. The candidate was
launched once without rebuilding (PID 80356). It is responsive, with a targetable
Future Notes window, clean captured logs and live Windows policy readback.
The user confirmed the requested manual checks passed: normal editor/existing
notes, typing, Save/reopen, attachment playback/document preview and locking
("it was working perfect"). Agent screenshot verification was unavailable:
Computer Use app approval timed out during the read-only window capture.
No original-note mutation was used as a test and no application was force-stopped.

## Implementation

- New release builds enable `--obfuscate`, `--split-debug-info` and a private
  obfuscation map. The installed Flutter 3.41.5 SDK produced a nonempty
  `app.windows-x64.symbols` file and a map containing 38,774 renamed symbols.
- Private artifacts have fresh version/revision/GUID directories under ignored
  `.private-release-symbols`, with a protected DACL granting only the build user
  and SYSTEM full control. They must be backed up privately for crash analysis.
- Package construction and verification reject symbol/map files at all depths,
  including accidentally nested Flutter assets. Release source-identity checks
  include the new private-symbol and PE-verification helpers.
- The MSVC Release runner explicitly uses /GS, CFG, DEP, dynamic-base ASLR,
  high-entropy ASLR and /DEPENDENTLOADFLAG:0xA00. A bounded PE parser checks the
  real output flags, stack cookie, CFG table and static-import search flags.
- Before COM/Flutter/plugin/storage initialization, the Release runner limits
  default DLL search to the application directory and System32, prefers
  System32, rejects remote and low-integrity images, disables legacy extension
  points and enables permanent strict-handle checks. Failure stops startup
  before note storage with a sanitized stage/error diagnostic.
- Debug is not subject to the new runtime policies. Prebuilt Flutter/media/PDF/
  Office DLLs are not recompiled by runner switches. No new packages, encryption
  changes, file-format changes or machine-wide exploit-policy changes were made.

## Validation

Flow review found no application use of name-based `runtimeType.toString()` or
Dart mirrors. Syntax, analysis and native/tooling checks completed before the
single Release build; the Flutter regression suite ran alongside compilation.

1. Whitespace, PowerShell AST parsing and Python compilation passed.
2. Release-tool suite: 14 tests initially passed; its new private-symbol ACL test
   initially failed. Investigation found inherited PowerShell 7 module paths
   selecting the wrong security module inside PowerShell 5, followed by
   `Set-Acl` requesting an unavailable audit privilege. Loading the host-native
   module explicitly and applying only the DACL corrected this. The one failed
   test was rerun and passed. Total: 15 distinct tooling tests passed; the other
   14 were not repeated.
3. `flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings`: exit 0,
   107 informational diagnostics, one existing unused-import warning in
   `test/file_details_dialog_test.dart`, zero errors. No Dart source was edited.
4. Native MSVC Release test: initial low-integrity fixture setup failed with
   Win32 error 5 because inherited Modify rights omitted WRITE_OWNER. The test
   now grants its owner full access to that disposable fixture only before
   labelling it. Final tests passed: policy readback, CFG active, DLL planting
   through working directory/PATH rejected, explicitly addressed normal fixture
   accepted, and explicitly addressed low-integrity fixture rejected.
5. One affected Flutter suite passed all 49 tests:

   ```powershell
   flutter test --no-pub test/storage/native_storage_integration_test.dart test/storage/attachment_open_cache_test.dart test/office_preview_service_test.dart test/attachment_document_preview_test.dart test/attachment_playback_test.dart test/attachment_gif_test.dart
   ```

   These tests use synthetic data. Flutter tests are not an obfuscated app run.
6. One build passed in 48.7 seconds:

   ```powershell
   flutter build windows --release --no-pub -t lib/main.dart --obfuscate --split-debug-info=<fresh-private-directory> --extra-gen-snapshot-options=--save-obfuscation-map=<fresh-private-directory>/obfuscation-map.json
   ```

   The existing CMake FetchContent_Populate deprecation warning remains. Actual
   runner PE verification passed. The private symbol/map artifacts were checked.
7. A disposable native process with the same policies successfully loaded the
   actual `flutter_windows.dll`, `libmpv-2.dll`, `pdfium.dll` and `office_oxide.dll`.
   This verifies imports, not interactive rendering, playback or engine startup.
8. Payload validation checked 55 build files, all required dependencies and the
   absence of private symbol/map files. It did not publish a portable release.

Evidence is under `.validation/windows-hardening-*`; build identity and binary
hashes are recorded in `windows-hardening-artifact-check.json`.

### Full-process startup follow-up

- Launched the unchanged candidate directly through `Start-Process`, using its
  Release directory as the working directory and redirecting stdout/stderr to
  `.validation/windows-hardening-runtime.*.txt`. There was no rebuild or test
  rerun. The canonical app uses its normal settings/library selection.
- Native process snapshots showed a nonzero window handle, title Future Notes
  and `Responding=true`. Computer Use independently returned exactly one window
  belonging to the candidate executable. Screenshot capture then stopped with
  `Computer Use app approval timed out`; no screenshot or UI input followed.
- Read-only `GetProcessMitigationPolicy` calls against the real app confirmed:
  image-load flags 7, extension-point flags 1, strict-handle flags 3 and CFG
  flags 1. The handle was closed after the queries.
- The running process loaded Flutter, media, CRT and Office modules from the
  candidate folder. The logs contained only successful protection initialization
  and media-library registration, with no error at the final read.
- At the final snapshot the working set was 242.6 MiB and total process CPU time
  25.66 seconds. Process elapsed time was 6,829.7 seconds; this is not a claim of
  continuous agent observation or a controlled idle-memory benchmark. Window
  capture approval interrupted observation, and user activity was not recorded.
- Launch, live-policy readback and final resource snapshots are in
  `windows-hardening-runtime-launch.json`, `windows-hardening-runtime-readback.json`
  and `windows-hardening-runtime-final.json`. The user subsequently accepted the
  requested editor, save, preview and lock checks. No agent automation keys,
  mouse input, attachment opening or forced shutdown was performed.

## Limits

This is exploit mitigation, not complete memory-injection prevention. A process
with sufficient rights can still write memory, create remote threads, modify
application files, or inspect an unlocked note's keys. Explicit absolute DLL
loads remain possible. The package is unsigned; hashes alone do not establish
publisher trust. Obfuscation does not encrypt resources or prevent reverse
engineering. Pre-entry static imports have a different lifecycle from policies
set at the runner entry point; already loaded code is not removed by a policy.

Dynamic-code prohibition and Microsoft-only image policies were not enabled:
they can break Flutter executable mappings/trampolines and bundled third-party
DLLs. The user accepted ordinary playback/rendering and typing. Dedicated
IME/accessibility compatibility, render-latency measurements, controlled idle
resource use and continuous operation were not established by that acceptance.
Network-share execution, low-integrity DLLs and legacy
injected hooks/IMEs may be incompatible with these restrictions. No universal
anti-injection or clean-second-PC claim is made.

## Primary references

- [Flutter obfuscation](https://docs.flutter.dev/deployment/obfuscate)
- [Default DLL directories](https://learn.microsoft.com/en-us/windows/win32/api/libloaderapi/nf-libloaderapi-setdefaultdlldirectories)
- [Image-load policies](https://learn.microsoft.com/en-us/windows/win32/api/winnt/ns-winnt-process_mitigation_image_load_policy)
- [Static dependent-load flags](https://learn.microsoft.com/en-us/cpp/build/reference/dependentloadflag?view=msvc-170)
