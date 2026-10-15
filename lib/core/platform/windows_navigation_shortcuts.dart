import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Windows reports non-extended Home/End as keypad 7/1. The platform text
/// shortcuts cover dedicated Home/End, but omit these Num Lock off aliases.
/// Leave numeric entry and Alt/Meta combinations to the platform.
const windowsKeypadNavigationShortcuts = <ShortcutActivator, Intent>{
  SingleActivator(LogicalKeyboardKey.numpad7, numLock: LockState.unlocked):
      ExtendSelectionToLineBreakIntent(forward: false, collapseSelection: true),
  SingleActivator(LogicalKeyboardKey.numpad1, numLock: LockState.unlocked):
      ExtendSelectionToLineBreakIntent(forward: true, collapseSelection: true),
  SingleActivator(
    LogicalKeyboardKey.numpad7,
    shift: true,
    numLock: LockState.unlocked,
  ): ExtendSelectionToLineBreakIntent(
    forward: false,
    collapseSelection: false,
  ),
  SingleActivator(
    LogicalKeyboardKey.numpad1,
    shift: true,
    numLock: LockState.unlocked,
  ): ExtendSelectionToLineBreakIntent(
    forward: true,
    collapseSelection: false,
  ),
  SingleActivator(
    LogicalKeyboardKey.numpad7,
    control: true,
    numLock: LockState.unlocked,
  ): ExtendSelectionToDocumentBoundaryIntent(
    forward: false,
    collapseSelection: true,
  ),
  SingleActivator(
    LogicalKeyboardKey.numpad1,
    control: true,
    numLock: LockState.unlocked,
  ): ExtendSelectionToDocumentBoundaryIntent(
    forward: true,
    collapseSelection: true,
  ),
  SingleActivator(
    LogicalKeyboardKey.numpad7,
    control: true,
    shift: true,
    numLock: LockState.unlocked,
  ): ExtendSelectionToDocumentBoundaryIntent(
    forward: false,
    collapseSelection: false,
  ),
  SingleActivator(
    LogicalKeyboardKey.numpad1,
    control: true,
    shift: true,
    numLock: LockState.unlocked,
  ): ExtendSelectionToDocumentBoundaryIntent(
    forward: true,
    collapseSelection: false,
  ),
};

class WindowsNavigationShortcuts extends StatelessWidget {
  const WindowsNavigationShortcuts({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      defaultTargetPlatform == TargetPlatform.windows
      ? Shortcuts(shortcuts: windowsKeypadNavigationShortcuts, child: child)
      : child;
}
