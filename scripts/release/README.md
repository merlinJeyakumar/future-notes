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

Private repositories need authenticated asset downloads. The bootstrap supports
an existing GH_TOKEN/GITHUB_TOKEN or a masked token prompt and uses the repository
API's asset IDs. It never persists credentials or changes repository visibility.
An uploaded bootstrap can be corrected without moving the application tag or
changing its native payload: commit the helper change to development, render it
against the existing verified manifest, rerun the downloader regression, replace
only that release asset and SHA256SUMS.txt, then verify actual API downloads.
Keep release notes explicit about this separate delivery-tool revision.
