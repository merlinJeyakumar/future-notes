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

## Collapsible attachment previews - 2026-10-15

The dock now collapses to small file-backed thumbnails and expands to larger
preview cards. It shows at most four attachments plus a +N overflow tile. On
narrow widths, fewer primary cards fit and +N still exposes every remaining
item in a scrollable gallery. Committed attachments and pending additions share
the limit; pending entries remain outside durable metadata. More stays visible,
compact progress/cancel/retry actions remain inline, and gallery actions use the
existing guarded Open/system/Save As/Remove paths. Rendering never prepares or
decrypts files; cached images use bounded 320x160 decode dimensions. Lock and
note/credential changes hide the gallery and dismiss its route.

Stitch Flash refined the existing design system with synthetic names only.
Pro was not exposed by the API. Screen 92636f73a0d74be5a37a5e5cadbe560c and local
assets are recorded in .stitch/metadata.json. No suggested unrelated controls
were introduced. The previous Release and existing notes remain preserved.

Formatting/whitespace and direct Dart analysis passed with no errors and the
original unused-import warning. The first combined affected suite returned
25 passed, seven failed due to vertical card overflow. Source sizing and compact
action corrections resolved the overflows. The failed file then returned seven
passed, one failed: its gallery test attempted an off-screen click. Scrolling
to the control corrected the interaction; the next attempt revealed an assertion
against the model getter despite injecting its separate UI notifier. Correcting
the fixture assertion passed the remaining named test. A repeated-Open test now
holds preparation pending while exercising duplicate clicks. Across the runs,
all 32 distinct affected tests pass; unchanged passing suites were not repeated.
Logs: .validation/attachment-dock-analysis*.txt,
.validation/attachment-dock-tests*.txt. An automatic permission-review timeout
occurred before checks started; its single permitted retry succeeded.

The single canonical Windows Release build passed in 65.2 seconds, followed by
one prebuilt-binary launch. Native inspection from the launch permission context
confirmed exactly one visible responsive window (PID 84272; working set
152,608,768 bytes). The first sandboxed inspection could not see its window handle;
the native inspection resolved that visibility limitation. Startup registered
Media Kit without a logged error. Logs:
.validation/attachment-dock-release-build.txt,
.validation/attachment-dock-release-runtime.txt. The agent sent no app input.
Manual layout acceptance and sustained resource/performance checks remain pending.
Changes are not committed or pushed by this follow-up.

## Smaller previews and metadata captions - 2026-10-15

Following user screenshots, normal expanded cards changed from 176x192 to
112x120 logical pixels: approximately 60% less area. Collapsed cards remain
88px wide, with two-line wrapped filenames. Both sizes now show file kind,
readable original size and a short local Stored dd/MM HH:mm caption. Tapping
the thumbnail opens it; visible More actions and +N overflow are retained.
Active/failed cards reserve extra space for progress and accessible icon actions.
The existing Stitch design was refined using synthetic samples only; screen
2fbcafcefc174601ae87b02b9f6d6a24 and assets are in .stitch/metadata.json.

No attachment-added timestamp exists in the current model. The caption therefore
uses the encrypted storage object's modification time, explicitly labelled Stored.
This can change after a rekey or replacement; it is not the original added date.
A metadata-only service validates the captured reference, attachment ID and root
containment, then stats the file. It never hashes or decrypts payloads, changes
settings, or writes metadata. Missing/failing dates show Date unavailable;
pending entries show Pending. The tile caches its date future by model, note,
credential and attachment identity; stale results cannot cross sessions. Existing
notes and formats are unchanged.

Formatting/whitespace and direct Dart analysis passed with zero errors and the
original unused-import warning. The combined affected suite passed 38 tests and
failed two old Retry-text assertions. Those were updated to the accessible retry
icon tooltip while keeping locked-state privacy assertions. Only that failed file
was rerun and both tests passed: 40 distinct affected tests pass. Coverage includes
area, wrapped names/captions, one metadata read through collapse/expand, stale and
failed dates, captured-root behavior, traversal rejection, no decryption/writes,
overflow, jobs, accessibility scale and lock/unlock. Logs:
.validation/attachment-caption-analysis.txt,
.validation/attachment-caption-tests.txt,
.validation/attachment-caption-lock-tests.txt.

