# Whole-app UX implementation — 2026-10-15

Base: `development` at `d2ace45aba57161d3329766e7d18411cf1d441b3`.
No branch, commit, push or tag changes were made. Existing unrelated generated-header
line-ending changes and untracked material were preserved. No ZIP was created.

## Implemented

| Area | Changes |
| --- | --- |
| Save/writing | Dedicated semantic Save state, private ownership, current-draft Retry, identical pending-revision joining before encoding, captured-library refresh scheduling outside mutation completion, local single-flight conversion, explicit Rich text/HTML controls, contextual toolbar, one editable title and retained dates |
| Cancellation | Post-confirmation finalization recheck, synchronous batch cancellation latching, Cancelling state, late-progress guards, atomic finalization admission, immediate acknowledgement only for unstarted transform descriptors |
| Attachments | Compact dock, inline phases/readable sizes, per-card progress and phase-only summaries, type classification, visible More/Open, per-owner Open intent guard, terminal Open history retirement with frame-delayed notifier disposal |
| Viewer | Direct guarded system-app fallback, Already open menu state, viewport-bound initial image decode (up to 2048 per dimension), decoded preview eviction, player disposal before cache cleanup, guarded focus restoration, Escape/close handling |
| Discovery/navigation | Sidebar-only list state, independent scanning/filtering flags, one active/latest pending filter, retained same-root results, scoped discovery failures, trailing watcher/Save refresh, canonical selected paths, checked listed navigation, persistent query, Clear, Ctrl+F and shared New Note handling |
| Settings/accessibility | Scrollable App settings, acknowledged-value publication, cached metadata futures, library terminology, accurate version, tray explanation, region-based header reflow, keyboard-labelled actions and improved theme contrast |

Persistence formats, encryption, file locations, retained recovery data and native
tray implementation are unchanged. Offline resolution changed only the lockfile
classification of existing `package_info_plus 9.0.1` to a direct dependency.

## Validation evidence

1. Offline resolution passed. Formatting initially found Windows-encoded ellipses
   in two edited tests; those files were explicitly converted to UTF-8.
2. `flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings` remained idle
   without diagnostics and was interrupted (exit 1). Its process termination was
   confirmed before using the direct SDK analyzer. The first direct invocation
   used Flutter's unsupported `--no-fatal-infos` flag (exit 64); Dart makes infos
   nonfatal by default. No silent pass or concurrent duplicate analyzer is claimed.
3. `dart analyze --format machine --no-fatal-warnings` passed after narrow source
   and lint corrections. Latest result: **0 errors, 1 existing unused-import warning,
   105 informational diagnostics**. This is not a strict lint-clean claim.
   Logs: `.validation/ux-analysis-final.txt`, `.validation/ux-retry-analysis.txt`.
4. One combined affected suite returned **198 passed, 22 failed**. Failures comprised
   missing Quill localization in the new layout harness and cascading widget errors,
   old presentation/scheduling expectations, a retirement assertion without a rendered
   frame, and two real layout defects (summary width and failed-card height).
   After corrections, the seven affected files passed **all 78 tests**. These runs
   overlap: **220 distinct affected regressions** are covered, not 276 distinct tests.
   Logs: `.validation/ux-tests.txt`, `.validation/ux-tests-retry.txt`.
5. Required regression coverage includes the confirmation/finalization race, queued
   cancellation, typing during Save/conversion/preparation, dirty-state ownership,
   scope of notifications, stale search/error ownership, refresh forward progress,
   cache reuse/revocation, viewer intents/disposal, decode bounds, settings failures,
   responsive layouts, contrast, tray behavior and actual-exit protocol.
6. `flutter build windows --release --no-pub -t lib/main.dart` passed once in
   **41.7 seconds**. Log: `.validation/ux-release-build.txt`.

The previous 27-file Release bundle was copied and every file SHA-256 verified at
`.validation/ux-previous-release-20261015-051559`. Tests used synthetic/disposable
notes and injected services. Unchanged 4/10 GiB cipher/package/cache gates were not
repeated. No original-note editing/deletion was performed by the agent.

