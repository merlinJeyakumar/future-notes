# Local attachment document previews

Implemented on development after 2e5c73d. No storage/encryption format changes,
release publication, existing tag changes or portable-folder replacement.

## Behavior and flow

- Explicit Open uses the existing completed decrypted attachment cache file.
  Row rendering does not open, decrypt or parse documents.
- PDF: file-backed PDFium rendering, previous/next page, zoom and fit-page.
  Retains one page raster with a maximum dimension of 2048 pixels.
- DOC/DOCX: local read-only text, formatting and tables. Legacy DOC layout can
  differ from Word. XLS/XLSX: local tables with horizontal and vertical scrolling.
  These are reading previews, not Office layout engines, formula recalculators
  or editors. Embedded document images/objects and active links are excluded.
- The existing More menu retains system Open, Save As and Remove.
- Opening/parse failures stay within the viewer and offer system Open. A preview
  failure is not reported as a decryption failure.
- Closing/locking revokes the surface, joins parsing/rendering and frees native
  handles before the existing cache invalidation removes its source.
- Office parsing runs in an owned isolate. Native parsing cannot be interrupted
  mid-call; close joins it. Preview-only bounds: 64 MiB source, 128 MiB declared
  ZIP expansion, 10,000 entries, 8 MiB generated HTML and 50,000 DOM elements.
  Attachment storage/export limits remain unchanged. Large/complex Office files
  retain system Open and Save As.
- Generated HTML allows passive text/table markup only. No browser, scripts,
  external images, active file links or remote conversion services are used.

## Dependencies and distribution

- pdfrx 2.2.24, flutter_widget_from_html_core 0.17.4. Existing ffi 2.1.4 and
  html 0.15.6 are promoted to direct dependencies without changing their versions.
- Required transitive synchronized changes from 3.1.0 to 3.4.0+1. Other preexisting
  package versions remain unchanged. Current Flutter/Dart SDK is retained.
- Office Oxide 0.1.15 Windows x64 DLL: pinned official release archive with
  SHA-256 00541bb8965f1a29ba1a56a90e6f1ecef1c25121a2480cc015046f2cd452f89f.
  CMake installs it beside FutureNotes.exe, with its MIT license under data/licenses.
- The PDFium plugin bundles chromium/7520 with its upstream license/notices.
  End users need no Microsoft Office installation or preview runtime download.
- Stitch screen d517ef2a3c004e5fb2009ce40aba1f3b informed the reading surface;
  unrequested mockup tabs/actions were excluded. Only synthetic content was used.

## Validation evidence

Formatting and whitespace checks passed. Initial lib/test analysis found eight
new protected-notifier warnings; the notifier implementation was corrected.
Targeted reanalysis of all corrected files passed without diagnostics. The
preexisting test/file_details_dialog_test.dart unused-import warning remains.

Combined affected command:

```powershell
flutter test --no-pub --concurrency=1 test/office_preview_service_test.dart test/attachment_document_preview_test.dart test/attachment_playback_test.dart test/attachment_gif_test.dart test/attachment_strip_test.dart test/attachment_job_panel_test.dart test/storage/attachment_open_cache_test.dart test/storage/attachment_cache_lifecycle_test.dart
```

Initial result: 56 passed, two failed (test temporary-directory setup and RichText
finder). Narrow corrections followed. A PDF native-worker initialization race
then caused a DLL-load error and a 30-second test timeout. Explicit bundled DLL
checking/preloading corrected that path; a missing-component regression was added.

Final affected-file command: `flutter test --no-pub --concurrency=1 test/office_preview_service_test.dart test/attachment_document_preview_test.dart`.
Result: 19 passed. The 41 existing attachment/cache regressions passed in the
combined run and were not repeated. Synthetic native DOC/DOCX/XLS/XLSX fixtures
are source-hash checked, with Unicode filenames; PDF tests render both pages,
exercise zoom/page UI and verify handle release. Malformed/oversized documents,
ZIP expansion, passive HTML, late completion and closing during parsing are covered.

Logs in ignored .validation: document-preview-source-analysis.txt,
document-preview-test-analysis.txt, document-preview-tests.txt,
document-preview-tests-corrected.txt, document-preview-pdf-corrected.txt,
document-preview-final-tests.txt and document-preview-release-build.txt.

Previous executable retained at .validation/document-preview-previous-release.
Windows Release build passed once in 47.8 seconds using
`flutter build windows --release --no-pub -t lib/main.dart`. CMake reported a
developer-only FetchContent_Populate deprecation warning; compilation succeeded.

Initial portable dependency verification rejected bcryptprimitives.dll. It is
an inbox Windows 10/11 component (verified against Microsoft documentation and
the valid Microsoft signature of the local System32 copy). The build-tool list
was corrected; no system DLL was copied. Python syntax and repeated affected
bundle verification passed: 55 files, including both native preview DLLs and
their license files. Existing portable release contents/tags remain unchanged.

