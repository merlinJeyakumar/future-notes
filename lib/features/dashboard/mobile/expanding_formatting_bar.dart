import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../core/theme/app_motion.dart';
import 'editor_panels.dart';

/// Touch disclosure stays in normal layout and never covers the writing area.
class MobileFormattingBar extends StatefulWidget {
  const MobileFormattingBar({
    super.key,
    required this.child,
    required this.expandedChild,
    required this.restoreEditorFocus,
    this.surfaceColor,
    this.outlineColor,
    this.panels,
  });
  final Widget child;
  final Widget expandedChild;
  final VoidCallback restoreEditorFocus;
  final Color? surfaceColor;
  final Color? outlineColor;
  final MobileEditorPanels? panels;
  @override
  State<MobileFormattingBar> createState() => _MobileFormattingBarState();
}

class _MobileFormattingBarState extends State<MobileFormattingBar> {
  final _ownedPanels = MobileEditorPanels();
  MobileEditorPanels get panels => widget.panels ?? _ownedPanels;
  bool get _expanded => panels.value == MobileEditorPanel.formatting;
  @override
  void dispose() {
    _ownedPanels.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: panels,
    builder: (context, _) => _build(context),
  );

  Widget _build(BuildContext context) {
    final theme = Theme.of(context);
    final available = math.max(
      0.0,
      MediaQuery.sizeOf(context).height -
          MediaQuery.viewInsetsOf(context).bottom -
          MediaQuery.paddingOf(context).vertical,
    );
    final panel = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Row(
            children: [
              Expanded(child: widget.child),
              SizedBox(
                height: 20,
                child: VerticalDivider(
                  width: 8,
                  color: theme.dividerColor.withValues(alpha: .4),
                ),
              ),
              IconButton(
                key: const ValueKey('formatting-touch-toggle'),
                tooltip: _expanded
                    ? 'Collapse formatting tools'
                    : 'Expand formatting tools',
                style: IconButton.styleFrom(
                  minimumSize: const Size(48, 48),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  foregroundColor: theme.colorScheme.primary,
                  backgroundColor: _expanded
                      ? theme.colorScheme.primary.withValues(alpha: .12)
                      : Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: () {
                  panels.toggle(MobileEditorPanel.formatting);
                  panels.restoreFocus(widget.restoreEditorFocus);
                },
                icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
              ),
            ],
          ),
        ),
        if (_expanded)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Divider(
              height: 1,
              color: theme.dividerColor.withValues(alpha: .4),
            ),
          ),
        if (_expanded)
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: math.min(180, available * .28),
            ),
            child: SingleChildScrollView(
              primary: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(6, 4, 6, 6),
                child: widget.expandedChild,
              ),
            ),
          ),
      ],
    );
    return MobilePanelRegion(
      panels: panels,
      panel: MobileEditorPanel.formatting,
      child: TextFieldTapRegion(
        child: FocusTraversalGroup(
          child: DecoratedBox(
            key: const ValueKey('formatting-card'),
            decoration: BoxDecoration(
              color:
                  widget.surfaceColor ?? Theme.of(context).colorScheme.surface,
              border: Border.all(
                color:
                    widget.outlineColor ??
                    theme.dividerColor.withValues(alpha: .3),
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(
                    alpha: theme.brightness == Brightness.dark ? .22 : .10,
                  ),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Semantics(
              expanded: _expanded,
              child: AppMotion.reduced(context)
                  ? panel
                  : AnimatedSize(
                      duration: AppMotion.panelIn,
                      reverseDuration: AppMotion.panelOut,
                      alignment: Alignment.topCenter,
                      curve: Curves.easeOutCubic,
                      child: panel,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
