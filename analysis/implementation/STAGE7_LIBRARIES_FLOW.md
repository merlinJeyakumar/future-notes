# Watcher and library-switch flow review

Status: source/test/build gate passed: 337 tests, exactly the prior 97 diagnostics
and Windows Debug compilation. Runtime and real-library activation remain
pending. Final evidence: [STAGE7_LIBRARIES_RESULTS.md](STAGE7_LIBRARIES_RESULTS.md).
The preceding 306-test source and executable remain at
`.validation/future-notes-validation-stage7-ordering-2d745fdf585041c7bbfdc24e7c65352d`.

## Ownership and joins

| Boundary | Guard and result |
| --- | --- |
| Opening another folder | Require an absolute path, recoverable settings and note owners; reject concurrent switches, loads, decisions and library-sensitive operations |
| Resolving the current draft | Drain accepted saves; use the existing library decision and revision permit; new notes still require explicit first Save |
| Candidate preparation | Acquire/recover its writer root and prepare its watcher before changing settings; Discard remains provisional |
| Watch startup | Capture one StorageBinding; observe the root recursively and its nearest existing ancestor shallowly; follow missing intermediate directories and root recreation without polling |
| Event delivery | Reject retired ownership, sibling events and `.future-notes-*` staging/recovery/lease events; use the existing two-second refresh debounce |
| Candidate completion | Recheck the draft revision, disposal and watch failure; retain the previous draft on stale preparation |
| Settings commit | Hold a library-specific cutover barrier, make editor/title temporarily read-only, and reject conflicting operations; recheck the expected settings root and draft permit before writing |
| Acknowledgement | Publish service binding and prepared watcher synchronously, invalidate old listing/search authority and clear credentials cached by basename |
| Unexpected programmatic edit during commit | Keep the edited draft and its captured old reference/lease; report that the new library opened and the previous-library draft still needs Save |
| Resource release | Cancel the old watcher and release its writer root only after publication; report post-commit cleanup failures without claiming the old library remained active |
| Abort cleanup | Close candidate watching and release the candidate root independently; retained cleanup failures return recoveryRequired and can be retried |
| Disposal | Awaitable watcher shutdown accompanies existing synchronous disposal; late preparation cannot publish an editor session; an acknowledged commit during disposal closes its prepared watcher |

Root release joins accepted persistence jobs, refuses new access to that root
during release, and retains its capability on failure. It participates in owned
service shutdown. Preparing a candidate reserves a generation without changing
the active generation. No note files are moved or deleted by a library switch.

## Scope and explicit limits

The default application still has no owned recoverable persistence. Its folder
action now routes through the coordinator and refuses unsafe switching until
real-library activation passes the planned compatibility/recovery gates.
Injected disposable Windows storage exercises the complete candidate. The old
direct setters remain an intermediate service API for existing callers/tests;
they are not the application's library-transition path and have not acquired
recoverable production guarantees in this batch.

A late programmatic mutation after commit starts cannot undo an acknowledged
settings write atomically. The draft is retained rather than cleared; the typed
conflict describes the actual published library. This is a preservation fallback,
not a claim that every transition can roll back. Complete attachment-path
ownership, the common attachment/password/Delete mutation queue and real-library
activation remain later gates. Native watcher behavior under OS handle faults,
continuous runtime, resource use, performance and other platforms remain pending.

Eight controlled watcher regressions cover recursive filtering, missing roots,
recreation, move destinations, sanitized errors, cancellation and partial startup.
Nineteen widget regressions cover draft decisions, preparation/commit joins,
late edits, competing operations, old events, disposal and cleanup outcomes.
Four native storage regressions join the real owned worker, native watcher,
settings conflict/acknowledgement and root lease release on synthetic files only.
Passing registration count: 31 new, 337 total. Tests use synthetic storage only.

Widget operation creation remains in fake async. A bounded join allows real
root-zone cancellation continuations through runAsync, then pumps fake microtasks.
Race and debounce timing remain fake. Resource-close acknowledgement is joined
inside the active test body before registered teardown and disposable cleanup.
This prevents the unbounded cross-zone teardown await observed in the failed
harness attempt; all original acceptance assertions remain.

Review compared the candidate against the preserved checkpoint. It checked
preparation versus publication, asynchronous ownership, independent abort cleanup,
settings acknowledgement, save ordering, input admission and disposal. The native
watcher uses injectable event sources following the existing test-injection
pattern; no new dependency, encryption change or framework is introduced.

The only proposed gate is [STAGE7_LIBRARIES_VALIDATION.md](STAGE7_LIBRARIES_VALIDATION.md):
format once, lint first, one suite and one Windows build. The previous intermittent
native-move failure remains unexplained; its numeric diagnostic remains intact.
