# Keyboard producer diagnostic results

Date: 2026-10-13. Gate: [KEYBOARD_PRODUCER_GATE.md](KEYBOARD_PRODUCER_GATE.md).

## Preservation and launch

- Reidentified the current project process, PID 29396, and its returned window.
- The first accessibility-index Save target was unavailable in the helper's
  cached state. Refreshed the screenshot and clicked its observed Save control.
  No save error appeared. Normal close entered “Finishing storage operations…”.
- Session 99752 then ended with exit 0, “Lost connection to device.” Process
  inspection found zero project instances. No force termination or discard.
- Executable and kernel SHA-256 still matched KEYBOARD_RESTART_GATE.md.
- The approved prebuilt command with SDK-cache access opened one visible fresh
  dashboard with a never-saved blank draft. No build occurred.
- New session 47155, PID 38080, started 16:57:53 Asia/Calcutta. Initial responding
  process snapshot: working set 366415872, private memory 312500224 bytes.
  These are Debug snapshots, not performance acceptance.

## Two separate input observations

The screenshot showed a title caret before the ordinary-key probe, although
initial accessibility focus reported a pane. Only the fresh synthetic draft
was targeted; existing note contents were not changed by either probe.

1. `sky.press_key({window: observedWindow, key: 'a'})` changed the synthetic
   title from `New Note` to `New aNote`. Refresh confirmed the title edit field
   was focused. Attached log inspection returned no new output/assertions.
2. `sky.press_key({window: observedWindow, key: 'Control_L+a'})` returned
   normally; refreshed title stayed unchanged. Accessibility did not expose
   selected text, and the screenshot did not establish full-title selection.
   Attached log inspection returned no new output/assertions.

No further automated key, `type_text` or `set_value` was sent. The chord's
selection outcome is inconclusive; do not call it successful. The earlier
malformed-sequence failure did not reproduce in these two logged observations.
This does not rule out deferred failure, interaction with other input APIs,
focus transitions or a different native event producer.

## Current status

The user confirmed “All still work” for physical title/editor Backspace, typing
and undo after both probes. Subsequent attached logs contained no new assertions.
No recovery restart was needed; the same single process remains running.
The approved two-probe gate is complete. The earlier `type_text` path was not
tested by this gate, and the modifier chord's selection effect is still
inconclusive. A new text-injection probe needs its own scoped approval.

No source/SDK/dependency changes, repeated lint/tests/builds, real-library
activation or original-note access. Last validated checkpoints remain untouched.
The exact initiating automation operation and its permanent correction remain
unconfirmed; no root-cause fix is claimed.
