import 'package:flutter/material.dart';

/// Motion changes presentation only; storage and security never wait for it.
abstract final class AppMotion {
  static const dialogIn = Duration(milliseconds: 220);
  static const dialogOut = Duration(milliseconds: 160);
  static const panelIn = Duration(milliseconds: 200);
  static const panelOut = Duration(milliseconds: 150);
  static const quickIn = Duration(milliseconds: 120);
  static const quickOut = Duration(milliseconds: 90);
  static const contentIn = Duration(milliseconds: 160);
  static const enterCurve = Curves.easeOutCubic;
  static const exitCurve = FlippedCurve(enterCurve);

  static bool reduced(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context) ||
      MediaQuery.accessibleNavigationOf(context);
  static Duration duration(BuildContext context, Duration value) =>
      reduced(context) ? Duration.zero : value;
  // Traversing the same curve backwards gives its paired ease-in exit and
  // preserves the current visual position when an interaction reverses.
  static double progress(Animation<double> animation) =>
      enterCurve.transform(animation.value);
  static AnimationStyle menu(BuildContext context) => AnimationStyle(
    duration: duration(context, quickIn),
    reverseDuration: duration(context, quickOut),
    curve: enterCurve,
    reverseCurve: Curves.easeOutCubic,
  );
}

/// Keeps one child mounted while reversing interrupted open/close gestures.
class AppReveal extends StatefulWidget {
  const AppReveal({
    super.key,
    required this.visible,
    required this.child,
    this.axis = Axis.vertical,
    this.duration = AppMotion.panelIn,
    this.reverseDuration = AppMotion.panelOut,
    this.fade = false,
  });
  final bool visible;
  final Widget child;
  final Axis axis;
  final Duration duration;
  final Duration reverseDuration;
  final bool fade;
  @override
  State<AppReveal> createState() => _AppRevealState();
}

class _AppRevealState extends State<AppReveal>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    value: widget.visible ? 1 : 0,
    duration: widget.duration,
    reverseDuration: widget.reverseDuration,
  );
  bool _reduced = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = AppMotion.reduced(context);
    if (_reduced) _controller.value = widget.visible ? 1 : 0;
  }

  @override
  void didUpdateWidget(AppReveal oldWidget) {
    super.didUpdateWidget(oldWidget);
    _controller.duration = widget.duration;
    _controller.reverseDuration = widget.reverseDuration;
    if (_reduced) {
      _controller.value = widget.visible ? 1 : 0;
    } else if (widget.visible != oldWidget.visible) {
      widget.visible ? _controller.forward() : _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    child: IgnorePointer(
      ignoring: !widget.visible,
      child: ExcludeFocus(
        excluding: !widget.visible,
        child: ExcludeSemantics(
          excluding: !widget.visible,
          child: TickerMode(enabled: widget.visible, child: widget.child),
        ),
      ),
    ),
    builder: (_, child) {
      final value = AppMotion.progress(_controller);
      return ClipRect(
        child: Align(
          alignment: Alignment.topLeft,
          widthFactor: widget.axis == Axis.horizontal ? value : 1,
          heightFactor: widget.axis == Axis.vertical ? value : 1,
          child: Offstage(
            offstage: !widget.visible && _controller.value == 0,
            child: widget.fade
                ? Opacity(
                    opacity: value,
                    child: Transform.scale(
                      scale: .98 + .02 * value,
                      child: child,
                    ),
                  )
                : child,
          ),
        ),
      );
    },
  );
}

/// Animates only the new presentation, never a retained outgoing editor.
class AppEntrance extends StatefulWidget {
  const AppEntrance({
    super.key,
    required this.trigger,
    required this.child,
    this.enabled = true,
    this.identity,
  });
  final Object trigger;
  final Widget child;
  final bool enabled;

  /// Changing notes commits incoming content without blanking its viewport.
  final Object? identity;
  @override
  State<AppEntrance> createState() => _AppEntranceState();
}

class _AppEntranceState extends State<AppEntrance>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    value: 1,
    duration: AppMotion.contentIn,
  );
  bool _reduced = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = AppMotion.reduced(context);
    if (_reduced) _controller.value = 1;
  }

  @override
  void didUpdateWidget(AppEntrance oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled || _reduced || oldWidget.identity != widget.identity) {
      _controller.value = 1;
    } else if (oldWidget.trigger != widget.trigger) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    child: widget.child,
    builder: (_, child) {
      final value = AppMotion.progress(_controller);
      return Transform.translate(
        offset: Offset(0, 6 * (1 - value)),
        child: Opacity(opacity: value, child: child),
      );
    },
  );
}

class AppDisclosure extends StatelessWidget {
  const AppDisclosure({super.key, required this.expanded});
  final bool expanded;
  @override
  Widget build(BuildContext context) => AnimatedRotation(
    turns: expanded ? .5 : 0,
    duration: AppMotion.duration(
      context,
      expanded ? AppMotion.panelIn : AppMotion.panelOut,
    ),
    curve: expanded ? AppMotion.enterCurve : AppMotion.exitCurve,
    child: const Icon(Icons.expand_more),
  );
}
