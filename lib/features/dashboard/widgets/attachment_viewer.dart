import '../../../core/theme/app_tooltip.dart';
import '../../../core/theme/app_motion.dart';
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../models/note_model.dart';
import '../viewmodels/content_viewmodel.dart';
import '../../../core/storage/attachment_open_cache.dart';
import 'attachment_presentation.dart';
import 'attachment_document_preview.dart';
import 'attachment_media_overlay.dart';

abstract class AttachmentMediaPlayer {
  Widget build(BuildContext context);
  Future<void> play();
  Future<void> pause();
  Future<void> dispose();
}

typedef AttachmentPlayerFactory = AttachmentMediaPlayer Function(String path);

class NativeAttachmentPlayer implements AttachmentMediaPlayer {
  NativeAttachmentPlayer(String path, {String? fileName, this.onOpenSystem}) {
    MediaKit.ensureInitialized();
    final name = fileName ?? path;
    _audioOnly = attachmentVisualKind(name) == AttachmentVisualKind.audio;
    _player = Player();
    try {
      // Audio uses a thumbnail and never creates a native video texture.
      if (!_audioOnly) _controller = VideoController(_player);
      _opening = _open(path);
    } catch (_) {
      _player.dispose();
      _failed.dispose();
      rethrow;
    }
  }
  late final Player _player;
  VideoController? _controller;
  late final bool _audioOnly;
  late final Future<void> _opening;
  final _failed = ValueNotifier(false);
  Future<void>? _disposal;
  bool _disposed = false;
  bool _wantsPlayback = false;
  final Future<void> Function()? onOpenSystem;

  Future<void> _open(String path) async {
    if (_disposed) return;
    // Viewer requests Play explicitly. A pause/close while opening must win.
    await _player.open(Media(path), play: false);
  }

  @override
  Future<void> play() async {
    if (_disposed) return;
    _wantsPlayback = true;
    await _opening;
    if (_disposed || !_wantsPlayback) return;
    if (_player.state.completed) await _player.seek(Duration.zero);
    if (!_disposed && _wantsPlayback) await _player.play();
  }

  Future<void> _toggle() async {
    if (_disposed) return;
    try {
      if (_player.state.playing) {
        await pause();
      } else {
        await play();
      }
    } catch (_) {
      if (!_disposed) _failed.value = true;
    }
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: _failed,
    builder: (context, failed, _) => FutureBuilder<void>(
      future: _opening,
      builder: (context, snapshot) {
        if (_disposed) return const SizedBox.shrink();
        if (failed || snapshot.hasError) {
          return AttachmentPreviewFallback(
            message: 'Playback unavailable.',
            onOpenSystem: onOpenSystem,
          );
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
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
            if (_audioOnly) {
              return StreamBuilder<bool>(
                stream: _player.stream.playing,
                initialData: _player.state.playing,
                builder: (context, state) => AudioAttachmentThumbnail(
                  playing: state.data ?? false,
                  onToggle: _toggle,
                ),
              );
            }
            return MaterialDesktopVideoControlsTheme(
              normal: const MaterialDesktopVideoControlsThemeData(
                playAndPauseOnTap: true,
                visibleOnMount: true,
              ),
              fullscreen: const MaterialDesktopVideoControlsThemeData(
                playAndPauseOnTap: true,
                visibleOnMount: true,
              ),
              child: Video(
                controller: _controller!,
                controls: MaterialDesktopVideoControls,
              ),
            );
          },
        );
      },
    ),
  );

  @override
  Future<void> pause() async {
    _wantsPlayback = false;
    if (!_disposed) await _player.pause();
  }

  @override
  Future<void> dispose() => _disposal ??= _dispose();

  Future<void> _dispose() async {
    _disposed = true;
    _wantsPlayback = false;
    try {
      await _player.dispose();
    } finally {
      _failed.dispose();
    }
  }
}

/// GIF uses Flutter's animated-image decoder, with pixel bounds matching images.
/// TickerMode pauses the current frame without restarting or converting the file.
class GifAttachmentPlayer implements AttachmentMediaPlayer {
  GifAttachmentPlayer(this.path, {this.onOpenSystem});
  final String path;
  final Future<void> Function()? onOpenSystem;
  final _playing = ValueNotifier(false);
  ImageProvider? _image;
  bool _disposed = false;
  Future<void>? _disposal;

  @override
  Future<void> play() async {
    if (!_disposed) _playing.value = true;
  }

  @override
  Future<void> pause() async {
    if (!_disposed) _playing.value = false;
  }

