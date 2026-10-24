import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:media_kit/media_kit.dart';
import 'attachment_thumbnail_codec.dart';

/// Android grants source access before a headless decoder may read it. The
/// caller retains its picked-source/cache ownership until this future settles.
class AndroidAttachmentThumbnails {
  AndroidAttachmentThumbnails({
    MethodChannel channel = const MethodChannel('future_notes/thumbnails'),
    Future<Uint8List?> Function(String)? fallback,
  }) : _channel = channel,
       _fallback = fallback ?? _queueVideoFrame;

  final MethodChannel _channel;
  final Future<Uint8List?> Function(String) _fallback;

  Future<Uint8List?> generate(String source, String path, String kind) async {
    if (!{'picked', 'cached'}.contains(source) ||
        !{'image', 'video'}.contains(kind)) {
      return null;
    }
    try {
      final result = await _channel.invokeMapMethod<String, Object?>(
        'generate',
        {'source': source, 'path': path, 'kind': kind},
      );
      final jpeg = result?['jpeg'];
      if (jpeg is Uint8List && AttachmentThumbnailCodec.validJpeg(jpeg)) {
        return jpeg;
      }
      // A null result or rejected source is never permission for another reader.
      if (kind != 'video' || result?['fallback'] != true) return null;
      final frame = await _fallback(path);
      return frame != null && AttachmentThumbnailCodec.validJpeg(frame)
          ? frame
          : null;
    } catch (_) {
      return null;
    }
  }

  // Use at most one temporary decoder, also across bulk attach/share jobs.
  static Future<void> _tail = Future.value();
  static Future<Uint8List?> _queueVideoFrame(String path) {
    final result = _tail.then((_) => _videoFrame(path));
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  static Future<Uint8List?> _videoFrame(String path) async {
    MediaKit.ensureInitialized();
    final player = Player(
      configuration: const PlayerConfiguration(
        muted: true,
        bufferSize: 4 * 1024 * 1024,
        protocolWhitelist: ['file'],
      ),
    );
    try {
      final native = player.platform as NativePlayer;
      // No VideoController/texture: initialization must not wait for a UI frame.
      for (final entry in {
        'vid': 'auto',
        'aid': 'no',
        'sid': 'no',
        'cache': 'no',
        'cache-on-disk': 'no',
        'hwdec': 'no',
        'vd-lavc-threads': '1',
      }.entries) {
        await native.setProperty(entry.key, entry.value);
      }
      // Opening paused also handles clips shorter than three seconds. Seek only
      // after the decoder has reported duration and a readable first frame.
      await player.open(Media(path), play: false);
      final deadline = Stopwatch()..start();
      var sought = false;
      while (deadline.elapsed < const Duration(seconds: 8)) {
        final video = player.state.videoParams;
        final width = video.w ?? 0, height = video.h ?? 0;
        if (width > 0 && height > 0) {
          if (width > 16777216 ~/ height) return null;
          if (!sought) {
            sought = true;
            final duration = player.state.duration.inMilliseconds;
            final millis = duration > 0
                ? math.min(3000, math.max(0, duration - 1))
                : 3000;
            await player.seek(Duration(milliseconds: millis));
            continue;
          }
          if (await native.getProperty('seeking') == 'yes') {
            await Future<void>.delayed(const Duration(milliseconds: 100));
            continue;
          }
          final frame = await player.screenshot();
          if (frame != null) {
            final edge = math.max(width, height);
            return FlutterImageCompress.compressWithList(
              frame,
              minWidth: math.max(1, (width * 160 / edge).round()),
              minHeight: math.max(1, (height * 160 / edge).round()),
              quality: 75,
            );
          }
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      return null;
    } finally {
      await player.dispose();
    }
  }
}
