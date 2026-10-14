# Backspace failure in the isolated Windows session

Date: 2026-10-13. Read-only diagnosis of the existing runtime process. No
automated keys, source correction, test/build rerun, restart or real-note access.

## Evidence and failure mechanism

The user reports that manual character typing works but the physical Backspace
key does nothing. This is a user report, not an independently observed fresh
manual-input test.

The attached Flutter output continues to report the same `KeyDownEvent#4c81a`
for logical `A`, physical `0x1600000000`, timestamp
`340:47:48.204908`, followed by an empty native JSON response. Earlier output
reported a synthesized key-up for logical `Control Left` with this same physical
identity, while Flutter recorded logical `A` for it.

The installed Flutter 3.41.5 source explains the repeated event and the split
between character entry and editing keys:

1. `HardwareKeyboard.handleKeyEvent` calls `_assertEventIsRegular` before
   updating pressed-key state or dispatching handlers
   (`C:/src/flutter/packages/flutter/lib/src/services/hardware_keyboard.dart`,
   lines 510–536 and 653–680). A mismatched key-up therefore leaves the prior
   pressed entry intact.
2. `KeyEventManager.handleRawKeyMessage` iterates
   `_keyEventsSinceLastMessage` at lines 1187–1189. The dispatch and queue clear
   occur only afterward, at lines 1198–1199. An assertion during the loop escapes
   before both operations. The next raw message consequently encounters the
   retained events; a previously processed down event now fails as already
   pressed. The repeated identical event in the output matches this replay.
3. The editor's Backspace command needs that key dispatch to reach Flutter's
   `DefaultTextEditingShortcuts` (`default_text_editing_shortcuts.dart:175`) and
   Quill's `DeleteCharacterIntent` action. Installed Quill 11.5.0 provides that
   action in `editor_keyboard_shortcut_actions_manager.dart:134` and its deletion
   implementation in `editor_keyboard_shortcut_actions.dart:13`. No app-specific
   Backspace override was found. The dashboard binds only Ctrl+S and Ctrl+N.
4. Character input has a separate native text path. The Windows engine's
   `text_input_plugin.cc:68` inserts text and sends an editing update; its
   `KeyboardHook` at lines 86–106 leaves Backspace/Delete/arrow handling to the
   framework. Character input can therefore continue while the framework's
   editing-key dispatch fails. That agrees with the user's report.

The immediate failure is a malformed keyboard sequence followed by a replaying
Flutter key-event batch, upstream of the editor deletion action. The evidence
does not justify changing note persistence, autosave or the deletion action.

## Initiating event and remaining uncertainty

`RawKeyEventDataWindows.physicalKey` maps an unknown scan code to
`LogicalKeyboardKey.windowsPlane + scanCode` at
`raw_keyboard_windows.dart:76–78`. The engine has the corresponding fallback
in `keyboard_key_embedder_handler.cc:115–121`. The Windows plane is
`0x1600000000`; that exact physical identity thus corresponds to the zero-scan
fallback in these paths. It is neither the normal physical `A` (`0x70004`) nor
Left Control (`0x700e0`). Distinct logical keys sharing this identity violate
Flutter's down/up sequence assumptions.

The malformed sequence was observed after automated keyboard interaction.
Automation is a plausible initiating source, but the exact helper operation,
Windows message producer and first malformed event were not captured. This
diagnosis establishes the current dispatch failure; it does not prove that
manual Backspace fails in a fresh process, or that a specific automation API
alone caused it. No helper internals, SDK files or dependencies were modified.

## Next discriminating check

Preserve the current synthetic draft, normally close this one isolated process,
then launch the already-built isolated executable once and test physical typing,
Backspace and Delete manually before sending any automated keys. This requires
the separate runtime/failure-resumption authorization in RULESBOOK.md. No
repeated analyzer, suite or build is needed for that unchanged-code check.

If clean manual input works, keep automation keyboard injection out of this
Flutter validation path until its scan codes and paired down/up behavior are
validated. If it fails, capture that clean failure before proposing an app or
framework correction. Do not suppress the assertions or reset framework state
inside the note application as an unvalidated workaround.

## Clean-process comparison result

The approved unchanged prebuilt restart completed. The user confirmed all
physical editor/title Backspace, Delete, selection deletion, undo and
Settings/focus checks work. Attached fresh-process logs contained no new
keyboard assertions. See [KEYBOARD_RESTART_RESULTS.md](KEYBOARD_RESTART_RESULTS.md).

This validates restoration of manual input and narrows the failure to the old
process's inconsistent key-event state. It does not establish which automation
operation initiated that state. Automated keyboard injection remains excluded
from this Flutter validation path; no editor/framework patch is justified by
this result alone.

## Further native-flow constraint

Read-only installed engine inspection adds two constraints on any eventual
producer correction (`keyboard_manager.cc`, lines 183–188 and 246–253):

- For a `WM_CHAR` following a buffered general key-down, Flutter takes the
  logical key from that key-down but the scan code from the character message's
  `lParam`. Correct key-down scan codes alone therefore do not prove the combined
  stream has correct physical identities.
- Key messages with `VK_PACKET` return before the normal scan-code/key handling.
  The separate character-only branch dispatches text when no general key-down
  precedes it. The actual message form used by `type_text` is unknown; do not
  equate Unicode text packets with malformed ordinary A/Control events.

These are source-flow observations, not evidence that a particular helper emits
those messages. They rule out a speculative key-down-only normalization fix
and keep a controlled text-injection observation as the next diagnostic gate.
