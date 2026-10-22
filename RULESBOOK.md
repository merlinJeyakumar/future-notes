# Future Notes Rulesbook

## Scope and instruction precedence

Read this file before starting work in this repository. Follow higher-priority instructions and the user's latest explicit decisions. Clarify unresolved conflicts before taking affected actions. Do not infer approval from silence.

This rulesbook applies to this repository only. Inspect other NativeDevps projects and their rules separately before working in them.

## Requested scope

Do only the work the user requests and the necessary supporting steps to complete it. Do not suggest extra features, unrelated improvements, optional validation, or follow-up tasks unless the user asks for suggestions. Use reasonable judgment for routine implementation details without expanding the requested outcome.

Do not silently substitute a guarded preview, restricted build, alternate backend, isolated app, or reduced feature set for the version the user requested. Testing in isolation does not authorize substituting an isolated app for the requested app. If the requested outcome cannot be delivered within the agreed constraints, explain the concrete blocker and ask one concise clarification before making that substitution.

Do not disable existing features, add user-facing restrictions or warnings, change storage locations, or create extra app entry points unless required by the requested work and already authorized. Preserve existing notes and unrelated changes throughout.

## Engineering priorities

1. Reliability
2. Accuracy
3. Low latency
4. Resource efficiency
5. Maintainability
6. New features

Investigate existing behavior before editing. Keep changes small, reversible, and consistent with established patterns. Do not add dependencies or architectural complexity without a measurable benefit. Preserve the last known validated implementation until its replacement passes validation; an untested checkout is not evidence of stable behavior.

## Project structure

The repository contains a Flutter/Dart notes application. The package name is currently `flutter_application_1`; preserve package imports unless renaming is explicitly in scope. Read `pubspec.yaml` and `pubspec.lock` for the actual SDK constraint and dependency versions.

| Path | Responsibility |
| --- | --- |
| `lib/main.dart` | Application entry point, theme, and dashboard routing |
| `lib/core/viewmodels/base_viewmodel.dart` | Shared `ChangeNotifier` busy state |
| `lib/features/dashboard/models/` | Note serialization and recent-file metadata |
| `lib/features/dashboard/viewmodels/content_viewmodel.dart` | Editing state, save/load, autosave, locking, file watching, and import coordination |
| `lib/features/dashboard/services/` | File operations and encryption behind existing interfaces |
| `lib/features/dashboard/views/` | Screen composition and platform actions |
| `lib/features/dashboard/widgets/` | Sidebar, editor, Markdown preview, and toolbar UI |
| `test/` | Flutter tests |
| `android/`, `ios/`, `linux/`, `macos/`, `web/`, `windows/` | Platform runners and configuration |

Preserve the existing view/view-model/service boundaries. Keep persistence and encryption in services and state transitions in the view model. Dispose controllers, timers, subscriptions, and listeners owned by a component. A declared dependency does not establish that the application uses it.

## Locked platform behavior

Accepted platform code, features, designs and bug fixes are locked while working on another platform. Android/iOS work must not change or regress accepted desktop behavior, and desktop work must not change or regress accepted mobile behavior. Keep platform presentation and native adaptations isolated. Do not remove an existing guard, feature or fix to make another platform work.

Mobile typing keeps attachment shelves behind the on-screen keyboard rather than above it; hiding presentation must not cancel jobs or recreate editor controllers. Mobile autosave is edit-driven, waits for a meaningful idle period and minimum write interval, and defers during attachment/import/export or other owned mutations. Explicit Save and private encrypted recovery remain available. Selection, progress, focus, lifecycle and configuration notifications alone must not schedule library writes or recovery rewrites. Desktop autosave policy is independent and remains unchanged by mobile scheduling work.

Provider change/resume notifications are hints, not a reason to reset the notes list or show a loading bar. Reconcile envelope metadata quietly, reuse unchanged discovered rows, and decode changed entries only. Explicit Refresh bypasses that display cache. Preserve errors, permission handling, storage revision checks and stale-result guards; a discovery cache is not write authorization. Do not display legacy settings on mobile when its active storage path does not use them; retain settings needed by accepted other-platform paths.

Before modifying shared code, identify every affected platform and compare the established implementation with Git. Limit changes to the user's authorized scope; if the change requires altering locked behavior on another platform, explain the concrete impact and obtain the user's decision first. Preserve the accepted artifacts and run the affected compatibility and runtime regressions before replacing them or claiming preservation. Passing tests or startup checks for the target platform alone does not validate other platforms. When an affected platform cannot be validated, report that gap and do not treat its locked behavior as verified.

## Before changes

