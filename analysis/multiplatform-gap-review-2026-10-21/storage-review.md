# Storage review: validation passes 2, 3 and 4

Date: 2026-10-21. Source baseline: development `a5be98cd520d501eb8f31e19bacb7bcd4cc8f4e6`, including the existing dirty worktree. Scope: source and native-contract analysis, proposed fixes only. No application changes, builds, tests or device operations were performed for this review. The untracked user note was not opened. These are three different evidence reviews, not three executions of a runtime test.

## Pass 2 — Storage entry points, ownership and settings

### Confirmed current behavior

| Area | Evidence read | Finding |
| --- | --- | --- |
| Normal bootstrap | `lib/main.dart:28-44`, `80-87` | Only Windows automatically resolves an owned environment. Android/iOS enter `MobileApp` first. A normal macOS/Linux launch without special defines initializes legacy settings and the default desktop screen. |
| Explicit owned startup | `lib/core/storage/owned_app_services.dart:20-25`; `owned_note_persistence.dart:21-25`; `owned_settings_persistence.dart:15-20` | All three reject non-Windows hosts. Setting the recovery define cannot enable a Mac/Linux implementation; it selects a constructor that rejects the host and the startup failure screen. |
| Owner worker | `lib/core/storage/storage_owner_worker.dart:103-115`, `469-477` | Both the caller and worker entry gate Windows. Removing a UI or bootstrap guard alone is insufficient. |
| Recoverable backend | `lib/core/storage/recoverable_store.dart:120-160` | Even an injected `StorageFileActions` is refused on non-Windows before I/O. Default actions are Windows-only. |
| Existing native contract | `lib/core/storage/windows_file_actions.dart:9-14` | A shared-looking interface already exists, but exposes only `moveWithoutReplace`. It does not describe volume identity, file identity, lock guarantees, directory sync or platform admission. Renaming this interface alone would not provide those capabilities. |
| Legacy note writes | `lib/features/dashboard/services/file_service.dart:433-447`, `506-542` | Legacy resolved saves write directly to the active envelope; older save methods are also direct writes. `flush: true` on the resolved path does not supply the owned journal protocol. |
| Settings | `lib/features/dashboard/services/settings_service.dart:134-143`, `220-221`, `411-465` | Recoverable settings require an injected owner. Without it, a direct JSON write replaces `settings.json`; most failures are caught and logged. This includes ordinary Android/iOS application settings, not just Mac/Linux. |
| Mobile note storage | `lib/features/dashboard/views/mobile_library_startup.dart:87-135`, `137-184`; `lib/features/dashboard/services/provider_note_files.dart:412-471` | Mobile selects an opaque provider library, probes it, initializes recovery before adoption and persists the selected library separately. Its note backend is not the legacy `FileService`. |
| Android library authority | `android/app/src/main/kotlin/com/nativedevps/futurenotes/LocalDocuments.kt:258-283` | Admits only the on-device/SD external-storage provider and requires persisted read/write grants. It checks tree membership; it does not guess a filesystem path from a URI. |
| iOS library authority | `ios/Runner/MobilePlatform.swift:94-123`, `315-354` | Source implements bookmarks, scoped access, local-volume filtering and coordinated operations. This is source presence, not a Mac build or iPhone acceptance result. |

### Definite additional iOS admission defect

The first-folder admission probe intentionally creates an already-existing filename and accepts only `LibraryAccessException.code == 'name_exists'` (`lib/core/storage/library_admission_probe.dart:72-85`). The Swift `create` branch correctly rejects the duplicate (`ios/Runner/MobilePlatform.swift:321-328`), but `reply` converts every thrown error into `FlutterError(code: 'native_document_failed', ...)` (`70-73`). `MobileLibraryDocuments._invoke` preserves that code (`lib/core/platform/mobile_library_documents.dart:91-98`). Therefore the deliberate successful collision rejection is treated as a fatal probe error on iOS. This is a deterministic source-contract mismatch; it has not been executed on iOS here.

