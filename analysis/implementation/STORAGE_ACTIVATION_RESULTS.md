# Activation gate results — stopped before launch

## Backup and compatibility rehearsal

After the user approved the gate, `git diff --check` first failed on an extra
blank line in STATUS.md added during preparation. The user approved removing
that documentation-only blank line and resuming. The whitespace check then
passed. No formatting or analyzer command was repeated.

`Prepare-StorageActivation.ps1 -Mode Prepare` returned 0. It retained and
hash-verified all three library files and 17 previous-executable files, with
matching source/copy inventories. Existing settings were absent. The immutable
backup and separate rehearsal copy remain excluded from Git. No original file
was written or deleted.

The opt-in rehearsal passed for both copied notes. Byte-identical worker commits
preserved their hashes and envelope formats; four injected interruption/reopen
checks restored the exact prior hashes. No password-protected body was unlocked
and no attachment decryption claim is made. Rehearsal receipts are private and
contain aggregate outcomes, not note text. The three new close-wait tests passed.

## Required suite failure

Exact SDK command:

```powershell
& 'C:\src\flutter\bin\flutter.bat' test --no-pub --concurrency=1 test/storage test/viewmodels test/draft_decision_dialog_test.dart
```

`FN_REHEARSAL_ROOT` selected only the reviewed disposable copy; the variable was
removed in the command's `finally`. The single command completed at 1:17 with
317 passes and eight failures, exit 1. No retry, build or launch followed.

Seven existing lease tests failed:

- owned_note_service_test: lease contention/preparation; thrown release cleanup;
  typed release cleanup; root release/reopen after failure.
- owned_settings_test: lease conflict/no direct-write fallback; thrown release
  cleanup; typed release cleanup.

They expected conflict while reopening the same root through the **same worker**.
Current worker source explicitly aliases that root for independent note/settings
capabilities sharing one store/lease/queue. The observed success is consistent
with that new contract. The tests must check an independent owner's exclusion
without weakening the conflict or cleanup assertions. That correction has not
been applied and independent-owner evidence for these seven scenarios is pending.

The eighth failure was `Windows native destination conflict preserves both
objects`, windows_file_actions_test.dart:62. Expected conflict, actual ioFailure,
message `Native file move failed (Win32 error -1).` Its preceding source and
destination byte assertions passed. Source maps a failed MoveFileExW with a
zero GetLastError result to -1; the loss of that error value is observed.
Interference at the Dart/native boundary is a hypothesis, not a proven cause.
This matches the previously unexplained native-move classification failure;
serial test-file execution did not eliminate it.

Microsoft requires immediate GetLastError capture because other calls can clear
it: https://learn.microsoft.com/windows/desktop/api/errhandlingapi/nf-errhandlingapi-getlasterror
Dart permits leaf FFI only for short, nonblocking calls:
https://api.dart.dev/dart-ffi/Native/isLeaf.html
Any proposed leaf change must apply only to GetLastError, never the potentially
blocking move operation. No native fix has been applied or validated.

## Current boundary

The retained backup and copied-note recovery are validated for the stated checks.
Overall integration validation failed. Original notes, formats, encryption and
the previous executable remain preserved; native-backend activation is off.
The launch script was not invoked. Application closing remains pending a new
build and the user's manual test. Further affected corrections and execution
require the RULESBOOK failure-gate confirmation.

## Approved correction and passing evidence

The user approved the narrow corrections and resumed gate. Seven lease tests
now probe exclusion/reacquisition through independent workers while retaining
their conflict, no-write, cleanup and retry assertions. Production alias
semantics were not changed. Only GetLastError uses leaf FFI, with its accessor
bound before MoveFileExW and its result captured immediately after failure.
The potentially blocking move remains non-leaf; no-replacement flags and
failure/cleanup protections remain unchanged. Twenty distinct destination
conflicts were added to one bounded regression, retaining both objects' bytes.

The activation launcher now requires a zero-exit test receipt bound to current
source, tests, runner, scripts, dependencies and captured configuration hashes.
The passing copied-note rehearsal alone cannot enable a failed candidate.

Formatting, whitespace and launcher parsing passed. Analysis returned 0 with
the same 101 diagnostics (99 info, original two warnings, no errors).
The single affected persistence suite returned 0 at 45 seconds: **130 passed**.
This includes the seven corrected independent-owner scenarios, nine native move
tests with 21 conflict cases, the 46 recoverable-store tests, worker/integration
tests and copied-note rehearsal. Both copied notes again restored prior hashes
after four interruptions. The original failed suite log was retained unchanged;
the other passing checks were not repeated as a full suite. The observed native
classification failure is corrected in these tested cases; the exact runtime
operation that previously cleared thread-local error is not directly traced.

## Native activation and manual handoff

The approved launch script matched the current candidate to its passing receipt,
then confirmed the original library and retained backup still matched the
verified inventory and no project app was running. The single source build/run
using `lib/main.dart` and private recoverable-storage defines succeeded. Windows
Debug compilation took 37.3 seconds. No dependency resolution, duplicate build,
automated input or original-note test edits were performed.

Startup logs contained no errors at inspection. Native process metadata showed
exactly one owned executable, PID 30428, with title “Future Notes”, a nonzero main
window handle and responding state. Working set was 361,492,480 bytes, a point
observation only. The captured original library's writer-lock object was present.
These observations establish process/window startup; they do not prove dashboard
content, editing, latency, continuous-operation or close behavior.

The user has been asked to confirm existing notes visually and manually test a
new synthetic note and one-click closing. Those results are pending. The app
was left running, with no agent input, restart or forced stop. The new backend
is enabled in this admitted executable; default unconfigured builds retain the
old writer. Extended attachment/password/import/export/Delete mutations and
opening another native library remain guarded pending their own integration.
Backups and the previous executable remain retained, with no encryption migration.

## Manual close failure after activation

The user reported that the window remained at “Storage closed. Closing window…”.
The captured launch log records WM_CLOSE handled by Flutter, watcher/storage
cleanup complete at 40 ms, and the dashboard's “returning exit to Windows” log.
No subsequent WM_CLOSE or WM_DESTROY appears in that captured log. The dashboard
callback's result alone does not establish the binding's aggregate exit result
or delivery to the native engine. Closing validation failed; no complete close
fix is claimed. The current app was not interacted with, restarted or stopped.
The backup and previous executable remain retained. Further affected changes
and execution require failure-gate confirmation.

## Analysis-only follow-up

Polling the original session 94245 later returned exit code 0 with additional
WM_CLOSE messages and WM_DESTROY. No agent input or stop was performed. This
confirms eventual native destruction, not one-click close or its latency.
Static inspection found that the shutdown screen removes text-field lifecycle
listeners while Flutter's exit aggregation retains an observer snapshot. Debug
callbacks on those disposed listeners can invalidate the aggregate response.
The evidence, limits and minimal repair proposal are in
CLOSE_HANDOFF_ANALYSIS.md. No diagnostic binding or source correction was
implemented after the user's analysis-only decision.