## Startup and pending acceptance

The built canonical Release binary was launched once without recompilation:

```powershell
& 'C:\src\flutter\bin\flutter.bat' run -d windows --release --no-pub --no-hot -t lib/main.dart --use-application-binary='D:\Project\NativeDevps\future-notes\build\windows\x64\runner\Release\flutter_application_1.exe'
```

Read-only native inspection confirmed exactly one visible unowned window belonging
to the sole app process (PID 36824), responsive, at 155,512,832 bytes working set and
0.453125 CPU seconds. Startup logs registered Media Kit and contained no startup
error. Log: `.validation/ux-release-runtime.txt`. These are startup observations,
not playback, input latency, frame-time or memory-growth measurements.

Manual acceptance is **pending** for writing/status/modes, attachment actions/lock,
query persistence/navigation/resize, settings, tray restoration and actual Exit.
The agent sent no keyboard or mouse input and performed no forced termination.

### Manual feedback and editor correction

The user reported unreadable/uneven header controls, physical Home/End doing
nothing even with the rich-text editor focused, and editor focus lost after
formatting. This is failed/pending acceptance, not a successful full-app check.
The supplied screenshot confirmed the selected Rich text button was unreadable.

Source inspection found selected-mode foreground inherited the same primary
color as its container, title enabled/focused borders inherited the global input
theme, and Save status reserved a fixed 200-pixel gap. These are corrected locally.
Formatting actions now restore editor focus without replacing the selection or
controller. Picker/dialog actions retain their existing focus handling.

Dedicated Windows Home/End and Shift/Ctrl variants now bind explicitly inside
Quill's shortcut scope using its existing visual-line/document-boundary actions.
Unmodified focused-editor events already passed in the widget harness, so the
native failure's underlying cause is **not established**; this is a scoped
navigation correction pending the user's physical-key check, not a proven
native root-cause fix. Other platform shortcut maps remain unchanged.

Formatting/whitespace and direct Dart analysis passed (no errors or new warnings;
the existing unused-import warning remains). The affected three-file suite passed
22 tests. After the explicit keyboard bindings and wrapped-line regression were
added, only the changed keyboard/focus file was rerun: all four tests passed.
These runs overlap; no duplicate full suite was run. Evidence:
`.validation/ux-keyboard-analysis.txt`, `.validation/ux-keyboard-tests.txt`,
`.validation/ux-keyboard-navigation-tests.txt`.

The user normally exited PID 36824 before the corrected Release build began.
The corrected canonical Windows Release built successfully in **33.5 seconds**:
`flutter build windows --release --no-pub -t lib/main.dart`.
It was launched once using the prebuilt-binary command above. Startup inspection
found one responsive process, PID 46240, with a native window handle; Media Kit
registered and no startup error was logged. Logs:
`.validation/ux-keyboard-release-build.txt`,
`.validation/ux-keyboard-release-runtime.txt`.
User validation of header appearance, physical Home/End and formatting focus is
still pending. No agent input or forced termination was performed.

### Stitch header refinement and changed Close requirement

The user first requested reverting the header appearance, then explicitly allowed
keeping the current changes and requested Stitch Design. Only the header and its
typography were refined; the other UX improvements remain. Stitch's installed API
does not expose Pro, so `GEMINI_3_8_FLASH` was selected and this limitation disclosed.
The existing design system was reused with synthetic content only. New screen:
`42171071cc8c4ba9a548fe69f6ed38e3` in project `6056916933162144137`.
Assets and metadata are under `.stitch/designs/ux-header-refinement-20261015.*`
and `.stitch/metadata.json`.

The header now groups borderless title/date, small Rich text/HTML controls,
secondary actions, one save status and one green Save button. Title text returns
to 14px, mode/status labels to 12px, and Save to 13px. Narrow widths reflow.
An initial run returned 21 passed, two failures: a 32px mode-control overflow
at 360px width and doubled text scale. A single named diagnostic located the
unconstrained segment row. Replacing it with wrapping segment layout corrected
the failure; no production build followed the failed check.

