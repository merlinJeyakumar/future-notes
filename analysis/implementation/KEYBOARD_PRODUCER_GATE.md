# Keyboard producer reproduction — approved; probes executed

Prepared 2026-10-13. Manual keys pass in the unchanged fresh isolated process;
the exact operation that initiated the earlier malformed sequence is unresolved.
This gate identifies the next minimal runtime evidence. It is not an app patch.

## Static flow review

The existing runner creates Flutter's native child view and focuses that child
in `windows/runner/win32_window.cpp`. Installed engine source processes key
messages in `FlutterWindow::HandleMessage`,
`C:/src/flutter/engine/src/flutter/shell/platform/windows/flutter_window.cc`,
lines 748–756, through the keyboard manager. The legacy channel serializes the
received scan code in `keyboard_key_channel_handler.cc`, lines 136–138.
Changing only the runner's top-level message handler would not repair this
child-window input path. No runner/framework correction is justified yet.

The supported Computer Use API documents `press_key(a)` and
`press_key(Control_L+a)`. The ordinary-key probe previously changed the title;
later logs showed conflicting A/Control identities without an operation-by-
operation attribution. The chord is a candidate reproduction, not a proven
cause. An ordinary key and a modifier chord need separate observations. Do not
inspect helper internals or add another Windows input injector.

## Preservation and runtime sequence

Risk: the suspect chord can poison key dispatch again. Use only the isolated
build and a fresh never-saved blank draft, never an existing note as the input
target. Existing original notes remain inaccessible to this validation build.

1. Reidentify the one currently running project process/window. Preserve its
   current draft through visible Save and successful transition resolution.
   Close normally and join the same process/session. If Save or normal close
   fails, stop; no force termination or second instance.
2. Recheck executable/kernel identity from KEYBOARD_RESTART_GATE.md. Require
   zero project instances. Run the exact prebuilt command below with SDK-cache
   access. This reuses embedded isolated paths and does not rebuild.
3. Verify visible startup and clean logs. Select and focus the observed blank
   draft title with the computer-use skill. Do not copy or report user text.
4. Send exactly one `sky.press_key({window: observedWindow, key: 'a'})`.
   Refresh the focused title and inspect the attached Flutter log. Stop on an
   assertion, failed input, ambiguity or timeout; do not retry the injected key.
5. Only if step 4 succeeds with clean logs, send exactly one
   `sky.press_key({window: observedWindow, key: 'Control_L+a'})` to that same
   synthetic title. Refresh, inspect selection where exposed and inspect logs.
   Record which single operation first fails, including numeric physical/logical
   identities. Do not send another automated key or use `type_text`/`set_value`.
6. Stop diagnostic input after those two operations, whether failure occurs or
   not. No speculative app/SDK correction, further probe, lint/test/build follows.
   A passing result is only non-reproduction, not proof the helper is correct.

## Explicit recovery after reproduction

Approval for this gate must also cover recovery if a probe fails: preserve the
synthetic draft with the visible Save control, close normally, join the same
process/session, recheck identity/zero instances, and launch the same prebuilt
command once with SDK-cache access. This recovery is containment, not permission
to continue failed diagnosis. If preservation or close fails, stop and report;
never force-kill the app or silently discard edits. If the probe passes, leave
that process running and do not perform a redundant restart.

Have the user confirm physical typing/Backspace/undo in the resulting healthy
window. Observe logs and leave exactly one isolated app running. Record startup
and process resource snapshots without claiming performance targets. The broader
30-minute mixed-use acceptance remains outside this diagnostic gate.

## Exact command for diagnostic launch and conditional recovery

From `D:\Project\NativeDevps\future-notes`, after each successful normal close
and identity check:

```powershell
if (@(Get-Process -Name flutter_application_1 -ErrorAction SilentlyContinue).Count -gt 0) {
  throw 'A project app is already running; no second instance will be launched.'
}
& 'C:\src\flutter\bin\flutter.bat' run -d windows --debug --no-pub --no-hot -t lib/validation_main.dart --use-application-binary='D:\Project\NativeDevps\future-notes\build\windows\x64\runner\Debug\flutter_application_1.exe'
```

At most two launches: diagnostic, then recovery only if needed. Bound each input
call to 30 seconds; timeout means unknown outcome, not terminal app state.
Reobserve the same window/session and do not repeat input. Do not terminate an
unexpected stalled launcher without refreshed ownership and appropriate approval.

## Approval source and pending status

RULESBOOK.md requires “Before builds, tests, device/emulator validation, CI, or
production actions, state the exact command and wait for approval”. The prior
clean-input gate expressly excluded automated keys. This document requests a
new exception solely for these two controlled probes and their stated recovery.
Preserved source/executable checkpoints stay untouched. No real-library
activation, package/protection/attachment/Delete workflows or repeated suite
are included. The user approved this gate. Both probes executed with no logged
assertion; the user confirmed physical input still works afterward. See
[KEYBOARD_PRODUCER_RESULTS.md](KEYBOARD_PRODUCER_RESULTS.md).
