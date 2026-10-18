# Android export activity visibility

## Change

Export jobs now participate in the mobile notes-list activity projection. Package
exports use the exported note's exact library and storage identity, including when
no editor is open. They are not attributed to a different selected note.

Single and batch attachment exports carry volatile storage IDs for the affected
files. Attachment rows show activity during export even in selection mode. Only
the current file displays stage bytes and percentage; other selected files show
an indeterminate export status. Completion, failure and cancellation remove the
export activity. The editor's existing compact progress area also includes export
jobs. Byte updates remain local to status widgets, without rebuilding the editor
or list structure.

No note metadata format, encryption, export verification policy or payload
processing was changed. Notifications, cancellation and the desktop presentation
remain on their existing paths.

## Validation — 2026-10-17

- Combined affected Flutter suite: **74 passed**. Covers mobile navigation,
  attachment presentation, normal/large-text export progress, exact note ownership,
  duplicate filename batches, cancellation, share failure cleanup, owned mutations,
  desktop attachment widgets and decrypted-cache reuse.
- Three export widget cases also passed with real fonts; normal and 2x text
  screenshots were inspected. Enlarged text retains the full footer progress;
  individual row labels use existing ellipsis behavior.
- Changed Dart files formatted; whitespace check passed. Final scoped analyzer:
  **zero errors, zero warnings**; existing informational lints remain.
- Eleven desktop presentation files and desktop `MyApp` still match `v1.4.1`.
- Protected normal-entry preview release built in **72.6 seconds**. All 18 native
  libraries present; 64-bit ELF load segments and APK ZIP alignment pass 16 KB
  checks.
- APK: `build/app/outputs/flutter-apk/app-preview-release.apk`, 131852457 bytes.
  SHA256: `66c48e710bae3920a96ffc26374fbf551c4a1331038cda753892f51b1350063e`.
- Previous accepted APK retained under `.validation/accepted-before-export-item/`
  with its SHA256 as the filename.

- Installed in place and launched on LG LM-G900, Android 12. The notes list was
  visibly rendered with the phone unlocked. The process remained stable for a
  20-second observation, with zero fatal/layout log matches and 151592 KiB total
  PSS. This startup observation does not establish sustained export performance.
- Manual acceptance of the new export indicators on the phone is **pending**.

No commit, push, release tag or portable update is included.