The user also changed the required Windows behavior: **Close must confirm then
exit, rather than minimize to tray**. Close and tray Exit now share the exit
confirmation and existing draft/active-operation/cleanup protocol. Dismissing or
choosing Keep open performs no storage shutdown. The obsolete Close-to-tray
toggle is replaced by accurate explanatory text; legacy stored settings remain
readable but no longer override the requested Close behavior.

Formatting, whitespace and analysis passed: zero errors, one existing warning,
103 informational diagnostics. One combined affected suite passed **all 34
tests**, including the layout correction, keyboard/focus, locked controls,
settings failure, actual-exit cancellation, concurrent requests and cleanup.
Logs: `.validation/ux-stitch-exit-analysis.txt`,
`.validation/ux-stitch-exit-tests.txt`; earlier failure/diagnostic logs:
`.validation/ux-stitch-header-tests.txt`,
`.validation/ux-stitch-header-overflow.txt`.

The user normally exited the previous app and zero instances were verified
before starting the final Release build. Manual acceptance remains pending.
The final `flutter build windows --release --no-pub -t lib/main.dart` passed in
33.5 seconds. A single prebuilt-binary launch then produced one visible,
responsive window (PID 51012); startup working set was 153,456,640 bytes and
CPU time 0.53125 seconds. Media Kit registered with no startup error in the log.
These are point startup observations, not sustained performance validation.
Logs: `.validation/ux-stitch-exit-release-build.txt`,
`.validation/ux-stitch-exit-release-runtime.txt`.

### Physical Home/End follow-up

The user confirmed the exit confirmation appears as expected, but unmodified
Home/End still fail in **both title and rich editor**. The same keys work in
Notepad and Ctrl+Home/Ctrl+End work in Future Notes. The explicit Quill bindings
therefore do not establish a fix. The previous runtime log records the normal
shutdown reaching completion and returning Exit.

A temporary compile-time opt-in `FN_NAVIGATION_KEY_TRACE` records only Home/End
and corresponding keypad logical/physical key codes, modifier flags, focus kind
and selection offsets. It never logs character/text values and always returns
false so it cannot consume input. The handler is removed on Dashboard disposal.
Default builds omit the enabled diagnostic. No storage/encryption changes were
made for this diagnosis.

Initial analysis rejected constant sets of keyboard-key objects (eight compile
errors); these were corrected to constant lists before any test or build. The
resumed analyzer passed with the existing warning baseline. Five focused tests
passed with the trace enabled, including title Home/End/Shift selection through
the actual MyApp/Dashboard shortcut tree. This is synthetic-event evidence;
physical-event diagnosis and a verified native fix are still pending.
Logs: `.validation/home-end-trace-analysis.txt`,
`.validation/home-end-trace-tests.txt`.

The full diagnostic Release built in 35.3 seconds and started as one visible,
responsive process (PID 32680). Existing runtime trace records captured the
physical failure without agent input: Home presses arrived as logical
`0x200000237` / physical `0x7005f` (Numpad 7), and End as logical
`0x200000231` / physical `0x70059` (Numpad 1). Ctrl/Shift/Alt/Meta were false,
rich-editor focus was present, and selection offsets did not move. A read-only
Windows `GetKeyState(VK_NUMLOCK)` check returned off. No further key probe was
requested after the user's “no” reply. The existing trace supplied the evidence.

The installed SDK's Windows shortcut map covers dedicated Home/End but omits
these keypad aliases. Sending the captured logical events through MyApp reproduced
the title failure: expected caret 0, actual 4. This distinguishes the underlying
mapping failure from the previously suspected editor-focus issue.

`WindowsNavigationShortcuts` now adds Num Lock off keypad Home/End aliases at the
shared application level, using the existing text-layout actions for both normal
text fields and Quill. Shift extends selection; Ctrl targets document boundaries.
Num Lock on, Alt and Meta combinations remain unclaimed. The ineffective
Quill-only bindings and all temporary tracing were removed.

