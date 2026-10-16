import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_motion.dart';

/// One persistent formatting row with additional controls in an anchored overlay.
/// Hovering never moves the editor or requests focus from its text selection.
class HoverFormattingBar extends StatefulWidget {
  const HoverFormattingBar({
    super.key,
    required this.toolbar,
    required this.primaryToolbar,
    required this.restoreEditorFocus,
    this.surfaceColor,
    this.outlineColor,
  });
  final Widget toolbar;
  final Widget primaryToolbar;
  final VoidCallback restoreEditorFocus;
  final Color? surfaceColor;
  final Color? outlineColor;
  @override
  State<HoverFormattingBar> createState() => _HoverFormattingBarState();
}

class _HoverFormattingBarState extends State<HoverFormattingBar>
    with SingleTickerProviderStateMixin {
  final _portal = OverlayPortalController()..show();
  final _link = LayerLink();
  late final AnimationController _animation;
  Timer? _leaveTimer;
  bool _showing = false;
  bool _hovered = false;
  bool _focused = false;
  bool _reduced = false;

  @override
  void initState() {
    super.initState();
    _animation = AnimationController(
      vsync: this,
      duration: AppMotion.quickIn,
      reverseDuration: AppMotion.quickOut,
    );
    FocusManager.instance.addEarlyKeyEventHandler(_key);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = AppMotion.reduced(context);
    if (_reduced) _animation.value = _showing ? 1 : 0;
  }

  void _show() {
    _leaveTimer?.cancel();
    if (_showing) return;
    setState(() => _showing = true);
    if (_reduced) {
      _animation.value = 1;
    } else {
      _animation.forward();
    }
  }

  void _close({bool restoreFocus = false}) {
    _leaveTimer?.cancel();
    if (!_showing) return;
    setState(() => _showing = false);
    if (restoreFocus) widget.restoreEditorFocus();
    if (_reduced || _animation.value == 0) {
      _animation.value = 0;
    } else {
      _animation.reverse();
    }
  }

  void _enter() {
    _hovered = true;
    _show();
  }

  void _leave() {
    _hovered = false;
    _scheduleHide();
  }

  void _scheduleHide() {
    _leaveTimer?.cancel();
    if (!_hovered && !_focused && _showing) {
      _leaveTimer = Timer(const Duration(milliseconds: 180), _hideIfIdle);
    }
  }

  void _hideIfIdle() {
    if (!mounted || _hovered || _focused) return;
    // Font/color/paragraph popups are separate routes. Let them complete before
    // retiring their originating toolbar; never remove an active dropdown.
    if (ModalRoute.of(context)?.isCurrent == false) {
      _leaveTimer = Timer(const Duration(milliseconds: 180), _hideIfIdle);
      return;
    }
    _close();
  }

  void _outside() {
    if (ModalRoute.of(context)?.isCurrent != false) _close();
  }

  KeyEventResult _key(KeyEvent event) {
    if (_showing &&
        event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape &&
        ModalRoute.of(context)?.isCurrent != false) {
      _close(restoreFocus: true);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    FocusManager.instance.removeEarlyKeyEventHandler(_key);
    _leaveTimer?.cancel();
    _animation.dispose();
    super.dispose();
  }

  Widget _card(double width) => Positioned(
    width: width,
    child: CompositedTransformFollower(
      link: _link,
      showWhenUnlinked: false,
      targetAnchor: Alignment.topLeft,
      followerAnchor: Alignment.topLeft,
      child: TextFieldTapRegion(
        child: TapRegion(
          onTapOutside: (_) => _outside(),
          child: MouseRegion(
            key: const ValueKey('formatting-hover-strip'),
            onEnter: (_) => _enter(),
            onExit: (_) => _leave(),
            child: Container(
              key: const ValueKey('formatting-card'),
              decoration: BoxDecoration(
                color:
                    widget.surfaceColor ??
                    Theme.of(context).colorScheme.surface,
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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: 64,
                    child: Row(
                      key: const ValueKey('formatting-primary-row'),
                      children: [Expanded(child: widget.primaryToolbar)],
                    ),
                  ),
                  AnimatedBuilder(
                    animation: _animation,
                    builder: (context, child) => ClipRect(
                      child: Align(
                        alignment: Alignment.topCenter,
                        heightFactor: AppMotion.progress(_animation),
                        child: Offstage(
                          offstage: _animation.value == 0,
                          child: Opacity(
                            opacity: AppMotion.progress(_animation),
                            child: child,
                          ),
                        ),
                      ),
                    ),
                    child: IgnorePointer(
                      ignoring: !_showing,
                      child: ExcludeFocus(
                        excluding: !_showing,
                        child: ExcludeSemantics(
                          excluding: !_showing,
                          child: TickerMode(
                            enabled: _showing,
                            child: widget.toolbar,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Focus(
      skipTraversal: true,
      onFocusChange: (value) {
        _focused = value;
        if (value) {
          _show();
        } else {
          _scheduleHide();
        }
      },
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: (_) => _card(constraints.maxWidth),
        child: CompositedTransformTarget(
          link: _link,
          // Only the resting row reserves space; the same card grows over the editor.
          child: SizedBox(height: 66, width: double.infinity),
        ),
      ),
    ),
  );
}
