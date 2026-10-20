import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Keeps selection actions inside the writing viewport, clear of app controls
/// and the IME. Callbacks and localized buttons still belong to the editor.
class MobileSelectionToolbar extends StatelessWidget {
  const MobileSelectionToolbar({
    super.key,
    required this.viewportKey,
    required this.anchors,
    required this.buttonItems,
    required this.layoutChanges,
  });

  final GlobalKey viewportKey;
  final TextSelectionToolbarAnchors anchors;
  final List<ContextMenuButtonItem> buttonItems;
  final Listenable layoutChanges;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: layoutChanges,
    builder: (context, _) => LayoutBuilder(
      builder: (context, constraints) {
        final viewport = viewportKey.currentContext?.findRenderObject();
        final overlay = Overlay.of(
          context,
          rootOverlay: true,
        ).context.findRenderObject();
        if (buttonItems.isEmpty ||
            viewport is! RenderBox ||
            !viewport.attached ||
            !viewport.hasSize ||
            overlay is! RenderBox) {
          return const SizedBox.shrink();
        }
        final origin = overlay.localToGlobal(Offset.zero);
        final view = View.of(context);
        final ratio = view.devicePixelRatio;
        final safe = Rect.fromLTRB(
          view.viewPadding.left / ratio,
          view.viewPadding.top / ratio,
          (view.physicalSize.width - view.viewPadding.right) / ratio,
          (view.physicalSize.height -
                  math.max(view.viewInsets.bottom, view.viewPadding.bottom)) /
              ratio,
        ).shift(-origin);
        final bounds =
            (viewport.localToGlobal(Offset.zero) - origin & viewport.size)
                .intersect(safe)
                .intersect(Offset.zero & constraints.biggest)
                .deflate(8);
        if (bounds.isEmpty) return const SizedBox.shrink();

        final buttons = SingleChildScrollView(
          primary: false,
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: AdaptiveTextSelectionToolbar.getAdaptiveButtons(
              context,
              buttonItems,
            ).toList(),
          ),
        );
        return CustomSingleChildLayout(
          delegate: _SelectionLayout(
            bounds,
            anchors.primaryAnchor - origin,
            (anchors.secondaryAnchor ?? anchors.primaryAnchor) - origin,
          ),
          child: Theme.of(context).platform == TargetPlatform.iOS
              ? CupertinoPopupSurface(
                  key: const ValueKey('mobile-selection-menu'),
                  child: buttons,
                )
              : Material(
                  key: const ValueKey('mobile-selection-menu'),
                  color: Theme.of(context).colorScheme.surface,
                  elevation: 2,
                  borderRadius: BorderRadius.circular(24),
                  clipBehavior: Clip.antiAlias,
                  child: buttons,
                ),
        );
      },
    ),
  );
}

class _SelectionLayout extends SingleChildLayoutDelegate {
  const _SelectionLayout(this.bounds, this.above, this.below);
  final Rect bounds;
  final Offset above;
  final Offset below;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints(maxWidth: bounds.width, maxHeight: bounds.height);

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final aboveY = above.dy - 8 - childSize.height;
    final belowY = below.dy + TextSelectionToolbar.kHandleSize + 8;
    final double y;
    if (aboveY >= bounds.top) {
      y = aboveY;
    } else if (belowY + childSize.height <= bounds.bottom) {
      y = belowY;
    } else {
      y = above.dy - bounds.top > bounds.bottom - below.dy ? aboveY : belowY;
    }
    return Offset(
      (above.dx - childSize.width / 2).clamp(
        bounds.left,
        bounds.right - childSize.width,
      ),
      y.clamp(bounds.top, bounds.bottom - childSize.height),
    );
  }

  @override
  bool shouldRelayout(_SelectionLayout oldDelegate) =>
      bounds != oldDelegate.bounds ||
      above != oldDelegate.above ||
      below != oldDelegate.below;
}
