Future Notes 1.3.0 is the protected Windows x64 portable release (build 6).

Changes since 1.2.2:

- HTML mode has code styling, line numbers and explicit structured formatting,
  including mixed inline markup, without changing rich-text styling or spacing.
- Drag files from Explorer into the desktop editor to attach them. More files
  can be added while earlier attachments process, and typing stays available.
- Attachment preparation adapts to the current computer with a 70% available-
  capacity target and advanced parallel-file and working-memory limits. These
  are cooperative scheduling targets, not hard OS CPU or memory caps.
- Finalization reports stage and byte progress. Attachment opening no longer
  waits behind an entire unrelated generation publication.
- Two extra viewing scans, Check encrypted file before opening and Verify
  decrypted output, are configurable and off by default. Required file-safety,
  framing, padding and known-length checks remain, and writes/recovery retain
  verification. Existing encryption formats are unchanged.
- Decrypted files are reused across viewer closure, Save and navigation, including
  after password changes. Lock, credential changes, removal and Exit still
  invalidate affected cache entries, with deferred cleanup for blocked files.
- Play and More are hidden on processing attachments. Cancel remains directly
  available only while safe; controls return afterward without resizing cards.

The accepted centered PDF zoom, touchpad pinch/pan and Fit page behavior from
1.2.2 is retained.

The normal editor, storage backend, note formats and existing functionality
are retained. Notes, settings, encryption and library locations are unchanged.
Dart name obfuscation and the existing Windows runner protections remain enabled:
Control Flow Guard, stack cookies, DEP, ASLR, high-entropy ASLR and restricted DLL
search/loading. Crash symbols and the name map stay in private build storage and
are excluded from downloadable files.

These are compatible exploit mitigations, not complete memory-injection
prevention. Obfuscation does not encrypt resources or prevent reverse
engineering. An administrator/debugger or process with sufficient rights can
still inspect or modify memory. Prebuilt third-party DLLs are not recompiled by
runner protections. Dynamic-code prohibition and Microsoft-only DLL policies
are not enabled because they can break Flutter and bundled native libraries.
The application remains unsigned.

Download **Download-FutureNotes.ps1**, run it in Windows PowerShell, then read
**RUN-ME.txt** in the verified `FutureNotes-1.3.0-windows-x64` folder and open
**FutureNotes.exe**. The helper reconstructs the folder from individual release
assets and verifies SHA-256 hashes. No ZIP, installer, administrator rights,
Flutter/Dart SDK, Microsoft Office or separate Visual C++ installation is needed.
Keep the EXE, all DLLs and the data folder together; the EXE alone is insufficient.

**RUNTIMES.txt** lists the bundled versions. Use a local folder on Windows 10
(1809+) or Windows 11 x64 with normal graphics/audio components. Network-share
execution, low-integrity DLLs and legacy injected hooks/IMEs may be incompatible
with the protected build. An unknown-publisher warning is possible.

Notes/settings are not distributed. Keep a separate notes backup and the prior
app folder. Transfer notes using backup or package export/import, and reselect
a custom library if its path differs on another PC. Existing release tags and
previous release assets, including v1.2.2, are preserved.

The included application changes passed their focused static checks, relevant
regression suites, protected Windows Release builds and user checks. The latest
cache-lifetime gate passed 80 tests; the processing-controls gate passed 19 tests
and manual acceptance. This promotion changes release identity and distribution
text without changing that accepted runtime code. Packaging validates native
imports and file hashes. Clean second-PC/VM execution and dedicated IME/
accessibility compatibility are not claimed tested.

This repository is private. Download the helper while signed in to GitHub. It
uses GH_TOKEN/GITHUB_TOKEN or prompts for a hidden repository-access token to
download assets; it never saves credentials in the app folder. Once downloaded,
the app runs offline without GitHub credentials. Exact downloadable file hashes
are recorded in SHA256SUMS.txt and release-manifest.json.
