# Attachment viewing and tray candidate — 2026-10-14

Base: development at ba462ed; v1.0.0 remains unchanged. Existing Release executable and original notes remain untouched during implementation.

## Reviewed flow

Rendering the unified strip observes metadata and job/cache notifiers, without initiating decryption. A pending addition lives only in job state, remains Finalizing until the note transaction acknowledges publication, then becomes its committed tile. The More menu exists on saved/pending tiles and viewers; pending Open/Save actions are disabled until publication. Password/package summaries and Save status remain separate.

An explicit Open captures reference, session, credentials and password before asynchronous initialization. The shared owned transform worker streams ciphertext into a receipt-owned plaintext cache candidate; no 8 MiB preview limit or whole-file array applies. Cache entries use note/attachment/credential identity, deduplicate preparation and validate source/cache file stats before reuse. A stale result cannot launch a viewer or system application. The embedded player owns its resources, pauses while hidden and closes before cache invalidation.

Windows supplies a cache directory with a protected current-user/SYSTEM DACL. Validation startup selects an explicitly confined disposable directory instead of the production cache. Opaque session directories hold an exclusive owner lease and cleanup manifest. Startup skips live owners, checks paths without following links, and cleans only known cache-file names. Cancelled/failed transforms close their handles before candidate cleanup. Lock/rekey/removal/Delete revoke cache use; sharing failures retain an opaque cleanup receipt and do not prevent lock/exit, as the user selected. Cache plaintext is not encrypted and secure erasure is not claimed.

Windows Close defaults to successfully registered tray hiding, retaining draft/storage ownership and workers; registration failure keeps the window open. Tray Exit bypasses hiding, resolves draft preservation and confirms cancellation of active preparation. Finalizing publication is awaited. Cache/viewers close before watcher/storage shutdown. Tray notification callbacks support keyboard activation and Explorer restart; no completion notification is generated.

## Dependency and design boundary

Pinned media_kit 1.2.6, media_kit_video 2.0.1 and media_kit_libs_video 1.0.7. Offline resolution failed because the packages were absent; online resolution added 16 packages without changing existing versions. Selecting synchronized 3.1.0 and wakelock_plus_platform_interface 1.3.0 preserved the existing resolved SDK floor. No dependency override or unrelated upgrade was added.

Stitch project 6056916933162144137, screen 09b5dd9b1a4546f98001ad4306363c16 supplied the unified row, visible More menu and player/tray controls. Pro was unavailable in tool selection, so the exposed model was used. Only synthetic filenames were sent. Invented ETA/security badges and RAM-decryption labels are excluded.

## Validation state

Candidate implemented and flow-reviewed. Formatting and whitespace checks passed. Analysis passed with the existing warning exception (108 informational diagnostics, two existing warnings, no errors or new warnings). The combined relevant regressions and narrow corrections passed; three editor/cache lifecycle regressions also passed. Both the 4 GiB + 17 byte and 10 GiB cache round trips passed, with one decryption per file across initial/repeated Open, matching hashes and plaintext removal. Peak observed cache-processing RSS remained below 177 MiB. The single Windows Release build passed; one canonical prebuilt app window is visible and responsive. The actual native cache root DACL check passed. Manual playback/tray acceptance remains pending.

On 2026-10-15 the user confirmed attachment addition and tray reopening worked. Remaining native player/system-association/cache-lock/background/Exit interaction is reserved for the user's manual check; no keyboard automation or forced app termination is authorized. The final commit gate passed formatting, whitespace, the analyzer baseline and one full suite (461 tests, three opt-in skips). The previous 16-file Release bundle is hash-verified at `.validation/attachment-view-tray-previous-release-20261014`. No ZIP or release-tag change belongs to this candidate. See [ATTACHMENT_VIEW_TRAY_RESULTS.md](ATTACHMENT_VIEW_TRAY_RESULTS.md) for evidence and remaining gates.
