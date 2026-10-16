Future Notes 1.2.1 is the protected Windows x64 portable release (build 4).

Changes since 1.2.0:

- Dart code is compiled with name obfuscation. Crash symbols and the name map
  remain in private build storage and are excluded from downloadable files.
- The native Release runner enables Control Flow Guard, stack cookies, DEP,
  ASLR and high-entropy ASLR. Build tooling checks the actual executable flags.
- DLL loading excludes the working directory and PATH, prefers System32 and
  rejects remote/low-integrity images. Legacy extension points are disabled and
  strict handle checks enabled before normal engine/plugin/storage startup.
- The normal editor, storage backend, note formats and existing functionality
  are retained. Notes, settings, encryption and library locations are unchanged.

These are compatible exploit mitigations, not complete memory-injection
prevention. Obfuscation does not encrypt resources or prevent reverse
engineering. An administrator/debugger or process with sufficient rights can
still inspect or modify memory. Prebuilt third-party DLLs are not recompiled by
runner protections. Dynamic-code prohibition and Microsoft-only DLL policies
are not enabled because they can break Flutter and bundled native libraries.
The application remains unsigned.

Download **Download-FutureNotes.ps1**, run it in Windows PowerShell, then read
**RUN-ME.txt** in the verified `FutureNotes-1.2.1-windows-x64` folder and open
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
previous release assets, including v1.2.0, are preserved.

The hardening candidate passed 49 affected Flutter regressions, 15 release-tool
tests, native loader/policy tests and actual executable-mitigation checks.
Windows policy readback confirmed the protections active in the running app;
captured logs showed no errors. The user accepted existing notes, typing,
Save/reopen, attachment playback/document preview and locking. Version 1.2.1
uses that same runtime code with updated release identity and a new obfuscated
build. Packaging validates native imports and file hashes. Clean second-PC/VM
execution and dedicated IME/accessibility compatibility are not claimed tested.

This repository is private. Download the helper while signed in to GitHub. It
uses GH_TOKEN/GITHUB_TOKEN or prompts for a hidden repository-access token to
download assets; it never saves credentials in the app folder. Once downloaded,
the app runs offline without GitHub credentials. Exact downloadable file hashes
are recorded in SHA256SUMS.txt and release-manifest.json.
