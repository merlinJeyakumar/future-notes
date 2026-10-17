import 'dart:math' as math;
import 'package:flutter/widgets.dart';

/// Overlay coordinates include the keyboard. Keep suggestions in the visible
/// region even when an IME opens or changes height while a query is active.
Rect mentionPopupBounds({
  required Rect caret,
  required Size overlay,
  required EdgeInsets insets,
  required EdgeInsets safeArea,
  required int matches,
}) {
  final left = safeArea.left + 8;
  final right = math.max(left, overlay.width - safeArea.right - 8);
  final top = safeArea.top + 8;
  final bottom = math.max(
    top,
    overlay.height - math.max(insets.bottom, safeArea.bottom) - 8,
  );
  final width = math.min(320.0, right - left);
  final desired = math.min(6, math.max(1, matches)) * 48.0 + 29;
  final below = (bottom - caret.bottom - 4).clamp(0.0, bottom - top);
  final above = (caret.top - 4 - top).clamp(0.0, bottom - top);
  final useBelow = below >= desired || below >= above;
  final height = math.min(desired, useBelow ? below : above);
  return Rect.fromLTWH(
    caret.left.clamp(left, math.max(left, right - width)),
    (useBelow ? caret.bottom + 4 : caret.top - height - 4).clamp(
      top,
      math.max(top, bottom - height),
    ),
    width,
    height,
  );
}
