# Mobile editing behavior validation

Candidate: protected Android Preview 1.4.2+9, based on development
`79720e016af810249cf16e2940dada6fb2f53c43`. No commit, push or publication.

## Implemented

- The mobile attachment shelf uses the owning Flutter view's keyboard inset.
  It hides behind the IME without disposing its state or editor controllers;
  background jobs continue and remain accessible through Background tasks.
- Mobile library autosave waits for 15 seconds of editing idle and at least
  30 seconds after the last successful write. It defers during owned jobs,
  mutation, loading, conversion and inactive/background lifecycle states.
  Explicit Save remains available. Desktop retains its existing two-second
  policy through the default constructor policy.
- Private encrypted draft recovery remains separate, with its existing
  750 ms edit debounce. Selection, progress, focus and repeated lifecycle
  notifications do not rewrite an unchanged draft.
- The unused mobile File compression setting is removed from presentation.
  Legacy settings and implementations used by other paths remain intact.
- Provider change/resume hints reconcile metadata quietly, preserving unchanged
  row identities and avoiding note-byte reads for unchanged envelopes with
  usable modification metadata. Explicit Refresh bypasses this display cache;
  unknown modification metadata is read normally. Storage authorization,
  permissions, stale-result guards and failure reporting remain in place.

## Automated validation

- Focused suite: 77 passed; lifecycle follow-up: 9 passed; compatibility suite:
  104 passed. These suites overlap and are not a combined unique-test count.
- Final `dart analyze lib`: zero errors or warnings, 315 informational lints.
  New mobile persistence and recovery tests: no analyzer issues.
- Formatting and `git diff --check` passed.
- Protected Windows compatibility probe passed legacy protected/unprotected
  fixtures, direct and worker decryption, cache reuse/revocation, Save/Attach/Open,
  all source/output-check combinations and UID-first import outcomes.
  The accepted workspace Windows executable was restored after the probe.
- Protected Android normal APK built successfully. Signing identity, package
  and version, ZIP alignment, native-library packaging and absence of private
  symbol files were checked. All packaged 64-bit ELF libraries have at least
  16 KiB load alignment.

## LG LM-G900, Android 12

Real SAF storage and disposable protected notes were used; user notes were
not edited. The probe removed its disposable provider folder afterward.

- The first timed run passed actual idle/cadence scheduling and zero-byte
  unchanged discovery. Its keyboard gate failed because the LG reported IME
  requested/shown but rendered no keyboard and provided no Flutter bottom inset.
- After the user enabled the visible on-screen keyboard, the remaining native
  probe passed real keyboard shelf hiding/restoration, stable document identity,
  attachment completion without an extra autosave, quiet list refresh,
  background autosave suspension and explicit Save.
- Two synthetic provider commits in the final run took approximately 2.58 and
  2.45 seconds. This is not a general storage-performance benchmark.
- Evidence is split across the timed cadence run and the final passing input
  run; the earlier keyboard failure is retained in the validation receipts.
- The normal protected Preview was installed with matching signing identity
  using `adb install --streaming -r`, without clearing data. Cold launch reported
  1,334 ms. Its PID remained stable for 20 seconds with no fatal/layout log
  matches and approximately 127 MiB total PSS. The normal notes list, search and
  New note control were visually confirmed. Android accessibility did not expose
  the title/search text to the exact-label check, so visual inspection completed
  that gate; the temporary startup image was then removed.

Machine receipts and command logs are under
`.validation/mobile-editing-behavior/` (ignored local evidence).

## Delivery and limits

Normal candidate SHA-256:
`590d38eadc7fff1521435cb18537d8d89cec07c62c369aa5b54f9d587b95b286`.
The accepted APK and published portable builds remain preserved. Desktop
presentation and Windows native source were not changed. Shared scheduling
and discovery changes were checked with the Windows runtime compatibility
probe and affected regressions. iOS device/build validation remains deferred;
this Android validation does not establish iOS runtime acceptance.

## Follow-up: horizontal mobile formatting

