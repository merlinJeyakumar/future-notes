# Mobile presentation isolation

The desktop presentation is frozen to the accepted v1.4.1 implementation.
The Android/iOS presentation lives under `lib/features/dashboard/mobile/`.

- Desktop dashboard, sidebar, editor, formatting bar, attachment dock, viewers,
  mention overlay, preview entry point, Settings and AppTheme match v1.4.1.
- The desktop MyApp class is unchanged. Main selects MobileApp only on Android
  and iOS; desktop window controls, theme, density and hover remain on their
  existing route. No installed desktop executable or D:\tools file is replaced.
- MobileApp has its own theme, notes browser, editor header, explicit touch
  formatting disclosure, attachment/gallery/viewer presentation and settings.
- The notes list uses a compact header/search, direct rows, menu actions and one
  New note floating button. The editor has Back/title/Save/options, one mode/action
  row, four primary formatting tools and bounded secondary controls in flow.
- Storage, note identity, encryption, draft coordination, jobs, cache and import
  services remain shared. UI changes do not introduce a second storage owner,
  a note migration or another encryption format.
- Mobile presentation variants intentionally own their layout/state and import
  each other rather than the desktop widgets. Metadata and worker behavior stay
  in the shared view model/services; keep future platform styling in this folder.
- Source-equality evidence: `.validation/desktop-presentation-preservation.json`.
  This is source preservation evidence, not a new Windows runtime acceptance run.

Stitch reference: screen 3e032dc43c1643d48a581a0b0289d2b5 in the existing project.
The generated board contains phone layouts; its design tokens were reused without
editing the existing desktop design system. Pro is unavailable; Flash was used.

Tests remain deferred by the user. The mobile fixture imports were moved to the
mobile presentation; no test suite was run. iOS validation remains on hold.
## Android delivery evidence

- Scoped mobile analysis completed with no errors or warnings; 24 informational
  notices remain. A broader analysis attempt stalled and was cancelled before the
  focused rerun. Formatting and whitespace checks completed.
- Final protected preview build passed in 68.1 seconds. No Windows build or executable
  replacement was performed. The previous preview APK remains preserved.
- Package: com.nativedevps.futurenotes.preview, 1.4.1+8, min API 24.
- APK: 131,245,457 bytes; SHA-256:
  c449ba704a27c13a9702d0de07f727536e94bb9c807d172db478bb1934d4d185.
- 18 packaged native libraries; all 64-bit ELF load segments satisfy 16 KB
  alignment and ZIP alignment passed. Existing 32-bit PDFium limitation is unchanged.
- adb install -r succeeded on LG LM-G900 / Android 12, retaining preview data.
  Final launch returned Status ok, COLD, TotalTime 963 ms, WaitTime 971 ms,
  PID 15282. The preview Activity was resumed; inspected startup logs contained
  no listed fatal/layout errors.
- The final mobile toolbar uses keyboard traversal while retaining its editing
  tap region. Its focused analysis reported no issues; no interaction test ran.
- The phone initially auto-locked. A later unlocked screenshot visibly confirmed
  the compact mobile notes list: header/search, direct note row and bottom New
  note action. The existing note remains present. No note was opened or edited
  by this startup inspection. Editor interaction and subjective design acceptance
  remain pending the user's review.
- Desktop presentation files also retain their expected Windows line endings and
  no longer appear as modified in Git; their content still matches v1.4.1.
- No commit, push, release publication, tag change or D:\tools modification.

## Mobile editing-control refinement (17 October)

- User feedback narrowed the remaining design issue to editing buttons and the
  formatting panel. Only mobile/content_area.dart and
  mobile/expanding_formatting_bar.dart changed in this refinement.
- One raised, subtly outlined card now uses grouped monochrome controls,
  circular tinted selection states and an explicit Format/Less disclosure.
  The bounded extra controls remain inside the same card above the editor.
  Touch targets remain 48 dp. Save is a labelled filled action; the mode
  selector retains the desktop finish with touch-sized buttons.
- Stitch screen 6a5ed9870b6544ba8a0ea5c4e8f6d204 supplies the reference;
  Flash used because Pro was unavailable. The board contains phone frames
  although Stitch identifies the board itself as DESKTOP. No desktop design
  or theme was edited. Suggested keyboard/light-mode explorations remain
  acceptance checks rather than claimed runtime results.
- Both changed files formatted. Scoped analysis: no errors/warnings,
  17 existing informational notices. Whitespace check passed. User-requested
  test-suite deferral remains in effect.