The previous 27-file Release bundle was copied and hash-verified at
.validation/attachment-caption-previous-release-20261015. The single Windows
Release build passed in 42.3 seconds and the canonical binary was launched once
without recompilation. Native inspection confirmed one visible responsive window
(PID 31068), with Media Kit registration and no startup error logged. Evidence:
.validation/attachment-caption-release-build.txt,
.validation/attachment-caption-release-runtime.txt. No automated app input or
forced termination occurred. Manual visual acceptance remains pending. These
follow-up changes are not committed or pushed.

## Smaller cards, filename hover and full-card activation - 2026-10-15

Expanded cards now measure 96x104 logical pixels, collapsed cards 76x92.
Attachment names, captions and status labels are reduced by 12%, retaining
wrapped names, type/size and Stored date captions. Only attachment typography
changes; note/editor/application text is unaffected. The existing Stitch design
was refined with synthetic content; screen bb3ef373e39348e58d31c18efb108374 and
local assets are in .stitch/metadata.json.

One card-level Tooltip shows the full filename after 350ms pointer hover. One
owned InkWell handles clicks on thumbnail, text, captions, empty padding and
keyboard activation; More and job controls retain their own gesture handling.
Pending/active items cannot Open. All Open paths retain the existing ownership,
cache, preparation and deduplication guards. No storage changes or automatic
payload decryption were introduced by this adjustment.

Formatting/whitespace and direct analysis passed with no errors and the original
unused-import warning. The affected suite passed 34 and failed one test: its
font-size comparison read an unresolved raw theme value. Switching that assertion
to the rendered theme passed the single named rerun. All 35 distinct affected
tests pass, including Windows pointer hover over captions, full filename tooltip,
clicking four card surfaces, keyboard Enter, independent More, disabled active
Open, overflow, scaled layouts and locked UI. Logs:
.validation/attachment-click-analysis.txt,
.validation/attachment-click-tests.txt,
.validation/attachment-click-tests-retry.txt.

After normal user exit, the previous 27-file Release bundle was copied and
hash-verified at .validation/attachment-click-previous-release-20261015. The single
Windows Release build passed in 100.4 seconds and its canonical main.dart binary
was launched once without rebuilding. Native inspection confirmed one visible
responsive window (PID 59480), Media Kit registration and no startup error in the
log. Evidence: .validation/attachment-click-release-build.txt and
.validation/attachment-click-release-runtime.txt. No forced stop or automated
native app input was performed. Manual visual acceptance remains pending; these
follow-up changes have not been committed or pushed.

## Media autoplay, central pause and audio thumbnail - 2026-10-15

Opening a supported video, audio file or GIF now requests playback once after
cached-file preparation. GIFs use the existing native media player and repeat,
allowing pause/resume. Static images retain the bounded image viewer. No new
package or encryption/cache change is introduced. The native player opens paused
internally, then accepts the viewer's explicit Play intent; a concurrent pause or
dispose revokes that intent before opening can complete. Disposal remains
idempotent. Opening a system app pauses embedded playback first.

Normal/fullscreen desktop video controls explicitly enable playAndPauseOnTap;
seeking, volume and fullscreen controls remain delegated to the installed player.
Audio creates no video controller/texture and shows a 160px music thumbnail with
an accessible central Play/Pause target and state icon. The existing Stitch
system supplied a synthetic audio design. Only its requested thumbnail/state
presentation is used; suggested waveform, speed and other controls were not added.
Assets and screen f9c6ecb18425437798e5f4b0404b0bf1 are in .stitch/metadata.json.

Formatting/whitespace and direct Dart analysis passed with zero errors and the
original unused-import warning. The analyzer took approximately two minutes;
one activity inspection showed a live analysis server with increasing CPU/memory.
It completed without interruption or a duplicate command. One combined affected
suite passed all 46 tests. New regressions cover autoplay requests for video,
WAV/MP3 and uppercase GIF, audio center-click pause/resume, static-image/document
exclusion, lifecycle pause/cleanup, actionable start failure and late failure
after closing. Existing attachment, locked UI, responsive, cache and tray/exit
regressions passed. Logs: .validation/media-autoplay-analysis.txt and
.validation/media-autoplay-tests.txt. Tests inject player spies: they establish
application intent and lifecycle behavior, not native codec/device playback or
video control hit testing. Those remain for manual user validation.

