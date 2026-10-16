Future Notes 1.2.2 is the protected Windows x64 portable release (build 5).

Changes since 1.2.1:

- PDF +/− zoom keeps the visible view centered, including after panning.
- Touchpad pinch and two-finger pan now use one transform owner. Pinching stays
  centered without sideways drift, including when reversing direction or when
  scroll signals arrive during a pinch. Separate scrolling pans without zooming.
- Fit page recenters the full page; existing zoom limits and page controls remain.

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
**RUN-ME.txt** in the verified `FutureNotes-1.2.2-windows-x64` folder and open
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
previous release assets, including v1.2.1, are preserved.

The PDF correction passed scoped static analysis, all nine affected document
preview tests, a protected Windows Release build and the user's physical
touchpad check for pinch/reversal, separate panning, +/− and Fit page. Version
1.2.2 uses that accepted runtime code with updated release identity and a new
obfuscated build. Packaging validates native imports and file hashes. Clean
second-PC/VM execution and dedicated IME/accessibility compatibility are not
claimed tested.

This repository is private. Download the helper while signed in to GitHub. It
uses GH_TOKEN/GITHUB_TOKEN or prompts for a hidden repository-access token to
download assets; it never saves credentials in the app folder. Once downloaded,
the app runs offline without GitHub credentials. Exact downloadable file hashes
are recorded in SHA256SUMS.txt and release-manifest.json.
