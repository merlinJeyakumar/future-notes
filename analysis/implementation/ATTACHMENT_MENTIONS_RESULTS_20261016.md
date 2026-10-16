# Attachment mentions — 16 October 2026

## Implementation

- Current-note committed attachments provide caret-anchored `@` suggestions, filename filtering with spaces/Unicode, type/size and duplicate-name ID suffixes. Suggestions read metadata only.
- Mouse and Up/Down + Enter/Tab insert; Escape, focus changes, navigation, locking and mode changes dismiss. IME composition suppresses suggestions. Existing editor controllers and Home/End handling remain in place.
- Rich text uses standard link attributes with Ctrl+click opening. HTML inserts escaped, editable `<a href="fnotes://attachment/...">` source. The converters retain valid attachment URIs while other URLs retain the pinned converter's sanitization.
- Typed internal routing handles attachment identities and unsupported resources; internal URIs are not registered with Windows or passed to system launchers. Existing `note://` handling remains.
- Optional `mentionId` is assigned with the first mention edit. Save, rekey, export/import, Duplicate and Back up & Replace preserve it across fresh storage IDs. Old notes are not rewritten on open. Missing/ambiguous references are unavailable.
- Cards and mentions share preview intent deduplication, cached opening, session/credential checks and viewer teardown. A space after insertion is unlinked; rich insertion is isolated in undo history.
- Stitch reference: project `6056916933162144137`, screen `5888686ce2454e0cb5ec52a9d0d4b3d7`, existing design system. The connected tool lacked Pro selection; Flash was disclosed and used with synthetic filenames. Only the popup refinement was adopted.

## Automated validation

All 96 distinct checks passed across the combined affected run and narrow correction runs: 85 existing focus/card/import/cache/session/save tests, eight mention tests and three owned-storage mention integration tests. This is accumulated passing coverage, not a claim that the first command passed.

Combined command:

```powershell
& 'C:\src\flutter\bin\flutter.bat' test --no-pub --concurrency=1 test/attachment_mentions_test.dart test/storage/attachment_mentions_integration_test.dart test/attachment_editor_focus_test.dart test/attachment_strip_test.dart test/storage/note_import_test.dart test/storage/attachment_cache_lifecycle_test.dart test/viewmodels/session_safety_test.dart test/viewmodels/save_coalescing_test.dart
```

- Initial compilation exposed an accidental brace-cleanup scope error in `note://`; it was corrected before any candidate build.
- The combined resumed run passed 91 and failed four checks. Three new fixtures needed their cache directory created. A rich popup check exposed a query beginning inside an existing link; the implementation now rejects it. Corrected integration tests all passed.
- Narrow mention reruns passed mouse/keyboard focus, actual Quill/HTML composition state, rich and HTML undo/redo, persistent metadata, unavailable/ambiguous references, HTML round trips and unchanged URL sanitization. Suggestions produced zero fake-cache opens and zero binary decryptions.
- Owned integration tests passed real streaming-cache reuse until lock; rekey/removal; binary and ZIP locked import with fresh storage IDs; duplicate detection, Duplicate and verified replacement with working references.
- Final raw-HTML context regression verifies that `<` operators in scripts/styles cannot suppress subsequent text suggestions. Final command `flutter test --no-pub test/attachment_mentions_test.dart` passed all eight; scoped parser/test analysis had no issues.
- Changed files passed Dart formatting and `git diff --check`. Scoped analysis had zero errors/warnings; existing informational notices remain in the large view model and UI files.

Local logs: `.validation/attachment-mentions-tests-resumed.txt`, `attachment-mentions-tests-correction.txt`, `attachment-mentions-html-context-final.txt`, `attachment-mentions-final-analysis.txt`.

## Protected Windows builds and preservation

The accepted executable was copied to `.validation/attachment-mentions-previous-candidate` and its EXE/AOT hashes matched before compilation. Published portable folders, tags and original notes were not modified by validation.

Protected canonical build:

```powershell
& 'C:\src\flutter\bin\flutter.bat' build windows --release --no-pub --dart-define=FN_MOTION_DIAGNOSTICS=true -t lib/main.dart --obfuscate "--split-debug-info=$privateSymbols" "--extra-gen-snapshot-options=--save-obfuscation-map=$privateSymbols/obfuscation-map.json"
```

Private symbols remain outside distributable output. PE verification passed ASLR, high-entropy ASLR, DEP, CFG, stack cookie and dependent-load flags `0xA00`.

The first protected build passed in 42.0 s. After final review identified the raw-HTML operator case, its passing parser correction required one replacement build (43.1 s), preserving that first candidate too. No unchanged duplicate build was run. The existing CMake `FetchContent_Populate` developer deprecation remains.

Final receipt: `.validation/attachment-mentions-final-build-receipt.json`; every receipt input and both binary hashes were checked before a single launch of the final candidate.

- EXE SHA256: `0BB6B62942CEB0B2E3E3C4D71B8F2FA8E58F24B7AD3F13B5F991A3C8E9EDC243`
- AOT SHA256: `FCB829AC50AC1084699366F33C3F1AB98532EA014CC3A2053563019F9332D0D7`

## Manual acceptance and runtime boundary

The user reported “works excellently” after the requested check of suggestions, keyboard/mouse insertion, Rich text Ctrl+click opening, non-clickable HTML source, focus, Save/reopen and Escape, and explicitly authorized validation, commit and push to development. The subsequent parser-only correction has automated regression coverage; the visible workflow is unchanged.

The final full editor was observed through a read-only window capture. No automated keyboard/mouse input or forced process termination was used. The first candidate remained responsive during manual use; its logs reproduced the existing Flutter Windows AXTree accessibility error also present in `.validation/editor-focus-collapse-runtime.stderr.txt`. This is not reported as a clean accessibility acceptance or a new mention failure. Final startup logged initialized process protection and media registration without an application error at the initial observation.

Resource/frame observations are bounded samples, not a memory-leak, prolonged stress or accessibility certification. The final candidate remains available for normal use. No release publication, ZIP or tag changes are part of this delivery.
