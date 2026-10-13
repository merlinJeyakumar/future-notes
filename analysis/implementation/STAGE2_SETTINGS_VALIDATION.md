# Eighth Stage 2 settings-service adoption gate

Status: approved and passed on 2026-10-13. The preceding worker gate passed all 16
focused tests, all 215 tests and Windows Debug compilation with exactly the prior
98 diagnostics. Its 73-file source/executable checkpoint remains available.

Run from `D:\Project\NativeDevps\future-notes`:

```powershell
$stage2SettingsPaths = @(
  'lib/core/storage/owned_settings_persistence.dart',
  'lib/features/dashboard/services/settings_service.dart',
  'test/storage/owned_settings_test.dart'
)
& 'C:\src\flutter\bin\dart.bat' format @stage2SettingsPaths
git diff --check
& 'C:\src\flutter\bin\dart.bat' format --output=none --set-exit-if-changed @stage2SettingsPaths
& 'C:\src\flutter\bin\flutter.bat' test --no-pub test/storage/owned_settings_test.dart test/storage/settings_isolation_test.dart
& 'C:\src\flutter\bin\flutter.bat' test --no-pub
& 'C:\src\flutter\bin\flutter.bat' analyze --no-pub --no-fatal-infos --no-fatal-warnings
& 'C:\src\flutter\bin\flutter.bat' build windows --debug --no-pub
```

Run sequentially. Stop at the first failed required check or unexpected new
warning/error. Inspect informational changes against 98 diagnostics: 96 info,
the original two warnings, no errors. Check for an existing project process
before building, without launching or stopping it. No dependency change.

Observed Windows results: all 26 focused tests (19 new plus seven existing)
and all 234 tests passed; Windows Debug compiled in 12.2 seconds. Analysis
reported 99 diagnostics: one new informational unnecessary_underscores lint,
the original two warnings, no errors. See [STAGE2_SETTINGS_RESULTS.md](STAGE2_SETTINGS_RESULTS.md).
Tests use an
injected owned worker and explicit disposable library/settings paths, including
a throwing Documents resolver. A settings root is released normally; no isolate
is terminated by these tests. Real notes/settings are not used.

The candidate connects SettingsService.withStorage to an injected owner. The
singleton and main application do not select that path. Production injection is
rejected before owner or Documents access. Tests cover acknowledgement-before-
publication, queued changes, explicit retry, external conflicts, unknown fields,
exact retained baselines, malformed/oversized input, load races, lease contention,
startup recovery, non-writable ambiguous recovery and resource release ordering.

Actual app startup, settings dialog error presentation, library acquisition and
switching, real interruption, cleanup failures, profiling/continuous operation,
production activation and other platforms remain pending. The settings payload
has a 64 KiB metadata bound; attachments retain their separately agreed limits.
