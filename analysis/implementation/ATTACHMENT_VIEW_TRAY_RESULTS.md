# Attachment viewing and tray validation — 2026-10-14

Implementation, native compilation and visible startup passed. On 2026-10-15 the user confirmed attachment addition and reopening from tray worked; remaining manual acceptance is pending. Implementation started from development at ba462edc731e62a37f760bfd972dce4d79882384, which the unchanged `v1.0.0` tag identifies. The user authorized validation, commit and push on 2026-10-15. No ZIP or tag movement belongs to this delivery. Original notes and unrelated untracked files were not used for tests.

## Static checks and regressions

Changed Dart sources were formatted and `git diff --check` passed. The latest `flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings` completed with 110 diagnostics: 108 info, the original two unused-import warnings, no errors and no new warnings. Informational diagnostics remain open; this is not a strict lint-clean claim.

The single combined affected suite covered cache service/row/tray, locked UI, job panel, settings, mutation integration, session safety, Save coalescing, libraries, actual exit and draft decisions. It initially returned 118 passes and three failures. Two fixtures held stale session ownership after unlock; the tray fixture incorrectly expected FlutterTest's overridden cancelable-exit implementation to dispatch an exit request. Fixtures were corrected, and an injected exit requester now lets the test exercise the native callback's ordinary production path. No native exit bypass or forced termination was introduced. The corrected tray/locked/exit files passed 13 tests.

Final cache/row/tray/locked/exit checks passed 27 tests, including three additional regressions for active cache cancellation, legacy mixed-key fallback into a fresh file, and truncated cleanup receipts. The three separate editor/cache lifecycle tests passed: navigation reuse; lock/rekey/removal/Delete revocation; preparation cancellation on actual Exit; and waiting for publication before actual Exit. These runs overlap; counts must not be added as though each run were a new complete suite. All 127 distinct affected regressions are covered across the combined run and required correction/new-test runs.

Raw output is retained in `.validation/attachment-view-tray-tests.txt`, `attachment-view-tray-retry-tests.txt`, `attachment-view-tray-final-tests.txt`, `attachment-view-tray-lifecycle-tests.txt` and `attachment-view-tray-lifecycle-analysis.txt`. The analyzer also caught an unused import in the new lifecycle test; that import and a redundant import were removed before tests ran.

## Large-file cache gate

Command: set `FN_LARGE_OPEN_CACHE_ROOT` to the explicit fresh `.validation/future-notes-validation-large-open-cache-20261014` directory, then run `flutter test --no-pub test/storage/large_attachment_cache_test.dart` once. Only synthetic data is read/written; the prior package/encryption large-file gates are not repeated.

Both cases passed (exit 0; the one test took 34:21 including fixture preparation). Hashes matched, initial/repeated Open performed exactly one transformation per file, and invalidation removed the plaintext. Results and raw output are retained under the disposable directory and `.validation/attachment-view-tray-large-tests.txt`. This measures cache payload processing, not native player memory or UI latency.

| Plaintext size | Peak observed RSS | Cache Open/hash/reuse time, excluding fixture preparation | Transformations |
| --- | --- | --- | --- |
| 4 GiB + 17 bytes | 177,606,656 bytes | 306,836 ms | 1 |
| 10 GiB | 185,401,344 bytes | 737,323 ms | 1 |

## Release and manual runtime gate

The previous 16-file Release bundle was copied and every file hash verified under `.validation/attachment-view-tray-previous-release-20261014`. The user closed the old application normally; no process was forced to stop. After the large-cache gate passed and zero app instances were confirmed, `flutter build windows --release --no-pub -t lib/main.dart` passed (exit 0; 58.6 seconds). It emitted two third-party Media Kit CMake developer-policy warnings for CMP0175; no application compiler error occurred. The native dependency sources were not patched. Raw output: `.validation/attachment-view-tray-release-build.txt`.

The prebuilt canonical application was launched once, without recompilation, using `flutter run -d windows --release --no-pub --no-hot -t lib/main.dart --use-application-binary=D:\Project\NativeDevps\future-notes\build\windows\x64\runner\Release\flutter_application_1.exe`. Native inspection confirmed exactly one visible, responsive Future Notes window (PID 66032). The startup log registered the Media Kit Windows library and showed no startup error. Idle working set was approximately 145 MiB; this does not measure playback or UI latency. Raw output: `.validation/attachment-view-tray-release-runtime.txt`.

The native cache root ACL was inspected after startup: protected DACL, exactly two access rules for the current user and SYSTEM, no unexpected principal and no reparse-point attribute. This checks the actual native root admission, not only an injected resolver. No cache payload or original note content was inspected.

At 278 seconds after launch the one process remained responsive, its working set was 151,670,784 bytes, and no new startup/operation error appeared in the runtime log. This is an idle/startup observation while waiting for manual interaction, not a continuous playback, frame-time or input-latency acceptance result.

A deterministic 9,217,192-byte AVI fixture is available at `.validation/future-notes-validation-attachment-open-20261014/fixtures/demo-video.avi`; generation passed. Native playback has not yet been verified. Fake-player/widget checks establish UI ownership and actions, not Windows codec availability.

### User manual result — 2026-10-15

The user reported: “i did until file attach and reopen from tray, it worked”. Attachment addition and tray reopening are therefore recorded as passed by the user. The reply does not establish embedded playback, individual player controls, cache reuse, locking, external opening, background preparation completion or actual Exit behavior. No further application interaction, build or test was performed to record this result.

Pending manual checks: explicitly confirm inline progress/no completion dialog; deliberately open embedded playback and seek/volume/fullscreen; open through a system association and exercise Save As/Remove; repeat Open and lock/reopen; confirm preparation continues while hidden; use actual Exit with keep-running/cancel and finalizing behavior. Explorer restart restoration, external file sharing/cleanup and continuous player/tray resource usage remain pending runtime evidence. Cache plaintext may remain temporarily when held externally; opaque cleanup receipts retry next startup and no secure-erasure claim is made.

## Commit validation — 2026-10-15

The 19 changed Dart files passed `dart format --output=none --set-exit-if-changed` without changes; whitespace checks passed. `flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings` completed with the same 110 diagnostics (108 info and two existing warnings), exit 0. Its cold run took 250.6 seconds. Process inspection located the SDK analysis-server subprocess; before an identity-checked cleanup could run, the analyzer finished. The guard rejected the stale helper identity, no process was stopped and no duplicate analyzer ran.

One final `flutter test --no-pub --concurrency=1` passed 461 tests with three opt-in checks skipped, exit 0, in 2:41. Output: `.validation/attachment-view-tray-commit-analysis.txt` and `.validation/attachment-view-tray-commit-tests.txt`. The unchanged large-file gates and native Release compilation were not repeated. The build/startup evidence above remains the 2026-10-14 result; it is not a new native build claim. An attempted direct comparison against Flutter's incremental `.filecache` was inconclusive (new dependencies lacked entries and one recorded hash differed), so no exact source-to-binary digest binding is claimed from that cache.

Only the 35 explicit application/native/dependency/test/fixture-script/evidence paths are selected for the commit. Local design previews, unrelated audits, old raw logs, build/validation output and original notes are excluded. The requested normal push of development also includes the four existing storage/backend integration commits already ahead of origin; no force push or tag update is requested.
