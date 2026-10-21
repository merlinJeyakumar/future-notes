Future Notes 1.4.3 is the protected Windows x64 portable release (build 10).

Changes since 1.4.2:

- Full-screen image previews preserve portrait and landscape proportions during
  bounded decoding on desktop and mobile. Original files, zoom, playback and
  decrypted-cache reuse are retained.
- Multiple files can be added in one pick. Desktop attachment galleries support
  batch selection and actions alongside the existing mobile selection workflow.
- Mobile editing preserves selection and formatting focus, provides a scrolling
  formatting row with explicit expansion, structures HTML source, and keeps
  attachment shelves behind the on-screen keyboard.
- Android background-task notifications update progress without flooding,
  support cancellation and remove stale active entries. Interrupted work remains
  available through the overflow recovery action.
- Android Preview accepts shared files for an existing or new note and continues
  attachment processing in the background. Shared .fnote packages offer Validate
  and Import. The destination list refreshes after cold startup without requiring
  the user to reopen the chooser.
- Android import retains access to picked files and reads package headers through
  the retained URI grant, fixing passwordless import failures. Matching note IDs
  still prompt Duplicate / Back up & Replace / Ignore before attachment extraction.

GitHub release assets contain the Windows portable build. A separately protected
Android Preview APK with the same version is delivered to the requested local
Drive folder; it retains the Preview package and signing identity and is not a
production Android upgrade. iOS sharing adapters are source-only readiness;
Mac builds and iPhone/iPad acceptance remain pending.

The normal editor, existing storage backend, encryption formats, note/settings
locations, optional-verification defaults and cache lifetime are retained. Opening notes
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
**RUN-ME.txt** in the verified `FutureNotes-1.4.3-windows-x64` folder and open
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

The application changes passed their affected automated suites, including the
163-test sharing/import regression suite and the 45-test image-preview suite.
Protected Android synthetic checks covered shared-file intake, cancellation,
draft preservation and cold-start destination loading. The user accepted mobile
sharing, multi-file selection, import, notification fixes and image proportions.
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