  @override
  Future<void> dispose() => _disposal ??= _dispose();
  Future<void> _dispose() async {
    _disposed = true;
    _playing.value = false;
    await _image?.evict();
    _playing.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: _playing,
    builder: (context, playing, _) {
      if (_disposed) return const SizedBox.shrink();
      return LayoutBuilder(
        builder: (context, constraints) {
          final ratio = MediaQuery.devicePixelRatioOf(context);
          final image = ResizeImage.resizeIfNeeded(
            (constraints.maxWidth * ratio).clamp(1, 2048).round(),
            (constraints.maxHeight * ratio).clamp(1, 2048).round(),
            FileImage(File(path)),
          );
          if (_image != image) _image?.evict();
          _image = image;
          final label = playing ? 'Pause' : 'Play';
          return Semantics(
            label: playing ? 'Pause animation' : 'Play animation',
            child: InkWell(
              key: const ValueKey('gif-playback-preview'),
              onTap: () => _playing.value = !playing,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  TickerMode(
                    enabled: playing,
                    child: Image(
                      image: image,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => AttachmentPreviewFallback(
                        message: 'GIF preview unavailable.',
                        onOpenSystem: onOpenSystem,
                      ),
                    ),
                  ),
                  Positioned(
                    right: 12,
                    bottom: 12,
                    child: Material(
                      color: Colors.black.withValues(alpha: .45),
                      borderRadius: BorderRadius.circular(8),
                      child: IconButton(
                        key: const ValueKey('gif-playback-toggle'),
                        tooltip: label,
                        iconSize: 20,
                        color: Colors.white.withValues(alpha: .85),
                        onPressed: () => _playing.value = !playing,
                        icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

/// Audio artwork is a lightweight local thumbnail, not a blank video texture.
class AudioAttachmentThumbnail extends StatelessWidget {
  const AudioAttachmentThumbnail({
    super.key,
    required this.playing,
    required this.onToggle,
  });
  final bool playing;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = playing ? 'Pause audio' : 'Play audio';
    return Center(
      child: AppTooltip(
        message: label,
        child: Material(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: const ValueKey('audio-playback-thumbnail'),
            onTap: onToggle,
            child: Semantics(
              button: true,
              label: label,
              child: SizedBox(
                width: 160,
                height: 160,
                child: Stack(
                  children: [
                    Center(
                      child: Icon(
                        Icons.music_note,
                        size: 72,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    Positioned(
                      right: 12,
                      bottom: 12,
                      child: Icon(
                        playing ? Icons.pause_circle : Icons.play_circle,
                        size: 28,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
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
    this.compact = false,
    this.onCancel,
    this.onRetry,
    this.onRemovePending,
  });
  final ValueChanged<AttachmentAction> onSelected;
  final bool enabled;
  final bool canRemove;
  final String? fileName;
  final bool alreadyOpen;
  final bool compact;
  final VoidCallback? onCancel;
  final VoidCallback? onRetry;
  final VoidCallback? onRemovePending;
  @override
  Widget build(BuildContext context) => PopupMenuButton<VoidCallback>(
    popUpAnimationStyle: AppMotion.menu(context),
    padding: compact ? EdgeInsets.zero : const EdgeInsets.all(8),
    tooltip: fileName == null
        ? 'More attachment actions'
        : 'More actions for $fileName',
    icon: const Icon(Icons.more_vert, size: 20),
    onSelected: (action) => action(),
    itemBuilder: (_) => [
      if (onCancel != null)
        PopupMenuItem(value: onCancel, child: const Text('Cancel attachment')),
      if (onRetry != null)
        PopupMenuItem(value: onRetry, child: const Text('Retry')),
      if (onRemovePending != null)
        PopupMenuItem(
          value: onRemovePending,
          child: const Text('Remove pending'),
        ),
      for (final item in [
        (AttachmentAction.open, 'Open in Future Notes'),
        (AttachmentAction.system, 'Open in system app'),
        (AttachmentAction.save, 'Save As'),
        (AttachmentAction.remove, 'Remove'),
      ])
        PopupMenuItem(
          value: () => onSelected(item.$1),
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
    this.documentFactory,
  });
  final ContentViewModel viewModel;
  final AttachmentModel attachment;
  final CachedAttachmentFile file;
  final AttachmentPlayerFactory? playerFactory;
  final AttachmentDocumentFactory? documentFactory;
  @override
  State<AttachmentViewer> createState() => _AttachmentViewerState();
}

class _AttachmentViewerState extends State<AttachmentViewer> {
  AttachmentMediaPlayer? _player;
  AttachmentDocumentRenderer? _document;
  Future<void>? _closing;
  Future<void>? _resources;
  bool _dismissing = false;
  bool _revoked = false;
  bool _playbackFailed = false;
  bool _documentFailed = false;
  bool _systemOpening = false;
  String? _systemError;
  ImageProvider? _previewImage;
  late final Future<DateTime?> _storedDate;
  @override
  void initState() {
    super.initState();
    _storedDate = widget.viewModel.attachmentStoredDate(widget.attachment.id);
    if (attachmentSupportsPlayback(widget.attachment.fileName)) {
      try {
        _player =
            widget.attachment.fileName.split('.').last.toLowerCase() == 'gif'
            ? GifAttachmentPlayer(widget.file.path, onOpenSystem: _openSystem)
            : widget.playerFactory?.call(widget.file.path) ??
                  NativeAttachmentPlayer(
                    widget.file.path,
                    fileName: widget.attachment.fileName,
                    onOpenSystem: _openSystem,
                  );
        unawaited(_startPlayback());
      } catch (_) {
        _playbackFailed = true;
      }
    }
    widget.viewModel.registerAttachmentViewer(close);
    widget.viewModel.registerAttachmentPauser(pause);
    if (attachmentSupportsDocumentPreview(widget.attachment.fileName)) {
      try {
        _document = (widget.documentFactory ?? NativeAttachmentDocument.new)(
          widget.file.path,
          widget.attachment.fileName,
          _openSystem,
        );
        unawaited(_loadDocument());
      } catch (_) {
        _documentFailed = true;
      }
    }
  }

  Future<void> _loadDocument() async {
    try {
      await _document!.load();
    } catch (_) {
      if (mounted && _closing == null) setState(() => _documentFailed = true);
    }
  }

  Future<void> _startPlayback() async {
    try {
      await _player?.play();
    } catch (_) {
      if (mounted && _closing == null) setState(() => _playbackFailed = true);
    }
  }

  Future<void> pause() async {
    await _player?.pause();
  }

  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    // Security/storage joins bypass the ordinary visual closing transition.
    if (mounted) setState(() => _revoked = true);
    if (mounted) {
      final route = ModalRoute.of(context);
      if (route != null && route.isActive) {
        Navigator.of(context).removeRoute(route);
      }
    }
    await _disposeResources();
  }

  Future<void> _disposeResources() => _resources ??= _releaseResources();
  Future<void> _releaseResources() async {
    widget.viewModel.unregisterAttachmentViewer(close);
    widget.viewModel.unregisterAttachmentPauser(pause);
    await _player?.dispose();
    await _document?.dispose();
    await _previewImage?.evict();
  }

  Future<void> _dismiss() async {
    if (_dismissing || _closing != null || !mounted) return;
    setState(() => _dismissing = true);
    try {
      await pause();
    } catch (_) {
      // A failed native pause must not leave an unclosable playing preview.
      await close();
      return;
    }
    if (!mounted || _revoked) return;
    final route = ModalRoute.of(context);
    Navigator.of(context).pop();
    if (route != null) await route.completed;
    await _disposeResources();
  }

  @override
  void dispose() {
    widget.viewModel.unregisterAttachmentViewer(close);
    widget.viewModel.unregisterAttachmentPauser(pause);
    unawaited(_disposeResources().catchError((Object _, StackTrace _) {}));
    super.dispose();
  }

  Future<void> _openSystem() async {
    if (_systemOpening || !mounted || _closing != null) return;
    setState(() {
      _systemOpening = true;
      _systemError = null;
    });
    try {
      await pause();
      final result = await widget.viewModel.openAttachment(
        widget.attachment,
        system: true,
      );
      if (!result.isSuccess && mounted)
        setState(
          () => _systemError = result.message ?? 'System opening failed.',
        );
    } catch (_) {
      if (mounted) setState(() => _systemError = 'System opening failed.');
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

  Widget _withInformation(Widget preview) {
    final name = widget.attachment.fileName;
    if (!attachmentSupportsPlayback(name) &&
        attachmentVisualKind(name) != AttachmentVisualKind.image) {
      return preview;
    }
    return AttachmentMediaOverlay(
      attachment: widget.attachment,
      length: widget.file.length,
      storedDate: _storedDate,
      child: preview,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_revoked) return const SizedBox.shrink();
    final extension = widget.attachment.fileName.split('.').last.toLowerCase();
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          unawaited(_dismiss());
        },
      },
      child: PopScope(
        canPop: _dismissing,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) unawaited(_dismiss());
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
                      onPressed: _dismissing ? null : _dismiss,
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
                  child: _withInformation(
                    _playbackFailed
                        ? AttachmentPreviewFallback(
                            message: 'Playback unavailable.',
                            onOpenSystem: _openSystem,
                          )
                        : _player != null
                        ? _player!.build(context)
                        : _documentFailed
                        ? AttachmentPreviewFallback(
                            message: 'Document preview unavailable.',
                            onOpenSystem: _openSystem,
                          )
                        : _document != null
                        ? _document!.build(context)
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
                              if (_previewImage != image)
                                _previewImage?.evict();
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
