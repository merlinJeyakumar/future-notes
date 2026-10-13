# Focused text-injection probe — approved; insertion failed

Date: 2026-10-13. Ordinary `press_key(a)` and the candidate Ctrl+A probe left
physical typing/deletion/undo working, with no new logged assertions. The
earlier `type_text` path remains an untested candidate. No permanent producer
correction is claimed.

Use the existing healthy isolated process, not another simultaneous app:

1. Preserve current edits using visible Save and successful draft resolution.
   Open a new blank draft using the observed New Note control. Stop on failure;
   never discard or alter an existing note for the probe.
2. Click the blank draft title, refresh and verify visible caret/focus.
3. Call exactly once `sky.type_text({window: observedWindow, text: 'x'})`, bounded
   to 30 seconds. Refresh and inspect attached logs. No shortcut injection,
   refocus/retry or second text call. Failure or ambiguity ends diagnostic input.
4. Have the user check physical Backspace/typing/undo. Success means only that
   this single call did not reproduce the bug; no helper correctness claim.
5. If input or logs fail, use explicit conditional containment: preserve the
   synthetic draft through visible Save, close normally, join the same process
   and session, require zero instances and unchanged executable/kernel hashes,
   then launch the unchanged isolated binary once with SDK-cache access. Stop
   if preservation or close fails. No force termination, discard or SDK edit.
   Ask for physical input confirmation after visible startup and leave one app
   running. Do not continue diagnosis after failure.

Exact conditional recovery command, from the project root:

```powershell
if (@(Get-Process -Name flutter_application_1 -ErrorAction SilentlyContinue).Count -gt 0) {
  throw 'A project app is already running; no second instance will be launched.'
}
& 'C:\src\flutter\bin\flutter.bat' run -d windows --debug --no-pub --no-hot -t lib/validation_main.dart --use-application-binary='D:\Project\NativeDevps\future-notes\build\windows\x64\runner\Debug\flutter_application_1.exe'
```

Risk: text injection may disable editing again until normal restart. Approval
must cover that limited probe and its conditional recovery. No rebuild,
lint/suite rerun, real-note access, attachment/password/package/Delete workflow,
source correction or real-library activation. Preserve stable checkpoints.
RULESBOOK.md requires exact-command approval before runtime validation; the
completed producer gate explicitly excluded `type_text`.

The user approved this gate. The single focused call returned normally but
inserted no character; log inspection contained no assertion. Diagnostic input
stopped and the approved normal-close/relaunch containment completed. See
[KEYBOARD_TEXT_RESULTS.md](KEYBOARD_TEXT_RESULTS.md).
