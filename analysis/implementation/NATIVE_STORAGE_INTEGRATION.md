# Native storage integration candidate

Branch: `integration/recoverable-storage`.
Preserved source checkpoint: `31dfe4e` on `repair/note-storage-safety`.

## Scope and activation

The normal entry point now composes the owned Windows backend when explicitly
requested. Default builds retain the prior writer. Opt-in is a preview, not a
completed production rollout. No original notes, settings, running process or
executable were accessed or changed while preparing this candidate.

`FN_RECOVERABLE_STORAGE=true` requires explicit absolute `FN_DATA_ROOT` and
`FN_SETTINGS_PATH`. The latter must name `settings.json`. Validation mode and
native preview cannot be combined. Malformed or partial input fails startup;
it does not silently fall back to another location or writer.

Do not enable the preview against original notes until backups are verified and
compatibility/recovery are rehearsed on an isolated copy. That gate remains
pending. This change does not move, convert or automatically select a library.

## Code-flow review

1. Capture configured paths before settings initialization. Only the captured
   library and configuration roots can receive worker capabilities. Reject
   overlapping roots unless they are identical, volume roots, traversal and
   existing filesystem links.
2. Start one owned Windows worker and recover settings under its lease. Strictly
   parse recovered settings and require the declared library to match the
   stored custom path, or the existing default layout when no custom path exists.
3. Prepare the note binding before exposing editor services or starting scans.
   If settings and notes share UserData, give each an independent capability
   referencing one recoverable store, writer lease and commit queue.
4. Save/autosave use captured references and acknowledged revisions. Note and
   settings operation sources stay inside a captured root; recovery files remain
   on the target volume. Preserve unknown fields and existing envelope/encryption
   formats. Retain originals and recovery versions.
5. Reject attachment mutation, password changes, import, package export,
   attachment export and Delete at both UI and view-model entry points. Service
   guards remain. Existing-note unlock/manual lock and editing/saving remain
   available; these paths still require runtime acceptance. Opening another
   native library is unavailable until that library has its own rollout review.
6. Report settings failures without optimistic UI publication. Failed startup
   retains acquired resources behind a non-editable error screen. Orderly exit
   reuses the existing watcher/storage cleanup sequence. Releasing one shared
   root capability must not close the other binding's lease.

## Validation disposition

The user retained code-review-only validation. Seven regression tests were added
for admission/isolation, shared-root commits and lease lifetime, settings-path
disagreement, external-write rejection and draft-preserving workflow guards.
They have not been executed.

Formatting parsed all 15 affected Dart files successfully (10 formatted), and
the tracked whitespace check passed. Static analysis completed with exit 0,
no errors, the original two unused-import warnings and 99 informational
diagnostics (101 total). Informational findings remain open; this is not a
lint-clean release or evidence of runtime correctness.

Exact successful static tooling commands used the bundled executable
`C:\src\flutter\bin\cache\dart-sdk\bin\dart.exe`: `format` on the 15 affected
Dart files and `analyze --no-fatal-warnings` on the repository. `git diff --check`
also passed. The formatter initially could not initialize its Dart configuration
folder under sandbox permissions; the retry used tooling access. A first
analyzer invocation used unsupported `--no-fatal-infos` and did not analyze
source. The corrected invocation analyzed source once; no duplicate test or
build runs occurred.

No tests, build, dependency resolution, app launch or real-note rehearsal were
performed. Prior executable and source checkpoints remain preserved; new source
is not proof of runtime safety.

Pending: isolated execution of the new regressions and existing storage/session
regressions, affected Windows compilation, manual runtime acceptance, backup and
recovery rehearsal, and explicit activation. Unfinished workflow adapters and
R01 encryption migration remain outside this integration candidate.
