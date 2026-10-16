import 'package:flutter/material.dart';
import '../../../core/theme/app_motion.dart';
import '../models/note_model.dart';
import 'attachment_presentation.dart';

/// Presentation metadata only: never reads, decrypts or probes a media file.
class AttachmentMediaOverlay extends StatefulWidget {
  const AttachmentMediaOverlay({
    super.key,
    required this.attachment,
    required this.length,
    required this.child,
    this.storedDate,
    this.visible,
  });
  final AttachmentModel attachment;
  final int length;
  final Widget child;
  final Future<DateTime?>? storedDate;

  /// Null follows pointer hover; documents use their explicit Info toggle.
  final bool? visible;
  @override
  State<AttachmentMediaOverlay> createState() => _AttachmentMediaOverlayState();
}

class _AttachmentMediaOverlayState extends State<AttachmentMediaOverlay> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final visible = widget.visible ?? _hovered;
    final extension = widget.attachment.fileName.split('.').last.toUpperCase();
    final format = extension == widget.attachment.fileName.toUpperCase()
        ? widget.attachment.mimeType ?? 'Media'
        : extension;
    return MouseRegion(
      onEnter: (_) {
        if (widget.visible == null) setState(() => _hovered = true);
      },
      onExit: (_) {
        if (widget.visible == null) setState(() => _hovered = false);
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          Positioned(
            top: 8,
            left: 12,
            right: 12,
            child: IgnorePointer(
              child: ExcludeSemantics(
                excluding: !visible,
                child: AnimatedOpacity(
                  opacity: visible ? 1 : 0,
                  duration: AppMotion.duration(
                    context,
                    visible ? AppMotion.quickIn : AppMotion.quickOut,
                  ),
                  child: Material(
                    key: const ValueKey('media-information-ribbon'),
                    color: Colors.black.withValues(alpha: .62),
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      child: DefaultTextStyle(
                        style: Theme.of(
                          context,
                        ).textTheme.labelSmall!.copyWith(color: Colors.white),
                        child: FutureBuilder<DateTime?>(
                          future: widget.storedDate,
                          builder: (_, snapshot) {
                            final date = snapshot.data?.toLocal();
                            String two(int value) =>
                                value.toString().padLeft(2, '0');
                            final details = [
                              format,
                              formatAttachmentBytes(widget.length),
                              if (date != null)
                                'Stored ${two(date.day)}/${two(date.month)} ${two(date.hour)}:${two(date.minute)}',
                            ];
                            return Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.attachment.fileName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  details.join(' · '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            );
                          },
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
