Future Notes 1.4.1 is the protected Windows x64 portable release (build 8).

Changes since 1.4.0:

- The formatting toolbar stays compact in one card and reveals its remaining
  controls on hover. Expanded controls keep the editor below the toolbar rather
  than covering it. Natural collapsed height removes the empty bottom strip;
  editor margins are tighter, with no extra chevron or horizontal scrolling.
- All/More attachments uses modest, consistent margins and responsive columns
  that fill complete rows. The title, search and cards share a left edge;
  filtered results and incomplete rows stay at the top-left.
- Export and other auxiliary operations use compact progress rows instead of
  tall, mostly empty cards. Progress, byte counts and relevant actions remain
  visible; multiple rows scroll vertically within a bounded panel.
- Export attachment-source checking now reports its stage and byte progress and
  responds to cancellation through the existing owned reader. A cancelled
  export preserves the note and existing destination, and another export can
  start afterward. Integrity checks and recoverable publication are retained.
- Closing a saved, idle app no longer asks for an extra exit confirmation.
  Required draft and active-work decisions remain, and finalizing work and
  resource cleanup still complete before exit.

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
**RUN-ME.txt** in the verified `FutureNotes-1.4.1-windows-x64` folder and open
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

The application changes passed their affected automated suites. The toolbar,
gallery and compact export/cancellation changes also received user acceptance;
the close guard has automated lifecycle coverage.
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
