# Stage 0 observed validation

Date: 2026-10-12. Branch: development. Baseline HEAD: a9f6d24.
The original executable remains preserved. No application launch occurred.

| Check | Observed result |
| --- | --- |
| Offline dependency resolution | Passed after granting SDK-cache access |
| Formatter, changed/new Dart files | Passed; 9 files processed |
| `git diff --check` | Passed; generated-file line-ending warnings only |
| Non-mutating format check | Passed; 0 changes required |
| Existing four-file test baseline | 39 passed |
| Full Flutter suite | 58 passed, including 19 new isolated storage/compatibility tests |
| `flutter analyze --no-pub` | Failed: exit 1, 79 diagnostics, no analyzer errors |
| Analysis with approved baseline exception | Passed: exit 0, same 79 diagnostics |
| Windows Debug build | Passed: exit 0, built flutter_application_1.exe in 28.4s |
| Runtime workflows/performance | Not run |

## Dependency changes

`path` remains 1.9.1 and changes from transitive to direct. Four other lockfile
versions match the installed Flutter SDK's explicit pins:

- characters: 1.4.0 → 1.4.1
- matcher: 0.12.17 → 0.12.19
- material_color_utilities: 0.11.1 → 0.13.0
- test_api: 0.7.7 → 0.7.10

These pins were checked in `C:/src/flutter/packages/flutter/pubspec.yaml` and
`C:/src/flutter/packages/flutter_test/pubspec.yaml`. No Flutter upgrade ran.
Flutter regenerated native plugin registrants; Git shows no semantic diff for
those generated files, only line-ending status/warnings.

## Exact failed command

```powershell
& 'C:\src\flutter\bin\flutter.bat' analyze --no-pub
```

The analyzer reported 2 warnings and 77 informational lints, ending with:
`79 issues found. (ran in 30.6s)` and exit code 1.

Warnings:

- `lib/features/dashboard/widgets/sidebar.dart:1:8`:
  unused import `dart:io`.
- `test/file_details_dialog_test.dart:1:8`:
  unused import `package:flutter/material.dart`.

Information includes existing production `print` calls, the transitive
`highlight` import, unnecessary imports, deprecated Flutter/share APIs,
asynchronous BuildContext use, unbraced control flow and styling lints.
The affected unchanged source and the retained print calls in FileService
already exist at the baseline revision. No diagnostics target the new storage
environment, new isolated tests or modified settings service.

This is a failed strict gate, not a clean analysis result. No required finding
is closed. The user explicitly approved retaining this baseline for Stage 0,
then the following commands completed with exit code 0:

```powershell
& 'C:\src\flutter\bin\flutter.bat' analyze --no-pub --no-fatal-infos --no-fatal-warnings
& 'C:\src\flutter\bin\flutter.bat' build windows --debug --no-pub
```

Analysis reported the same 79 issues in 18.5s. Windows build completed in 28.4s.
No running project application was found by the pre-build process check. The
executable was not launched; runtime behavior remains unvalidated.

## Isolation evidence and limits

Tests used disposable synthetic settings and libraries with a production
Documents resolver that throws if called. The isolation tests passed, including
missing/invalid configuration, copied external library settings, traversal and
existing links. Existing tests exercise dialogs/models without application
startup. The root opaque note and real UserData were not read or modified.

The initial sandboxed dependency attempt stalled without output and was
interrupted (exit 1). Flutter's batch startup retries a writable SDK-cache lock
outside the workspace sandbox. Retrying the same approved offline command with
SDK-cache access completed successfully. This was an environment-startup issue,
not a passing or failing application test.

Existing autosave and later repair stages remain unimplemented. These results
do not authorize an app launch, real-library writes, or platform/performance
claims.
