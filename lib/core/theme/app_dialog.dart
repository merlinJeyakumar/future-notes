import 'package:flutter/material.dart';
import 'app_motion.dart';

Future<T?> showAppDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  bool useRootNavigator = true,
  bool useSafeArea = true,
  RouteSettings? routeSettings,
  bool? requestFocus,
}) {
  final navigator = Navigator.of(context, rootNavigator: useRootNavigator);
  return navigator.push<T>(
    AppDialogRoute<T>(
      context: context,
      builder: builder,
      themes: InheritedTheme.capture(from: context, to: navigator.context),
      barrierDismissible: barrierDismissible,
      useSafeArea: useSafeArea,
      settings: routeSettings,
      requestFocus: requestFocus,
    ),
  );
}

class AppDialogRoute<T> extends DialogRoute<T> {
  AppDialogRoute({
    required super.context,
    required super.builder,
    super.themes,
    super.barrierDismissible,
    super.useSafeArea,
    super.settings,
    super.requestFocus,
  }) : _initialReduced = AppMotion.reduced(context),
       super(
         barrierColor: DialogTheme.of(context).barrierColor ?? Colors.black54,
         animationStyle: AnimationStyle(
           duration: AppMotion.duration(context, AppMotion.dialogIn),
         ),
       );
  final bool _initialReduced;
  bool _snapScheduled = false;
  @override
  Duration get reverseTransitionDuration =>
      _initialReduced ? Duration.zero : AppMotion.dialogOut;
  void _finishReducedMotion() {
    if (_snapScheduled) return;
    _snapScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _snapScheduled = false;
      final current = controller;
      if (current != null && current.isAnimating) {
        current.value = current.status == AnimationStatus.reverse ? 0 : 1;
      }
    });
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final reduced = AppMotion.reduced(context);
    if (reduced) _finishReducedMotion();
    final value = reduced ? 1.0 : AppMotion.progress(animation);
    final dismissing = animation.status == AnimationStatus.reverse;
    return IgnorePointer(
      ignoring: dismissing,
      child: ExcludeFocus(
        excluding: dismissing,
        child: ExcludeSemantics(
          excluding: dismissing,
          child: Opacity(
            opacity: value,
            child: Transform.scale(scale: .97 + .03 * value, child: child),
          ),
        ),
      ),
    );
  }
}
