# Window-wide desktop attachment drops

The user confirmed that drops on sidebar/header areas should attach to the
currently selected editable note, rather than being limited to the editor.

## Implementation and flow

The single existing DesktopAttachmentDropZone now wraps the dashboard client
area (Scaffold, header, sidebar, attachment dock and bottom controls). The inner
editor drop target was removed, preventing duplicate dispatch. The existing hover
border/hint remains pointer-transparent and now spans that whole area. Windows'
native non-client caption/borders are outside Flutter's dashboard surface.

The dashboard listens to the same editor, lock and attachment-job state. It
disables drops during shutdown or a global busy operation as well as the
existing note admission guards. The drop widget retains its current-route check
so dialogs suppress drops behind them. File drops still call attachDroppedFiles
with asynchronous admission through the established coordinator; no alternate
storage, encryption or intake path was added. Normal clicks, writing and sidebar
shortcuts remain. First explicit Save, captured ownership and source validation
remain in the existing view-model flow.

Stitch screen e6dde3c0462c4e749d131de6124ceaef refines the existing desktop
reference. The unavailable Pro model was disclosed; GEMINI_3_8_FLASH was used.
Only the existing hover surface was extended; generated extra labels were not
implemented. Design HTML/PNG are retained under .stitch/designs/window-drop-*.

## Validation

Formatting and whitespace passed. Scoped analysis found no errors or warnings;
existing informational diagnostics remain. One new test brace lint was corrected
before tests, and the new test file then analyzed without issues.

One combined suite passed all 17 tests: dashboard file-drop integration, existing
HTML/drop behavior, dashboard exit and tray/close behavior. The integration test
uses real owned persistence in disposable synthetic roots and bounded async joins.
It attaches four files from sidebar, note header, attachment dock and bottom edge,
checks one drop target and one attachment per drop, retains the selected note/body,
and checks full coverage after hiding the sidebar. A second scenario verifies
busy, modal and locked rejection, then restored admission after unlock.

Evidence prefix: .validation/window-drop-. One protected canonical Windows Release
candidate build passed in 41.6 seconds, with private symbols/map and runner
mitigation checks passing. The existing CMake FetchContent deprecation remains.
The previous executable bundle was preserved with matching EXE/AOT hashes before
compilation. The candidate launched once as PID 27016 with a visible responsive
window and clean protection/media-registration logs. Four samples over 15 seconds
remained responsive, with working set 149.8 MiB. No automated app input or forced
termination was used. On 16 October 2026 the user answered "working fine" to the
Explorer-drop check over sidebar, header and blank areas, with each file attached
once to the selected note and the window-wide hover hint. Manual acceptance passed.
The user then requested validation, commit and push to development. The tested
application inputs are verified against the protected build receipt before
committing; unchanged tests/builds are not repeated. The published v1.3.0 portable
folder, tags, real notes and unrelated files remain preserved. No release update
or tag change is included in this commit.
