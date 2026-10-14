# Shutdown candidate — resumed validation

Date: 2026-10-13. The user approved SHUTDOWN_FIX_GATE.md.

The six-path formatter passed (six files inspected, five formatted). `git diff
--check` passed; generated platform files emitted line-ending notices only.

The following required command failed, exit 1, after 135.6 seconds:

```powershell
& 'C:\src\flutter\bin\flutter.bat' analyze --no-pub --no-fatal-infos --no-fatal-warnings
```

Analysis reported 98 diagnostics: the previous 95 informational diagnostics,
the original two warnings, and one error:

```text
test/storage/validation_app_services_test.dart:73:18
undefined_getter: The getter 'ownerRoot' isn't defined for the type 'NoteReference'.
```

Inspection confirms the existing reference API declares `storageOwner`, not
`ownerRoot`. The failing assertion checks ownership after an acknowledged
synthetic write. Correcting its field name would preserve that assertion's
purpose without changing production code. The origin of this test mismatch
relative to earlier reported validation is not established.

The suite, compilation, candidate launch and shutdown timing checks did not run.
The candidate remains unvalidated. The unchanged isolated app and preserved
source/executable paths remain available. No original notes were accessed.

The user subsequently approved the test-only field correction and resumption.
The assertion now uses `saved.storageOwner`; production code was unchanged by
this correction. Formatting and whitespace passed. The same nonfatal analyzer
command returned 0 after 3.9 seconds: 99 diagnostics, 97 info, original two
warnings, no errors. Formatting exposed two pre-existing brace-style statements
in this test file; no new warning or error appeared.

The single approved `flutter test --no-pub` suite returned 0 with all 353 tests
passing in 17 seconds. This includes the five shutdown-sequence regressions and
two discovery-close regressions. No duplicate focused suite or build ran.

The existing isolated app was observed on a blank draft. Its visible Save action
reported “The new draft is empty.” A normal window-close request entered the old
binary's “Finishing storage operations…” screen. The same command session
62965 remains live; no force termination, restart or second instance occurred.
Candidate build/startup/shutdown timing validation must wait for normal exit.

Repeated observations of this same session across several minutes still show
pending cleanup and no additional logs. The process is confirmed live and
responding: PID 75712, exact project Debug executable, start time
`2026-10-13T11:38:09.3930542Z`. The last observed working set was 367,607,808 bytes
and private memory 311,599,104 bytes. These are point observations, not a profile.
The delayed stage remains unconfirmed in the old binary. This is a runtime
handoff blocker, not a failed timing measurement of the unlaunched candidate.

The approved gate excludes forced termination. No candidate build or launch
can proceed while the old instance retains its resources. A separate narrow
approval is requested to terminate only this exact isolated process after
rechecking its identity, join its original session, then resume the already
approved build/runtime gate. Such termination can interrupt old cleanup; no
original library is involved, the draft was confirmed empty, and prior binaries
remain preserved. At that observation no termination had been performed.

The user approved the exact identity-checked stop and continuation. PID, path
and start time were rechecked. The restricted attempt returned “Access is
denied”; the same approved command with elevated access returned 0. Session
62965 then ended with “Lost connection to device”, exit 0. This was a forced
termination, not successful orderly cleanup. Zero project processes were
confirmed before the candidate's single build/launch command began (session
56635). No repeated lint/tests or automated keys ran. Ownership and release
followed the local release-chat-processes skill; unrelated processes were not
targeted. Candidate startup and timing results were pending at that point.

## Candidate runtime failure

The single approved source build/launch succeeded: Windows Debug compilation
took 18.8 seconds. One visible dashboard window opened with clean startup logs.
Its process was PID 77620, start time `2026-10-13T12:11:01.0118964Z`. Startup
working set was 367,169,536 bytes, private memory 314,380,288 bytes; these are
point observations only.

One normal Close action on the unchanged blank draft produced:

```text
Storage shutdown: watchers at 0 ms
Storage shutdown: storage at 7 ms
Storage shutdown: note roots at 0 ms
Storage shutdown: settings root at 43 ms
Storage shutdown: worker at 44 ms
Storage shutdown: complete at 53 ms
```

The dashboard showed “Storage closed.” The window and process still existed
38,849 ms after the close request, exceeding the gate's ten-second limit. The
same session 56635 remained live and responding with no later error logs.
Therefore runtime exit validation FAILED. Cleanup completion is observed; the
remaining exit-response/window-destruction path is unconfirmed. Do not describe
this candidate as a successful shutdown repair or attribute the remaining delay
to note storage.

Runtime work stopped at this failure. No second Close action, forced termination,
reopen, repeated compilation or source correction followed. At that point the isolated
candidate remained open on its non-writable completed-cleanup screen. Original
notes and previous checkpoints remain preserved. Further diagnosis/correction
requires confirmation under RULESBOOK.md.

## Subsequent manual result and current disposition

Before the approved exit-trace work began, session 56635 was observed terminal
(exit 0, “Lost connection to device”) and zero project processes were found.
No second Close or forced termination was performed by the agent. The cause of
that eventual exit was not established.

The user then requested manual testing and explicitly stopped agent testing.
No exit-trace source changes, diagnostic compilation or further runtime input
were performed. The user subsequently reported that typing and closing worked
perfectly in the normal run, and suggested the discrepancy might involve the
agent/sandbox run.

Manual typing/closing acceptance is user-confirmed. The earlier automated exit
failure remains recorded; manual elapsed times and long-run behavior were not
measured. An automation, launcher or sandbox cause is a hypothesis, not an
established root cause. The candidate's build/launch used SDK-cache access, so
that permission issue alone does not explain the observed window-close delay.
Leave current application behavior in place; no speculative runner or SDK
change is justified by the current evidence. Further automated testing remains
stopped at the user's request. Original notes and prior checkpoints remain
preserved.