Installed Media Kit 1.2.6 / Video 2.0.1 source and its primary documentation were
checked for explicit Play, repeat and desktop tap behavior:
https://github.com/media-kit/media-kit/blob/main/README.md.
The previous 27-file Release bundle was copied and hash-verified at
.validation/media-autoplay-previous-release-20261015. The single canonical
Windows Release build passed in 35.3 seconds; a single prebuilt-binary launch
then produced one visible responsive window (PID 42720), Media Kit registration
and no startup error logged. Evidence:
.validation/media-autoplay-release-build.txt and
.validation/media-autoplay-release-runtime.txt. No agent app input or original-note
mutation was performed. Native playback/manual acceptance is still pending.
These follow-up changes have not been committed or pushed.

## GIF-only repair after manual feedback - 2026-10-15

The user confirmed video and audio are working. GIF animated in the dock but
failed in the native video view. Source confirmed separate routes: dock images
used Flutter's multi-frame image decoder while the opened GIF used Media Kit.
The underlying native decoder failure for the user's GIF is not established.
GIF now uses a dedicated file-backed Flutter image player in the same preview
modal; video/audio keep their confirmed native path. A cached dock image is
wrapped in disabled TickerMode, showing its first frame without animation.

The GIF player starts only after explicit Open/cache preparation. TickerMode
controls pause/resume through the central click/keyboard target, retains the
current frame, and participates in existing lifecycle pause and close/cache
cleanup. Decoded preview dimensions remain bounded to 2048 each; this is not a
constant-memory claim for arbitrary encoded GIF sizes. Corrupt GIFs expose a
preview error and system-app fallback. Encryption, cached source files, notes,
formats and dependencies remain unchanged.

Flutter SDK Image source and primary documentation confirm paused multi-frame
images display their first frame when initially loaded with TickerMode disabled:
https://api.flutter.dev/flutter/widgets/Image-class.html.

Formatting/whitespace and direct Dart analysis passed with zero errors and the
original unused-import warning. One combined affected suite passed all 45 tests.
The new 129-byte synthetic two-frame GIF fixture is actually decoded by Flutter;
pixel samples prove a static dock, animation only after Open, central pause,
resume, lifecycle pause and close. The regression rejects any attempt to send
GIF through the native video factory. Corrupt GIF fallback and the existing
video/audio, attachment, locked UI and tray/exit tests passed. No repeated suite
or speculative native decoder fix was used. Logs:
.validation/gif-repair-analysis.txt and .validation/gif-repair-tests.txt.

The previous 27-file Release bundle was copied and hash-verified at
.validation/gif-repair-previous-release-20261015. The single Windows Release build
passed in 62.7 seconds. One prebuilt-binary launch produced exactly one visible
responsive window (PID 8680), Media Kit registration and no startup error in the
log. Evidence: .validation/gif-repair-release-build.txt and
.validation/gif-repair-release-runtime.txt. The user then confirmed the GIF
recheck: "done, its working now." The checked GIF's still thumbnail, opened
animation and central pause/resume are manually accepted, alongside the earlier
video/audio acceptance. No original-note or attachment content was used as test material and
no native app input was sent. Follow-up changes are uncommitted/unpushed.

## Fixed attachment progress height - 2026-10-15

The user reported that clicking Open makes every attachment card grow. Source
confirmed `_tileHeight` added 96 logical pixels for an active job, or 112 for a
failure; the dock's stretched Row applied that height to all cards. This was
layout behavior, not growth of the attached file or cached data.

The expanded/collapsed dock now keeps its existing 104/92 logical-pixel base
height (scaled for accessibility) through all job phases. Only the explicit
expand/collapse button changes that height. Inline phase, bytes and progress
temporarily replace the affected card's metadata captions. Cancel, Retry and
Remove pending fit beside the preview; More remains present. Captions return
after completion. Overflow-gallery cards follow the same sizing rule. Storage,
encryption and playback routes are unchanged.

The initial combined suite passed 45 and failed two existing locked-state
assertions because the first candidate omitted the disabled More button on a
failed pending item. Restoring More exposed a narrow-layout hit-target overlap:
the first correction passed 14 and failed one existing Remove-pending click.
Explicit compact tap-target sizing corrected that overlap. The affected two-file
rerun passed all 15 tests, for 47 distinct affected tests passing across the
combined suite and correction run. The new regressions click Open and check
identical dock/all-four-card bounds through preparation, decryption,
verification, finalizing and failure in both display modes. Existing scaled
layout, overflow actions, static GIF thumbnails, playback and locked-state
coverage passed. No duplicate full-suite rerun was used.

