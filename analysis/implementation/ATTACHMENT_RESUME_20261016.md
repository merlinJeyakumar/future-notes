# Large-attachment checking/finalization after idle

## Evidence and limits

The user accepted concurrent intake, then reported four large videos totalling
about 8 GB. After display lock/off and waking the computer, the last item showed
Finishing safely and opening completed items showed Checking attachment at zero.
The user later confirmed all processing eventually completed. This was a long
operation with misleading status, not a confirmed deadlock or failed commit.

The candidate (PID 22788) remained responsive. A read-only five-second sample
observed 265,289,728 read bytes and 17,825,792 write bytes: it was doing I/O, not
established to be deadlocked. A later three-second sample observed 1,442,553 read
bytes and 0.53125 CPU seconds. Existing logs showed no exception. No original
note payload was inspected, modified or used for destructive testing.

Source inspection established that attachmentSource requested a full revision
hash from the single storage actor. Its command loop awaits the complete journal
commit before processing another command. Multi-GiB commits retain multiple full
hash/copy/readback checks; therefore source checks waited behind that work, while
finalization exposed no stage/byte progress. This creates head-of-line blocking
and misleading zero/indeterminate status, irrespective of screen locking.

Separately, the adaptive limiter measured Stopwatch time across asynchronous
file work. Disk waits or actual suspension could be charged as compute and
create unnecessary cooldown. This is a verified code defect, not proof that
system sleep occurred in this report. Classic suspend/resume event-query results
are recorded separately; display off/lock is not itself proof of system sleep,
and modern standby is not ruled out by absence of classic events.

## Changes

- Measure Windows current-thread CPU only around synchronous cipher/hash work.
  Begin/end pairs never cross await/thread migration. A separate cooperative
  pacer accounts for that compute, handles changing quotas and cancellation,
  and never charges time spent on asynchronous I/O or between windows. Other
  platforms use synchronous-block timing as a fallback; this turn validates
  Windows, not universal power-state behavior.
- Verify immutable committed attachment sources through owned read jobs using
  the existing shared preparation budget, rather than the writer command queue.
  Exact root/identity validation, full source SHA, filesystem/link checks,
  metadata-change checks, source revalidation during transformation and
  independent plaintext readback remain enabled. Persistence tracks reads and
  joins their closed handles before releasing root ownership.
- Cache source checks carry cancellation through to the reader and join it.
  Queued, checking and decrypting are reported separately. Failed/cancelled reads
  cannot create plaintext cache entries or start decryption afterward.
- Carry bounded, throttled stage/byte messages from the journal actor to the
  owning job. Staging, source rechecks, staged verification, publication checking
  and receipt confirmation remain in place. No hash pass, flush, journal,
  baseline or recovery boundary was removed.
- Finalization remains noncancellable. Its inline tile now reports the actual
  stage and per-stage bytes. Phase-detail changes and terminal byte updates
  publish immediately; ordinary byte updates retain existing throttling.
- StorageOwner remains compatible with existing injected owners; progress is an
  additional optional capability. Generic read/transform results remain typed.

## Validation and delivery state

- Formatting/whitespace passed. Changed-source static checks have zero errors
  and warnings after removing one unused new-test import and two new brace
  lints. Remaining informational diagnostics are on existing source.
- One combined affected suite passed 175 tests, including cipher compatibility,
  resource pressure, root lifetime, owned mutation, cache, UI and interrupted
  journal/recovery boundaries.
- Final targeted checks passed seven tests after improving source-start progress
  and asserting progress observations outside protected callbacks. This added
  source-check cancellation and real view-model journal-progress coverage.
- The final queued-status/cache/UI gate passed 40 affected tests after queued
  labels were connected. Total distinct tests across these gates: 177.
- Synthetic regressions simulate long elapsed-time jumps without CPU work,
  changed quotas, paused cancellation, source reads during a paused publication,
  full hash equality, closed-handle cancellation, bounded journal bytes and
  finalization remaining noncancellable. They do not simulate a physical
  laptop suspend or establish 8 GB throughput on the user's drive.

Evidence prefix: `.validation/attachment-resume-`. No build or restart has run
for this correction at the time of the source/test report. After the user
confirmed processing completed, a process check found no running project app,
allowing the protected build to proceed. Physical large-file/idle-resume
acceptance of the corrected candidate remains pending. The agent requested
normal closure only after publication finishes; no forced termination,
automated app input, real-note mutation, tag movement or release publication
occurred. Published releases and previous executable checkpoints are retained.

## Protected candidate delivery

After normal closure was confirmed by a zero-instance process check, the prior
bundle was copied to `.validation/attachment-resume-before-fix-release`; EXE/AOT
hash equality was verified. One canonical protected Windows Release build passed
in 45.0 seconds. Private symbol/map validation and runner ASLR, high-entropy ASLR,
DEP, CFG, stack cookie and restricted DLL loading checks passed. The only build
warning was the existing CMake FetchContent deprecation.

The corrected candidate launched once as PID 34492. Its window was visible and
responsive, with clean protection/media-registration logs. Initial working set
was 149 MiB. A separate observation file records continuous startup/resource
samples. This establishes startup only; physical large-file/idle-resume acceptance
of this correction remains pending the user's response. No tests or full builds
were repeated for delivery, and no app input, forced shutdown, note mutation,
commit, push or release publication occurred.

## User acceptance

On 16 October 2026, the user answered "it was working fine only" to the
corrected-candidate check for large-attachment progress and opening a completed
attachment during publication. Record this as positive acceptance of the
reported check; no failure was reported. The reply did not explicitly establish
that a physical lock/wake cycle was exercised, so that specific condition remains
unconfirmed. No additional execution, code change, commit or publication followed
from this acceptance reply.
