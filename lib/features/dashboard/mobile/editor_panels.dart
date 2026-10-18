import 'package:flutter/material.dart';

enum MobileEditorPanel { formatting, attachments }

/// Presentation only: one disclosure at a time, with no idle timers.
class MobileEditorPanels extends ValueNotifier<MobileEditorPanel?> {
  MobileEditorPanels() : super(null);
  bool restoringFocus = false;
  bool _disposed = false;

  void toggle(MobileEditorPanel panel) {
    value = value == panel ? null : panel;
  }

  void collapse([MobileEditorPanel? panel]) {
    if (!_disposed && (panel == null || value == panel)) value = null;
  }

  void restoreFocus(VoidCallback restore) {
    restoringFocus = true;
    restore();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_disposed) restoringFocus = false;
    });
  }

  void editorFocused() {
    // Formatting pickers restore editor focus too. Pointer/text interaction
    // and panel focus traversal distinguish editing from that restoration.
    if (!restoringFocus) collapse(MobileEditorPanel.attachments);
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Owned pickers are separate routes; they do not count as outside interaction.
class MobilePanelRegion extends StatelessWidget {
  const MobilePanelRegion({
    super.key,
    required this.panels,
    required this.panel,
    required this.child,
  });
  final MobileEditorPanels panels;
  final MobileEditorPanel panel;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    void leave() {
      if (ModalRoute.of(context)?.isCurrent != false &&
          !panels.restoringFocus) {
        panels.collapse(panel);
      }
    }

    return TapRegion(
      // Let the new control receive its tap before changing layout.
      onTapUpOutside: (_) => leave(),
      child: Focus(
        onFocusChange: (focused) {
          if (!focused) leave();
        },
        child: child,
      ),
    );
  }
}
