# Android-first parity through desktop 1.4.1

Status: Android development paths implemented; full Flutter regression and
targeted Android runtime evidence are recorded in COMMIT_VALIDATION.md. Complete
mobile parity acceptance remains pending. No production upgrade is included.

## Preservation

- Production package `com.nativedevps.futurenotes` and its private data stay untouched.
- Preview package `com.nativedevps.futurenotes.preview` uses synthetic notes only.
- No changes to desktop portable files in `D:\tools`, release tags or signing identity.
- Source commit/push to development is authorized. No release/tag/store publication is included.
- Note IDs, mention IDs, timestamps, body whitespace, unknown metadata and encryption formats remain compatibility requirements.

## Acceptance gates

Each item requires implementation, automated evidence and Android runtime acceptance.
An unchecked item is pending, including if a platform runner or plugin exists.

- [ ] Phone list/search to full-screen editor; tablet split view; stable navigation.
- [ ] Rich text and HTML, formatting, HTML formatter, undo/redo, IME and external keyboard.
- [ ] Touch formatting expansion without occlusion or selection loss; desktop hover unchanged.
- [ ] Inline unlocking, retained per-note unlock state, icons, updated-time/short-ID subtitles.
- [ ] Collapsed attachments, four-icon overflow, expanded contents, searchable full-screen gallery.
- [ ] Metadata, touch actions, compact jobs, cancellation and editor-focus collapse.
- [ ] Metadata-only mention suggestions, keyboard avoidance, touch Open and stable identities.
- [ ] Full-screen image/GIF/audio/video/PDF and native DOC/DOCX/XLS/XLSX previews.
- [ ] Playback, static GIF thumbnails, audio artwork, media Info and centered PDF gestures.
- [ ] Cache reuse across viewers/notes/background; immediate invalidation on lock/credentials/removal/exit.
- [ ] UID-safe import with Duplicate / Back up & Replace / Ignore and verified recovery copies.
- [ ] Export, streaming cancellation, native picking, sharing, external opening and supported drops.
- [ ] Themes, reduced motion, protected snapshots, media pause and no background auto-lock.
- [ ] Typed platform document handles and bounded byte I/O, with unchanged Windows backend.
- [ ] Persisted local/SD folder grants, disposable admission probes, precise provider errors.
- [ ] Recoverable provider publication, revision checks, backups, attachment-first order and readback.
- [ ] Versioned journals and pending guards compatible with desktop 1.4.1 cold opening.
- [ ] Short writes/full disk/revocation/ID changes/duplicate names/SD removal fault coverage.
- [ ] Private authenticated draft recovery, protected key, explicit Recover/Discard and revision checks.
- [ ] One retained Android writer/runtime, foreground jobs and notification cancellation.
- [ ] Durable safe job restart without stored passwords; timeout/permission/process-death recovery.
- [ ] Adaptive 70% resource budget with memory/thermal feedback and capacity preflight.
- [ ] Protected preview APK: obfuscation, R8, resource shrinking, private symbols, native ABI/alignment.
- [ ] Connected Android 12 runtime; minimum/current API and tablet coverage.
- [ ] Sustained large-file session, recreation/lock/wake/death, frame/CPU/memory/thermal evidence.
- [ ] Manual acceptance of all Android gates.

## iOS readiness (validation on hold: no Mac or iOS device)

- [ ] Shared interfaces and native scoped-bookmark/coordinated-I/O adapters.
- [ ] Keychain drafts, cache protection, external opening, lifecycle and bounded background tasks.
- [ ] Pinned Office static XCFramework build recipe and integration.
- [ ] Correct iOS 13 project inputs and native permission declarations.
- [ ] Mac/Xcode compilation and iPhone/iPad acceptance (unavailable on this Windows host).

## Toolchain decisions

Android Gradle Plugin is raised from 8.11.1 to 8.12.1 to satisfy the already
locked share_plus 12.0.1 requirement. Dependency versions remain pinned.
Preview signing uses the local development key only; production signing remains
separate and must not fall back to a development identity.

Stitch Pro is unavailable in the connected tool; the available Flash model is
used with synthetic content and the existing design system.
