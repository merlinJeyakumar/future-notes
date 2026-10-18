Future Notes 1.4.2 is the protected Windows x64 portable release (build 9).

Changes since 1.4.1:

- Package import reads bounded note metadata first. A matching note ID prompts
  Duplicate / Back up & Replace / Ignore before extracting attachments. Ignore
  skips attachment processing; proceeding imports retain format checks,
  cancellation, progress and recovery backups. Existing attachment payloads are
  not compared before the choice.
- Optional source checking, decrypted-output verification, exported-backup
  validation and extra verification after large writes default to off. Saved
  choices are respected. Required bounds, framing, streamed CRC, short-write
  detection and recoverable publication remain. Necessary provider transfers and
  recovery backups still take time; no hidden full-payload rescan is added.
- Processing uses streamed write receipts and checksums to avoid redundant
  reads and copies where supported. Import/export progress describes the actual
  stage, file and byte counts. Password changes and prepared exports preserve
  existing encryption and package compatibility.
- Windows attachment opening retains its accepted private-cache path, including
  short-name directory aliases. Reopening reuses decrypted files until lock,
  credential changes, removal or exit. Content-free failure codes aid diagnosis.
- Interrupted-task recovery is available from the overflow menu. The existing
  desktop layout, formatting, gallery and window controls are preserved.

The shared source also contains the separately validated Android Preview work.
This release distributes the Windows portable build only, not a production
Android upgrade or an iOS build.

The normal editor, existing storage backend, encryption formats, note/settings
locations, attachment processing and cache lifetime are retained. Opening notes
does not migrate their attachment metadata. Decrypted attachment files remain
cached until locking, credential changes, removal or actual Exit invalidates
them, with deferred cleanup for files held open by another application.

Dart name obfuscation and the existing Windows runner protections remain enabled:
Control Flow Guard, stack cookies, DEP, ASLR, high-entropy ASLR and restricted DLL
search/loading. Crash symbols and the name map remain private and are excluded
from downloads. These mitigations do not prevent all memory injection or reverse
engineering. An administrator/debugger or sufficiently privileged process can
still inspect or modify memory. Prebuilt third-party DLLs are not recompiled.
Dynamic-code prohibition and Microsoft-only DLL policies remain disabled for
Flutter/native-library compatibility. The application is unsigned.

Download **Download-FutureNotes.ps1**, run it in Windows PowerShell, then read
**RUN-ME.txt** in the verified `FutureNotes-1.4.2-windows-x64` folder and open
**FutureNotes.exe**. The helper reconstructs the folder from individual release
assets and verifies SHA-256 hashes. No ZIP, installer, administrator rights,
Flutter/Dart SDK, Microsoft Office or separate Visual C++ installation is needed.
Keep the EXE, all DLLs and the data folder together; the EXE alone is insufficient.

**RUNTIMES.txt** lists included versions. Windows 10 (1809+) or Windows 11 x64,
with normal graphics/audio components, is required. Run from a local folder;
network-share execution, low-integrity DLLs and legacy injected hooks/IMEs can
be incompatible. An unknown-publisher warning is possible.

Notes/settings are not distributed. Keep a separate notes backup and the prior
app folder. Transfer notes with backup or package export/import and reselect a
custom library if its path differs on another PC. Existing release tags and
previous GitHub release assets are preserved.

The application changes passed their affected automated suites. The final
metadata-first import work passed 193 affected host tests plus protected Windows
and Android synthetic probes. The user accepted the Windows attachment-opening
correction and duplicate choices appearing before attachment extraction.
Release promotion additionally verifies packaging, native imports, private-symbol
exclusion, hashes and portable-folder startup. Same-machine checks do not prove
clean second-PC/VM compatibility. The existing Flutter Windows accessibility-tree
error has been observed during use; dedicated accessibility/IME acceptance and
clean second-PC playback/driver/workflow checks are not claimed complete.

This repository is private. Download the helper while signed in to GitHub. It
uses GH_TOKEN/GITHUB_TOKEN or prompts for a hidden repository-access token to
download assets; it never saves credentials in the app folder. Once downloaded,
the app runs offline without GitHub credentials. Exact hashes are recorded in
SHA256SUMS.txt and release-manifest.json.