Direct Dart analysis reported zero errors and the existing one unused-import
warning. Changed-file correction analysis reported no warning/error; the
existing informational intl direct-dependency lint remains. The sandboxed Dart
batch bootstrap produced no output; direct SDK execution completed formatting.
Evidence: .validation/attachment-fixed-height-analysis.txt,
.validation/attachment-fixed-height-tests.txt,
.validation/attachment-fixed-height-correction-tests.txt and
.validation/attachment-fixed-height-controls-tests.txt.

The previous 27-file Release bundle was copied and hash-verified under
.validation/attachment-fixed-height-previous-release-20261015. The single Release
build passed in 39.8 seconds. A prebuilt-binary launch through lib/main.dart
produced exactly one visible, responsive window (PID 33392), Media Kit
registration and no startup error in the observed log. Evidence:
.validation/attachment-fixed-height-release-build.txt and
.validation/attachment-fixed-height-release-runtime.txt. Native manual acceptance
of this specific height correction is pending; the agent sent no app input.
No commit/push or original-note test was performed.

## Icon-only collapsed attachment strip - 2026-10-15

The user clarified that collapsed attachments should display small icons instead
of miniature metadata cards. Collapsed targets are now 56 by 36 logical pixels,
with a file-type icon or an already-cached still thumbnail and a visible More
button. Filenames/type/size/date captions remain in expanded cards; collapsed
filenames appear on hover and in accessibility labels. Primary mouse/keyboard
Open, More actions, four-item maximum and +N overflow are retained. Rendering
does not initiate decryption. Cached GIF thumbnails remain still.

Collapsed progress is a thin fixed-height stripe, with phase/bytes in the
tooltip and accessibility value. Cancel attachment, Retry and Remove pending
use More, avoiding extra controls or text below the icons. Expanded cards keep
their existing layout and direct job controls. Only presentation/menu dispatch
changed; note data, encryption, cache ownership and playback are unchanged.

Stitch screen 3f988913409f4e9c868f12c7853e7791 was generated by editing the existing
attachment design with synthetic filenames and its existing design system.
The exposed tool offered Flash rather than Pro; GEMINI_3_8_FLASH was selected
and the limitation disclosed. Its HTML contains the compact collapsed state;
the supplied screenshot initially displays expanded mode. Assets and metadata
are retained under .stitch/designs/attachment-collapsed-icons-20261015.*.
Suggested extra actions were not added.

Formatting and whitespace passed. Static analysis reported no errors and the
same one existing unused-import warning. The combined affected suite initially
passed 47 and failed one scaled narrow-layout test: the collapsed +N text
wrapped, overflowing its Column by eight pixels at 200 percent text scaling.
Two bounded named diagnostics located the exact Column; no dependency or
unrelated layout change was made. The +N label now fits within a scale-down
container. Changed-file analysis had no warning/error (existing intl dependency
info retained), then all 14 attachment-strip tests passed. This gives 48 distinct
affected tests passing across the suite and correction. New coverage checks
icon-only dimensions, no captions, full-name hover, mouse/keyboard Open and
independent system-open/menu actions. Existing phase sizing, scaled overflow,
pending controls, GIF/playback, lock and exit checks are retained.

Evidence: .validation/attachment-collapsed-icons-analysis.txt,
.validation/attachment-collapsed-icons-tests.txt,
.validation/attachment-collapsed-icons-overflow-detail.txt and
.validation/attachment-collapsed-icons-correction-tests.txt.
After the user's normal-close confirmation, zero app instances were verified.
The previous 27-file Release bundle was copied and hash-verified under
.validation/attachment-collapsed-icons-previous-release-20261015. One Windows
Release build passed in 37.5 seconds. A prebuilt-binary launch through lib/main.dart
produced exactly one visible, responsive window (PID 77784), Media Kit
registration and no startup error in the observed log. Evidence:
.validation/attachment-collapsed-icons-release-build.txt and
.validation/attachment-collapsed-icons-release-runtime.txt. Native manual
acceptance remains pending. No agent native input, original-note test, commit
or push was performed.

## Limits

First Open still performs captured-source hashing, transformation and verification.
Finalizing includes recoverable copying and full-file verification. Those phases
can remain lengthy for large files. Cancellation during the initial source-revision
scan waits for that command to return. No throughput/frame-time improvement or
prompt cancellation of that scan is claimed. Initial image zoom magnifies a bounded
preview; system Open and Save As retain the original cached file. Other platforms
and native playback performance are not newly validated by this delivery.
