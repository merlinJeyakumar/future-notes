Future Notes 1.4.4 (build 11) provides protected Windows x64 portable,
Android Preview APK and macOS universal DMG downloads.

Changes since 1.4.3:

- macOS uses native selected-file/folder permissions and retained library
  bookmarks. Library switching, refresh, autosave and restart retain the selected
  folder and saved notes. Finder metadata is excluded from note identity scans.
- macOS export saves both new files and replacements through the authorized save
  target, preserving recoverable predecessors. Import resolves matching IDs before
  attachment extraction and supports Duplicate, Back up & Replace and Ignore.
- macOS image, GIF, audio, video, PDF and Office attachment previews, external
  opening, Finder reveal, multiple-file attachment/drop and batch Save are available.
- Find inside a Mac rich-text note is separate from sidebar file search. Enter
  accepts the highlighted match and returns typing to the editor. Close also
  restores typing after the Find dialog has finished closing.
- Shared attachments retain their current storage generation through password
  set/removal. Failed protection saves preserve the existing data and allow retry.
- Native storage adapters and iOS permission/task-notification source are staged
  without changing accepted Windows/Android defaults or encryption/package formats.

Downloads:

- Windows: use Download-FutureNotes.ps1 to reconstruct the complete portable
  folder from individual release assets. Keep FutureNotes.exe, DLLs and data
  together; the EXE alone is insufficient. No ZIP or runtime installation is needed.
- Android: FutureNotes-Preview-1.4.4.apk is a release-mode, obfuscated/R8-protected
  Preview using the existing .preview package/signing identity. It is not a
  production-package/store upgrade. Existing Preview notes are retained on update.
- Mac: Future-Notes-1.4.4-build11-macOS-universal.dmg contains Future Notes.app and
  the Applications shortcut. It packages Intel and Apple Silicon binaries. The
  app is ad-hoc signed, not Developer ID signed or notarized.

Source/build provenance:

- v1.4.4 identifies the development source and the unchanged Windows/Android
  Flutter 3.41.5 / Dart 3.11.3 dependency baseline.
- v1.4.4-apple-compat identifies the approved Monterey compatibility source,
  Flutter 3.38.3 / Dart 3.10.1 and its separate pinned compatibility lock/tooltip
  adaptation. The functional fixes and application version are aligned.
- release-provenance.json records each artifact's exact source and SHA-256.
  Private crash symbols, name maps, notes, settings, recovery drafts and decrypted
  caches are excluded from release assets.

Validation and limits:

The accepted Intel Mac on macOS 12.7.6 passed the selected-library, export new/
replace, package import conflict outcomes, media/PDF/Office preview, attachment
picker/drop/password/batch-save, restart and actual Find Enter/Close typing checks.
This does not establish Apple Silicon runtime or every OS/codec/large-file case.
iOS native app build/link, signing, App Group registration, permission prompts,
background expiration and iPhone/iPad acceptance remain pending; Linux native
acceptance is not claimed. Windows remains unsigned; same-PC validation is not
clean second-PC acceptance. Android remains the previously selected Preview.

Release promotion checks the affected suites, builds, private-symbol exclusion,
native library packaging, signatures/identities, portable startup and uploaded
asset sizes/digests before publication. See the release-provenance record for the
actual results. All optional file-verification settings still default to off;
basic encryption/format/bounds/recovery protections remain enabled.

Keep prior releases and a separate notes backup. Existing tags, release assets,
library locations and notes are preserved. The repository is private; authenticated
GitHub downloads are required. Download helpers never persist credentials.
