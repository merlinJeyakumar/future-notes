# Canonical Windows backend integration

The requested launch is `lib/main.dart` in Windows Debug, with the existing settings file and its selected library. No validation target or preview launcher substitutes for that launch. The user performs app interactions; the agent reads logs only.

## Ownership and publication

- Windows bootstrap checks the existing configuration without rewriting it, then creates owned settings and note services. Settings recovery and note-root recovery precede discovery and watchers. Native library admission is explicit; validation libraries stay inside their disposable run directory.
- One view-model mutation queue orders Save/autosave, attachment publication/removal, password generation changes, import publication and permanent Delete. An idle queue starts in its caller's zone; pending work is serialized. Transitions join publication before capturing their draft decision.
- File workers process reopenable descriptors with 1 MiB windows. Preparation leaves the committed generation active. Publication captures the latest draft, checks session and credential ownership and the exact storage revision, then acknowledges the complete envelope. Edits made during commit stay dirty.
- Each attachment uses a fresh immutable identity. Rekey inventories every declared file and preserves unknown metadata. Failed preparation cannot publish credentials or attachment references. Retained original objects continue to support recovery versions.
- Note and attachment preparation sources live under the note's opaque storage identity inside managed storage. Cleanup failure retains them; permanent deletion inventories and journals them with active objects, recovery versions and replacement records.
- Deletion intents are admitted before replacement recovery. Tombstones block older saves and resurrection. Incomplete deletion is exposed on startup for explicit retry; changed external files survive. No recursive deletion or rollback guarantee is used.
- Export captures metadata and attachment references without reloading controllers. It checks completeness, builds and verifies a sibling candidate, checks the reviewed destination revision and retains an existing export before publication. Export cannot overwrite settings, note objects or journals. Imports validate complete packages before committing fresh identities.

## Compatibility and display

The existing `.med` AES-SIC/PKCS7 layout and note envelope readers remain. Padding is not authenticated integrity. Old mixed-key fallback owns a fresh candidate. Binary-v1 framing stays unchanged and rejects individual records above its 32-bit limit. Stored ZIP64 entries use `attachments/<id>/<safe-basename>` and compatible string-map metadata; legacy DEFLATE import uses a bounded immediate sink and CRC checks.

Attachment cards, password-batch status and Save status have separate notification paths. Committed previews remain while transformations prepare. Cards expose Queued, Preparing, Decrypting/Encrypting, Verifying, Finalizing and terminal states; commit disables Cancel. Worker byte events are throttled to 100 ms and UI byte events to 200 ms, with immediate phase changes. Typing remains enabled. Preview reads are deduplicated and bounded to 8 MiB per file with a 32 MiB cache.

## Evidence boundaries

The fresh `20261014-full-backend` backup captured seven existing files and retained the previous executable; its rehearsal copy is separate. Original notes are not used for destructive tests.

Current evidence is recorded in `FULL_BACKEND_RESULTS.md`. Large-file streaming, independent ZIP64 reading and canonical visible startup passed. On 2026-10-14 the user confirmed all checks in the presented manual full-app checklist passed. The subsequently reported locked-note UI issue has separate evidence in `LOCKED_NOTE_UI_RESULTS.md`. Platform claims cover Windows only; measured native UI performance is not established. Earlier recovery copies keep their original protection when a password is added.
