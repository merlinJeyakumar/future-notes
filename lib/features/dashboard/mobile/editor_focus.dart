import 'package:flutter/material.dart';

/// Mobile editing starts from a deliberate input gesture, not route restoration.
class MobileEditorFocus {
  MobileEditorFocus(Iterable<FocusNode> nodes)
    : _original = {for (final node in nodes) node: node.canRequestFocus} {
    for (final node in _original.keys) {
      _focused[node] = node.hasFocus;
      node.canRequestFocus = false;
      node.addListener(_changed);
    }
  }

  final Map<FocusNode, bool> _original;
  final Map<FocusNode, bool> _focused = {};
  final Set<FocusNode> _allowed = {};
  final Map<FocusNode, FocusNode> _regions = {};
  bool _disposed = false;

  void attachRegion(FocusNode node, FocusNode region) {
    _regions[node] = region;
    region.descendantsAreFocusable = _allowed.contains(node);
  }

  void detachRegion(FocusNode node, FocusNode region) {
    if (identical(_regions[node], region)) _regions.remove(node);
  }

  void allow(FocusNode node, {bool request = false}) {
    if (_disposed || _original[node] != true) return;
    _allowed.add(node);
    _regions[node]?.descendantsAreFocusable = true;
    node.canRequestFocus = true;
    if (request) node.requestFocus();
  }

  void _changed() {
    for (final node in _original.keys) {
      final wasFocused = _focused[node] ?? false;
      _focused[node] = node.hasFocus;
      if ((wasFocused && !node.hasFocus) ||
          (node.hasFocus && !_allowed.contains(node))) {
        _revoke(node);
      }
    }
  }

  void _revoke(FocusNode node) {
    _allowed.remove(node);
    _regions[node]?.descendantsAreFocusable = false;
    node.canRequestFocus = false;
    node.unfocus();
  }

  void dismiss() {
    if (_disposed) return;
    for (final node in _original.keys) {
      _revoke(node);
    }
  }

  /// A hardware Tab action remains an explicit way to enter the editor.
  void allowTraversal() {
    if (_disposed) return;
    for (final node in _original.keys) {
      allow(node);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_disposed) return;
      for (final node in _original.keys) {
        if (!node.hasFocus) _revoke(node);
      }
    });
  }

  void dispose() {
    _disposed = true;
    for (final entry in _original.entries) {
      entry.key.removeListener(_changed);
      entry.key.canRequestFocus = entry.value;
    }
  }
}

class MobileEditorInputRegion extends StatefulWidget {
  const MobileEditorInputRegion({
    super.key,
    required this.focus,
    required this.node,
    required this.enabled,
    required this.child,
  });

  final MobileEditorFocus focus;
  final FocusNode node;
  final bool enabled;
  final Widget child;

  @override
  State<MobileEditorInputRegion> createState() =>
      _MobileEditorInputRegionState();
}

class _MobileEditorInputRegionState extends State<MobileEditorInputRegion> {
  final _region = FocusNode(
    debugLabel: 'Mobile editor input intent',
    canRequestFocus: false,
    skipTraversal: true,
    descendantsAreFocusable: false,
  );

  @override
  void initState() {
    super.initState();
    widget.focus.attachRegion(widget.node, _region);
  }

  @override
  void didUpdateWidget(covariant MobileEditorInputRegion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focus != widget.focus || oldWidget.node != widget.node) {
      oldWidget.focus.detachRegion(oldWidget.node, _region);
      widget.focus.attachRegion(widget.node, _region);
    }
    if (!widget.enabled) widget.focus.dismiss();
  }

  @override
  void dispose() {
    widget.focus.detachRegion(widget.node, _region);
    _region.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus.withExternalFocusNode(
    focusNode: _region,
    child: TextFieldTapRegion(
      onTapOutside: (_) => widget.focus.dismiss(),
      child: Semantics(
        onTap: widget.enabled
            ? () => widget.focus.allow(widget.node, request: true)
            : null,
        child: Listener(
          onPointerDown: widget.enabled
              ? (_) => widget.focus.allow(widget.node)
              : null,
          child: widget.child,
        ),
      ),
    ),
  );
}