The collapsed mobile formatting row now exposes all existing tools through
horizontal touch scrolling. The expand/collapse button remains outside that
viewport, and expansion retains the existing wrapped layout. Desktop toolbar
source is unchanged. A real-editor widget test verifies scroll extent, swipe
movement, fixed disclosure position, stable height, selection, focus and
document identity. The combined toolbar, mobile focus, keyboard/persistence and
desktop toolbar suite passed all 24 tests. Scoped analysis has zero errors or
warnings (18 informational lints). The protected Preview APK built in 103.4 s,
passed signing/packaging/alignment checks and was installed without clearing
data, with a reported cold launch of 1,428 ms. Physical swipe acceptance remains
pending the user's check; iOS device acceptance remains deferred.

APK: `build/releases/FutureNotes-Preview-1.4.2-toolbar-scroll.apk`.
SHA-256: `23d2d848243d09561f42e3427a1913e49dfb827de8af54d06d8afa253d54f4c0`.
Receipts: `.validation/mobile-toolbar-scroll/`.

## Follow-up: selection-menu placement

The mobile Rich text context menu now measures its actual size and stays inside
the visible editor viewport, excluding the header, formatting bar, safe areas
and keyboard. It uses the editor's existing localized adaptive buttons and
callbacks. First-line selections place the menu below the handles; lower
selections prefer available space above. Narrow layouts can scroll the action
row. Keyboard and panel changes reflow the placement without replacing editor
controllers. Desktop selection and formatting code are unchanged.

Nine new tests passed: Android/iOS widget layouts at first/middle/bottom and
multiline selections, enlarged text, horizontal action access, IME resizing,
and real Quill Copy callback/clipboard-write behavior. The initial iOS label
assertion and clipboard mock were corrected; no production clipboard behavior
was changed to satisfy tests. The affected existing toolbar/focus/keyboard
tests also passed. New selection source/test analysis reports no issues;
the mobile content file retains its 18 informational lints and has no analyzer
errors or warnings. Protected Android build passed in 74.3 s, packaging/alignment
and matching signing identity passed, and Preview was updated without clearing
data. Physical device gesture acceptance remains pending; iOS build/device
validation remains deferred.

Stitch refinement used the existing Future Notes design system with synthetic
content. Pro was not an available model enum; `GEMINI_3_8_FLASH` was used. The
review recommends the same below-first-line / above-lower-selection rule and
narrow-screen access. Local reference: `.stitch/designs/mobile-selection-menu.*`.

APK: `build/releases/FutureNotes-Preview-1.4.2-selection-menu.apk`.
SHA-256: `28ad972d0dfc6c0ea3d2194845901b218d7beac79b5f25cb4a80ad4f8e2d58ed`.
Receipts: `.validation/mobile-selection-menu/`.

The installed normal candidate retained a stable PID for 20 seconds with no
fatal/layout log matches and about 63 MiB PSS while backgrounded. The LG was
locked (`keyguardShowing=true`, Preview not resumed), so this is a process
stability observation, not visible startup or physical menu acceptance.

After the user unlocked the LG, the normal installed Preview was launched and
checked using a disposable unsaved draft. Physical-device screenshots confirm
that the first-line menu appears below the selection handles while the real LG
keyboard is visible, with formatting controls unobstructed. A lower-line
selection places the menu above the text. Copy then Paste replaced the selected
synthetic word correctly, verified visually because Android accessibility did
not expose the complete Quill body. The temporary draft was explicitly
discarded without saving, and Preview was returned to the notes list. Existing
notes were not edited. Content-free receipts and synthetic screenshots are in
`.validation/mobile-selection-menu/device-*`.

## Final commit validation, 20 October 2026

One combined affected suite passed all 186 tests across mobile editing,
recovery, toolbar/menu placement, keyboard/focus, navigation, HTML, job lifecycle,
provider discovery, save/session safety, library switching, owned mutations,
attachment cache and the unchanged desktop toolbar. Formatting checked 20 Dart
files with zero changes. Scoped analysis completed with zero errors or warnings
and 132 informational lints. The staged scope excludes desktop widgets/views,
native runners, generated headers, dependency configuration, APKs, private
symbols, notes and unrelated analysis/design artifacts. The earlier protected
Android build and native Android/Windows evidence above cover the unchanged
executable patch; no new product code was added during this commit review.
