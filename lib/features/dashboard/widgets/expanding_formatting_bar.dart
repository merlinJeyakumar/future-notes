import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show OverflowBoxFit;
import 'package:flutter/services.dart';
import '../../../core/theme/app_motion.dart';

/// A compact card that wraps controls in normal layout on hover or expansion.
class ExpandingFormattingBar extends StatefulWidget {
  const ExpandingFormattingBar({
    super.key,
    required this.child,
    required this.restoreEditorFocus,
    required this.expandedChild,
    this.surfaceColor,
    this.outlineColor,
  });
  final Widget child;
  final Widget expandedChild;
  final VoidCallback restoreEditorFocus;
  final Color? surfaceColor;
  final Color? outlineColor;
  @override
  State<ExpandingFormattingBar> createState() => _ExpandingFormattingBarState();
}

class _ExpandingFormattingBarState extends State<ExpandingFormattingBar> {
  Timer? _leaveTimer;
  bool _expanded = false;
  bool _hovered = false;
  bool _focused = false;

  void _enter() {
    _leaveTimer?.cancel();
    _hovered = true;
    if (!_expanded) setState(() => _expanded = true);
  }

  void _scheduleClose() {
    _leaveTimer?.cancel();
    if (!_hovered && !_focused && _expanded) {
      _leaveTimer = Timer(const Duration(milliseconds: 180), _closeIfIdle);
    }
  }

  void _closeIfIdle() {
    if (!mounted || _hovered || _focused) return;
    // A font/color dropdown must finish before its originating controls retire.
    if (ModalRoute.of(context)?.isCurrent == false) {
      _leaveTimer = Timer(const Duration(milliseconds: 180), _closeIfIdle);
      return;
    }
    setState(() => _expanded = false);
  }

  @override
  void dispose() {
    _leaveTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextFieldTapRegion(
    child: Focus(
      skipTraversal: false,
      onFocusChange: (value) {
        _focused = value;
        if (value) {
          _leaveTimer?.cancel();
          if (!_expanded) setState(() => _expanded = true);
        } else {
          _scheduleClose();
        }
      },
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          setState(() => _expanded = false);
          widget.restoreEditorFocus();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: MouseRegion(
        onEnter: (_) => _enter(),
        onExit: (_) {
          _hovered = false;
          _scheduleClose();
        },
        child: Container(
          key: const ValueKey('formatting-card'),
          width: double.infinity,
          decoration: BoxDecoration(
            color: widget.surfaceColor ?? Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color:
                  widget.outlineColor ??
                  Theme.of(context).dividerColor.withValues(alpha: .3),
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x26000000),
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: _sizeTransition(
            Semantics(
              expanded: _expanded,
              child: _expanded ? widget.expandedChild : _compactRow(),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _sizeTransition(Widget child) => AppMotion.reduced(context)
      ? child
      : AnimatedSize(
          duration: AppMotion.panelIn,
          reverseDuration: AppMotion.panelOut,
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: child,
        );

  Widget _compactRow() => ExcludeFocus(
    child: ClipRect(
      child: OverflowBox(
        fit: OverflowBoxFit.deferToChild,
        alignment: Alignment.topLeft,
        minWidth: 0,
        maxWidth: double.infinity,
        child: widget.child,
      ),
    ),
  );
}
