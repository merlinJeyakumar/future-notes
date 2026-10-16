import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/platform/window_actions.dart';
import '../../../core/operations/operation_result.dart';

/// Stays above Navigator routes so dialogs do not cover the window controls.
class DesktopWindowFrame extends StatefulWidget {
  const DesktopWindowFrame({
    super.key,
    required this.actions,
    required this.child,
  });
  final WindowActions actions;
  final Widget child;
  static const height = 36.0;
  static const buttonWidth = 46.0;
  @override
  State<DesktopWindowFrame> createState() => _DesktopWindowFrameState();
}

class _DesktopWindowFrameState extends State<DesktopWindowFrame> {
  bool _available = true;
  bool _pending = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final configured = await widget.actions.configureFrame(true);
      if (mounted && !configured.isSuccess) setState(() => _available = false);
    });
  }

  Future<void> _run(Future<OperationResult<void>> Function() command) async {
    if (_pending) return;
    setState(() {
      _pending = true;
      _error = null;
    });
    final result = await command();
    if (mounted) {
      setState(() {
        _pending = false;
        _error = result.isSuccess ? null : result.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Overlay.wrap(
    child: Column(
      children: [
        if (_available)
          ValueListenableBuilder<DesktopWindowState>(
            valueListenable: widget.actions.state,
            builder: (context, state, _) => Material(
              color: Theme.of(context).colorScheme.surface,
              child: SizedBox(
                key: const ValueKey('window-caption'),
                height: DesktopWindowFrame.height,
                child: Directionality(
                  textDirection: TextDirection.ltr,
                  child: Row(
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(left: 12),
                          child: Tooltip(
                            message:
                                _error ??
                                'Drag to move · Double-click to maximize or restore',
                            child: Text(
                              _error ?? 'Future Notes',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelMedium,
                            ),
                          ),
                        ),
                      ),
                      _button(
                        'Minimize',
                        Icons.remove,
                        widget.actions.minimize,
                      ),
                      _button(
                        state.maximized ? 'Restore' : 'Maximize',
                        state.maximized ? Icons.filter_none : Icons.crop_square,
                        widget.actions.toggleMaximize,
                      ),
                      _button(
                        'Close',
                        Icons.close,
                        widget.actions.requestClose,
                        close: true,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        Expanded(child: widget.child),
      ],
    ),
  );
  Widget _button(
    String label,
    IconData icon,
    Future<OperationResult<void>> Function() command, {
    bool close = false,
  }) => SizedBox(
    width: DesktopWindowFrame.buttonWidth,
    height: DesktopWindowFrame.height,
    child: IconButton(
      tooltip: label,
      onPressed: _pending ? null : () => unawaited(_run(command)),
      style: IconButton.styleFrom(
        shape: const RoundedRectangleBorder(),
        hoverColor: close ? Colors.red.withValues(alpha: .8) : null,
      ),
      icon: Icon(icon, size: 15),
    ),
  );
}
