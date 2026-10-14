# Isolated application integration — prepared, unvalidated

Update: the approved gate subsequently passed analysis, all 346 tests, Windows
Debug build and visible startup. Workflow validation stopped on unchanged title
input; app versus automation cause is unconfirmed. This review records the
pre-execution candidate; current results are in
[VALIDATION_APP_RESULTS.md](VALIDATION_APP_RESULTS.md).

The requested runtime work needs an actual UI composition using the tested
owned writer. Production activation is still blocked by incomplete attachment,
password, package and Delete mutation integration. Original notes are untouched.

## Startup and isolation

`lib/validation_main.dart` is a separate target. It requires explicit validation
defines, configures the fallback singleton before initialization, and constructs
independent settings and file services sharing one worker. Production mode is
rejected, including when defines are absent. Paths and filesystem links are
checked before worker/service I/O. Both settings and library roots acquire their
leases and recover before `runApp`, so dashboard discovery starts afterward.

The UI receives the exact independent settings and file services. Normal
`main.dart` still uses its previous singleton composition and does not enable
the owned writer. No dependency, file format or encryption change is included.
Startup failures display sanitized text without opening an editing dashboard.
Acquired ownership is retained until cleanup succeeds or can be retried.

## Shutdown joins

For the validation dashboard only: resolve the draft first. Cancellation keeps
the editor open. After success, remove focus, switch to a non-editable finishing
screen, close watcher resources, release note/settings roots, then acknowledge
worker close. Keyboard Save/New callbacks also check shutdown ownership.

Both service releases are attempted independently. A partial release retains
the worker and retry handles; its failure cancels window exit and leaves the
validation editor non-writable. Another close request retries. Normal dashboard
exit has no injected runtime cleanup callback and retains its existing behavior.
Native Windows close cancellation and these joins need runtime evidence.

## Prepared regressions and limits

Nine tests cover production rejection, shared-root preparation, service-backed
round trip, unchanged legacy bytes, corrupt settings/startup refusal, partial
cleanup retry, close before/during initialization, sanitized startup failure,
and application theme/home injection. Service tests use real async; the widget
test performs filesystem operations through `runAsync`.

No tests, analysis, build or launch have run for this candidate. The previous
84-file source/executable checkpoint is preserved. Runtime acceptance is scoped
to synthetic Save/autosave/reopen, drafts, watcher/library switching and exit.
Attachment/protection/package/Delete UI workflows must not be exercised until
their shared mutation ordering is integrated. Thirty minutes of mixed use cannot
yet establish the original encryption-while-typing acceptance criterion.

Real-library activation needs completion of the remaining correctness stages,
verified backups and compatibility/recovery rehearsal on a separate copy. This
entry point cannot activate it. Static/native test evidence does not establish
visible startup, continuous operation, frame/input latency or other platforms.
