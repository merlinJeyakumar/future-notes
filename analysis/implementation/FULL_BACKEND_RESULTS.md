# Full Windows Debug backend evidence

## Implementation

Implemented the canonical Windows startup and transactional adapters for attachment preparation/publication/removal, password generations, package import/export, permanent Delete and library switching. The preview banner is removed; the normal FileService exposes these adapters. Unsafe legacy direct writers remain inaccessible to owned sessions rather than bypassing the new backend. `lib/main.dart` resolves existing settings and the selected library; the IDE Windows Debug configuration targets that entry point.

Code flow is described in [FULL_BACKEND_FLOW.md](FULL_BACKEND_FLOW.md). Native UI interaction is reserved for the user. No original note has been overwritten or deleted by validation.

## Validation

| Gate | Observed result |
| --- | --- |
| Fresh backup and previous executable | Seven existing files copied and hash-verified; separate rehearsal copy; previous executable retained under the `20261014-full-backend` snapshot. |
| Combined relevant regression suite | First run interrupted at a fake-async Save join after four failures. Resumed run completed with 422 passed, three failed, one large-file test skipped pending its separate explicit run. Failures are recorded below, not treated as passes. |
| Affected correction suite | 112 passed: native moves, replacement recovery, deletion interruption/retry, note persistence, complete generations/packages, loaders and exit. |
| Final ownership/rehearsal | 40 passed: settings ownership, worker readiness/lifecycle and recovery on the copied current library. |
| DEFLATE framing | 21 passed after adding bounded compressed-input consumption checks, including a crafted trailing-byte archive and actual legacy DEFLATE fixtures. |
| Worker/package/UI flow | 49 passed: worker terminal ordering, cancellation, verification byte progress, explicit empty archive passwords, packages, mutation joins, loaders and one-click exit. |
| Nonblocking Save/startup | 45 passed: Save uses its own status, typing during commit stays dirty, coalescing/transitions, selected startup roots and exit. |
| Empty-message compatibility | 71 passed: standard legacy PKCS7 empty-block encoding, independent readers, streamed attachments/packages, protection generations, shared codec and existing compatibility fixtures. |
| Final deletion/selection/session gate | 188 passed, including missing active attachment recovery, preserved legacy sharing, selected-library rollback at startup and copied-library recovery. A nullable-root analysis error was corrected before tests ran. |
| Latest static analysis | Exit 0; 110 diagnostics: 108 informational, the original two unused-import warnings, no errors or new warnings. Original warnings remain in sidebar.dart and file_details_dialog_test.dart. |
| Large-file validation | Passed actual 4 GiB + 17 byte and 10 GiB length/SHA-256 round trips. Sampled peak RSS: 232,620,032 and 235,364,352 bytes (221.8 and 224.5 MiB); cipher round-trip times: 490,225 and 1,208,370 ms. 1 MiB payload windows. The full large-file test completed in 33m56s. Python zipfile independently consumed the 10,737,418,272-byte ZIP64 attachment, validated CRC and matched the ciphertext SHA-256. Later verification-progress instrumentation changes reporting only; the cipher/data path and stored-ZIP writer used by this gate are unchanged. |
| Preactivation verification | Original and backup inventories match. An initial comparison failure was PowerShell 7.6 parsing ISO strings as DateTime and changing their JSON representation; seven byte hashes, lengths and timestamps and all 14 entries were unchanged. Reading manifest dates as strings corrected comparison without modifying the originals or backup. |
| Canonical Windows build/launch | Passed one Windows Debug compilation in 21.4 s using `flutter run -d windows --debug --no-pub --no-hot -t lib/main.dart`. Owned-storage readiness and the first editor frame are logged. PID 48812 is the sole project process; native EnumWindows confirms its FLUTTER_RUNNER_WIN32_WINDOW is visible, unowned and in the same desktop session as Codex. The initial .NET MainWindowHandle result was insufficient evidence; native inspection confirmed visibility without input or window manipulation. No startup errors observed in captured logs. Previous executable remains retained. |
| User's full-app workflows | On 2026-10-14 the user reported "All checks passed" for the presented full-app checklist: existing notes, Save/reopen, attachments, password changes, import/export, library switching, one-click Close and synthetic-note Delete. This is user-reported evidence; no automated keyboard input or forced application termination. The subsequently reported locked-note UI issue is tracked separately in LOCKED_NOTE_UI_RESULTS.md. |

These suites overlap; their counts must not be added to claim a distinct total. Only affected gates were repeated after substantive changes or failures; no duplicate optional full suite or build was run.

## Failures and corrections

- The first native library fixture omitted its selected-library setting while using separate configuration/library roots. The fixture now supplies the existing-layout setting explicitly and avoids disposing the same editor twice after setup failure.
- An older coalescing assertion expected two calls into the writer. The stale queued snapshot now fails its revision precheck before that second call; all typed conflict, retained-edit and byte-preservation assertions remain.
- Cancellation at the final verification event was ignored. A final cancellation check now runs before acknowledging preparation; per-window verification byte progress is also published.
- The active-job decision dialog test did not cover its new Keep editing / Cancel & wait choices. Those outcomes are now asserted explicitly.
- An idle mutation queue joined a future created in Flutter's fake-async zone, stalling a Save invoked through runAsync. Idle work now starts in the caller's zone, while pending work retains serialization.
- Preparation sources are now managed under an opaque note identity. The cleanup regression compares retained transaction/recovery artifacts separately from sources that cleanup deliberately removes; its failure/retry assertions remain.
- A loader card overflowed vertically. Its height now accommodates its controls and text scaling.
- A failed native move sometimes returned no Win32 error. The precise thread-local error-loss cause remains unconfirmed. Preexisting destinations are rejected before the native call; a racing occupied destination with a retained source is classified from checked state. An unexplained failure with no destination remains I/O failure. Real no-replace moves, preserved bytes and injected unknown-error/racing-destination cases passed.
- Native DEFLATE did not expose unused compressed bytes. An installed-parser pass with only 32 KiB history now checks exact consumption/count/CRC, while the bounded native sink separately validates and writes the payload.
- The archive dialog converted explicit Skip/empty input into Cancel. It now retains an empty string for no password and null for cancellation.
- The old buffered AES writer could not emit empty payloads. It now emits the existing full PKCS7 empty-message block; independent legacy readers verify the unchanged layout.
- Delete now inventories attachment transaction/recovery objects even when their live file is absent. Legacy aliases sharing an attachment directory return a conflict without removing either note. Failed partial cleanup keeps its Retry entry; the selected editor is read-only only during destructive deletion.
- Verified settings recovery can restore a previous library selection after bootstrap captured the interrupted new value. Only a receipt-verified restoration of the settings target can admit that recovered selection; unrelated configuration mismatches still fail.
- Save & Continue for the first attachment can explicitly create its blank prerequisite note. Autosave still cannot create a never-saved draft.
- The unused unrestricted workaround entry point was removed after successful canonical startup; explicit validation targets remain available for tests.

## Limits

Windows is the validated target. Other platforms and measured native UI latency remain outside the evidence above. Portable flush/rename does not guarantee complete power-loss atomicity. Permanent deletion can be partial and retains a journal for retry; external changes are preserved. Existing recovery copies retain their earlier protection when a password is added. Legacy encryption remains unauthenticated; encryption redesign is not part of this implementation.
