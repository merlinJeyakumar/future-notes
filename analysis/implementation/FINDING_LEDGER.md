# Finding repair ledger

Source: the development analysis at a9f6d24 and its supporting reports.
The correctness scope contains 49 findings. R01 remains separately deferred.
Stage 0 provides validation prerequisites and does not close any finding.

Status vocabulary: **pending**, **implemented** (candidate code only),
**validated** (required evidence recorded), **deferred** (separate agreed gate).
Platform and performance findings cannot be closed by Windows compilation alone.
Stage 1 transition/exit, the first ten Stage 2 candidates and Save coalescing passed their
source/test/build gates. Runtime and production integration remain pending;
isolated backend evidence does not close a finding.

| Finding | Required repair | Stages | Status | Acceptance evidence |
| --- | --- | --- | --- | --- |
| DEV-C01 | Reject locked Save | 1 | Implemented | 26-test focused gate passed; locked zero-write regression; UI/runtime pending |
| DEV-C02 | Canonical complete autosave | 3 | Implemented (partial) | Shared save path and Save coalescing regressions passed; latest 100 focused/266 total tests and Windows build; application durability/runtime pending |
| DEV-C03 | Rebind document observation | 1, 3 | Implemented | Replacement/immediate-Save regressions passed; runtime pending |
| DEV-C04 | Capture identity and serialize mutations | 1–4 | Implemented (partial) | Session Save queue and injected revision-aware note-service regressions passed; full mutation queue and runtime pending |
| DEV-C05 | Recoverable note/settings replacement | 2 | Implemented (partial) | Backend/worker/settings/note gates passed; latest integrated Save regressions: 100 focused/266 total tests/build; app integration/interruption/runtime pending |
| DEV-C06 | Transactional library switch | 2, 3 | Implemented (partial) | 23 synthetic draft/storage regressions passed in 337-test suite, unchanged analyzer baseline and Windows Debug build; see STAGE7_LIBRARIES_RESULTS.md; real-library activation and runtime pending |
| DEV-C07 | Import without basename overwrite | 6 | Pending | Pending |
| DEV-C08 | Compatible discovery and canonical text import | 2, 6, 7 | Pending | Pending |
| DEV-C09 | Failed loads never grant write authority | 1, 2 | Implemented | Failed/stale load and shared codec regressions passed; runtime pending |
| DEV-C10 | Transactional password transformation | 4 | Pending | Pending |
| DEV-C11 | Preserve legacy identity and resolved paths | 2 | Pending | Pending |
| DEV-C12 | Complete attachment packages | 6 | Pending | Pending |
| DEV-C13 | Resolve drafts before destructive transitions | 1, 3 | Pending | Pending |
| DEV-C14 | Truthful, serialized permanent Delete | 3 | Pending | Pending |
| DEV-C15 | Owned operation state and typed failures | 1–7 | Pending | Pending |
| DEV-C16 | Root-bound recursive watcher lifecycle | 7 | Implemented | Eight controlled watcher regressions, library-event ownership and native synthetic integration passed in 337-test suite and Windows build; see STAGE7_LIBRARIES_RESULTS.md; continuous native runtime/platform evidence pending |
| DEV-C17 | Worker readiness and listing/search generations | 7 | Implemented (partial) | Readiness, scan coalescing, root/request and query/list guards passed 22 new/306 total tests, unchanged analyzer exception and Windows build; earlier native failure unresolved; runtime pending |
| DEV-C18 | Attachment ownership and durable publication | 4, 5 | Pending | Pending |
| DEV-C19 | Consistent selected-session notifiers | 1 | Implemented | Lock/reset flag regressions passed; UI/runtime pending |
| DEV-C20 | Complete asynchronous resource disposal | 1, 2, 7 | Implemented (partial) | Owned shutdown/cleanup regressions passed: eight new, 54 focused/274 total and Windows build; complete UI/worker disposal and runtime pending |
| DEV-C21 | Bounded 10 GiB attachment processing | 4, 6 | Pending | Pending |
| DEV-C22 | Publish settings only after durable success | 2, 3 | Implemented (partial) | Injected settings-service gate passed 19 new/26 focused and 234 total tests/build; singleton/UI/library adoption and runtime pending |
| DEV-C23 | Retain stored timestamps | 2 | Pending | Pending |
| DEV-U01 | Password verification preserves editor | 1, 4 | Implemented | Controller-preservation regression passed; UI/protection transactions pending |
| DEV-U02 | Export preserves active draft | 1, 6 | Pending | Pending |
| DEV-U03 | Import feedback follows typed outcome | 6, 7 | Pending | Pending |
| DEV-U04 | Save/export/password feedback follows outcome | 1–7 | Pending | Pending |
| DEV-U05 | Preserve user titles and observe title changes | 1, 3 | Implemented | Short-title/autosave regressions passed; UI/runtime pending |
| DEV-U06 | Separate archive Cancel from no password | 6 | Pending | Pending |
| DEV-U07 | Disable rich-text controls in HTML mode | 7 | Pending | Pending |
| DEV-U08 | Guard asynchronous dialog ownership | 7 | Pending | Pending |
| DEV-U09 | Keyboard focus and accessible action labels | 5, 7 | Pending | Pending |
| DEV-U10 | Dispose local password controllers | 7 | Pending | Pending |
| DEV-U11 | Accurate timestamp labels | 7 | Pending | Pending |
| R01 | Reviewed opt-in authenticated encryption migration | 8 | Deferred | Separate migration specification and acceptance |
| R02 | Preserve duplicate ZIP display basenames | 6 | Pending | Pending |
| R03 | Transform pre-existing attachments when adding password | 4 | Pending | Pending |
| R04 | Reject incomplete or damaged packages | 6 | Pending | Pending |
| R05 | Strict bounded package parsing | 6 | Pending | Pending |
| R06 | Separate decrypt payload and failure | 2, 4, 6 | Implemented (partial) | Typed editor/envelope/preview readers and 14 regressions passed; 127 total tests/build passed; package/protection adapters and runtime pending |
| PLAT-01 | Preserve image bytes on unsupported compression targets | 7 | Pending | Actual Windows/Linux validation pending |
| PLAT-02 | Native file-based mobile attachment Save | 7 | Pending | Actual Android/iOS validation pending |
| PLAT-03 | macOS selected-file entitlements | 7 | Pending | Actual macOS validation pending |
| PLAT-04 | macOS test-host configuration | 7 | Pending | Actual macOS validation pending |
| PLAT-05 | Guard unsupported browser-native features | 7 | Pending | Browser validation pending |
| PLAT-06 | Windows UTF conversion bounds and cleanup | 7 | Pending | Native regression/build validation pending |
| PLAT-07 | Compression MIME/extension matches output | 7 | Pending | Supported-target validation pending |
| DEV-X01 | Preserve plaintext boundary whitespace | 2 | Implemented | Legacy raw-body and shared codec whitespace regressions passed; runtime pending |
| DEV-X02 | Shared legacy envelope recognition | 2, 6, 7 | Implemented | 13 codec regressions passed, 113 total; editor/discovery/package/export metadata readers adopted; full import/export/runtime pending |
| DEV-X03 | Strict, reachable internal note-link handling | 7 | Pending | Pending |

The separate attachment loaders are required acceptance behavior for stages 4/5,
even though the baseline did not assign their complete design a separate finding
ID. Performance evidence must cover the 14 baseline PERF mechanisms with matched
workloads; no improvement is claimed from source changes alone.
