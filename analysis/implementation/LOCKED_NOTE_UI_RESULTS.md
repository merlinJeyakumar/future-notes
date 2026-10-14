# Locked-note UI correction — 2026-10-14

## Cause and change

The content header always rendered Save and File Settings; only its formatting and attachment actions checked the lock state. The separate attachment-job panel did not observe the lock notifier, exposing terminal job filenames while the body was locked.

The header now hides Save/status and File Settings while locked, shows a Locked breadcrumb/icon, and preserves the read-only title/date and Unlock actions. Save also checks draft write authority. The job panel independently observes lock notifications and hides all job details until unlock, without discarding job state or touching note storage. Failed-card action buttons use bounded flexible widths after the new tests exposed their overflow.

## Validation

Formatted four affected files using the installed Dart SDK. The initial batch formatter bootstrap stalled and was interrupted; direct formatting with required SDK configuration access passed. Analysis used the retained baseline exception:

```powershell
& 'C:\src\flutter\bin\flutter.bat' analyze --no-pub --no-fatal-infos --no-fatal-warnings
```

Final result: exit 0, unchanged 110 diagnostics (108 informational, original two warnings), no errors or new warnings.

The initial affected test gate returned 27 passed and two failed due to the failed attachment-card action row overflowing horizontally. A first wrap correction changed that into an eight-pixel vertical overflow; its rerun also returned 27 passed and two failed. Bounded flexible buttons corrected the layout. The final narrow rerun was:

```powershell
& 'C:\src\flutter\bin\flutter.bat' test --no-pub test/content_area_locked_test.dart test/attachment_job_panel_test.dart
```

All four widget tests passed. They cover desktop/compact locked controls, wrong-password rejection, unlock/relock, completed/failed job visibility, direct lock-notifier updates without a parent rebuild, typing during progress and Finalizing/collapsed status. Existing `test/viewmodels/session_safety_test.dart` had all 25 tests pass in the preceding affected runs; it was not rerun after the card-only layout correction. Synthetic lock/unlock checks performed zero note writes.

## Windows build

After the user confirmed normal closure, process inspection found zero project instances. The previous Debug bundle was copied to `.validation/future-notes-locked-ui-previous-debug-20261014`; SHA-256 comparison verified all 17 copied files before compilation.

```powershell
& 'C:\src\flutter\bin\flutter.bat' build windows --debug --no-pub -t lib/main.dart
```

Passed with exit 0 in 19.0 seconds, producing `build/windows/x64/runner/Debug/flutter_application_1.exe`. Passed tests and analysis were not repeated.

## Pending

Native runtime verification of this UI patch is pending; earlier full-backend manual acceptance applies to the retained previous executable. There has been no restart, automated native input, forced termination or original-note access for this correction.
