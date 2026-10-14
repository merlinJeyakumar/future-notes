# Watcher/library-switch lint-first gate

Status: the final approved cleanup correction passed formatting, whitespace,
analysis (exact prior 97 diagnostics), all 337 tests and Windows Debug build.
Runtime and real-library activation remain pending. Earlier failed attempts and
their separately approved corrections are retained in
[STAGE7_LIBRARIES_RESULTS.md](STAGE7_LIBRARIES_RESULTS.md) and
[STAGE7_LIBRARIES_DIAGNOSTIC.md](STAGE7_LIBRARIES_DIAGNOSTIC.md).
Candidate review:
[STAGE7_LIBRARIES_FLOW.md](STAGE7_LIBRARIES_FLOW.md).

From `D:\Project\NativeDevps\future-notes`, sequentially:

```powershell
& 'C:\src\flutter\bin\dart.bat' format test/viewmodels/library_switch_test.dart
git diff --check
& 'C:\src\flutter\bin\flutter.bat' analyze --no-pub --no-fatal-infos --no-fatal-warnings
& 'C:\src\flutter\bin\flutter.bat' test --no-pub
& 'C:\src\flutter\bin\flutter.bat' build windows --debug --no-pub
```

This is the final approved sequence: one suite and one required build, without
a duplicate focused or optional run. Earlier formatting covered the ten candidate
paths; only the harness changed in the final correction. Analysis exactly matched
the retained exception: 97 diagnostics, 95 info, original two warnings, no errors.
All 337 registrations passed. No dependency resolution ran.

Tests use synthetic disposable roots and injected services only. No project app
launch/stop, real-note access, production persistence activation or encryption
change. The process-check fallback listed no matching project process. The final
84-file source/executable checkpoint was created only after this gate passed;
previous checkpoints remain. Runtime/platform support stays pending.
