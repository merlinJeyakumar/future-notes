# Discovery readiness gate

Status: approved and attempted; stopped at full-suite failure. Current candidate
had passed focused tests but had not passed its integration gate. See
[STAGE7_READINESS_RESULTS.md](STAGE7_READINESS_RESULTS.md).
The subsequently approved integration retry passed all required source/test/build
checks; the earlier failure remains recorded with an unconfirmed cause.
The preceding cleanup gate passed 54 focused tests, all 274 tests, Windows
Debug compilation and the retained analyzer exception (98 diagnostics: 96 info,
original two warnings, no errors). Its 78-file source/executable checkpoint is
retained at
`.validation/future-notes-validation-stage2-cleanup-080a5e6fd65d48158615f428e89c9b34`.

From `D:\Project\NativeDevps\future-notes`, sequentially:

```powershell
$stage7ReadinessPaths = @(
  'lib/features/dashboard/services/background_service.dart',
  'lib/features/dashboard/viewmodels/content_viewmodel.dart',
  'test/storage/discovery_readiness_test.dart'
)
& 'C:\src\flutter\bin\dart.bat' format @stage7ReadinessPaths
git diff --check
& 'C:\src\flutter\bin\dart.bat' format --output=none --set-exit-if-changed @stage7ReadinessPaths
& 'C:\src\flutter\bin\flutter.bat' test --no-pub test/storage/discovery_readiness_test.dart test/storage/note_codec_test.dart test/viewmodels
& 'C:\src\flutter\bin\flutter.bat' test --no-pub
& 'C:\src\flutter\bin\flutter.bat' analyze --no-pub --no-fatal-infos --no-fatal-warnings
& 'C:\src\flutter\bin\flutter.bat' build windows --debug --no-pub
```

Stop on failed required checks or unexpected new warnings/errors. Inspect
informational deltas; retain the original two-warning exception. Ten new tests
are prepared; expected total is 284, not passing evidence.

Tests use explicit disposable settings/library environments. Real scans read
only synthetic fixtures. Injected missing-handshake/error/exit readers perform
no filesystem operations and own no writer handles. Timeout/disposal may stop
only these owned read-only isolates, not project apps or persistence workers.
No app launch/stop, real-note access, dependency resolution or encryption change.
Check for an existing project process before building without stopping it.

This gate does not establish listing/search generations, scan coalescing,
watcher/root rebinding, native reader handle cleanup, actual Windows startup,
continuous-use behavior or measured UI performance. Application adoption of
owned persistence and the remaining correctness stages remain pending.
