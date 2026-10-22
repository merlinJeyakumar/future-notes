import 'package:flutter/material.dart';

/// Retains Material's positioning, styling, semantics and visibility behavior.
class AppTooltip extends Tooltip {
  const AppTooltip({
    super.key,
    required super.message,
    required super.child,
    super.waitDuration,
    super.showDuration,
  });
}
