# Discovery and search flow review

This records the source/control-flow review; execution evidence is in
[STAGE7_ORDERING_RESULTS.md](STAGE7_ORDERING_RESULTS.md). The previous 79-file tested source and
Windows executable remain preserved at
`.validation/future-notes-validation-stage7-readiness-8fd98d0b852a4d62ac70fb61964f2bf0`.

## Ownership and joins

| Boundary | Captured authority | Publication/continuation guard |
| --- | --- | --- |
| Path resolution begins | View-model listing-path request | Invalidate scanner publication before the first await; reject older resolved paths and errors |
| Scan request accepted | Canonical absolute root, root generation, monotonically increasing request ID | One active descriptor and one replaceable latest pending descriptor |
| Native worker receives commands | Captured DiscoveryRequest | One drain loop; await each scan before consuming the latest pending request |
| Worker sends partial/final inventory | Same captured request | Service requires active request match; only desired request publishes |
| Service receives terminal success/failure | Active request match | Release active slot and dispatch latest pending; late/unmatched terminals cannot finish another scan |
| Queued inventory event reaches editor | Snapshot request | Recheck scanner ownership at delivery; then increment listing revision |
| Query/listing changes | Search generation, query string, listing revision | Clear stale filtered list, cancel debounce, capture immutable new inventory |
| Filtering starts/returns/fails | Captured search generation/query/listing | Check all three plus disposal before starting and after await; stale results/errors are ignored |
| Editor/scanner disposes | Disposed flag and invalidated generations | Cancel timers/subscriptions, invalidate pending descriptors, reject late publication |

The read-only scanner does not own writer leases or commits. This batch does
not activate repaired persistence or touch attachment/protection/package writes.
Internal protocol messages have no raw error text. Worker fatal errors remain
sanitized through the existing startup/exit handler.

Publication changes from repeated cumulative lists to at most one initial
ten-note snapshot and one final snapshot per scan. Ten or fewer valid notes
produce only a final snapshot. This limits list delivery, not the total inventory
size or note-body decoding allocations; no latency/memory improvement is claimed
without measurement. Discovery ignores symlink entries rather than traversing
them; application-native watchers remain a separate repair.

## Prepared regression evidence

Eleven native/read-only tests cover coalescing 100 pending descriptors,
superseded partial/final replies, root generation changes, path-resolution
invalidation, unmatched/late terminal replies, current/stale failures, disposal,
real synthetic inventories of 125 and ten notes, and rejected relative/traversal
input. Test readers own no filesystem or writer handles; real scans use only
explicit disposable roots.

Eleven widget regressions use injected in-memory services to control query/list
and path-resolution joins, stale success/failure, disposal, sanitized errors,
debounce cancellation and immutable filtering input. They assert zero note
writes. The ten existing readiness tests are adapted to the tagged protocol.

Review found and removed one trailing blank line before the gate. The approved
gate then passed formatter, analyzer, all 306 tests and Windows Debug build,
with lint before the single required suite/build. No separate focused/full
duplication or repeat passing checks ran. Static review is not runtime proof.

Root watcher rebinding, transactional library publication, complete browser
guards, actual reader handle-close evidence, application startup/continuous use,
and performance profiling remain pending. The earlier Windows native-move
failure's cause remains unresolved; the numeric diagnostic is retained.
