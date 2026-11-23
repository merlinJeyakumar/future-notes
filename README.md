# Future Notes

Future Notes is a local-first Flutter notes application for writing, organising, protecting, and carrying notes with attachments across desktop and mobile workflows.

It supports rich-text writing and HTML/source editing, local note libraries, attachments, previews, import/export, search, sharing, and platform-aware file handling. Desktop and mobile experiences use different UI and platform adapters where the underlying operating-system interaction differs.

## What you can do

- Create and edit notes with a rich-text editor.
- Switch to an HTML/source editing mode when working directly with note markup.
- Organise notes in local libraries and select the working library on each platform.
- Save drafts, track save state, and recover from interrupted local operations.
- Search and filter notes and attachments.
- Add files and media to notes.
- Preview supported image, GIF, audio, video, PDF, Office, and document attachments through the available platform/UI paths.
- Import notes and packages, with conflict-aware import flows.
- Export notes and attachment content through file and package export paths.
- Share notes and attachments through the mobile and desktop integrations available for the current platform.
- Use password-protected note and attachment flows where those are enabled.
- Use Android-specific background-job, notification, document, share-intake, thumbnail, and attachment-transform integrations.

## How it works

Future Notes keeps note and attachment work local to the selected library. The application coordinates note content, attachments, previews, imports, exports, drafts, search, sharing, and recovery through a shared Flutter layer, then uses platform-specific adapters for file access and operating-system actions.

The main application chooses a startup and storage path for the current platform:

| Platform family | Application path |
| --- | --- |
| Windows | Uses the Windows-owned storage startup path. |
| Android and iOS | Use the mobile application path and mobile file/share adapters. |
| macOS and Linux | Use desktop storage-admission and file-access paths. |

## Main feature areas

| Area | Included capabilities |
| --- | --- |
| Writing | Rich-text editing, HTML/source editing, drafts, save state, note search, and filtering. |
| Local libraries | Library selection, discovery/admission, note envelopes/codecs, local write handling, recovery concepts, deletion, and shutdown handling. |
| Attachments | File selection, attachment ownership, previews, thumbnails, cache handling, media/document support, and background transforms where supported. |
| Import and export | Note/file import, conflict-aware import handling, package and streaming export paths, and mobile sharing destinations. |
| Platform integration | Android document/file channels, share intake, notifications, diagnostics, job state, thumbnails, and private drafts; iOS/macOS document and file-access adapters; desktop window and file actions. |
| Protection paths | Password-protected note and attachment workflows, application protection paths, and Android native-cipher capability integration where enabled. |

## Platform and release status

The source includes platform adapters for Windows, Android, iOS, macOS, and Linux. Availability and acceptance are not identical across those platforms.

| Platform | Current documented status |
| --- | --- |
| Windows | The repository documents a portable Windows x64 release workflow. Keep the complete release folder together when using a portable build. |
| Android | The repository documents an Android Preview build. It is not described as a production package or store-upgrade path. |
| macOS | The release notes record acceptance on an Intel Mac running macOS Monterey. Apple Silicon runtime acceptance remains separate and is not claimed here. |
| iOS | Mobile source and file/share integration paths are present. Native build, signing, device, and release acceptance remain pending. |
| Linux | Desktop source is present. Native build and runtime acceptance remain pending. |

See [release notes](scripts/release/RELEASE_NOTES.md) and the [implementation status](analysis/multiplatform-gap-review-2026-10-21/implementation-status.md) for current evidence and platform-specific limits.

## Toolchain baseline

Use the pinned Flutter SDK before resolving dependencies, analyzing, testing, or building:

| Component | Pinned value |
| --- | --- |
| Flutter | `3.41.5` stable |
| Framework revision | `2c9eb20739dfec95e2c74bd3dfa4601b0a8a36aa` |
| Bundled Dart | `3.11.3` |
| Application version | `1.4.4+11` |

Confirm the installed toolchain before work:

```sh
flutter --version --machine
flutter pub get --enforce-lockfile
flutter analyze --no-pub
flutter test --no-pub
```

Use the same Flutter/Dart baseline on build hosts and in the editor. The pinned toolchain supports reproducibility; it does not by itself establish that every native platform has passed release acceptance.

Desktop builds must be prepared on their native host. The repository includes a desktop Office-engine preparation script:

```sh
bash tools/build-desktop-office.sh
```

The script preserves an existing Office artifact rather than overwriting it. Native signing, permissions, packaging, and device validation remain separate release gates.

## Project layout

| Path | Purpose |
| --- | --- |
| `lib/` | Flutter application, local storage, platform adapters, note/attachment features, and desktop/mobile UI. |
| `android/` | Android integrations for file access, sharing, attachment work, diagnostics, notifications, and background jobs. |
| `ios/` and `macos/` | Apple platform document, sharing, file-access, and application lifecycle integrations. |
| `windows/` and `linux/` | Desktop runner and platform integration code. |
| `test/` | Static tests for storage, recovery, encryption paths, imports/exports, attachments, UI behavior, and motion. |
| `tools/` and `scripts/` | Build, release, validation, and platform-support tooling. |
| `analysis/` | Retained implementation and platform-validation evidence. |

## Local data and protection

Future Notes includes local storage and protection paths for notes and attachments. The application also includes recovery, generation-aware writes, file admission, caches, and storage ownership handling.

These source paths should not be interpreted as an independent security or privacy certification. Review the application, release configuration, device storage, and target platform requirements before relying on it for a specific security or compliance use case.

## Verification status

The repository contains static tests across storage, recovery, attachments, imports/exports, UI behavior, library discovery, and motion. This README does not claim a current green test run; run the relevant validation on the pinned toolchain and the target platform before a release.

## License and notices

Review the repository’s [licenses](licenses) directory and release tooling before distributing a build. Preserve existing third-party notices and platform-specific release requirements.