- Read applicable `AGENTS.md` files and this rulesbook, then inspect the branch, Git status, relevant source, and existing tests.
- Establish the requested scope, expected behavior, and available validation evidence.
- State concrete risks and limitations before implementation, especially for note storage, encryption, autosave, and platform behavior.
- Preserve unrelated edits and untracked files. Do not reset, clean, overwrite, or discard them.
- Do not commit, push, deploy, or change the user's branch unless the user authorizes that action.
- Avoid hand-editing generated files. Change their inputs and use the appropriate generator when required and authorized.

## Notes, storage, and encryption

Native file services currently use a `UserData` directory under the application documents directory. Web saving uses a browser download; native directory listing and file operations are not equivalent to web behavior. Platform folders alone do not prove platform support.

- Use disposable notes and an isolated data location for destructive validation. Never delete or overwrite real user notes as a test.
- Preserve note JSON fields, existing file formats, and legacy decryption compatibility unless a migration is explicitly authorized.
- Before changing formats, encryption, password handling, storage paths, or import collision behavior, define backup, migration, rollback, and failure recovery. Validate compatibility with existing data before enabling the replacement.
- Keep plaintext notes, passwords, keys, and sensitive paths out of logs, screenshots, fixtures, and reports.
- Do not describe existing encryption as secure merely because it uses AES. Review key derivation, IV handling, integrity protection, and error behavior when those paths are in scope.
- Check that failed saves, failed unlocks, malformed files, and interrupted operations preserve existing content. Do not persist error messages as note content or report a failed write as successful.
- Validate autosave and file-watcher interactions for overlapping writes, stale updates, and resource cleanup when changing those paths.

## Processing defaults and import behavior

- Apply the same processing policy across supported platforms. Preserve encryption/package compatibility, note and mention identities, recovery guarantees, and the accepted desktop/mobile designs.
- Do not plan, add, or re-enable extra full-file verification, comparison, or read-back passes unless the user explicitly requests them. If correctness appears to need an extra verification pass, explain the purpose and cost and obtain the user's decision before adding it. Do not silently describe an optional pass as required.
- Default all optional checks to `false`: source checking, decrypted-output verification, exported-backup validation, and extra verification after large writes. Missing older settings and Reset defaults must also use `false`. Preserve explicitly saved user choices; do not let platform rules or helpers silently override the captured job policy.
- Perform encryption, decryption, extraction, copying, or packing in the necessary processing pass. Calculate required checksums/CRC during that pass. Avoid separate checksum scans, plaintext intermediates, repeated staging reads, and redundant copies. Keep necessary provider transfers and recovery backups; report them as actual work.
- Preserve basic safety: valid paths and filenames, format/framing and bounds checks, capacity limits, short-read/write detection, flush/close, ownership and destination conflicts, cancellation, journals, attachment-first publication, and small note-metadata revision checks. Recovery may inspect ambiguous interrupted transactions. These protections do not authorize optional normal-job payload rescans.
- On package import, use the note ID to detect conflicts and show Duplicate / Back up & Replace / Ignore. Do not compare incoming and existing payloads before showing the choices, or silently skip the dialog because their contents appear identical. Keep necessary incoming-package extraction and format checks.
- Read bounded note metadata and resolve a matching UID before attachment extraction. For ZIP, decompress only the note metadata entry for this decision; for a protected archive, decrypt only its metadata. Ignore must stop without extracting or decrypting attachments. Proceeding imports retain their existing payload-format checks, progress, publication and recovery guarantees. Check source file metadata across the decision and retain the reviewed note identity; do not add full-file fingerprints or verification passes for this guard.
- Ignore and Duplicate must not read existing attachment payloads. Back up & Replace must retain the recovery predecessor and check attachment availability without full-file predecessor hashing or a second attachment-revision scan. Keep the note-envelope revision and draft/session guards so conflicting edits do not overwrite the current note.
- Reuse valid decrypted caches across viewers and note switches until lock, credential changes, removal, or exit revoke them. Reuse prepared exports when source and options are unchanged; invalidate them when their inputs or owning session change. Do not decrypt or repack again merely because the user reopens the same item or requests the same unchanged export.

## Processing messages and results

- Use concise, professional labels that describe the actual operation: Encrypting, Decrypting, Extracting package, Packing export, and Saving encrypted files. Use "Saving encrypted files" for the local provider write instead of "Publishing encrypted data"; do not imply an upload or another encryption pass.
- Show the current filename, File N of M for batches, changing processed/total bytes, percentage when the total is known, and a progress indicator. Use an indeterminate indicator when the total is unknown. Do not invent progress or display checking/verifying stages when those optional passes are disabled.
- Present one progress entry per job. Make active work discoverable from its note/file item and Background tasks, and allow hidden progress to reopen for the same job. Progress updates must not steal editor focus or change panel expansion.
- Keep job execution separate from its dialog. Hide/Back hides active progress without cancelling; cancellation remains an explicit action. Release export editing locks when processing ends, while retaining an already-open terminal result until the user closes it.
- When a mobile export is ready, offer separate platform-native Save and Share actions with a meaningful, safe filename based on the note title. Keep the result dialog available after either action or native-picker cancellation until the user explicitly dismisses it.

