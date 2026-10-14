# Watcher/library-switch gate results

Status: final approved cleanup correction passed formatting, whitespace, analysis,
all 337 tests and Windows Debug compilation. Runtime and real-library activation
remain pending. Earlier failed attempts are retained below as history.

The user approved the exact lint-first gate in
[STAGE7_LIBRARIES_VALIDATION.md](STAGE7_LIBRARIES_VALIDATION.md).

| Command | Observed result |
| --- | --- |
| Dart format on the ten approved paths | Exit 0; ten files formatted |
| `git diff --check` | Exit 0; existing generated-file LF/CRLF notices only |
| `flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings` | Exit 1; 118 diagnostics: seven errors, original two warnings, 109 info |
| `flutter test --no-pub` | Not run |
| `flutter build windows --debug --no-pub` | Not run |

Analysis took 8.8 seconds wall time (analyzer reported 6.4 seconds). All seven
errors concern the coordinator's local `service`, whose static type remains
IFileService after testing an unrelated LibraryFileService interface. The
undefined members are supportsLibrarySwitch (line 615), currentLibrary (643),
prepareLibrary (651), openLibraryWatch (653), publishLibrary (682), and
releaseLibrary (716 and 791), in content_viewmodel.dart after formatting.

The proposed correction separates the interface check from capability admission,
then explicitly casts the checked service for library operations, following the
existing watcher-side pattern. No interfaces, encryption or persistence protocol
need change. Fourteen new informational brace lints also appeared in the new
code; the original two warnings are unchanged. Raw evidence:
[STAGE7_LIBRARIES_ANALYSIS.txt](STAGE7_LIBRARIES_ANALYSIS.txt).

The previous 81-file source/executable checkpoint remains preserved at
`.validation/future-notes-validation-stage7-ordering-2d745fdf585041c7bbfdc24e7c65352d`.
No app launch/stop, real-note access, dependency resolution or encryption change.
The 31 new regressions remain unexecuted; runtime and real-library activation
remain pending. RULESBOOK requires confirmation before correction and resuming
the failed gate.

## Approved cast/brace correction and resumed gate

The user explicitly approved the checked interface cast, all 14 newly introduced
brace lints and the same lint-first command sequence. The coordinator now checks
the interface, then uses an explicit LibraryFileService cast. No persistence,
encryption, dependency or test-harness behavior was changed by this correction.

| Resumed command | Observed result |
| --- | --- |
| Dart format on approved ten paths | Exit 0; one file changed |
| `git diff --check` | Exit 0; existing generated-file LF/CRLF notices only |
| `flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings` | Exit 0; exactly 97 diagnostics (95 info, original two warnings, no errors) |
| `flutter test --no-pub` | Stalled at 318 passed; interrupted with Ctrl+C, exit 1 |
| `flutter build windows --debug --no-pub` | Not run |

Corrected analyzer evidence:
[STAGE7_LIBRARIES_CORRECTED_ANALYSIS.txt](STAGE7_LIBRARIES_CORRECTED_ANALYSIS.txt).
Analysis took 8.3 seconds wall time (analyzer reported 5.9 seconds). Normalized
severity/path/rule/message counts exactly match the previous 97-diagnostic
baseline; no new diagnostics remain. Formatting/analysis were repeated only
for the approved correction. The integration suite ran once; no focused test
or optional rerun followed it.

The last progress was `00:15 +318`, naming the first new widget regression:
`candidate preparation precedes durable settings and old-root release`.
Subsequent output reads contained no progress or assertion failure. The run was
interrupted rather than leaving an unbounded wait. None of the 19 new widget
regressions completed; the exact blocked body/cleanup step has not been
established. A pass count is not a completed suite. No Windows compilation or
replacement checkpoint follows this interrupted gate.

The user subsequently approved test-only phase labels and a bounded single-test
diagnostic. Formatting, whitespace and analysis passed with the same 97
diagnostics. The named test stalled after settings acknowledgement, library
publication and a watcher-close marker, without returning from switchLibrary.
Assertions and teardown were not reached. Interruption yielded exit 1; Flutter
also reported a temporary listener cleanup error during interrupted finalization.
The exact cause remains unconfirmed. No correction, suite rerun or build followed.
See [STAGE7_LIBRARIES_DIAGNOSTIC.md](STAGE7_LIBRARIES_DIAGNOSTIC.md) for commands,
phase evidence and timing limits. The prior checkpoint and real notes remain untouched.

