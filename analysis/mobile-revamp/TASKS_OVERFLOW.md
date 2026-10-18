# Background tasks overflow access

Implemented 2026-10-18 following the request for a professional icon and overflow placement on every platform layout.

## Presentation

- Removed the standalone mobile task button. Notes-list headers use the standard More actions overflow; editor Note actions include Background tasks.
- The Background tasks action uses Material `pending_actions`. Desktop sidebar and editor use the same placement and label, including access while the note is locked.
- Extracted the existing dialog into a shared widget. Desktop does not create a mobile job binding. Mobile retains its existing export/recovery routing and native notification ownership.
- Jobs, cancellation, recovery records, encryption, caches, optional verification settings and notes are unchanged by this presentation change. No persistent completed-job history was added.
- Stitch Flash reference saved under `.stitch/designs/tasks-overflow.*`; Pro was unavailable. Generated additional menu actions and count badges were not adopted.

## Automated validation

Formatting and whitespace checks passed. Scoped analysis had zero errors/warnings and 41 informational lints (including existing editor/context/deprecation notices); `--no-fatal-infos` completed successfully.

One combined affected suite covered overflow access, task lifecycle/recovery, export progress, navigation, note opening and keyboard focus. It initially found a 1.6 px label overflow in two new tests. A flexible menu label corrected it; the affected five-test file then passed. Final result: 40 distinct tests passing, not 43 (which included reruns).

Protected Android build: 61.9 s. APK SHA-256:
`32d3bd36b81835b5f31d20f2005de7a71da16f44fdaae6115e27f09f1afad715`.
18 native libraries inspected; all 64-bit ELF load segments and APK alignment passed 16 KiB checks.

Protected Windows build: 56.9 s. ASLR, high-entropy ASLR, DEP, CFG, stack cookie and dependent-load flags passed existing hardening checks.

## Runtime and acceptance

LG LM-G900, Android 12: no foreground attachment service before replacement; data-preserving install succeeded. Cold launch 1371 ms. Stable foreground PID for 20 seconds, keyguard absent, zero fatal/layout matches, PSS 162632 KiB. Screenshot confirmed normal notes list with settings and overflow, without a standalone task indicator. No app input or note edits were sent.

Windows candidate: main window created in 3609 ms; responsive after 20 seconds, zero fatal/layout matches, working set 166735872 bytes. No note edits performed. Manual menu acceptance is pending on both devices; shared widget tests cover opening and selection.

Other platform layouts share this implementation; iOS/macOS/Linux/browser builds and device acceptance were not performed. Existing support limitations remain unchanged.

Accepted APK and full Windows bundle preserved in `.validation/tasks-overflow-accepted/`. `D:\tools`, notes, existing tags and portable releases untouched. No commit, push or publication.

Evidence: `.validation/tasks-overflow-analysis-final.txt`, `tasks-overflow-tests.txt`, `tasks-overflow-tests-corrected.txt`, `tasks-overflow-apk.json`, `tasks-overflow-install.json`, `tasks-overflow-startup.json`, `tasks-overflow-windows-startup.json` and task-specific build logs.
