# Clean-input repair gate — manual input restored

Date: 2026-10-13. See [KEYBOARD_RESTART_GATE.md](KEYBOARD_RESTART_GATE.md).

## Completed actions

- Reidentified the existing isolated process/window, PID 20220. An uncommitted
  Set Password dialog was open; Cancel dismissed it without submitting a
  password or exercising a protection-change workflow.
- Clicked the visible Save Note control. No failure was displayed. A completed
  transaction and note object already existed in the isolated second library;
  this does not by itself prove that the click performed another write.
- Requested normal Windows close. The dashboard entered “Finishing storage
  operations…”, which follows successful draft resolution in `_resolveExit`.
  Waited on the same process and attached Flutter session, without force-killing
  or starting a second instance.
- The original session completed with exit 0 and “Lost connection to device.”
  A subsequent process check confirmed no project app remained.
- Rechecked the executable/kernel hashes recorded in the gate; both matched.
  Required Flutter DLL/ICU files were present.
- The first exact approved prebuilt, `--no-hot --no-pub` attempt initially
  printed no output and produced no app window. No build was observed.

## Historical bootstrap wait

At the stopping point, command session 40083 remained live. Read-only
process inspection found launch PowerShell PID 48536 and its child `cmd.exe`
PID 55732, both created at 16:32:56 Asia/Calcutta. No associated Dart child or
project app was present. PID/ownership must be refreshed before any cleanup;
these are observations, not reusable termination authority.

The installed `bin/internal/shared.bat` repeatedly tries to open
`bin/cache/flutter.bat.lock` for writing under suppressed stderr before starting
Dart. The launch used the default restricted execution context, where the SDK
is outside the writable roots. A denied cache-lock open is the leading
explanation for the silent bootstrap wait; the actual native open error was
not captured. Read-only CIM inspection initially required escalation and then
succeeded. No SDK files or lock files were changed or removed by diagnosis.

The original gate excluded forced termination, so helper cleanup and SDK-cache
access retry required separate confirmation. That confirmation was obtained
before the actions below. The original app had already exited normally.

## Approved helper cleanup and fresh startup

The user approved identity-checked termination of that helper and the same
prebuilt launch with SDK-cache access. `Stop-Process -Id 55732` failed with
“Object reference not set to an instance of an object.” Read-only inspection
confirmed unchanged ownership. The authorized helper cleanup then succeeded
with `taskkill /PID 55732 /F`; session 40083 ended with exit 1. No app process
was terminated. Binary identity and zero project instances were rechecked.

The exact prebuilt command in the gate then launched with SDK-cache access,
without build output. Session 99752 attached to one new app, PID 29396,
started at 16:41:12 Asia/Calcutta. The foreground Future Notes dashboard was
visibly observed. No automated keyboard input was sent to this process.

## Physical-key acceptance

The user confirmed “All listed key checks work” for:

- Editor typing, two Backspaces after three characters, Delete and selection
  deletion.
- Ctrl+Z undo and title-field Backspace.
- The same behavior after opening/closing Settings and refocusing the editor.

Attached Flutter output contained no new keyboard assertions after those checks.
The latest process observation found exactly one responding project app:
working set 434835456 bytes and private memory 369803264 bytes. These are Debug
snapshots, not memory-growth, latency, frame-time or continuous-use benchmarks.
The isolated app remains running.

The validation settings file still acknowledges the second-library selection.
Validation startup deliberately clears the copied custom path and binds to the
embedded explicit first-library root. The second-library note remains stored;
the different startup listing is not evidence of note loss. No notes were moved
or deleted, and no original-library content was accessed.

## Result and remaining scope

Normal physical editing is restored and validated by the user in the fresh
process, with clean logs. The unchanged application handles Backspace correctly
in this comparison. The malformed event/replay failure mechanism is documented
in [VALIDATION_KEYBOARD_ROOT_CAUSE.md](VALIDATION_KEYBOARD_ROOT_CAUSE.md).

The exact initiating automation operation remains unconfirmed and has not been
fixed. Keep automated keyboard injection excluded from this Flutter validation
path. Use manual physical input; mouse-only observation may continue within
its approved scope. Do not suppress assertions, reset framework key state, or
patch the editor without new evidence. A controlled producer reproduction would
need a separate authorized runtime gate and disposable data.

No application/SDK/dependency changes, repeated lint/tests/builds or real-library
activation occurred. Preserved source/executable checkpoints remain untouched.
The broader 30-minute acceptance and performance checks remain pending.