- Protected preview build passed in 58.0 seconds. APK SHA-256:
  1973aa37a7ec5ef2fbf2df7c68ff3be9ca0652a1d40711e4d5e0a858b2eaa1fc.
  Size 131,261,737 bytes. All 18 native libraries present; 64-bit ELF and
  ZIP 16 KB alignment checks passed. Previous accepted APK preserved under
  .validation/mobile-toolbar-before-refinement/.
- Fresh source comparison confirms 11 desktop presentation files and MyApp
  still match v1.4.1. Manual mobile editor acceptance is pending. Tests and
  iOS validation remain deferred; no commit/push/release or portable changes.
- Installation with adb install -r succeeded, preserving preview data. Launch
  returned Status ok / WaitTime 3034 ms. PID 16826 stayed stable during a
  20-second observation; inspected logs had zero fatal/layout-error matches,
  and total PSS was 50,172 KiB. The phone remained keyguard-locked and the
  Activity was not resumed, so visible startup/editor acceptance is pending
  unlock rather than claimed complete. No user note was opened or edited.

## Mobile Rich text / HTML selector refinement

- User requested matching the selector to the accepted mobile design. The
  previous tall outlined segments are replaced with a 36 dp visible rail,
  inset selected pill and active accent text. Each independently focusable
  target remains 48 dp tall. Conversion guards, progress, mode switching and
  editor controllers remain unchanged; source comparison confirms that only
  this mobile presentation method and its comment changed.
- Stitch reference and local assets are recorded in .stitch/metadata.json
  and .stitch/designs/mobile-mode-selector.html/png. Flash used because Pro
  was unavailable. Suggested HTML, keyboard focus and light-mode checks are
  manual acceptance items, not claimed results.
- Formatting/whitespace and scoped analysis passed with zero errors/warnings
  and 17 existing informational notices. Desktop source preservation passed.
  Test suites remain deferred by the user; iOS validation remains held.
- Protected preview build passed in 72.9 seconds. APK: 131,294,681 bytes;
  SHA-256 56fc02635646d0e8b3e8799342db9b783e0e071916b7cf6c8fde82190abc71d2.
  All 18 native libraries and 64-bit ELF/ZIP 16 KB alignment checks passed.
  Previous accepted APK/source: .validation/mobile-mode-selector-before/.
- adb install -r succeeded. LG Android 12 COLD launch: TotalTime 1086 ms,
  WaitTime 1093 ms. PID 20743 remained stable during 20 seconds; Activity
  resumed, keyguard off, zero fatal/layout-error matches in inspected logs,
  total PSS 151,381 KiB. Evidence: .validation/mobile-mode-selector-startup.json.
  Selector appearance and both mode interactions await the user's check;
  no existing note was opened or edited by startup inspection.
- No desktop executable, D:\tools portable, note format, note content, release
  tag, commit, push or publication change.

## Mobile Save placement

- Removed the filled Save pill from the note-title row. Save is now an
  outlined icon action at the far right after Attach and Lock, with matching
  48 dp touch geometry. Its save-state listener, command, retry/disabled guards
  and saving indicator remain unchanged. No persistence behavior was edited.
- The secondary row uses OverflowBar so the action group remains right-aligned
  and can flow below the mode selector on narrow screens rather than overflow
  or shrink touch targets. The accepted mode selector and toolbar are retained.
- Stitch reference/local assets: .stitch/designs/mobile-save-placement.html/png
  and .stitch/metadata.json. Flash used because Pro was unavailable. Suggested
  dirty/saved, narrow-screen and shortcut checks remain manual acceptance.
- One mobile Dart file changed; formatting, whitespace and scoped analysis
  passed (zero errors/warnings, 17 existing informational notices). Desktop
  presentation preservation passed. Tests remain deferred; iOS validation held.
- Protected preview build passed in 67.3 seconds. APK: 131,294,681 bytes;
  SHA-256 739dc7fe4980b523974d0c8b50e41a02ffe4b1e27ff31ec0ddb6d1e67e9998bb.
  All 18 native libraries and 64-bit ELF/ZIP 16 KB alignment checks passed.
  Previous APK/source: .validation/mobile-save-placement-before/.
- adb install -r succeeded with no active attachment service detected. LG
  Android 12 COLD launch: TotalTime 985 ms, WaitTime 991 ms. PID 22023 stayed
  stable for 20 seconds; Activity resumed, keyguard off, zero fatal/layout
  error matches in inspected logs; total PSS 169,985 KiB. Runtime record:
  .validation/mobile-save-placement-startup.json. No existing note was opened
  or edited during inspection. Placement and Save interaction acceptance await
  the user's synthetic-note check; sustained resource behavior was not tested.
- No commit, push, tag, publication, D:\tools or desktop executable changes.
