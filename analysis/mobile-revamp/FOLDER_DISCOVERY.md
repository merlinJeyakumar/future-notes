# Selected-folder discovery isolation

## Scope

Provider discovery previously admitted every regular file and resolved it before
the per-entry format-error handler. Oversized metadata, unreadable entries and
other I/O failures could abort the whole scan. The original on-phone exception
was not recorded, so the precise trigger of the reported failure is unconfirmed.

## Implementation

- Enumerate provider metadata and inspect at most 256 header bytes before
  resolving an individual candidate. Unrelated oversized files receive no
  payload reads. Keep arbitrary legacy filenames and existing plain JSON and
  app-encrypted envelopes; do not migrate or write library content.
- Retain the existing 32 MiB note metadata bound. Damaged, oversized, missing or
  unreadable entries are silently skipped, while valid entries remain visible.
  Their safe stage/reason codes remain diagnostic-only, as requested.
- Whole-folder listing/grant failures remain failed scans, not empty successful
  snapshots. Existing view-model behavior retains previous rows. A permission
  failure now explains how to restore folder access.
- Use provider timestamp/size metadata for discovery instead of opening an
  additional native source merely to stat it.
- Add numeric-only discovery stage/reason diagnostics. Never log note content,
  names, IDs, provider URIs or raw exceptions.
- Entry-level permission denial also stays silent if the subsequent root-access
  check succeeds. Genuine library-grant loss remains a folder-access error.
  Desktop presentation and note/encryption formats are unchanged.

## Automated validation

`flutter test --no-pub test/storage/provider_discovery_test.dart
test/viewmodels/discovery_search_test.dart test/storage/discovery_readiness_test.dart
test/storage/discovery_ordering_test.dart`: 43 passed.

Coverage includes mixed canonical and arbitrarily named legacy notes, actual
legacy encrypted metadata, synthetic 3 GiB backups with zero payload reads,
bounded media/ZIP probing, empty unrelated files, damaged/unreadable/oversized
note isolation, safe diagnostics, grant loss, provider outage, retained previous
rows, individual permission denial, retry, and stale-request rejection. Synthetic provider
objects remain untouched.

Scoped analysis passed with no errors/warnings and 89 existing informational
notices (`--no-fatal-infos`). Changed Dart files formatted; whitespace checked.

## Delivery and acceptance

The previous protected APK is retained under the ignored validation directory
and its SHA256 remains `3e6e935597cf0857f54655898bb7479c48b40be68af59489e50a24e30c1197d3`.
The protected normal Preview build succeeded in 58.3 seconds. Replacement APK:
132196809 bytes; SHA256
`76fd92807c8efb28c8aac6554d7e025c986702f431174eae1127f910320117f6`.
All 18 native libraries passed inspection; 64-bit ELF and APK 16 KiB alignment
checks passed. Existing signing, dependencies and protection settings retained.

On LG LM-G900 / Android 12, `pm clear com.nativedevps.futurenotes.preview` returned
Success. Replacement installation returned Success; cold launch took 1277 ms.
The process remained stable and foreground for 20 seconds with no fatal/layout
error matches; total PSS was 140866 KiB. Screenshot inspection confirmed the
expected Choose library folder startup screen after reset, not the error screen.
This does not validate actual selected-folder access: folder selection and
on-device mixed-folder acceptance are pending user interaction.

The user explicitly authorized clearing Android app data. This removes Preview
private state and persisted SAF permissions; it does not authorize deleting the
user-selected shared library folder. Folder selection must be restored after
reset. iOS device validation remains deferred.

## Silent-entry follow-up

The user requested no notification when an individual note cannot be read.
Removed the partial-scan warning and its shared snapshot field entirely. Entry
failures remain numeric-only diagnostics. A denied individual document does not
produce a UI error while the library-root access check succeeds; real folder
failures retain the existing error/retry behavior.

The final combined suite again passed all 43 tests, including individual
permission-denial isolation. Scoped analysis passed with no errors/warnings and
65 informational notices. Protected build succeeded in 55.3 seconds. APK SHA256:
`585c63867e10fa4893e0f796531b9608a60180b0b7b8185d18d99d3c0ad2fe99`.
Native ABI/16 KiB alignment checks passed. The preceding APK was retained at
`folder-discovery-silent-accepted` in the ignored validation directory.
In-place installation succeeded; cold launch took 1074 ms. On the LG Android 12
phone, the process stayed stable and foreground for 20 seconds, with no
fatal/layout log matches and total PSS 138735 KiB. No repeat data wipe was run.
Screenshot inspection confirmed three listed notes with no discovery error.
The on-device unreadable-entry scenario still awaits manual acceptance; its
automated coverage passed.