One canonical Release instance started with a responsive visible Future Notes
window (PID 70684). Startup stderr was empty. Resource/startup observation is in
.validation/document-preview-runtime-observation.json. No agent input, forced
termination or original-note mutation was performed. Manual preview/lock
acceptance is pending the user's checks of the synthetic fixture directory.

## Follow-up: Office appearance and expanded attachment dock

User confirmed documents can be viewed, and clarified the Office limitation as
unattractive styling. Other manual PDF/lock checks were not individually reported.

- Word previews now use a centered paper surface, constrained reading width,
  comfortable margins and heading/paragraph spacing. Office tables use clearer
  padding, borders, actual header-cell styling and alternating existing rows.
  Spreadsheet scrolling remains available on both axes, with explicit scrollbars.
  Cell data and header roles are not inferred or changed.
- Expanded attachments show every file in wrapped rows with a bounded scroll
  viewport; no +N tile appears. Collapsed mode keeps the existing small icons and
  overflow action. Sizes, progress, More actions and collapse-on-open/unlock stay.
- Stitch refinement: screen 5767042c901a4a2cbe9405577c29c6af, synthetic content only.
- Format/whitespace passed. Scoped analysis had only the existing intl dependency
  informational lint in attachment_strip.dart; no errors/warnings.
- One affected suite passed all 36 tests:
  `flutter test --no-pub --concurrency=1 test/attachment_strip_test.dart test/attachment_document_preview_test.dart test/office_preview_service_test.dart`.
  Includes 20-file wrap/scroll without decryption, collapsed overflow, stable
  progress geometry, paper sizing and preserved table/header contents.
- Previous executable retained in .validation/office-styling-previous-release.
  Logs: office-styling-analysis.txt, office-styling-tests.txt and
  office-styling-release-build.txt under .validation.
- Windows Release build passed once in 41.8 seconds. Both native preview DLL
  hashes match the previously verified bundle. Updated app launched once as
  PID 72604; visual acceptance of styling and the expanded dock remains pending.

## Follow-up: left alignment and searchable Show all

User accepted Office styling and expanded file visibility, but reported the dock
had moved to the center. Cause: its shrink-wrapped root was centered by the
editor's parent Column. The dock now explicitly takes the available width and
keeps its contents left aligned.

Show all precedes the attachment count and opens All attachments, including
every committed/pending entry. Local case-insensitive filename search, clear
with retained focus and No matching attachments are provided. Existing file
actions and owner/lock/credential invalidation are retained. Rendering/searching
does not decrypt or open a file. Collapsed overflow retains its remaining-file
dialog, which also supports search.

Stitch screen de64fd33b6d14e92a04da30f460e1734 uses synthetic names only.
No dependencies, attachment formats or Office preview behavior changed.

The first `flutter test --no-pub test/attachment_strip_test.dart` run had 14
passed/3 failed: header wrapping moved cards during progress, and the new test's
More locator matched a background tile. Header labels now remain on one line
with ellipsis/full tooltip; the test targets the dialog. Scoped analysis has
only the existing intl dependency info. The same affected-file gate then
passed all 17 tests. Format/whitespace passed. No unrelated suite was repeated.

Previous executable: .validation/searchable-attachments-previous-release.
Logs: searchable-attachments-analysis[-corrected].txt,
searchable-attachments-tests[-corrected].txt, searchable-attachments-release-build.txt.
Release built once in 39.5 seconds and launched as PID 19988. Startup produced
a responsive Future Notes window and no stderr errors. Manual visual check of
left alignment and searchable Show all remains pending.

## Commit validation

Final review on 16 October 2026: all eight changed Dart files passed a
non-writing format check (zero changes), and whitespace checks passed. Latest
affected attachment gate: 17 passed; prior combined document/style gate: 36
passed, with the earlier media/cache regressions retained as recorded above.
Latest Windows Release build passed and startup logs had no errors. Unchanged
tests/builds were not repeated for the commit request. The current Show all
dialog remains pending explicit user visual acceptance.

Only task source, generated FFI plugin lists, pinned dependency lockfile,
licenses/notices, synthetic fixtures, Stitch designs and this report are included.
Existing notes, unrelated analysis files, preexisting registrant-header changes,
portable release folders and release tags are excluded.

The staged whitespace gate initially treated the ASCII synthetic PDF as text
and rejected its required xref spacing. A scoped binary .gitattributes rule now
preserves all five fixture formats across CRLF-normalizing Windows checkouts.
Working-file and staged-blob hashes were compared; no fixture bytes or app code
changed, so no runtime gate was repeated for this Git-only correction.
