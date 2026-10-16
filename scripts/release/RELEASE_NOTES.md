Future Notes 1.4.0 is the protected Windows x64 portable release (build 7).

Changes since 1.3.0:

- Type @ in Rich text or HTML to suggest committed attachments from the current
  note. Filter filenames, including spaces, and choose with the mouse or
  Up/Down and Enter/Tab. Duplicate names show a short identity suffix.
- Rich text mentions use standard links: Ctrl+click opens the attachment through
  the existing decrypted-file cache. HTML inserts editable fnotes:// source.
  Suggestions never decrypt attachment payloads. Stable mention identities survive
  Save, password changes, export/import, Duplicate and Back up & Replace.
- Drop Explorer files anywhere on the dashboard window, including the sidebar
  and note header, to attach them to the selected editable note.
- The in-app title bar provides Minimize, Maximize/Restore and confirmed Exit,
  with dragging, double-click maximize and edge resizing. The notification-area
  tray icon is removed; Close follows the confirmed application-exit flow.
- Dialogs, sidebar, viewers and attachment panels use consistent transitions
  with reduced-motion support. Note selection no longer dims the whole editor;
  refresh preserves the sidebar list position. Locking removes protected content
  immediately, without retaining it for an exit animation.
- Media information appears on hover and hides when the pointer leaves.
  Non-media previews use an Info button. GIF playback has subtle play/pause
  controls. Returning focus to Rich text or HTML collapses expanded attachments
  while preserving typing focus.

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
**RUN-ME.txt** in the verified `FutureNotes-1.4.0-windows-x64` folder and open
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

The application changes passed their affected automated suites and user checks.
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