These runtime processing defaults do not waive the development validation requirements below. Do not repeat successful development checks without a new change, failure, or unresolved concern that justifies the rerun.

## Design workflow

Use the Stitch Design plugin for design work and prefer the Stitch Pro model. If the plugin or preferred model is unavailable, report that limitation before using an alternative. Follow any explicit user planning-only or approval boundary before editing application UI, uploading design assets, or building.

Keep designs compatible with the Flutter implementation, including keyboard interaction, focus, readable contrast, and responsive layouts on the requested platforms.

## Validation and execution approval

Treat a user's request to implement, fix, validate, build, run, or launch as authorization for the task-focused commands and permission requests reasonably required to complete that request. This includes formatting, syntax checks, static analysis, relevant tests, affected-platform builds, dependency resolution that does not upgrade versions, isolated runtime validation, and ordinary retries or narrow corrections after a failed check. State material commands and their scope in progress updates, but do not stop to request another approval merely because the exact command was not written by the user.

Task-focused authorization persists until the requested outcome is complete, the user pauses or cancels it, or the work would cross one of the boundaries below. Request explicit approval before:

- destructive or irreversible actions;
- production deployment or production-data mutation;
- accessing or mutating real notes when the request is limited to isolated validation;
- forced process termination when normal shutdown has not completed;
- committing, pushing, changing branches, or publishing unless the task request already authorizes it;
- expanding into unrelated work or materially increasing the agreed risk.

Request necessary sandbox or operating-system permissions directly through the available execution tool when they are task-focused. Do not ask the user a separate conversational permission question first. Existing authorization remains valid for corrections and reruns within the same scope; do not request it repeatedly.

For executable code changes, run syntax/format checks, static analysis, relevant tests, and a build for the affected target after each coherent change, once authorized. Use the repository's existing tooling. Typical commands from the repository root are:

```powershell
git diff --check
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build windows
```

Select a narrower formatting/test scope where appropriate. `flutter build windows` applies to Windows changes; choose the requested platform's build command for other targets. Do not run every platform build by default. Install dependencies with `flutter pub get` only when needed; do not upgrade dependencies as a side effect of validation.

For documentation-only changes, review content, referenced paths, whitespace, and the Git diff. Application builds and runtime tests do not validate prose and are not required for that scope.

For runtime features, verify visible startup, logs, error handling, latency, resource usage, and continuous operation for a stated duration. Test integrations under realistic usage conditions. For note workflows, cover the affected save/reopen, editing/preview, import, lock/unlock, and failure paths. Report the device/platform, commands, duration, and observed evidence. Passing static checks or a build does not establish runtime success or support for other platforms.

If validation fails, stop dependent actions, report the exact command and failure, diagnose the cause, and make narrowly scoped corrections within the already authorized task. Rerun only the relevant failed gate without requesting repeated approval. Ask before proceeding only when the correction crosses an approval boundary above, enables an unvalidated replacement on real data, or materially changes scope or risk. Preserve the last validated path. If a required check cannot run, state the reason and mark the work as pending validation.

## Release assets and preservation

Future releases must publish only these three application downloads:

- Android: the protected APK directly, without an additional ZIP wrapper.
- macOS: the DMG directly, without an additional ZIP wrapper.
- Windows: one ZIP containing the complete protected portable folder, including the EXE, DLLs, data, runtimes, licenses and instructions needed to run it.

Do not upload loose Windows files, downloader scripts, checksums, manifests or provenance as additional release assets. Include supporting files inside the appropriate package or provide checksums and provenance in the release description. GitHub-generated source archives are separate from these uploaded application assets. Validate package contents and the final uploaded asset inventory before declaring the release complete.

Preserve all existing releases, their assets and existing tags. A new release or promotion does not authorize deleting older releases, pruning older local release builds, replacing existing release assets, or moving, overwriting or deleting tags. Perform such cleanup only when the user explicitly requests that specific change. Preserve notes and unrelated files throughout.

## Existing validation limitations

These observations come from source inspection when this rulesbook was created; recheck them before relying on them:

- `test/widget_test.dart` contains starter counter assertions while `MyApp` opens the dashboard. It does not establish coverage of note workflows, and it has not been run in this session.
- `analysis.txt` references counter files absent from the inspected tree. Treat it as historical output, not a current analyzer result.
- Platform runners are present, but builds and runtime support have not been validated in this session.

## Reporting and completion

Be concise, factual, and direct. Report what changed, what was tested, the observed result, and remaining risks or limitations. Admit mistakes promptly and correct them carefully.

Distinguish implemented, validated, partially working, unsupported, and pending work. Never claim a feature works without relevant validation. A feature is complete only after successful validation; a failed experiment must not disrupt the stable path.
