Future Notes 1.3.0 - Protected Windows x64 build

Run FutureNotes.exe from this folder. Keep the DLLs and data folder
beside it. Flutter, Dart, Visual Studio, Python and a separate Visual C++ runtime
installation are not needed on the destination computer. Windows 10 (1809+)
or Windows 11 x64 is required. No ZIP is produced.

No installer is required. Close Future Notes normally before switching versions.
Keep this version in its own folder instead of overwriting your previous copy.
See RUNTIMES.txt for exact component versions. DLL names are intentionally kept
unchanged because the Windows loader references them by those names.

For GitHub downloads without an archive: download Download-FutureNotes.ps1 and
run it in Windows PowerShell. It downloads the individual release files into a
new FutureNotes-1.3.0-windows-x64 folder and checks their SHA-256 hashes. Then open
FutureNotes.exe yourself. No SDK, runtime installer or administrator access is
required. If Windows blocks a downloaded script, inspect it and use Properties
> Unblock only after confirming it came from this project's release page.

Notes/settings stay in your Windows Documents/UserData folder or the library
you selected in Settings. Copying the application does not copy your notes.
Use a separate backup or the application's package export/import to transfer
notes. A custom library path saved on one PC can be invalid on another PC;
select the correct library in Settings. Never distribute your settings,
AttachmentCache, UserData, .future-notes-* folders or note_* files as app files.

This release is unsigned. Windows may show an unknown-publisher warning.
Application-local runtime DLLs are serviced with application releases; replacing
the whole application bundle retains files outside that bundle.

This build includes Dart name obfuscation and compatible Windows exploit
mitigations. Debug symbols and the name map are private and are not included.
Run it from a local folder: remote/low-integrity DLLs and legacy injected hooks
are blocked. These controls reduce selected injection paths; they do not prevent
all memory injection, hide assets or defeat an administrator/debugger.

Build and dependency checks plus local startup are recorded in the repository.
A clean second-PC playback/driver/workflow check remains separate evidence.
