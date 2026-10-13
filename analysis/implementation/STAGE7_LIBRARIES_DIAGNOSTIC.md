# Bounded library-switch diagnostic

Status: diagnostic reproduced the stall; no correction or integration validation
is claimed. Production code was not changed in this diagnostic.

The user explicitly approved test-only phase labels and these commands, from
`D:\Project\NativeDevps\future-notes`:

```powershell
& 'C:\src\flutter\bin\dart.bat' format test/viewmodels/library_switch_test.dart
git diff --check
& 'C:\src\flutter\bin\flutter.bat' analyze --no-pub --no-fatal-infos --no-fatal-warnings
& 'C:\src\flutter\bin\flutter.bat' test --no-pub test/viewmodels/library_switch_test.dart --plain-name 'candidate preparation precedes durable settings and old-root release' --timeout 30s
```

| Check | Observed result |
| --- | --- |
| Format | Exit 0; one file changed |
| Whitespace | Exit 0; existing generated-file CRLF notices only |
| Analysis | Exit 0; 97 diagnostics: 95 info, original two warnings, no errors; no diagnostic in the changed test |
| Single named test | Stalled with zero completed tests; interrupted, exit 1 |

The runner reported `00:28 +0` when interruption marked the test incomplete.
The overall tool elapsed time was approximately 35 seconds including approval,
startup and interruption handling; the terminal returned a batch-termination
prompt, which was answered to finish the owned diagnostic command. Flutter also
reported a temporary listener `PathNotFoundException` during interrupted
finalization. That cleanup error does not identify the original stall.

Sanitized phase evidence (no note data, credentials or storage paths):

```text
library-switch diagnostic: fixture construction begin
library-switch diagnostic: settings init
library-switch diagnostic: fixture construction complete
library-switch diagnostic: initial pump begin
library-switch diagnostic: reader init
library-switch diagnostic: current library
library-switch diagnostic: watch open begin
library-switch diagnostic: watch open complete
library-switch diagnostic: discovery request
library-switch diagnostic: initial pump complete; body begin
library-switch diagnostic: load begin
library-switch diagnostic: load complete
library-switch diagnostic: listing publish begin
library-switch diagnostic: listing pump complete
library-switch diagnostic: switch begin
library-switch diagnostic: settings init
library-switch diagnostic: current library
library-switch diagnostic: candidate prepare begin
library-switch diagnostic: candidate prepare complete
library-switch diagnostic: watch open begin
library-switch diagnostic: watch open complete
library-switch diagnostic: settings commit begin
library-switch diagnostic: settings commit complete
library-switch diagnostic: library publish
library-switch diagnostic: watch close
```

The test reached load, listing publication, candidate preparation, settings
acknowledgement and library publication. Its last marker is watcher close.
The switch did not return, and body assertions, finally disposal and teardown
were not reached. The exact stalled continuation remains unconfirmed; these
markers do not prove that watcher close itself is the cause.

No additional test, full suite, Windows build or app launch followed the failure.
The previously validated source/executable remains preserved. Existing notes
were not read or changed. Further correction or diagnosis needs confirmation
under RULESBOOK.md.

## Approved fake-clock probe

The user approved changing only the first scenario to start the switch, pump
50 times at 20 ms and assert completion before retaining its original assertions.
The same four approved commands ran once for that test-only change.

Formatting and whitespace passed. Analysis exited 0 and reported 97 diagnostics.
The named test exited 1 without interruption (4.85 seconds command wall time):

```text
Expected: not null
Actual: <null>
Switch did not complete within one second of fake time.
```

The failure is at library_switch_test.dart:72. The switch reached library
publication, but no watcher-close marker appeared during the fake-clock loop.
The two watcher-close markers appeared after the assertion failed and the
framework began finalization. All labelled teardown phases, including the
disposable-directory cleanup, completed. No runner cleanup exception occurred.
This is evidence against a missing fake timer advance as the sole explanation;
the original success/preservation assertions were not reached.

Read-only SDK inspection then identified a relevant scheduling boundary:

- async/stream_impl.dart:232-240: cancellation falls back to Future._nullFuture.
- async/broadcast_stream_controller.dart:230-245: broadcast cancellation removes
  its listener synchronously and returns null to that fallback.
- async/future.dart:230-235: the shared null future uses the root-zone future.
- internal/internal.dart:160: nullFuture is explicitly created with Zone.root.run.
- async/future_impl.dart:525-545: late future listeners use the future's zone
  to schedule their continuation.
- flutter_test/src/binding.dart:1968-2040: runAsync explicitly permits real
  microtasks/timers; reentrant calls are forbidden.

The coordinator awaits the old subscription cancellation before closing its
watcher. The observed pending switch and post-finalization close markers are
consistent with the root-zone continuation waiting outside fake async. This
is a source-backed explanation, not validation of a correction.

Proposed harness correction: retain operation creation and timers in fake async,
but join cancellation-dependent operations through a shared bounded helper that
allows a real event-loop turn using runAsync, then pumps fake microtasks. Keep
controlled race ordering, fake-time watcher debounce and all existing outcome/
preservation assertions. Remove the temporary diagnostic/probe code. Production
code remains unchanged.

The user subsequently approved that join and then moving its cleanup acknowledgement
into the active test body. The final gate passed all 337 tests, unchanged analysis
and Windows Debug build. Historical failures above remain diagnostic evidence;
the final correction is no longer pending approval. See
[STAGE7_LIBRARIES_RESULTS.md](STAGE7_LIBRARIES_RESULTS.md).