Proposed narrow correction: typed native error categories for name conflict, permission loss, source disappearance, unsupported provider, capacity and I/O failures; map them to the existing Dart contract. Preserve safe messages and content-free diagnostics. Do not weaken the probe to accept every native failure as a name collision.

### Ownership is more than replacing `Platform.isWindows`

`NativeStoragePrimitives.acquireLease` reserves a normalized path in a static set and holds a `RandomAccessFile.lock` handle (`native_storage_primitives.dart:145-193`). The set is isolate-local. Dart documents that Linux/macOS file locks are advisory and process scoped; different isolates in one process can obtain them, and closing another descriptor for the lock file can release the process lock. Consequently one owner isolate and an application-wide root identity are required. The current path set is not proof against two owner isolates or aliases. Do not transplant the Windows rule and call it equivalent. [Dart lock semantics](https://api.dart.dev/dart-io/RandomAccessFile/lock.html).

Proposed contracts should retain the established `StorageOwner` operations and inject a small desktop capability object containing the existing move action plus ownership/root identity and declared persistence semantics. Keep Windows binding unchanged. Add macOS/Linux bindings independently; keep Android/iOS provider coordination separate. Additional abstraction is justified only by native semantics actually needed by those bindings.

### Status after pass 2

| Capability | macOS | Linux | Android | iOS |
| --- | --- | --- | --- | --- |
| Normal note backend | Legacy direct filesystem writes | Legacy direct filesystem writes | Provider backend present | Provider source present; initial admission code mismatch |
| Desktop owned journals | Blocked by constructors and worker | Blocked by constructors and worker | Not the intended backend | Not the intended backend |
| Ordinary settings recovery | Legacy direct writer | Legacy direct writer | Legacy direct writer; native selection is separate | Legacy direct writer; native selection is separate |
| Folder access model | Existing path plus future distribution/sandbox decision | Existing path plus package/portal decision | Persisted SAF tree grants | Bookmarks and coordination, unbuilt here |

This corrects the report's grouping of Android/iOS and its implication that mobile settings already have a separate recoverable model. Notes, selection, job ledger and private draft persistence are different responsibilities and must be assessed separately.

## Pass 3 — Publication and host filesystem semantics

### Confirmed export routing defect

Two independently broken routes exist:

1. `ExternalFileExport.publishOwned` selects Windows actions on Windows and `PosixFileActions` on every other host (`lib/core/storage/external_file_export.dart:64-69`).
2. `PosixFileActions.moveWithoutReplace` explicitly admits only Android/iOS and requires both paths to be direct children of one private export root (`lib/core/storage/posix_file_actions.dart:22-30`). Thus the owned macOS/Linux route rejects publication.
3. Checked/legacy publication selects POSIX only for Android/iOS and Windows actions everywhere else (`external_file_export.dart:160-165`). `WindowsFileActions` rejects non-Windows at `windows_file_actions.dart:56-60`. Thus the checked macOS/Linux route also rejects publication.

The Mac report is correct on this concrete defect. It is not fixed by removing a single mobile guard: the current mobile POSIX class only handles one-directory private export paths, not all nested journal moves.

### Existing safety and work that must survive

- Owned export reviews destination type/metadata, requires a current owner-issued receipt, stages beside its destination, retains a previous export, uses no-replace moves and preserves copies after ambiguity (`external_file_export.dart:26-39`, `55-137`).
- The checked legacy API performs payload revision reads (`external_file_export.dart:176-225`). Keep unowned API protection unless a caller acquires ownership. Do not route newly ported jobs through that API merely because it is convenient: it would reintroduce optional large-file scans against the user's explicit policy.
- Windows uses a same-volume metadata move with destination exclusion and no copy/replace flags (`windows_file_actions.dart:91-114`, `248-254`). This accepted binding should remain unchanged during macOS/Linux work.
- Mobile private export uses Android `renameat2(RENAME_NOREPLACE)` when exposed, otherwise `link`/`unlink` (`posix_file_actions.dart:38-89`). Successful linking followed by a failed unlink can leave two copies and reports recovery, not success. It does not prove an atomic multi-file transaction or power-loss durability.
- Provider publication orders attachments before the final note envelope and uses guards, predecessor copies and a completion receipt (`provider_generation_store.dart:113-117`, `210-237`, `258-315`). Its comment explicitly excludes coordination with an already-open uncooperative writer (`49-52`). Preserve this distinction.
- Android provider rename checks for existing names but deliberately infers no atomic/no-replace guarantee (`LocalDocuments.kt:492-500`). Document IDs returned after rename are authoritative. Android's API permits the provider to return a new URI; cached old tokens must not silently remain write authority. [DocumentsContract](https://developer.android.com/reference/android/provider/DocumentsContract#renameDocument(android.content.ContentResolver,android.net.Uri,java.lang.String)).

### Host-specific proposal and limits

| Target | Proposed publication binding | Limit that must remain explicit |
| --- | --- | --- |
| macOS | Dedicated same-volume no-replace move using an available native exclusive-rename facility, capability-admitted for the actual volume; capture native file/root identity; implement required metadata ordering and error translation. | Apple exposes whether a volume supports exclusive renaming; not every chosen volume can be assumed to do so. A plain existence check followed by ordinary rename is not no-replace. Sandboxed external folders need persistent scoped access. |
| Linux | Dedicated same-volume `renameat2(RENAME_NOREPLACE)` path when the actual kernel/filesystem supports it; explicit supported fallback only if it preserves the contract; native identity and error translation. | `RENAME_NOREPLACE` depends on filesystem support. Do not silently use replacing `rename()` after `ENOSYS`/`EINVAL`, or enable cross-volume copies as though they were atomic moves. |
| Android | Keep provider generations for selected folders and the accepted private-file publication path. | SAF URI grants and document identities remain authoritative. No direct-path emulation, generic rename atomicity or unlimited-background guarantee. |
| iOS | Keep coordinated bookmark-backed provider generations and one necessary encrypted transfer until a held output-sink contract is implemented and tested. | Direct sink is explicitly unsupported in `mobile_library_documents.dart:24-30`; do not claim Android's direct streaming optimization is present on iOS. Native contract/error fix and real host validation are prerequisites. |

Apple's volume capability API documents the connection to exclusive rename. Linux's `rename` reference documents replacement semantics, no-replace support and same-filesystem restrictions. [Apple volume capability](https://developer.apple.com/documentation/foundation/urlresourcevalues/volumesupportsexclusiverenaming), [Linux rename](https://man7.org/linux/man-pages/man2/rename.2.html).

### Durability language needs correction before claiming parity

The current shared interface has no directory sync. The recoverable backend flushes candidate and small intent/receipt handles (`recoverable_store.dart:859`, `929`) and invokes native moves; those facts alone do not prove power-loss persistence of newly created directory entries. Linux documents that file `fsync` does not necessarily persist the containing directory entry. Apple also distinguishes normal flushing from physical storage guarantees, and warns that stronger flushing has a cost. Proposed acceptance must distinguish process termination/restart from OS/power loss. Adding a durability barrier is not a payload verification scan, but it must be specified and measured rather than gratuitously repeated. [Linux fsync](https://www.man7.org/linux/man-pages/man2/fsync.2.html), [Apple disk writes](https://developer.apple.com/documentation/xcode/reducing-disk-writes).

Do not describe Windows as universally power-loss-proof on the basis of the current code either. Preserve the validated Windows behavior; the Mac report's old-complete/new-complete standard is a target for specific tested failures, not evidence that every filesystem/power-loss condition already satisfies it.

## Pass 4 — Recovery, migration and failure safety

### Compatibility traps in a naive port

| Trap | Evidence | Required handling |
| --- | --- | --- |
| Host-dependent journal identity | `commit_record.dart:32-41`, `64-83`; `recoverable_store.dart:566` | Windows journal object directories hash lowercase targets; POSIX defaults hash the target as written. Existing `windowsObjectPaths` decode support must be preserved and explicitly selected when reading Windows-authored journals. Do not rewrite existing records or broaden canonical parsing. |
| Case-insensitive Mac volumes | `native_storage_primitives.dart:154-156`; `recoverable_store.dart:1030-1031` | OS checks distinguish only Windows from other hosts. Actual volume case behavior and aliases need native root/file identity; treating all Macs as case sensitive admits duplicate authorities or incorrect collision keys. Preserve existing Windows IDs and encoded records. |
| Trusted OS directory aliases | `storage_environment.dart:257-289`; `native_storage_primitives.dart:51-65`; `mobile_export.dart:57-68` | Shared paths currently reject all traversed links. The accepted mobile export path resolves a trusted OS cache root before child allocation. Mac system-temp aliases require an equivalent explicit trusted-root policy; never broadly turn off link checks or resolve arbitrary user paths without admission. |
| Windows/provider journal versions | `provider_generation_store.dart:49-52`, `264-270`; `recoverable_store.dart:554-587` | Provider-v2 guards intentionally block a legacy desktop cold-open until recovery completes. A new desktop reader must recognize supported transaction protocols through a designed bridge or fail closed. It must not delete unknown guards to enable opening. |
| Source and output ownership | `recoverable_store.dart:367-405`; `provider_note_files.dart:428-445`; `provider_generation_store.dart:165-192` | Fast paths require current owner-issued receipts. Do not adopt original picked files or bypass receipt identity checks when adding a host. Keep the one encrypted-transfer fallback. |
| Attachment-first composition | `owned_note_persistence.dart:398-448`; `provider_generation_store.dart:113-117` | Owned desktop attachment objects commit before the envelope; a failed later envelope can leave unused recoverable ciphertext. This differs from provider graph recovery. Preserve referential consistency, not an invented claim that both backends make identical multi-file atomic transactions. |
| Completed-journal recovery work | `recoverable_store.dart:620-634` | Startup verifies retained baselines even for completed records. This can perform payload reads, so a broad claim that all completed startups never rescan payloads is not established. Any optimization requires separate design; do not add or re-enable normal-job scans as part of the port. |
| Legacy application settings | `settings_service.dart:444-465` | Direct saves rebuild known fields and replace the active file. Porting ownership must retain unknown metadata and explicit verification choices, report write failures accurately and preserve existing defaults/location. |

### Proposed migration sequence

1. Establish a disposable fixture corpus matching real legacy layouts: folder notes, legacy flat notes, locked/unlocked notes, attachments and mention IDs, existing timestamps/whitespace/unknown metadata, default and custom library roots, and existing version-1/provider journals. No real note inspection or modification is needed.
2. Add the narrow platform primitive bindings and root admission first, retaining Windows implementation and Android provider routing. A failed host admission must leave its current library, draft and selection untouched. Do not silently switch to a private library, weaker writer or new folder.
3. Generalize the bootstrap's capability decision while retaining the read-only existing-config discovery behavior (`windows_storage_bootstrap.dart:10-45`). Do not relocate libraries or encryption formats. On macOS, explicitly decide sandbox/distribution access and persistent authorization before enabling arbitrary external library switching.
4. Open/admit and recover the chosen library and settings root before presenting a writable editor. Ambiguous transactions retain all candidate/predecessor material and remain blocked/readable only according to the existing protocol. No fallback writer may reinterpret failure as success.
5. Activate the new writer only after the host's contract and failure gates pass. Preserve the last accepted artifact and a source rollback; rollback must understand or safely refuse any newly introduced transaction version. Avoid new versions if existing canonical journal semantics can serve the port unchanged.
6. Address mobile ordinary settings as a separate scoped correction, rather than forcing mobile selected libraries through the desktop owner. Native mobile selection, draft and job records remain platform-owned. Fix the iOS error mapping before calling the provider source ready for acceptance.

### Exact host acceptance gates proposed, not executed here

All fixtures must be synthetic and isolated under a canonical temporary root. Ordinary jobs must keep optional checks off; no full-file validation pass is added to product runtime. Verification fixtures can independently inspect results after the operation as a test oracle.

| Gate | macOS | Linux | Android | iOS |
| --- | --- | --- | --- | --- |
| Ownership and identity | APFS default/case-sensitive volumes; second process and same-process second owner; path/case aliases; clean release and process death | Intended distro/package and real local filesystem; second process/isolate, aliases, lock release | Retained runtime reconnect; no duplicate provider writer on activity recreation | Bookmark restoration, scoped lifetime and coordination on real local Files locations |
| Publication | New/colliding destination; nested journals; same-volume move; unsupported/cross-volume denial; source retained | Same plus actual `renameat2` availability/unsupported filesystem; collision and errno mapping | Existing SAF local/SD providers; changed IDs/names; never guessed paths | First admission duplicate-create must yield `name_exists`; create/rename collision; coordinated access |
| Fault boundaries | Candidate create/write/flush, intent write/flush, predecessor move, publish, receipt and cleanup | Same, including unsupported directory-sync behavior | All `ProviderCommitBoundary` values; permission revocation, SD removal/reinsert, short write/full storage | Same provider boundaries, bookmark revocation/staleness, interrupted coordination and expiration |
| Recovery outcome | Reopen gives verified old or acknowledged new visible note, or explicit retained ambiguity; no mixed visible attachment references | Same | Whole predecessor graph or acknowledged generation; legacy guard interoperability | Same, after native adapter is built; no simulator-only claim for external Files behavior |
| Settings and library switch | Preserve prior selection/draft on cancellation/failure; unknown metadata/defaults; restart | Same | Native selected-library record plus ordinary settings failure behavior | Same, with bookmarked folder reauthorization |
| Cross-platform corpus | Read Windows/Android-authored completed libraries/packages; handle pending Windows/provider guards safely | Same | Read completed desktop library; respect pending desktop journals; no ID mutation | Same on Mac + iPhone/iPad; source presence alone cannot pass |
| Export | Owned and checked routing, replace rollback, cache reuse, safe filename, cancellation and retained result | Same | Native Save and Share, URI grant/cancel, retained result and necessary transfer | Native Files Save/Share and iPad presentation, retained result; one-transfer fallback |

For executable implementation, gates must include formatting, scoped analysis, relevant shared/host tests and the native host build once per coherent change. This analysis did not execute those commands, so it does not certify runtime support on any platform.

### Corrections to the submitted Mac report

- **Confirmed:** Windows-only owned bootstrap/constructors, macOS/Linux export routing rejection, weaker legacy note/settings writes.
- **Refined:** mobile provider code is a separate note backend, but ordinary settings remain the shared legacy writer; Android and iOS cannot share a blanket support status.
- **New definite blocker:** iOS collision error mapping prevents the admission probe from completing normally.
- **Refined:** shared journal logic is substantial but not host-semantic-neutral yet; root identity, advisory locks, per-volume case behavior, aliases, journal object hashing and directory persistence require explicit decisions.
- **Refined:** no-replace rename of one file does not imply atomic publication of a note generation; the provider protocol explicitly avoids that claim.
- **Refined:** old-complete/new-complete recovery should be scoped to actual fault tests; source inspection of flush/move calls cannot certify power-loss behavior.
- **Preserved:** the report's Mac build/test counts are attributed to that Mac run; none were reproduced here. No additional payload verification is proposed. Existing Windows/Android features, UI, encryption formats and accepted artifacts remain untouched.
