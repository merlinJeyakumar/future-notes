# Adaptive attachment preparation

## Requested behavior

Detect the computer running Future Notes, target 70% of available preparation
capacity by default, expose extended settings, and accept more attachments while
earlier additions process. Preserve notes, existing formats, verification,
recovery, cancellation and published releases.

## Implementation

- A shared process-wide scheduler admits encryption, rekey, decrypted-open and
  file-export transforms. Different worker instances do not receive independent
  resource allowances. Preparation may run concurrently; note publication still
  uses the existing mutation coordinator and the latest acknowledged reference,
  current draft and attachment list. Session/credential/identity checks remain.
- Windows telemetry uses GetSystemTimes, GetProcessTimes and GlobalMemoryStatusEx.
  The budget is logical processors × (1 − other-process CPU fraction) × target.
  Memory admission uses the target fraction of available physical memory, with
  an estimated 64 MiB scheduling allowance per worker. Optional parallel-file and
  memory ceilings can only lower admission. The first sample or unavailable
  telemetry uses one worker with fractional duty. Low memory can pause workers;
  cancellation remains responsive while paused. Sampling is cached for 250 ms
  and refreshed once per second while preparation exists; idle polling stops.
- Workers cooperate between bounded 1 MiB processing/verification windows. CPU
  duty changes and cancellation reach owned isolates through their control ports.
  Actual OS CPU usage, disk bandwidth and process RSS are not hard capped. A
  single ordered stream need not consume the full allowance; parallel files use
  additional capacity. This is not GPU or disk-bandwidth detection.
- New additions no longer hold the exclusive password/package-operation guard.
  Desktop drop and file picking release intake after admission. Pending cards
  remain queued until a slot starts. Individual cancellation preserves independent
  files. Exit waits for an uncancellable publication, then resolves remaining
  preparations instead of waiting blindly for every queued large file.
- App settings includes the default 70% target, 10–90% adjustment, live hardware/
  queue readout, and Advanced configuration for automatic/manual parallel-file
  and estimated working-memory limits. Settings publish after durable settings
  acknowledgement. Invalid or failed candidates retain previous values.
- Removed an unused extra source SHA pass only when no expected source digest
  exists. Captured expected-digest checks, plaintext hashing, independent staged
  readback verification, source-change checks, flushing, AES-SIC/PKCS7 layout,
  cache reuse and recoverable commits remain enabled.
- Stitch settings design: screen 3ccfc50c4a3f4853851c0ff43e633d54 in existing
  project 6056916933162144137. The available Flash model was used after reporting
  Pro unavailability. Only the settings concept was applied; generated algorithm
  labels were not applied. The actual encryption format was not redesigned.
- win32 remains pinned at its already resolved 5.15.0 version; offline dependency
  resolution promoted it from transitive to direct without upgrading packages.

## Validation

- Formatting and whitespace passed. The first formatter attempt was blocked by
  Dart's user-cache permissions and was rerun with SDK access.
- Initial static analysis found one nullable-path error plus new style lints;
  those were corrected before tests. Final changed-source analysis: zero errors
  or warnings, 48 informational diagnostics on unchanged HEAD source lines.
  Origin evidence: `.validation/attachment-performance-info-origin.json`.
- Combined affected suite: 116 passed, covering compatibility, owned mutation,
  settings acknowledgement, cache, UI, drops and Save coalescing.
- Actual isolate sharing/pressure and previously unrun lifecycle/session checks:
  40 passed. They prove two worker instances obey one pool, encrypted/decrypted
  hashes match, close drains ownership, memory-pressure cancellation removes
  partial output after handles close, and existing lock/Exit paths remain valid.
- Final ordering/Exit cases: three passed, one repeated because the settings
  publication order changed. Total distinct tests: 158. No full-suite duplication.
  A brace-only test lint correction then passed analysis.
- A disposable 64 MiB Dart JIT baseline/candidate experiment produced identical
  plaintext hashes and output lengths. It ran alongside other checks, so its
  recorded elapsed difference is not accepted as a Release throughput benchmark
  or a promised speedup. Evidence: `.validation/attachment-performance-benchmark.*`.
- One protected canonical Windows Release build passed in 45.4 seconds. Private
  symbols/obfuscation map and runner ASLR, high-entropy ASLR, DEP, CFG, stack cookie
  and restricted DLL loading passed. Only the existing CMake FetchContent
  deprecation warning appeared.

Evidence prefix: `.validation/attachment-performance-`. The accepted executable
and full bundle were copied and EXE/AOT hashes checked under
`.validation/attachment-performance-previous-release` before compilation.
Published portable folders and tags remain unchanged. Destructive tests used
synthetic data. No original notes were edited by the agent. Existing HTML/drop
work and unrelated dirty files are retained. Nothing was committed or published.

Windows startup/resource observation and physical multi-file/settings acceptance
are recorded separately; test success alone does not establish universal runtime
performance. Native Windows telemetry is exercised on this host; synthetic
capacity tests cover 1, 2, 8 and 64 logical processors. Linux probe code exists
but is not runtime-accepted here; other unavailable telemetry uses the fallback.

## Candidate startup observation

Canonical candidate launched once as PID 22788. After initialization it had a
visible, responsive Future Notes window. Protection and media registration logs
were clean. Six read-only samples over approximately 33 seconds remained
responsive, with working set 176.6–191.3 MiB and normalized process CPU
0.04–0.98%. This low-load observation is startup/idle evidence, not evidence that
large-file processing achieves a particular CPU percentage or throughput.

Physical multi-file queuing, typing, advanced-setting persistence and cancellation
acceptance was requested through the user prompt. Its response remains pending.
No agent keyboard/mouse input or forced shutdown occurred. The candidate remains
open for that check; published releases remain unchanged.

## Subsequent manual result

Concurrent intake worked with four large videos (about 8 GB), but after display
lock/off the user reported a last item remaining in finalization and completed
items waiting in source checking. The user subsequently confirmed all processing
eventually completed; no deadlock or failed commit was established. The remaining
issue is long blocking verification with misleading progress.
Investigation and the correction's separate validation state are recorded in
ATTACHMENT_RESUME_20261016.md. Do not treat the initial test/build pass as complete
manual acceptance or claim the currently running older executable contains that
correction.