The initial combined correction gate passed 16 tests and failed the new alias
test because Flutter's test default was Android, leaving the Windows wrapper
inactive. The keyboard test file now explicitly selects the Windows variant.
Only that failed file was rerun: **all six Windows tests passed**, covering the
actual observed IDs, title/editor, dedicated keys, wrapped lines, formatting
focus, modifiers and the Num Lock on exclusion. Static analysis passed with no
new warnings/errors. Logs: `.validation/home-end-keypad-reproduction.txt`,
`.validation/home-end-keypad-fix-analysis.txt`,
`.validation/home-end-keypad-fix-tests.txt`,
`.validation/home-end-keypad-fix-tests-retry.txt`.
The user normally exited the diagnostic app. Process inspection confirmed zero
Future Notes instances; its log recorded shutdown completion in 7ms and the Exit
response. A normal Release build without tracing was then started. Corrected
native keyboard acceptance remains pending.
The build passed in **33.7 seconds**. A single launch without recompilation
produced one visible responsive process (PID 33292), with a startup working set
of 153,755,648 bytes and CPU time 0.4375 seconds. Media Kit registered and no
startup error or navigation diagnostic was logged. These are startup observations,
not a physical-key acceptance claim. Logs:
`.validation/home-end-keypad-fix-build.txt`,
`.validation/home-end-keypad-fix-runtime.txt`.

On 2026-10-15 the user explicitly confirmed **“Both work now”** for physical
Home/End in the title and editor of the corrected Release. This closes the
reported native keypad-navigation defect. No repeat tests, rebuild or automated
input were needed to record this acceptance. Header appearance and focus after
formatting were the final reported UX issues requiring explicit acceptance.
The user then explicitly confirmed **“Both are good now”** for the refined
header/text sizes and editor focus after formatting. All reported exceptions
from the initial whole-app manual check have now been resolved and accepted.

The initial whole-app check was reported as “Done”, with the header, Home/End
and formatting focus identified as exceptions. This supports the reported basic
workflow acceptance; it is not evidence of exhaustive native failure injection,
performance targets or unsupported-platform coverage. Those remain bounded by
the synthetic tests and limits below.

## Completion audit

| Requirement | Current evidence | Status |
| --- | --- | --- |
| Save/retry ownership, typing and conversion | `ux_state_test.dart`, `save_coalescing_test.dart`, mutation integration and previously recorded affected-suite results | Implemented; synthetic regressions passed |
| Inline attachment status, guarded Open, cancellation and cache/player lifetime | Attachment strip/panel, streaming worker, cache and mutation tests in the recorded combined gate; initial manual workflow check reported Done | Implemented and regression validated; native acceptance limited to reported basic workflows |
| Search/list ownership, retained query, watched-root refresh and safe navigation | Discovery/search, ordering and library-switch regressions in the recorded combined gate; initial manual workflow check reported Done | Implemented and regression validated; native acceptance limited to reported basic workflows |
| Stitch header, readable selected mode, scaled layout and locked controls | Synthetic Stitch assets; final 34-test gate; user confirmation Both are good now | Implemented, regression validated and visually accepted |
| Physical Home/End | Captured native keypad IDs, reproduced failure, shared Windows aliases, six explicit Windows widget regressions and user confirmation “Both work now” | Implemented and manually validated in both title and editor |
| Focus after formatting | Guarded editor-focus callbacks, Windows selection/focus regression and user confirmation Both are good now | Implemented and manually validated |
| Confirmed actual Close, Keep open and cleanup | `dashboard_tray_test.dart`, `dashboard_exit_test.dart`; user confirmed confirmation appears as expected; normal exits recorded in runtime logs | Implemented; confirmation/normal exit manually verified; cancellation/failure paths regression validated |
| Preserve notes and stable path | Agent made no note mutations; retained verified previous bundle; no branch/tag/commit/push changes | Preserved within the agent's actions |
| Canonical Release startup | Final build output; one visible responsive process PID 33292 and clean startup log; user checked this build | Verified startup and reported manual workflows |

