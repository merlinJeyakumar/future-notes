Future Notes 1.2.0 is a Windows x64 portable release (build 3).

Changes since 1.1.0:

- Open PDF, DOC, DOCX, XLS and XLSX attachments inside Future Notes, locally and
  offline. PDF has page navigation and zoom. Word and spreadsheet previews have
  clearer page spacing, table styling and scrolling. Office layouts are reading
  previews of text/tables; embedded images/objects and exact Office layout are
  not reproduced. Complex or oversized files retain Open in system app/Save As.
- Expanded attachments show every file in wrapped rows. The dock stays left
  aligned; Show all opens a searchable filename dialog. Collapsed notes retain
  the small-icon row. Opening/unlocking a note keeps attachments collapsed.
- Exports retain note identity. Reimporting a matching note offers Duplicate,
  Back up & Replace, or Ignore in a dedicated dialog.
- Unlock protected notes directly in the editor with automatic password focus.
  Sidebar lock icons retain the correct state when switching notes. Sidebar
  subtitles show updated time and the final five ID characters.

Download **Download-FutureNotes.ps1**, run it in Windows PowerShell, then read
**RUN-ME.txt** in the verified `FutureNotes-1.2.0-windows-x64` folder and open
**FutureNotes.exe**. The helper reconstructs the folder from individual release
assets and verifies SHA-256 hashes. No ZIP, installer, administrator rights,
Flutter/Dart SDK, Microsoft Office or separate Visual C++ installation is needed.
Keep the EXE, all DLLs and the data folder together; the EXE alone is insufficient.

**RUNTIMES.txt** lists exact bundled versions, including Office Oxide and PDFium.
The target is Windows 10 (1809+) or Windows 11 x64 with its normal graphics/audio
components. The application is unsigned; an unknown-publisher warning is possible.

Your notes/settings are not distributed. Existing file locations and encryption
formats remain compatible. Keep a separate notes backup and the previous app
folder. Transfer notes using backup or package export/import, and reselect a
custom library if its path differs on another PC. Existing release tags,
including `v1.0.0` and `v1.1.0`, remain unchanged.

Validation covers synthetic document/attachment regressions, release-tool tests,
Windows Release compilation, app-local DLL dependency and SHA-256 verification,
and local copied-folder startup. Document viewing and Office styling were
manually checked; the newest Show all dialog has regression/startup coverage.
Clean second-PC/VM execution has not been performed, so graphics/playback and
full workflow compatibility on another computer are not claimed as tested.

This repository is private. Download the helper while signed in to GitHub. It
uses GH_TOKEN/GITHUB_TOKEN or prompts for a hidden repository-access token to
download assets; it never saves credentials in the app folder. Once downloaded,
the app runs offline without GitHub credentials. Exact downloadable file hashes
are recorded in SHA256SUMS.txt and release-manifest.json.
