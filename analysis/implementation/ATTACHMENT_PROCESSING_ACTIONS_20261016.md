# Processing attachment actions

## Change

Hide the preview/Play glyph and More menu only on the affected processing tile,
in both collapsed and expanded layouts. The card keeps its original dimensions,
filename tooltip, phase and byte-progress indication. Open remains disabled
while processing. Cancellable preparation exposes Cancel directly, including in
the collapsed row; Finalizing and Cancelling show no unusable action icons.

Idle/finished attachments retain their preview and menu. A failed collapsed item
keeps its error indicator; pending failures retain Retry/Remove pending. Other
attachments' menus remain accessible. No storage, encryption or job-lifecycle
behavior changes.

The existing Stitch dock design was refined as screen
3692fb90f45a4190b93d476daa94f1d8. Pro was unavailable; the available
GEMINI_3_8_FLASH model was used as disclosed. Synthetic attachment names only.
Generated assets are retained; unrequested status icons/labels were not added
to the application.

## Validation

Formatting and whitespace checks passed. Scoped analysis of the changed widget
and its tests reported zero errors/warnings, with the existing informational
diagnostic for the transitive intl import retained.

The combined strip/job-panel suite initially passed 18 tests and failed one new
assertion: it incorrectly expected Play rather than the existing error icon on a
failed collapsed tile. The assertion was corrected without production changes;
the named rerun passed. Both layout regressions additionally passed their
completed-state transition checks. All 19 distinct affected tests passed.
Coverage includes all processing phases, safe cancellation visibility, idle
action restoration, unchanged neighboring controls, fixed card dimensions,
pending retry/removal, keyboard and hover actions, and no rendering decryption.

Evidence prefix: .validation/attachment-processing-actions-. One protected
canonical Windows Release build passed in 41.9 seconds. Private symbols/map and
runner mitigation checks passed. The existing CMake FetchContent deprecation
remains. The previous accepted bundle was preserved with matching EXE/AOT hashes
in .validation/attachment-processing-actions-previous-release before compilation.

The candidate launched once as PID 26120 with a visible responsive window and
clean protection/media-registration logs. All four samples across 15 seconds
remained responsive; working set ranged from 148.5 to 156.6 MiB. No automated app
input or forced termination was used. On 16 October 2026 the user answered
"perfect" to hidden Play/More during processing, safe cancellation visibility
and normal action restoration after completion. Manual acceptance passed.
The user then requested committing and pushing this validated correction to
development. Application code is unchanged since the passing tests/build and
manual acceptance, so those checks are retained without duplicate execution.
Notes, tags, published releases and unrelated changes remain preserved; no
release publication or tag change is included.
