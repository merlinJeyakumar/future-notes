# Focused text-injection diagnostic

Date: 2026-10-13. Approved [gate](KEYBOARD_TEXT_GATE.md).

## Observations

- Reidentified the one healthy isolated process, PID 38080, session 47155.
- Visible Save preserved the current synthetic edits; the sidebar gained their
  note entry. New Note then opened a blank draft without a failure or decision
  dialog. Do not include the user's test text in this report.
- Clicked its title and refreshed. Screenshot showed the caret, and focus
  metadata identified the `New Note` title edit field.
- Called exactly once `sky.type_text({window: observedWindow, text: 'x'})`.
  The helper returned normally. The subsequent focused title value remained
  `New Note`; the screenshot showed no inserted character.
- Attached logs returned no new output/assertion. This reproduces silent text
  insertion failure, not the earlier malformed A/Control sequence or physical
  Backspace failure. No further injected text or key was sent.

## Approved containment

Diagnostic input stopped. The unchanged blank draft had no new content to
retain. Its visible Save returned “The new draft is empty.” This is an empty-
draft admission result, not a failed I/O commit; the earlier edits had already
been saved before the probe. Normal close resolved that unchanged draft without
discarding edits and entered “Finishing storage operations…”.

Session 47155 eventually ended with exit 0, “Lost connection to device.” A
process check confirmed zero project instances. No force termination occurred.
The prolonged cleanup wait prompted the user's new request to fix the shutdown
screen. Its exact delayed stage was not instrumented in the old binary.

Executable/kernel identities matched the recorded gate. The approved prebuilt
recovery then launched one visible fresh isolated dashboard, session 62965,
PID 75712, started 17:08:09 Asia/Calcutta. No keyboard injection was sent to it;
attached logs showed no new assertion. Manual input confirmation remains pending
while work follows the user's shutdown-fix steering.

## Interpretation

`type_text` failed to insert into the observed focused Flutter title while
ordinary `press_key(a)` previously inserted text and manual input worked. The
supported text API is unsuitable for this workflow on the observed target.
The failure does not establish whether it produced invalid keyboard identities;
no such diagnostic appeared during this probe. The exact producer of the older
Backspace failure remains unresolved. No app/framework patch is justified yet.

No executable-code, dependency or SDK changes; no repeated tests/lint/builds,
force termination, real-note access or real-library activation. Checkpoints
remain preserved.
