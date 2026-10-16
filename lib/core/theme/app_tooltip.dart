import 'package:flutter/material.dart';
import 'app_motion.dart';

/// Retains Material's positioning, styling, semantics and visibility behavior.
class AppTooltip extends Tooltip {
  const AppTooltip({
    super.key,
    required super.message,
    required super.child,
    super.waitDuration,
    super.showDuration,
  });
  @override
  State<Tooltip> createState() => _AppTooltipState();
}

class _AppTooltipState extends TooltipState {
  @override
  Widget build(BuildContext context) {
    final material = super.build(context);
    if (material is! RawTooltip) return material;
    final reduced = AppMotion.reduced(context);
    return RawTooltip(
      key: material.key,
      semanticsTooltip: material.semanticsTooltip,
      hoverDelay: material.hoverDelay,
      touchDelay: material.touchDelay,
      dismissDelay: material.dismissDelay,
      enableTapToDismiss: material.enableTapToDismiss,
      triggerMode: material.triggerMode,
      enableFeedback: material.enableFeedback,
      onTriggered: material.onTriggered,
      positionDelegate: material.positionDelegate,
      animationStyle: AppMotion.menu(context),
      tooltipBuilder: (context, animation) {
        if (reduced) {
          return animation.status == AnimationStatus.reverse
              ? const SizedBox.shrink()
              : material.tooltipBuilder(
                  context,
                  const AlwaysStoppedAnimation(1),
                );
        }
        return Transform.translate(
          offset: Offset(0, 2 * (1 - animation.value)),
          child: material.tooltipBuilder(context, animation),
        );
      },
      child: material.child,
    );
  }
}
