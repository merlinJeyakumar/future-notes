# Stage 0 validation request

Status: this sequence was approved and ran through the failed strict analyzer.
The user subsequently approved the recorded diagnostic baseline. Analysis using
the exact approved exception flags and the Windows build passed; see
[observed results](VALIDATION_RESULTS.md).
The working directory is `D:\Project\NativeDevps\future-notes`. Commands run
sequentially, stopping on the first failed required check. No application launch
is included.

Offline dependency resolution is necessary because `path` is now directly
imported and promoted at its already-installed version, 1.9.1. Review and record
the lockfile diff; allow only the promotion and required installed-SDK-compatible
resolution. Do not upgrade the dependency stack.

The formatter scope contains only changed/new Dart files. First establish the
four unchanged test files' baseline, then run the complete suite, including the
new synthetic storage tests. The existing tests exercise dialogs/models and do
not initialize the application. New file tests inject both settings and library
locations under operation-owned disposable directories, with production
Documents resolution forbidden.

```powershell
& 'C:\src\flutter\bin\flutter.bat' pub get --offline
& 'C:\src\flutter\bin\dart.bat' format lib/core/storage/storage_environment.dart lib/features/dashboard/services/settings_service.dart lib/features/dashboard/services/file_service.dart lib/main.dart test/storage test/support
git diff --check
& 'C:\src\flutter\bin\dart.bat' format --output=none --set-exit-if-changed lib/core/storage/storage_environment.dart lib/features/dashboard/services/settings_service.dart lib/features/dashboard/services/file_service.dart lib/main.dart test/storage test/support
& 'C:\src\flutter\bin\flutter.bat' test --no-pub test/password_dialog_test.dart test/export_options_dialog_test.dart test/import_confirmation_dialog_test.dart test/file_details_dialog_test.dart
& 'C:\src\flutter\bin\flutter.bat' test --no-pub
& 'C:\src\flutter\bin\flutter.bat' analyze --no-pub
& 'C:\src\flutter\bin\flutter.bat' build windows --debug --no-pub
```

The preserved executable is available in the baseline bundle described in
[STATUS.md](STATUS.md). Check for an existing project app before the build; do
not terminate or start one. If an existing process would prevent replacement,
report it and defer the build.

Report pre-existing baseline failures separately from patch regressions. A
failed required command still stops this stage. Passing these checks would
establish only Stage 0's tested behavior and Windows compilation; visible startup,
later correctness repairs and all other platform validation remain pending.
