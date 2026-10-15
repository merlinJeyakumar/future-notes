import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../models/note_model.dart';
import '../viewmodels/content_viewmodel.dart';
import '../../../core/storage/attachment_open_cache.dart';
import 'attachment_presentation.dart';

abstract class AttachmentMediaPlayer {
  Widget build(BuildContext context);
  Future<void> pause();
  Future<void> dispose();
}

typedef AttachmentPlayerFactory = AttachmentMediaPlayer Function(String path);

class NativeAttachmentPlayer implements AttachmentMediaPlayer {
  NativeAttachmentPlayer(String path, {this.onOpenSystem}) {
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
  final Future<void> Function()? onOpenSystem;
  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
    future: _opening,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return AttachmentPreviewFallback(
          message: 'Playback unavailable.',
          onOpenSystem: onOpenSystem,
        );
      }
      return StreamBuilder<String>(
        stream: _player.stream.error,
        builder: (context, failure) {
          if (failure.hasData && failure.data!.isNotEmpty) {
            return AttachmentPreviewFallback(
              message: 'Playback unavailable.',
              onOpenSystem: onOpenSystem,
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
    this.fileName,
    this.alreadyOpen = false,
  });
  final ValueChanged<AttachmentAction> onSelected;
  final bool enabled;
  final bool canRemove;
  final String? fileName;
  final bool alreadyOpen;
  @override
  Widget build(BuildContext context) => PopupMenuButton<AttachmentAction>(
    tooltip: fileName == null
        ? 'More attachment actions'
        : 'More actions for $fileName',
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
          enabled: item.$1 == AttachmentAction.remove
              ? canRemove
              : (item.$1 == AttachmentAction.open && alreadyOpen)
              ? false
              : enabled,
          child: Text(
            item.$1 == AttachmentAction.open && alreadyOpen
                ? '${item.$2} (Already open)'
                : item.$2,
          ),
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
  bool _systemOpening = false;
  String? _systemError;
  ImageProvider? _previewImage;
  @override
  void initState() {
    super.initState();
    if (attachmentVisualKind(widget.attachment.fileName) ==
        AttachmentVisualKind.video) {
      try {
        _player =
            widget.playerFactory?.call(widget.file.path) ??
            NativeAttachmentPlayer(widget.file.path, onOpenSystem: _openSystem);
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
    await _previewImage?.evict();
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
    _previewImage?.evict();
    super.dispose();
  }

  Future<void> _openSystem() async {
    if (_systemOpening || !mounted) return;
    setState(() {
      _systemOpening = true;
      _systemError = null;
    });
    try {
      final result = await widget.viewModel.openAttachment(
        widget.attachment,
        system: true,
      );
      if (!result.isSuccess && mounted)
        setState(
          () => _systemError = result.message ?? 'System opening failed.',
        );
    } finally {
      if (mounted) setState(() => _systemOpening = false);
    }
  }

  Future<void> _action(AttachmentAction action) async {
    switch (action) {
      case AttachmentAction.open:
        break;
      case AttachmentAction.system:
        await _openSystem();
      case AttachmentAction.save:
        await widget.viewModel.exportAttachment(widget.attachment);
      case AttachmentAction.remove:
        await widget.viewModel.removeAttachment(widget.attachment.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final extension = widget.attachment.fileName.split('.').last.toLowerCase();
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          close();
        },
      },
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) close();
        },
        child: Dialog(
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
                    AttachmentMoreButton(
                      onSelected: _action,
                      alreadyOpen: true,
                      enabled: !_systemOpening,
                      fileName: widget.attachment.fileName,
                      canRemove: !widget.viewModel.hasAttachmentJobs,
                    ),
                    IconButton(
                      tooltip: 'Close preview',
                      onPressed: close,
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                if (_systemError != null)
                  Semantics(
                    liveRegion: true,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(_systemError!),
                    ),
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
                      ? LayoutBuilder(
                          builder: (context, constraints) {
                            final ratio = MediaQuery.devicePixelRatioOf(
                              context,
                            );
                            // Bound initial decoded pixels. Zoom magnifies this preview;
                            // the original file remains available through system Open.
                            final width = (constraints.maxWidth * ratio)
                                .clamp(1, 2048)
                                .round();
                            final height = (constraints.maxHeight * ratio)
                                .clamp(1, 2048)
                                .round();
                            final image = ResizeImage.resizeIfNeeded(
                              width,
                              height,
                              FileImage(File(widget.file.path)),
                            );
                            if (_previewImage != image) _previewImage?.evict();
                            _previewImage = image;
                            return InteractiveViewer(
                              child: Image(
                                image: image,
                                fit: BoxFit.contain,
                                semanticLabel: widget.attachment.fileName,
                                errorBuilder: (_, error, stack) =>
                                    AttachmentPreviewFallback(
                                      message: 'Image preview unavailable.',
                                      onOpenSystem: _openSystem,
                                    ),
                              ),
                            );
                          },
                        )
                      : AttachmentPreviewFallback(
                          message: _playbackFailed
                              ? 'Playback unavailable.'
                              : 'No in-app preview for this file.',
                          onOpenSystem: _openSystem,
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class AttachmentPreviewFallback extends StatefulWidget {
  const AttachmentPreviewFallback({
    super.key,
    required this.message,
    this.onOpenSystem,
  });
  final String message;
  final Future<void> Function()? onOpenSystem;
  @override
  State<AttachmentPreviewFallback> createState() =>
      _AttachmentPreviewFallbackState();
}

class _AttachmentPreviewFallbackState extends State<AttachmentPreviewFallback> {
  bool _opening = false;
  String? _error;
  Future<void> _open() async {
    if (_opening || widget.onOpenSystem == null) return;
    setState(() {
      _opening = true;
      _error = null;
    });
    try {
      await widget.onOpenSystem!();
    } catch (_) {
      if (mounted) setState(() => _error = 'System opening failed.');
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.message, textAlign: TextAlign.center),
          if (_error != null) Text(_error!),
          if (widget.onOpenSystem != null)
            TextButton.icon(
              onPressed: _opening ? null : _open,
              icon: const Icon(Icons.open_in_new),
              label: Text(_opening ? 'Opening…' : 'Open in system app'),
            ),
        ],
      ),
    ),
  );
}
