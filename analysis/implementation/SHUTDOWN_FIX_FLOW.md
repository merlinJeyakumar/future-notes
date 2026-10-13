# Slow shutdown candidate — implemented, not validated

Date: 2026-10-13. The user asked why the isolated app remains at “Finishing
storage operations…” and requested a fix. The earlier text-probe process did
eventually exit normally; that proves neither acceptable close latency nor
which cleanup stage delayed it. No writer was force-terminated.

## Observed code defects and changes

The dashboard previously awaited watcher cleanup and validation service close
with an unchanged message and no exit-response deadline. Read-only discovery
subscriptions, its worker and debounce/search work stayed active until widget
disposal, which only occurs after successful exit.

The candidate:

- Quiesces discovery/search and cancels their subscriptions before watcher/root
  release, preventing late listing/search work during storage shutdown. The
  stopped scanner is read-only; writer ownership is retained until acknowledgement.
- Tracks one watcher/storage cleanup attempt. A ten-second exit-response timeout
  leaves the window open and the editor non-writable; it does not cancel cleanup
  or start duplicate releases. Repeated close requests join the same operation.
- Shows the current cleanup phase and a slow-close message. Successful late
  completion requests another cancelable Flutter exit after the old response
  finishes. It never forces exit or bypasses other exit observers.
- Retries genuinely failed cleanup stages while retaining completed stages.
  Failures remain sanitized and do not show successful exit.
- Logs only constant phase names and elapsed milliseconds, including note-root,
  settings-root and worker boundaries. No note contents, paths or credentials.

Five controlled cleanup tests and two discovery shutdown regressions are
prepared. They are not run. The Flutter window-exit/late-completion integration
still needs runtime evidence; coordinator tests alone cannot prove it.

## Flow and ownership review

Draft resolution and latest Save acknowledgement still precede service cleanup.
The ten-second limit applies only afterward. Cleanup's owned future survives the
timed exit request. A pending future is never converted into successful cleanup,
and neither timeout nor retries terminate the worker. Normal application storage
activation remains unchanged. No encryption, note format or recovery retention
changes are included.

This repairs the unbounded exit response and live read-only work during cleanup.
The exact native latency source remains pending timed runtime evidence. Do not
claim the observed slow shutdown is fully fixed before the gate passes. A still-
slow stage must be reported accurately and investigated instead of reducing
preservation requirements or removing the close wait.

The unchanged recovery app is currently left running. Previous validated
source/executable checkpoints remain preserved. No new lint/test/build/runtime
gate has executed for this source candidate.