The same live launch session and PID 51012 were rechecked during the audit. The
process remained responsive; the log had no new errors. Working set was
153,423,872 bytes and cumulative CPU time 0.875 seconds. No sustained workload,
latency or playback claim follows from these observations. No further tests,
builds, restarts or automated input were performed for that audit. Its outstanding
user checks were subsequently resolved by the explicit acceptance recorded above.

The agreed Windows UX implementation is complete with the validation boundaries
recorded here. No further code, test/build run, app input, commit, push or tag
change was performed to record acceptance. Changes remain uncommitted on
`development`; the retained previous Release and original notes remain preserved.

## Header follow-up — right-aligned actions and clean Save

The user subsequently requested that attachment/note actions and Save return to
the right edge, with no extra save-status label, and that Save be disabled when
there is nothing to save. The compact header now reserves its trailing edge for
those actions; narrow/scaled layouts wrap while retaining right alignment.
The standalone SaveStatusIndicator was removed. Saving and failed retry appear
inside the existing button instead of adding another header label.

SaveUiState now carries semantic `hasChanges` so an edited never-saved draft
enables Save even though its phase remains Unsaved draft. Clean existing notes,
empty drafts, active writes and non-writable sessions disable Save. No persistence,
encryption, location or draft-authority behavior was changed.

Formatting, whitespace and static analysis passed with the existing warning
baseline. One affected suite passed **all 31 tests**, including right-edge
positions across width/text-scale/theme variants, clean/new/dirty/saving/saved
and failed-retry transitions, locked controls and the Windows keypad fix.
Logs: `.validation/header-right-save-analysis.txt`,
`.validation/header-right-save-tests.txt`. The user normally exited the app and
zero instances were verified before the single Release build.
`flutter build windows --release --no-pub -t lib/main.dart` passed in 60.3 seconds.
The resulting canonical binary was launched once without rebuilding; startup
logs registered Media Kit without errors. Evidence:
`.validation/header-right-save-build.txt`,
`.validation/header-right-save-runtime.txt`. Visual/manual acceptance of this
follow-up remains separate from the passed widget geometry/state checks.

## Smaller interface typography follow-up

The user requested smaller app text. UI theme typography is reduced by 10% in
both themes, with fixed header labels/title, sidebar heading and note-action
dialog text reduced proportionally. System text scaling remains enabled.
Rich-note paragraph/heading sizes and the explicit 14px HTML source font remain
unchanged; no note document or stored formatting was rewritten.

The first affected suite returned seven passed and 17 failed because applying
a size factor to unresolved Material theme styles asserted on null font sizes.
The theme now resolves the existing Material font-size geometry before applying
the reduction. Formatting/whitespace and analysis passed with the existing
warning baseline. Only the failed UI/locked-control files were rerun: all 22
tests passed, including both themes, responsive/scaled layouts, Save transitions
and unchanged Quill paragraph/heading sizes. The two sidebar date tests had
already passed and were not repeated. Evidence:
`.validation/compact-ui-text-analysis.txt`,
`.validation/compact-ui-text-tests.txt`,
`.validation/compact-ui-text-tests-retry.txt`.
The user normally exited the app and zero instances were verified before the
single Release build. No agent input or real-note changes were performed.
The Release build passed in 33.7 seconds and was launched once without rebuilding.
The startup log registered Media Kit with no error. Logs:
`.validation/compact-ui-text-build.txt`,
`.validation/compact-ui-text-runtime.txt`. User visual acceptance is separate
from the passed layout/typography checks.

## Further 20% text reduction and bottom sidebar control

The user requested another 20% interface text reduction and a bottom sidebar
button resembling Codex's panel toggle. Theme size factors changed from 0.9
to 0.72; explicit UI labels/dialog text were multiplied by 0.8. Rich-note body
and heading sizes and HTML source's 14px font remain unchanged. System text
scaling and icon hit areas remain enabled/preserved.