The approved fake-clock probe subsequently exited 1 without stalling: the pending
switch did not finish after one second of fake time. Teardown completed. Analysis
reported 97 diagnostics, exit 0. Read-only SDK inspection identifies root-zone
scheduling in the broadcast-cancellation completion; the proposed bounded
test-harness join is still unimplemented/unvalidated. See the diagnostic report.

## Approved bounded harness join and integration retry

The user approved a test-only join that permits a real async event-loop turn,
then pumps fake microtasks. Library operations still start in fake async; all
outcome, preservation, race and debounce assertions remain. Temporary diagnostic
logging and the one-second fake-clock probe were removed. Production code was
not changed by this harness correction.

Formatting and whitespace passed. Analysis exited 0 with exactly the same
normalized 97 diagnostics (95 info, original two warnings, no errors), and
reported 4.7 seconds. The approved single full-suite command again stalled at
318 passed, naming the first library-switch scenario. It reported no assertion
failure or next library-switch scenario. The command was interrupted, exit 1.
Windows build did not run; no replacement checkpoint was created.

The correction also added an awaited closeLibraryResources call to the fixture's
registered teardown. That future originates when dispose runs in fake async,
while the teardown later awaits it without the fake-clock join. This was an
unbounded wait introduced by the harness correction and must be moved to the
test body's finally block while the bounded join can still pump continuations.
The unchanged progress label does not establish whether the stall is in the
body join or this teardown wait; the proposed cleanup correction is not validated.

Proposed next correction: dispose and join closeLibraryResources inside finally,
then retain the three-second debounce pump. Registered teardown closes its
stream controllers and disposable directory without awaiting a future owned by
the earlier fake-async scope. No production changes or additional tests followed
the failed retry. RULESBOOK requires confirmation before correction/resuming.

## Final approved cleanup join and passing integration gate

The user approved moving resource shutdown into the active scenario's finally
block. That block now disposes the editor, joins closeLibraryResources through
the bounded helper and pumps beyond autosave debounce. Registered teardown
closes fake stream controllers and the disposable directory without awaiting
the earlier fake-zone shutdown future. Production code and existing assertions
were not changed by this correction.

From the repository root, the exact approved sequence ran once:

```powershell
& 'C:\src\flutter\bin\dart.bat' format test/viewmodels/library_switch_test.dart
git diff --check
& 'C:\src\flutter\bin\flutter.bat' analyze --no-pub --no-fatal-infos --no-fatal-warnings
& 'C:\src\flutter\bin\flutter.bat' test --no-pub
& 'C:\src\flutter\bin\flutter.bat' build windows --debug --no-pub
```

| Check | Observed result |
| --- | --- |
| Format | Exit 0; zero formatting changes |
| Whitespace | Exit 0; existing generated-file CRLF notices only |
| Analysis | Exit 0; exactly the prior normalized 97 diagnostics: 95 info, original two warnings, no errors; reported 4.5 seconds |
| Full suite | Exit 0; all 337 tests passed, runner reported 15 seconds |
| Windows Debug build | Exit 0; reported 12.5 seconds |

Raw final evidence: [analysis](STAGE7_LIBRARIES_FINAL_ANALYSIS.txt) and
[test output](STAGE7_LIBRARIES_FINAL_TESTS.txt). No duplicate focused run or
optional test/build followed this passing gate. All 31 added regressions are
included: eight controlled watcher, nineteen widget coordinator and four native
owned-storage integration tests. They cover synthetic files only.

The initial read-only CIM process query was denied; Get-Process fallback listed
no matching project process. No application was launched or stopped.

Preserved final checkpoint:
`.validation/future-notes-validation-stage7-libraries-acd44f557c3f4b049b6d0039176baf38`.
All 67 allowlisted source and 17 runtime files matched their copied SHA-256
hashes. manifest.json records paths/lengths/hashes; validation.json records the
baseline, counts and runtime limit. The preceding 81-file checkpoint remains
intact. No notes, library data or settings data were included in either copy.

The root-zone explanation and bounded harness cleanup are now supported by a
passing integrated suite. This does not establish visible startup, continuous
native watcher behavior, OS fault handling, performance or other platform
support. Default production switching remains refused until owned persistence
activation passes the planned compatibility/recovery gates. Earlier intermittent
native-move failure remains unexplained; this suite passed that regression.
