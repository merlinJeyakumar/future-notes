Windows release promotion uses unpacked folders and individual GitHub assets.
It never creates ZIP files, copies libraries/settings into a release, installs
runtime dependencies on user computers, or changes an existing tag.

1. Update `pubspec.yaml`, release text and notes to a new version/build number.
   Retain dependency versions. Review code flow and run whitespace, analysis,
   `python -m unittest discover -s scripts/release -p test_*.py`, and relevant
   Flutter tests. Keep the prior executable. Close the running app normally.
2. Commit only the reviewed changes on `development`, leaving unrelated files
   and notes untouched. Then run:

   ```powershell
   .\scripts\release\New-WindowsRelease.ps1 -FlutterPath C:\path\to\flutter.bat -PythonPath C:\path\to\python.exe
   ```

   The script builds canonical `lib/main.dart` once, verifies the executable
   identity and all regular/delay DLL imports, then copies into a fresh
   `build/releases/FutureNotes-<version>-windows-x64` directory. CMake finds
   licensed Release CRT files in the compiler's redistributable directory.
   Windows 10/11 supply the Universal CRT and standard Windows APIs. Missing
   third-party dependencies, wrong architectures, links, user-data names,
   source changes, hash mismatches and existing destinations fail validation.
3. Check the copied app's startup/loaded runtime paths without automated editor
   input. Do not launch a second instance or use real notes for destructive tests.
   A same-machine copied-folder check is not clean-PC compatibility evidence.
4. Publish only after the relevant checks pass:

   ```powershell
   .\scripts\release\Publish-WindowsRelease.ps1 -PythonPath C:\path\to\python.exe
   ```

   This verifies the source revision and bundle, creates a fresh annotated tag,
   atomically pushes development/tag, uploads individual files to a draft, checks
   remote asset lengths and SHA-256 digests, preserves `v1.0.0`, then publishes.
   A failure leaves the prior release and any incomplete draft available; do not
   overwrite a release/tag or claim success. The generated downloader pins the
   manifest hash and reconstructs the portable directory without installing tools.

The app is unsigned. No signing certificate is created or publisher trust
claimed. No other-machine result is inferred from local build/dependency checks.

Release hardening (applies to new builds, not existing published assets):
- The release script enables Flutter `--obfuscate` and `--split-debug-info`,
  retaining the name map and crash symbols in fresh `.private-release-symbols/`
  directories accessible to the build user and SYSTEM. Back these up privately
  with the exact version and source revision. They are never release assets.
  The installed Flutter SDK determines whether crash files are SYMBOLS or PDB.
- Packaging/verification rejects private symbol and map files at every depth.
  Do not add symbol paths to assets or upload the private directory to GitHub.
- Release runners use /GS, CFG, DEP, ASLR and high-entropy ASLR. The build verifies
  actual PE flags, CFG metadata and static-import DLL search flags before staging.
- At entry, Release runners restrict default DLL search to the application and
  System32 directories, prefer System32, reject remote/low-integrity DLLs, disable
  legacy extension points and enable permanent strict-handle checks. Failure
  stops before COM, engine/plugin initialization and note storage. Windows still
  resolves static imports before entry; /DEPENDENTLOADFLAG limits the runner's
  static import search. Prebuilt DLLs are not recompiled by these switches.
- Run the portable app from a local folder with normal Windows permissions.
  Network-share execution, low-integrity DLLs and legacy injected hooks/IMEs can
  be incompatible. Modern text input and accessibility need manual acceptance.
- Dynamic-code prohibition and Microsoft-only DLL policies are intentionally
  excluded: they can break Flutter and the unsigned third-party native libraries.
  Debug stays debuggable. No anti-debug tricks, binary packers, machine-wide
  exploit-policy changes or new runtime dependencies are introduced.
- This reduces selected exploit/injection paths. It does not prevent a process
  with sufficient access from writing memory, creating remote threads, loading
  an explicitly named trusted-location DLL, changing binaries, or reading keys
  already needed by an unlocked note. Obfuscation does not encrypt assets.
  The app remains unsigned; these controls are not a tamper-proof trust boundary.

Private repositories need authenticated asset downloads. The bootstrap supports
an existing GH_TOKEN/GITHUB_TOKEN or a masked token prompt and uses the repository
API's asset IDs. It never persists credentials or changes repository visibility.
An uploaded bootstrap can be corrected without moving the application tag or
changing its native payload: commit the helper change to development, render it
against the existing verified manifest, rerun the downloader regression, replace
only that release asset and SHA256SUMS.txt, then verify actual API downloads.
Keep release notes explicit about this separate delivery-tool revision.