The existing Stitch design system was reused; Pro is not exposed by the installed
API, so the available Flash model was selected and disclosed. Synthetic-only
screen `5b750795125a4acfb654affa83e575e9` and its downloaded assets are recorded
under `.stitch/designs/ux-bottom-toggle-20261015.*` and metadata. Only the
requested typography/placement changes were implemented; no suggested new
shortcut or settings feature was added.

The middle divider chevron was replaced with a bottom-left split-panel icon in
a reserved 48px desktop footer. It stays available when collapsed and cannot
overlap the note/attachment dock. Its owned focus node is disposed with the
dashboard. An initial combined affected suite passed 69 tests and failed the new
Ctrl+F regression: removing a focused search could leave focus outside the
dashboard shortcut scope. Explicitly retaining focus on the toggle corrected
that issue. The failed dashboard file alone was rerun: all nine tests passed.
No duplicate full suite was run. Coverage includes footer placement, retained
editor identity/draft/query, collapse/expand, Ctrl+F, responsive/scaled typography,
dialogs, locked UI and preserved note text sizes.

Formatting/whitespace and analysis passed with the existing warning baseline.
The user normally exited the app before the single Release build began. Logs:
`.validation/bottom-toggle-text-analysis.txt`,
`.validation/bottom-toggle-text-tests.txt`,
`.validation/bottom-toggle-text-tests-retry.txt`.
The Windows Release build passed in 42.9 seconds and its canonical binary was
launched once without rebuilding. Startup registered Media Kit with no logged
error. Evidence: `.validation/bottom-toggle-text-build.txt`,
`.validation/bottom-toggle-text-runtime.txt`. Visual/manual acceptance remains
separate from the passed layout, focus and typography regressions.

## Interface text increased by 8%

The requested relative increase multiplies the current interface sizes by 1.08;
light/dark theme factors are now .7776 instead of .72. Explicit interface labels
use the same increase. HTML source remains 14px and rich-text document styles
are unchanged. The bottom sidebar control and existing behavior are retained.

Formatting and whitespace passed. Direct Dart analysis returned zero errors,
the original unused-import warning and 103 informational diagnostics. The single
combined affected UI/dialog/exit suite passed all 70 tests. Logs:
`.validation/ui-text-plus8-analysis.txt`, `.validation/ui-text-plus8-tests.txt`.
An initial sandboxed SDK formatter helper produced no output and was interrupted;
the SDK-access retry completed successfully. No application process was stopped.

After normal user exit, the single Windows Release build passed in 35.0 seconds.
The canonical main.dart binary was launched once without rebuilding. Exactly one
visible responsive window was observed (PID 83000); startup registered Media Kit
and showed no logged error. No automated input was sent. Visual acceptance of
the adjusted size remains manual. Evidence: `.validation/ui-text-plus8-build.txt`
and `.validation/ui-text-plus8-runtime.txt`.

## Delivery acceptance - 2026-10-15

After the final 8% interface-text increase, the user confirmed “looks good” and
requested committing and pushing the accumulated changes to development.
Earlier user confirmations accepted Home/End in both title and editor, formatting
focus, refined header sizes, and the Close confirmation. These manual observations
supplement the recorded automated checks; they do not establish unmeasured
performance or additional platform support. No unchanged tests/builds were repeated
for this delivery. The latest Release remains running for the user.

Only task-related source, regressions, this report and the three UX Stitch designs
are selected for the commit. Unrelated audit files, generated-header line-ending
changes, the older attachment-design files and the local note remain untouched.
No ZIP or tag change is included.

## Limits

First Open still performs captured-source hashing, transformation and verification.
Finalizing includes recoverable copying and full-file verification. Those phases
can remain lengthy for large files. Cancellation during the initial source-revision
scan waits for that command to return. No throughput/frame-time improvement or
prompt cancellation of that scan is claimed. Initial image zoom magnifies a bounded
preview; system Open and Save As retain the original cached file. Other platforms
and native playback performance are not newly validated by this delivery.
