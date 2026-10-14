# Isolated application gate — static/build passed, runtime partial

Date: 2026-10-13. Branch `development`, HEAD
`a9f6d247d7e27322d4afe542aa27240c72af031e`.
Gate: [VALIDATION_APP_GATE.md](VALIDATION_APP_GATE.md).

## Observed results

- Approved formatter: exit 0, five files checked, four formatted.
- `git diff --check`: exit 0; existing generated-file line-ending notices only.
- `flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings`: exit 0,
  exactly 97 diagnostics (95 info, original two warnings, no errors).
  Normalized diagnostic messages/rules match the previous baseline exactly.
- `flutter test --no-pub`: exit 0, all 346 registrations passed in 22 seconds.
  This includes the nine application-composition regressions.
- Single-instance and unused runtime-directory checks: passed.
- Approved `flutter run -d windows --debug --no-pub -t
  lib/validation_main.dart` with the explicit gate defines: Windows Debug build
  succeeded in 24.2 seconds. One app process/window appeared.
- After explicit foreground activation, the Future Notes dashboard was visible
  with an empty isolated library. No startup error appeared in the observed
  Flutter output. Initial capture showed an occluding browser; it was not
  accepted as app visibility evidence and was not retained as an artifact.

## Runtime blocker

The Windows automation helper's first title `set_value` attempt reported:
`element 7 is not available in cached app state for flutter_application_1.exe`.
State was refreshed and coordinate-based title focus was confirmed visually.
An observed focused title edit was followed by `type_text` of synthetic text;
its value remained `New Note`. One refocus/retry also left the same value.
The helper reported no error for those typing actions. Their input outcome
cannot be accepted as successful.

Cause is unconfirmed: this evidence does not distinguish application behavior
from the automation helper/input path. No production correction or further
workflow validation follows this failure without confirmation. No note Save,
Delete, password, import/export or original-note access occurred. The isolated
library contains only its writer-lock file at the stopping point.

The app remains running, PID 20220, in the approved disposable environment.
The Flutter command session remains attached; no second instance was launched.
Last process snapshot: responding true, 38 threads, 379445248 working-set bytes,
321806336 private bytes, 6.296875 cumulative CPU seconds. Initial snapshot was
367284224 working-set bytes and 317665280 private bytes. Approximately 158
seconds elapsed between the first state/metrics observation and the stopping
snapshot. These are Debug process observations, not latency or frame benchmarks.

Save/autosave/reopen, watcher/library switching, native close cancellation,
shutdown joins, 30-minute continuous mixed use and performance targets remain
pending runtime evidence. Real-library activation remains disabled. Previous
validated source/executable checkpoints are preserved; the runtime-blocked
candidate has not been promoted over them. No redundant suite/build was run.

## Approved key probe and conditional runtime resumption

The user approved one ordinary `a` key probe and conditional continuation of
the original isolated checks. With freshly observed title focus, `press_key(a)`
changed the displayed title from `New Note` to `New Noate`. The earlier text
injection limitation remains open; this establishes a working ordinary-key path,
not a complete explanation of the helper behavior.

The same process/window stayed running. No source correction, lint/test/build
rerun, restart or second instance occurred. Observed checks on synthetic data:

- A changed never-saved title/body created no note before explicit first Save.
- First Save produced a canonical note, transaction receipt and sidebar item.
- A rich-text body edit autosaved: ciphertext SHA-256 changed and the receipt
  count advanced from one to two. Navigation away and reopen restored the edit.
- A title-only edit produced a third receipt and updated the sidebar title.
- Normal Windows close with a dirty new draft opened Save/Discard/Cancel.
  Cancel retained the visible window, process and draft. The retained draft
  was then explicitly saved as a second synthetic note.
- Native folder selection switched to the disposable `second-library`.
  Settings on disk acknowledge that path, the sidebar became empty, and the two
  existing synthetic notes stayed in the first library. No notes were moved.

## Keyboard assertion — resumed validation stopped

The subsequent log inspection exposed a Flutter services-library assertion
during a platform message callback:

```text
A KeyUpEvent is dispatched, but the state shows that the physical key is
pressed on a different logical key.
Failed assertion: line 527 pos 11:
'_pressedKeys[event.physicalKey] == event.logicalKey'
```

The event reported physical key `0x1600000000`, logical `Control Left`, and
recorded logical `A`. Repeated following diagnostics reported:

```text
Unable to parse JSON message: The document is empty.
A KeyDownEvent is dispatched, but the state shows that the physical key is
already pressed.
```

The stack enters `HardwareKeyboard.handleKeyEvent`, platform channels and
`PlatformDispatcher._dispatchPlatformMessage`. Read-only inspection of the
installed SDK at `packages/flutter/lib/src/services/hardware_keyboard.dart`,
lines 510–536, confirms these are physical/logical event consistency checks.
No `HardwareKeyboard`, `RawKey`, `WM_KEY` or `WM_CHAR` override was found under
the app's `lib` or Windows runner. That does not prove the assertion's origin;
automation, framework and native event handling remain to be distinguished.
No assertion suppression, framework patch or production correction was made.

Runtime work stopped on observing these errors. Roughly 550 seconds of resumed
interaction elapsed before the stopping metrics snapshot; this is not a completed
30-minute test. Latest snapshot: PID 20220, responding true, 42 threads,
467763200 working-set bytes, 360673280 private bytes and 73.171875 cumulative
CPU seconds. These snapshots do not establish a leak, latency or frame targets.

The isolated app is left running with Settings open on the second library.
Further input/runtime validation requires confirmation. Search, switching back,
watcher recreation, completed shutdown, 30-minute mixed use and performance
measurements remain pending. Original notes were never accessed. The unfinished
attachment/password/package/Delete workflows and real-library activation remain
disabled/pending; existing validated source/executable checkpoints are preserved.

## Manual Backspace report and read-only diagnosis

The user reports that manual typing works, but the physical Backspace key does
nothing. Read-only SDK/editor inspection identifies the failing key-batch replay
and explains why native text entry can still work. See
[VALIDATION_KEYBOARD_ROOT_CAUSE.md](VALIDATION_KEYBOARD_ROOT_CAUSE.md) for the
source trace, zero-scan physical identity and bounded attribution. The initiating
input producer is not established; a clean manual-input process comparison has
not run. No further automated keys, source edits, tests/builds, restart or real
library activation occurred during this diagnosis.

## Approved clean-input restart result

The old app closed normally after draft resolution. One unchanged prebuilt
isolated instance opened after identity-checked bootstrap-helper cleanup and an
approved SDK-cache-access retry. The user confirmed all requested physical-key
checks work, including title/editor Backspace, Delete, selection deletion, undo
and Settings/focus transitions. Fresh logs showed no keyboard assertions.
The app remains running; no automated keys were sent to this process.

Manual input is restored. The exact initiating input producer remains
unconfirmed; automated keyboard injection stays excluded from this validation
path. See [KEYBOARD_RESTART_RESULTS.md](KEYBOARD_RESTART_RESULTS.md) for the
command, preservation, startup and resource evidence. No source/build change,
repeated tests or real-library activation accompanied this check. Broader
continuous-use/performance acceptance remains pending.
