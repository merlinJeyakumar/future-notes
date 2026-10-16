# Windows custom title bar — 16 October 2026

## Scope and implementation

Replaces the native Windows title bar in the normal `lib/main.dart` app with a compact 36-logical-pixel caption. It displays the app name and Minimize, Maximize/Restore and Close buttons. Removes notification-area tray registration, callbacks and the unused Dart tray API. Minimize uses the taskbar. Close posts the same native WM_CLOSE request used by the existing Flutter exit confirmation, draft decisions, attachment joins and storage cleanup.

The caption sits above the Navigator, so modal dialogs leave the controls accessible. An outer Overlay supplies caption tooltips. Native hit-testing retains caption dragging, double-click behavior and resize edges, scaled to the current window DPI. Maximized client calculation uses the monitor work area. Native keyboard window commands remain on the existing overlapped-window style. No additional package was added; comctl32 is a Windows system library.

The frame activates after the caption's first Flutter frame. Configuration failure rolls back the native frame and removes the redundant Flutter caption. The startup-failure page retains its native frame. Native state notifications update the Restore icon. Existing persisted tray metadata remains readable for compatibility but has no tray behavior or settings UI.

Storage, encryption, attachment processing and note formats are unchanged. No automated editor input or note mutation was performed. Existing unrelated changes and loose notes remain untouched.

## Design

Stitch project `6056916933162144137`, screen `5c926ace8b1e4843b08da7e4b2bbb394`. The requested compact caption and existing theme were retained; the generated dashboard content was not substituted into the app. The available Flash model was used because Pro was not selectable, as disclosed before design work.

References: `.stitch/designs/window-chrome-20261016.html` and `.png`.

## Validation

- Formatted the ten affected Dart files and passed `git diff --check`. Existing generated-header line-ending notices are unrelated and preserved.
- Scoped `dart analyze` passed, exit 0, with five pre-existing informational diagnostics and no errors/warnings. The initial run found two errors in the new test fake's inferred state type and two new brace notices; those were corrected before tests/build. Evidence: `.validation/window-chrome-analysis.txt`.
- Combined affected command:

  ```powershell
  & 'C:\src\flutter\bin\flutter.bat' test --no-pub test/window_actions_test.dart test/desktop_window_frame_test.dart test/dashboard_window_controls_test.dart test/dashboard_exit_test.dart test/dashboard_file_drop_test.dart test/attachment_strip_test.dart
  ```

  Initial result: 33 passed, four failed because caption tooltips outside the Navigator had no Overlay. No build/launch followed that failure. Added the required outer Overlay; its scoped analysis passed with no issues. Reran only the two affected files, `test/desktop_window_frame_test.dart` and `test/dashboard_window_controls_test.dart`: all six tests passed. Across these runs all 37 distinct tests pass. Evidence: `.validation/window-chrome-tests.txt`, `window-chrome-overlay-analysis.txt`, `window-chrome-tests-correction.txt`.
- One protected Windows Release build, canonical main entry point, exit 0, 46.7 seconds:

  ```powershell
  & 'C:\src\flutter\bin\flutter.bat' build windows --release --no-pub -t lib/main.dart --obfuscate "--split-debug-info=$privateSymbols" "--extra-gen-snapshot-options=--save-obfuscation-map=$privateSymbols/obfuscation-map.json"
  ```

  Private symbol retention and the existing runner PE hardening check passed (ASLR, high-entropy ASLR, DEP, CFG, stack cookie, dependent-load flags 0xA00). The existing office FetchContent deprecation warning remains. No new compiler error/warning was reported. Evidence: `.validation/window-chrome-build.txt`; input and executable/AOT hashes: `.validation/window-chrome-build-receipt.json`. Inputs include current lib sources, native runner sources, Windows CMake configuration and pubspec files.

## Observed runtime and preservation

Confirmed zero project app instances, then launched one full protected candidate from `build/windows/x64/runner/Release/FutureNotes.exe` at 09:26:41 UTC, PID 66904. Before launch, all receipt input hashes and executable identity matched. Computer Use returned exactly one target window and a screenshot showed the normal editor, existing library list, integrated caption and its three controls. No mouse/keyboard input was sent.

Three read-only samples from 09:27:30 to 09:27:50 UTC all reported Responding=true. Working set stayed approximately 151 MiB; private memory approximately 146–147 MiB; handles decreased from 596 to 591. CPU time increased by 0.047 seconds over the 20.1-second observation. Startup/operation logs contained the expected media registration and process-protection messages, with no error output. This is an idle startup observation, not evidence of long-running load or physical window-control acceptance.

The previously accepted executable and AOT were copied to `.validation/window-chrome-previous-release`; both match the prior accepted build receipt. Published `build/releases/FutureNotes-1.3.0-windows-x64` was not modified. `v1.3.0` still resolves to `4a8d1a2cfd4a2f9a22d577e465ee3c108b0fb636`. Build and launch did not change tags, branch, commits, remote state or release assets.

## Manual acceptance

The user replied "perfect, commit and push" to the requested checks of Minimize/taskbar restoration, Maximize/Restore, caption dragging/double-clicking, edge resizing, Close confirmation/Exit, and removal of the native title bar and tray icon. This records acceptance of the requested behavior on the tested Windows system. Automated regression and build checks pass. Multi-monitor/DPI transitions and Windows 11 maximize-hover Snap Layouts were not separately confirmed; no claim is made for that flyout.
