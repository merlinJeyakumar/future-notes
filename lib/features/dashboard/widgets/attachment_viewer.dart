import 'dart:io';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../models/note_model.dart';
import '../viewmodels/content_viewmodel.dart';
import '../../../core/storage/attachment_open_cache.dart';

abstract class AttachmentMediaPlayer {
  Widget build(BuildContext context);
  Future<void> pause();
  Future<void> dispose();
}

typedef AttachmentPlayerFactory = AttachmentMediaPlayer Function(String path);

class NativeAttachmentPlayer implements AttachmentMediaPlayer {
  NativeAttachmentPlayer(String path) {
    MediaKit.ensureInitialized();
    _player = Player();
    try {
      _controller = VideoController(_player);
      _opening = _player.open(Media(path), play: false);
    } catch (_) {
      _player.dispose();
      rethrow;
    }
  }
  late final Player _player;
  late final VideoController _controller;
  late final Future<void> _opening;
  Future<void>? _disposal;
  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
    future: _opening,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return const Center(
          child: Text('Playback unavailable. Use Open in system app.'),
        );
      }
      return StreamBuilder<String>(
        stream: _player.stream.error,
        builder: (context, failure) {
          if (failure.hasData && failure.data!.isNotEmpty) {
            return const Center(
              child: Text('Playback unavailable. Use Open in system app.'),
            );
          }
          return Video(
            controller: _controller,
            controls: MaterialDesktopVideoControls,
          );
        },
      );
    },
  );
  @override
  Future<void> pause() => _player.pause();
  @override
  Future<void> dispose() => _disposal ??= _player.dispose();
}

enum AttachmentAction { open, system, save, remove }

class AttachmentMoreButton extends StatelessWidget {
  const AttachmentMoreButton({
    super.key,
    required this.onSelected,
    this.enabled = true,
    this.canRemove = true,
  });
  final ValueChanged<AttachmentAction> onSelected;
  final bool enabled;
  final bool canRemove;
  @override
  Widget build(BuildContext context) => PopupMenuButton<AttachmentAction>(
    tooltip: 'More attachment actions',
    icon: const Icon(Icons.more_vert, size: 20),
    onSelected: onSelected,
    itemBuilder: (_) => [
      for (final item in [
        (AttachmentAction.open, 'Open in Future Notes'),
        (AttachmentAction.system, 'Open in system app'),
        (AttachmentAction.save, 'Save As'),
        (AttachmentAction.remove, 'Remove'),
      ])
        PopupMenuItem(
          value: item.$1,
          enabled: item.$1 == AttachmentAction.remove ? canRemove : enabled,
          child: Text(item.$2),
        ),
    ],
  );
}

class AttachmentViewer extends StatefulWidget {
  const AttachmentViewer({
    super.key,
    required this.viewModel,
    required this.attachment,
    required this.file,
    this.playerFactory,
  });
  final ContentViewModel viewModel;
  final AttachmentModel attachment;
  final CachedAttachmentFile file;
  final AttachmentPlayerFactory? playerFactory;
  @override
  State<AttachmentViewer> createState() => _AttachmentViewerState();
}

class _AttachmentViewerState extends State<AttachmentViewer> {
  AttachmentMediaPlayer? _player;
  Future<void>? _closing;
  bool _playbackFailed = false;
  @override
  void initState() {
    super.initState();
    final extension = widget.attachment.fileName.split('.').last.toLowerCase();
    if ([
      'mp4',
      'mkv',
      'mov',
      'webm',
      'avi',
      'wmv',
      'm4v',
      'mpg',
      'mpeg',
      '3gp',
    ].contains(extension)) {
      try {
        _player = (widget.playerFactory ?? NativeAttachmentPlayer.new)(
          widget.file.path,
        );
      } catch (_) {
        _playbackFailed = true;
      }
    }
    widget.viewModel.registerAttachmentViewer(close);
    widget.viewModel.registerAttachmentPauser(pause);
  }

  Future<void> pause() async {
    await _player?.pause();
  }

  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    widget.viewModel.unregisterAttachmentViewer(close);
    widget.viewModel.unregisterAttachmentPauser(pause);
    await _player?.dispose();
    if (mounted) {
      final route = ModalRoute.of(context);
      if (route != null) Navigator.of(context).removeRoute(route);
    }
  }

  @override
  void dispose() {
    widget.viewModel.unregisterAttachmentViewer(close);
    widget.viewModel.unregisterAttachmentPauser(pause);
    _player?.dispose();
    super.dispose();
  }

  Future<void> _action(AttachmentAction action) async {
    switch (action) {
      case AttachmentAction.open:
        break;
      case AttachmentAction.system:
        await widget.viewModel.openAttachment(widget.attachment, system: true);
      case AttachmentAction.save:
        await widget.viewModel.exportAttachment(widget.attachment);
      case AttachmentAction.remove:
        await widget.viewModel.removeAttachment(widget.attachment.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final extension = widget.attachment.fileName.split('.').last.toLowerCase();
    return Dialog(
      child: SizedBox(
        width: 960,
        height: MediaQuery.sizeOf(context).height * .78,
        child: Column(
          children: [
            Row(
              children: [
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    widget.attachment.fileName,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                AttachmentMoreButton(onSelected: _action),
                IconButton(
                  tooltip: 'Close preview',
                  onPressed: close,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            Expanded(
              child: _player != null
                  ? _player!.build(context)
                  : [
                      'jpg',
                      'jpeg',
                      'png',
                      'webp',
                      'gif',
                      'bmp',
                    ].contains(extension)
                  ? InteractiveViewer(
                      child: Image.file(
                        File(widget.file.path),
                        fit: BoxFit.contain,
                        errorBuilder: (_, error, stack) => const Center(
                          child: Text(
                            'Image preview unavailable. Use Open in system app.',
                          ),
                        ),
                      ),
                    )
                  : Center(
                      child: Text(
                        _playbackFailed
                            ? 'Playback unavailable. Use Open in system app.'
                            : 'No in-app preview. Use Open in system app.',
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
