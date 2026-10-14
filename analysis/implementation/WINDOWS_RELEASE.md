# Windows Release delivery — 2026-10-14

Version remains `1.0.0+1`. Canonical `lib/main.dart` includes the full recoverable backend, compatible attachment/password and package workflows, journaled deletion, library switching, one-click close and locked-note UI correction. No reduced preview or validation entry point is substituted.

## Validation

```powershell
& 'C:\src\flutter\bin\flutter.bat' test --no-pub --concurrency=1
& 'C:\src\flutter\bin\flutter.bat' build windows --release --no-pub -t lib/main.dart
```

The single integration suite passed: 440 passed, two opt-in tests skipped, no failures (69 seconds). The skipped verified-copy rehearsal and large-file streaming tests retain their separately recorded passing evidence in [FULL_BACKEND_RESULTS.md](FULL_BACKEND_RESULTS.md); they were not repeated. Windows Release compilation passed in 59.3 seconds. Recent analysis remains unchanged: no errors/new warnings, original two warnings and 108 informational diagnostics under the retained exception. No application source changed between that analysis, these tests and the build.

The release ZIP at `build/releases/FutureNotes-Windows-1.0.0+1-20261014.zip` contains the complete Release folder. All 16 packaged files were verified by length and SHA-256 against build output. ZIP SHA-256: `9AD8CD60B90DD35C4C2EE6674DFF72EA6C5691E1F4C87C1A77D38862D35E89D4`.

## Delivery boundary

Commit application/test sources, pinned dependency declarations, task-scoped scripts and implementation Markdown; merge the integration branch into local `development`. Exclude original notes, `.validation`, executable/build output, raw logs, unrelated audit artifacts and generated platform-file normalization. Preserve all excluded files. No remote push, GitHub release publication, version bump or application launch is included.

The previous Debug bundle and library backups remain retained. User-reported full Debug workflows passed; the Release executable has not been run. Native manual verification of the locked-note UI correction and Release runtime remain pending. Other platforms, measured UI performance and authenticated encryption redesign are outside this delivery's validation.
