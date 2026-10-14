# Keyboard failure repair — first execution gate

Prepared 2026-10-13. Approved and completed: one unchanged prebuilt instance
opened, and the user confirmed all requested physical-key checks pass. See
[KEYBOARD_RESTART_RESULTS.md](KEYBOARD_RESTART_RESULTS.md) for evidence and the
remaining input-producer uncertainty. Goal: restore and verify physical
Backspace behavior without sacrificing the current draft or accessing real notes.

## Evidence captured before restart

- Branch `development`, HEAD `a9f6d247d7e27322d4afe542aa27240c72af031e`.
- The existing isolated process is PID 20220, started 2026-10-13 at 15:49:16
  Asia/Calcutta, with the project Debug executable. Recheck before interaction;
  do not act on a reused PID or an unrelated window.
- The current source/build previously passed 346 tests and the retained analyzer
  baseline. Runtime acceptance remains partial because of the keyboard failure.
- The executable SHA-256 is
  `931C7D6D2A6639316749438A0CD7C66422663F6486FE7E575B1ADDE207F89080`.
- Its `data/flutter_assets/kernel_blob.bin` SHA-256 is
  `50B5ACAEB25141709AC7595197B9ECDF9BA580303BDDECF3561FF3BC77D475C6`.
  Both were read from the current build during this gate preparation. These
  hashes identify this candidate, not a claim of complete runtime validation.

The compiled validation entry point requires explicit isolated settings and
library paths under `.validation/future-notes-validation-runtime-20261013a`.
The prebuilt launch reuses those embedded defines; it cannot accept new storage
locations through runtime `--dart-define` arguments. Normal application startup
and real-library activation are outside this gate.

## Approved actions

1. Observe the uniquely matched existing app window with the computer-use skill.
   No automated keyboard input. Preserve any current edits through the visible
   Save control and confirm success before requesting normal Windows close.
   Stop if Save fails, a password is required, ownership is ambiguous or cleanup
   fails. Never discard the draft or force-kill the process.
2. Confirm the same old process and Flutter run session terminate normally. A
   timeout is not permission to restart; recheck the same handles. Refuse a
   second instance while any project app remains running.
3. Recheck the executable/kernel hashes above and support-file availability;
   stop on a mismatch. Launch the unchanged candidate once with the command
   below. Source inspection of the installed Flutter tools confirms that a
   prebuilt Windows executable skips `buildForDevice`. `--no-hot` also avoids
   introducing hot-reload state into this comparison.
4. Confirm visible startup and inspect the new log session. Have the user enter
   synthetic characters manually in the title and rich editor, then use physical
   Backspace/Delete, selection deletion and undo. Repeat after closing Settings
   and restoring editor focus. Do not send `type_text`, `press_key`, Ctrl+A or
   other keyboard injection through automation. Observe UI outcomes and logs.
5. Stop on the first input/assertion failure and record it. If clean manual input
   works, retain manual keyboard interaction for Flutter runtime validation and
   classify automation attribution as suspected until a controlled producer
   reproduction identifies it. If it fails, prepare the minimal diagnostic
   target or smallest evidenced application correction for its own lint-first
   execution gate. Do not silently proceed to SDK edits or upgrades.

## Exact launch command

From `D:\Project\NativeDevps\future-notes`, after safe normal shutdown and the
read-only identity checks:

```powershell
if (@(Get-Process -Name flutter_application_1 -ErrorAction SilentlyContinue).Count -gt 0) {
  throw 'A project app is already running; no second instance will be launched.'
}
& 'C:\src\flutter\bin\flutter.bat' run -d windows --debug --no-pub --no-hot -t lib/validation_main.dart --use-application-binary='D:\Project\NativeDevps\future-notes\build\windows\x64\runner\Debug\flutter_application_1.exe'
```

This gate contains no source edits, dependency resolution, formatter, analyzer,
test-suite rerun, Windows rebuild, force termination or real-note access. Leave
the fresh isolated app running after a successful check. Preserved stable
source/executable checkpoints remain untouched. This is the discriminating
runtime step, not a completed repair or the 30-minute acceptance test.

RULESBOOK.md requires: “Before builds, tests, device/emulator validation, CI, or
production actions, state the exact command and wait for approval” and “If
validation fails, stop affected work and report the exact command and failure.
Ask for confirmation before proceeding”. The existing runtime failed; the
request to fix authorizes preparation, but not this new exact execution gate.
