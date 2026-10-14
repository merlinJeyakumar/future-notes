# Backup, recovery rehearsal and manual rollout gate

Branch: `integration/recoverable-storage`, starting at `683a6c1`.

The user requested verified backups, recovery rehearsal on an isolated copy,
activation for existing notes, and manual application testing. Native discovery
confirmed two top-level note objects in the existing default shared UserData
layout. Settings and app-managed recovery are absent. No note payload has been
read and no original file has been written during preparation. The user saved
and closed the prior app; a native process query then confirmed zero instances.

## Close behavior and evidence

The user reports that completed storage cleanup still requires another Close.
The existing code cancels the original exit request after ten seconds and later
issues a separate cancelable exit request. The candidate replaces this with a
latency warning while the original exit request remains pending. Successful
cleanup returns exit through that same request; failed cleanup still cancels
exit and allows an explicit retry. Neither a required exit nor forced process
termination is introduced. Three new tests cover late completion, fast completion
and failure. Debug-only native close/destroy labels and the Dart exit response
label allow observation during the user's manual test.

This repairs the timeout/retry path. It does **not** establish the cause of the
earlier 53-ms cleanup followed by a retained window. That fast-path observation
and the new manual two-click report remain unresolved until manual acceptance.
The Flutter SDK and native message routing are unchanged.

## Prepared backup and rehearsal

`Prepare-StorageActivation.ps1` consumes the private verified locations receipt,
requires zero app instances and admits only the reviewed shared-root layout.
It rejects links before descending, uses bounded file copying, retains effective
Windows access rules, hashes every copied file, preserves modification times,
and compares the original inventory again. It never deletes or overwrites an
existing backup destination. Partial copies remain unacknowledged on failure.

The retained backup is `.validation/future-notes-backup-activation-20261013`.
It includes all library objects and a verified copy of the previous Debug
executable directory. It is excluded from Git and is not a disposable-test root.
No automatic rollback against a live library is provided. Recovery copies keep
the protection of their original revisions; encryption is not migrated.

A separate disposable copy is
`.validation/future-notes-validation-activation-rehearsal-20261013`.
The opt-in rehearsal test refuses any other location before accessing content.
It verifies copy hashes, uses the shared codec and owned worker for byte-identical
commits, checks declared attachment presence, and interrupts replacement after
moving the prior target and after publication for each copied note. Reopening
must restore the exact prior hash without read-only ambiguity. Copied metadata
and protected bodies are retained; title changes happen only on the copy.
Password-protected bodies are not unlocked, and attachment decryption is not
claimed. The existing synthetic storage tests cover other fault boundaries,
external conflicts, unknown fields, lease ownership and session races.

Only after passing the necessary tests and rehearsal, the launch script rechecks
the original and backup inventories, refuses a second app instance, and compiles
and launches `lib/main.dart` once with explicit native storage defines. Startup
will acquire a writer lease and can create app-managed recovery directories in
the original root. Agent-driven edits and destructive tests on original notes
are excluded. The user will manually test visible startup, notes, editing,
Save/reopen and a single Close. Extended attachment/password/import/export/Delete
mutations and opening another library remain blocked by this preview.

## Static preparation results

Dart formatting and PowerShell parsing passed. Static analysis returned 0 with
101 diagnostics: 99 info, the original two unused-import warnings, no errors.
The initial rehearsal brace diagnostics were corrected and the analysis delta
returned to the integration baseline. Tracked whitespace passed. Tests, backup
execution, recovery rehearsal, compilation and app launch are pending.

## Exact requested execution gate

From `D:\Project\NativeDevps\future-notes`, sequentially, stop on the first
failure. The analyzer has already passed; do not repeat it without another code
change. SDK/user-folder access is needed for the commands, but no dependency
resolution or SDK modification is included.

```powershell
git diff --check
& '.\scripts\storage\Prepare-StorageActivation.ps1' -Mode Prepare
if ($LASTEXITCODE -ne 0) { throw 'Backup preparation failed.' }
$env:FN_REHEARSAL_ROOT = 'D:\Project\NativeDevps\future-notes\.validation\future-notes-validation-activation-rehearsal-20261013'
try {
  & 'C:\src\flutter\bin\flutter.bat' test --no-pub --concurrency=1 test/storage test/viewmodels test/draft_decision_dialog_test.dart
  if ($LASTEXITCODE -ne 0) { throw 'Required storage/session checks failed.' }
} finally {
  Remove-Item Env:\FN_REHEARSAL_ROOT -ErrorAction SilentlyContinue
}
& '.\scripts\storage\Start-RecoverableNotes.ps1'
```

The launch script's exact SDK command is:

```powershell
& 'C:\src\flutter\bin\flutter.bat' run -d windows --debug --no-pub --no-hot -t lib/main.dart --dart-define-from-file=D:\Project\NativeDevps\future-notes\.validation\future-notes-activation-config-20261013\defines.json
```

One relevant suite includes the seven previously unrun native integration tests,
three new close-wait tests and the copied-note rehearsal once. Serial test-file
execution limits incidental native test contention; the earlier unexplained
native-move outcome failure is not considered fixed. One compilation/launch,
no duplicate focused/full suite and no separate duplicate build. Failure stops
activation and preserves original notes, the backup and the earlier executable.
No forced stop, keyboard injection, app clicking, push or merge is included.

RULESBOOK requires exact-command approval before tests, builds and production
actions. This gate needs that approval; the broad goal authorizes preparation
but does not waive the retained execution rule.
