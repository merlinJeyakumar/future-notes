# First Stage 1 validation attempt

The user approved the exact command gate, including the recorded analyzer
baseline exception for this candidate. No application launch occurred.

| Check | Observed result |
| --- | --- |
| Formatter | Confirmed exit 0; 11 files, 0 changes on repeat |
| `git diff --check` | Exit 0; generated-file LF/CRLF warnings only |
| Non-mutating format check | Exit 0; 11 files, 0 changes |
| Focused regression command | Four captured-reference tests passed; first widget test stalled during setup; interrupted, exit 1 |
| Full suite | Not run |
| Analysis | Not run |
| Windows Debug build | Not run |
| Runtime | Not run |

The first formatter invocation's tool output was truncated. Repeating the same
approved command established a successful result without additional changes.

## Stopped command

```powershell
& 'C:\src\flutter\bin\flutter.bat' test --no-pub test/viewmodels/session_safety_test.dart test/storage/captured_reference_test.dart
```

The runner loaded both files and reported `+4`, from the captured-reference
tests. The first widget test, `locked manual Save and autosave perform zero
writes/encryption`, never completed. There was no assertion failure or compiler
error in the captured output. The command was interrupted with Ctrl+C and
returned exit code 1 rather than waiting for Flutter's ten-minute backstop.

Source inspection identified an asynchronous OS filesystem operation in widget
test setup: `EditorHarness.create()` awaits `Directory.systemTemp.createTemp()`
before constructing the editor. It runs directly inside `testWidgets`' fake-async
environment. The installed Flutter `WidgetTester.runAsync` documentation warns
that OS-thread asynchronous work invoked directly in this environment can
deadlock. This is the leading diagnosis; a corrected rerun must confirm it.

The next proposed change is limited to making disposable harness setup safe in
the widget-test environment. No production behavior correction or additional
dependency is proposed on this evidence. Under RULESBOOK's failed-validation
rule, confirmation is required before correction and further validation.

The full suite, analyzer delta and build remain pending. The Stage 0 source and
executable checkpoint remains preserved; no finding is closed. No real notes
were used for this attempt.

## Approved harness correction and rerun — 2026-10-13

The user approved correcting temporary-directory setup and rerunning the gate.
`EditorHarness.create()` now creates its empty disposable directory synchronously,
avoiding an unresolved OS future in fake async. Production code was not changed
by this correction. Asynchronous path-checked teardown remains in place.

Formatting processed 11 files, changing the harness only; the subsequent format
check required no changes. `git diff --check` returned 0 with the same generated
file line-ending warnings.

The exact focused command above returned exit code 1 in 9.2 seconds, with
**24 passed and 2 failed**. All 26 tests ran, confirming that the setup stall was
resolved. The failures were:

- `typing while another note loads keeps the existing draft`
- `verification and repeated unlock preserve an editable draft`

Both failed the Flutter cleanup assertion:
`A Timer is still pending even after the widget tree was disposed.`
The pending timer was the two-second autosave debounce created by
`ContentViewModel._scheduleAutoSave`. These two tests intentionally leave dirty
drafts and rely on package-level `addTearDown` to dispose their editors. That
disposal occurs after the widget binding's timer invariant check. The editor's
existing `dispose()` explicitly cancels the autosave timer; the proposed repair
is to dispose the editor inside these two test bodies after their assertions,
then pump beyond the debounce and verify that no write occurs.

This diagnosis does not establish a production timer leak or validate production
lifecycle behavior. No production change is proposed for these failures. Further
test correction and execution await confirmation under the failed-gate rule.
The full suite, analysis and Windows build were not run. No app was launched and
no real notes were accessed.

## Approved cleanup correction and completed gate — 2026-10-13

The user approved disposing the editors inside the two failing widget test
bodies after their assertions. Each now pumps three seconds after disposal and
asserts zero write attempts. Production code was unchanged for this correction.

| Check | Final result |
| --- | --- |
| Formatter | Exit 0; 11 files, 0 changes |
| `git diff --check` | Exit 0; generated-file line-ending warnings only |
| Non-mutating format check | Exit 0; 11 files, 0 changes |
| Focused regression command | Exit 0; all 26 passed |
| `flutter test --no-pub` | Exit 0; all 84 passed |
| `flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings` | Exit 0; 90 diagnostics in 29.6s |
| `flutter build windows --debug --no-pub` | Exit 0; built executable in 22.3s |
| Runtime | Not run |

Analysis is not clean: 88 informational diagnostics and the same two unused-import
warnings remain. Compared with Stage 0's 79 diagnostics, the net increase is 11
informational lints. New unbraced control-flow lints occur in the guarded VM code,
captured FileService guard and one test loop. No error or new warning appeared.
Existing production prints, deprecated APIs, transitive highlight import and
async-context lints remain open. Formatting does not resolve these lints.

No project application process was found before the build. The executable was
not launched. Tests cover controlled VM interleavings, isolated synthetic-file
reference behavior and the earlier compatibility fixtures. They do not prove
runner exit cancellation, recoverable durability, attachment transactions or
performance. Complete transition UI and later stages remain pending.

The source/tests, dependency manifests and Debug bundle are checkpointed at
`.validation/future-notes-validation-stage1-587d03dd00b84c949d4966449d7d8257`.
All 52 copied files match their source SHA-256 hashes. No notes were copied.
