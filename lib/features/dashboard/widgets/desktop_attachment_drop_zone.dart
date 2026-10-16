import '../../../core/theme/app_motion.dart';
import 'dart:async';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// External desktop drops are attachments, never editor text or HTML.
class DesktopAttachmentDropZone extends StatefulWidget {
  const DesktopAttachmentDropZone({
    super.key,
    required this.enabled,
    required this.onDrop,
    required this.child,
  });
  final bool enabled;
  final Future<void> Function(List<String>) onDrop;
  final Widget child;
  @override
  State<DesktopAttachmentDropZone> createState() =>
      _DesktopAttachmentDropZoneState();
}

class _DesktopAttachmentDropZoneState extends State<DesktopAttachmentDropZone> {
  bool _hovering = false;
  bool _dropping = false;

  Future<void> _drop(DropDoneDetails details) async {
    if (!widget.enabled ||
        _dropping ||
        !(ModalRoute.isCurrentOf(context) ?? true)) {
      return;
    }
    setState(() {
      _hovering = false;
      _dropping = true;
    });
    try {
      await widget.onDrop(
        details.files.map((file) => file.path).toList(growable: false),
      );
    } finally {
      if (mounted) setState(() => _dropping = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final desktop =
        !kIsWeb &&
        {
          TargetPlatform.windows,
          TargetPlatform.linux,
          TargetPlatform.macOS,
        }.contains(defaultTargetPlatform);
    if (!desktop) return widget.child;
    final enabled =
        widget.enabled &&
        !_dropping &&
        (ModalRoute.isCurrentOf(context) ?? true);
    final accent = Theme.of(context).colorScheme.primary;
    return DropTarget(
      enable: enabled,
      onDragEntered: (_) => setState(() => _hovering = true),
      onDragExited: (_) => setState(() => _hovering = false),
      onDragDone: (details) => unawaited(_drop(details)),
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          if (enabled)
            Positioned.fill(
              child: IgnorePointer(
                child: AppReveal(
                  visible: _hovering,
                  fade: true,
                  duration: AppMotion.quickIn,
                  reverseDuration: AppMotion.quickOut,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(color: accent, width: 2),
                      color: accent.withValues(alpha: .06),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Material(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.attach_file, color: accent, size: 18),
                              const SizedBox(width: 8),
                              const Text('Drop files to attach'),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
