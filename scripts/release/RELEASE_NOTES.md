Future Notes 1.1.0 is a Windows x64 portable release. It includes the attachment
layout, file-backed viewing, video/audio autoplay, GIF playback, and writing UX
repairs from development. Existing note/encryption formats and storage locations
are retained.

Download **Download-FutureNotes.ps1**, run it in Windows PowerShell, then read
**RUN-ME.txt** in the verified `FutureNotes-1.1.0-windows-x64` folder and open
**FutureNotes.exe**. The downloader reconstructs the directories from individual
release files and verifies SHA-256 hashes. No ZIP, app installer, administrator
rights, Flutter/Dart SDK or separate Visual C++ installation is required.
The EXE alone is insufficient: keep all DLLs and the data directory together.

**RUNTIMES.txt** records the included versions. Microsoft Visual C++ Release
runtime DLLs are deployed beside the application. The target is Windows 10
(1809+) or Windows 11 x64, with the operating system's graphics/audio components.
The program is unsigned; an unknown-publisher warning is possible.

Your notes are not part of the download. Existing notes/settings stay under
your Documents/UserData location or your selected library. Transfer notes using
a separate backup or the app's package import/export; reselect a custom library
path if it differs on another PC. Keep previous application folders for rollback.
`v1.0.0` is retained unchanged.

Validation includes release-tool tests, synthetic startup/storage and attachment
regressions, Windows Release compilation, and PE dependency/hash verification.
Local portable startup and app-local runtime loading are checked separately.
No clean second-PC/VM execution has been performed; graphics, playback and full
workflow compatibility on another computer remain subject to that check.
