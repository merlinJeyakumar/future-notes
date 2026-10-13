# Static review and repair checkpoint

Date: 2026-10-13.
Source baseline: `development` at `a9f6d247d7e27322d4afe542aa27240c72af031e`.
Delivery branch: `repair/note-storage-safety`.

The user requested review by code and a local commit on a new branch, without
running tests. This checkpoint does not activate persistence on a real library
or complete the full repair plan.

## Review performed

- Traced locked/failed-load write authority, prospective-load publication,
  session/request generations, draft decisions and document subscriptions.
- Traced immutable save capture, coalescing, acknowledged revisions, retained
  metadata/body content and autosave failure handling.
- Reviewed compatible envelope decoding and typed empty decryption results.
  Existing encryption formats remain; authenticated migration is deferred.
- Reviewed isolated storage admission, captured references, writer ownership,
  staged commits, baseline/version retention and conservative recovery.
- Traced candidate-library preparation, settings acknowledgement, watcher
  publication, stale discovery/search rejection and cleanup joins.
- Reviewed the shared shutdown attempt and timeout/retry ownership. No native
  runner or SDK patch was introduced for the automated close discrepancy.

This is static code-flow review, not fresh compiler or runtime evidence. No
tests, build, dependency resolution, application launch or automated UI input
were run for this commit. Git whitespace and staged-path inspection are the
only execution checks in this delivery.

## Prior evidence and limits

Earlier authorized gates recorded 353 passing tests and Windows Debug
compilation. The latest recorded analyzer result had no errors, 97 informational
diagnostics and the original two warnings. These are historical results, not
checks rerun for this commit; see [shutdown results](SHUTDOWN_FIX_RESULTS.md).

The automated shutdown check exceeded its time limit despite storage cleanup
completing in 53 ms. The user subsequently confirmed manual typing and closing
worked. The difference remains unexplained; sandbox/automation involvement is
an unconfirmed hypothesis. No continuous-operation or performance acceptance
is claimed.

Recoverable persistence and library switching are enabled only through the
explicit isolated Windows validation entry point. The normal application still
uses its existing persistence backend. Attachment/password/Delete mutation
ordering, streaming, separate encryption loaders, complete packages, platform
repairs and real-library backup/recovery rehearsal remain pending. R01 remains
deferred. See [status](STATUS.md) and [finding ledger](FINDING_LEDGER.md).

## Commit boundary

Include application changes, regression-test sources, pinned dependency changes,
the rulesbook and implementation Markdown evidence. Test
sources are included without executing them again.

Exclude existing note data, `.validation`, executable/build output, generated
platform-file normalization and earlier baseline audit artifacts/raw logs.
Preserve all excluded files and previous source/executable checkpoints. No
remote push is part of this delivery.

The first staged whitespace check exposed pre-existing trailing spaces in an
older platform audit and three raw analyzer logs, plus an extra final blank
line in an older UI audit. Those historical artifacts were left unchanged and
excluded from this code checkpoint. This does not resolve their formatting.
