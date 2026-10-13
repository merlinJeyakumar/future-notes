# Future Notes Rulesbook

## Scope and instruction precedence

Read this file before starting work in this repository. Follow higher-priority instructions and the user's latest explicit decisions. Clarify unresolved conflicts before taking affected actions. Do not infer approval from silence.

This rulesbook applies to this repository only. Inspect other NativeDevps projects and their rules separately before working in them.

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

## Design workflow

Use the Stitch Design plugin for design work and prefer the Stitch Pro model. If the plugin or preferred model is unavailable, report that limitation before using an alternative. Follow any explicit user planning-only or approval boundary before editing application UI, uploading design assets, or building.

Keep designs compatible with the Flutter implementation, including keyboard interaction, focus, readable contrast, and responsive layouts on the requested platforms.

## Validation and execution approval

Before builds, tests, device/emulator validation, CI, or production actions, state the exact command and wait for approval unless the user requested that exact run in the current turn. Existing explicit authorization remains valid for its stated scope; do not request it again. Production actions require explicit production authorization.

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

If validation fails, stop affected work and report the exact command and failure. Ask for confirmation before proceeding, enabling the feature, or replacing stable behavior. Preserve the last validated path. If a required check cannot run, state the reason and mark the work as pending validation.

## Existing validation limitations

These observations come from source inspection when this rulesbook was created; recheck them before relying on them:

- `test/widget_test.dart` contains starter counter assertions while `MyApp` opens the dashboard. It does not establish coverage of note workflows, and it has not been run in this session.
- `analysis.txt` references counter files absent from the inspected tree. Treat it as historical output, not a current analyzer result.
- Platform runners are present, but builds and runtime support have not been validated in this session.

## Reporting and completion

Be concise, factual, and direct. Report what changed, what was tested, the observed result, and remaining risks or limitations. Admit mistakes promptly and correct them carefully.

Distinguish implemented, validated, partially working, unsupported, and pending work. Never claim a feature works without relevant validation. A feature is complete only after successful validation; a failed experiment must not disrupt the stable path.
