import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import '../models/note_model.dart';

/// Restores bounded encrypted metadata only. Never opens an attachment payload.
class MobileAttachmentThumbnails extends ChangeNotifier {
  MobileAttachmentThumbnails({required this.restore, bool? enabled})
    : enabled = enabled ?? Platform.isAndroid;
  final bool enabled;
  final Future<Uint8List?> Function(AttachmentModel) restore;
  Object? _owner;
  int _refreshRevision = 0;
  int _epoch = 0;
  bool _running = false, _closed = false, _deferred = false;
  List<AttachmentModel> _entries = [];
  final _attempted = <String, String?>{};
  final _images = <String, Uint8List>{};
  Uint8List? image(String id) => _images[id];
  void reportDecodeFailure(String id, Uint8List bytes) {
    // Image error builders run during layout; publish the failure afterwards.
    scheduleMicrotask(() {
      if (_closed || !identical(_images[id], bytes)) return;
      _images.remove(id);
      _evict(bytes);
      debugPrint('THUMBNAIL_RENDER_FAILED');
      notifyListeners();
    });
  }

  void update({
    required Object? owner,
    required List<AttachmentModel> attachments,
    required bool unlocked,
    bool defer = false,
    int refreshRevision = 0,
  }) {
    if (_closed || !enabled) return;
    if (_owner != owner || !unlocked) {
      _owner = owner;
      _epoch++;
      _clear();
    }
    _deferred = defer;
    if (_refreshRevision != refreshRevision) {
      _refreshRevision = refreshRevision;
      // Explicit refresh retries failed metadata restores; progress updates do
      // not trigger retry loops or evict already displayed pictures.
      _attempted.removeWhere((id, _) => !_images.containsKey(id));
    }
    _entries = unlocked ? List.of(attachments) : [];
    final byId = {for (final a in _entries) a.id: a.encryptedThumbnail};
    for (final id in _attempted.keys.toList()) {
      if (!byId.containsKey(id) || byId[id] != _attempted[id]) {
        final old = _images.remove(id);
        if (old != null) _evict(old);
        _attempted.remove(id);
      }
    }
    unawaited(_drain());
  }

  Future<void> _drain() async {
    if (_running || _closed || _deferred) return;
    _running = true;
    try {
      while (!_closed && !_deferred) {
        final next = _entries
            .where((a) => !_attempted.containsKey(a.id))
            .firstOrNull;
        if (next == null) break;
        _attempted[next.id] = next.encryptedThumbnail;
        if (next.encryptedThumbnail == null) continue;
        final epoch = _epoch;
        bool current() =>
            !_closed &&
            epoch == _epoch &&
            _entries.any(
              (a) =>
                  a.id == next.id &&
                  a.encryptedThumbnail == next.encryptedThumbnail,
            );
        try {
          final bytes = await restore(next);
          if (bytes != null && current()) {
            _images[next.id] = bytes;
            notifyListeners();
          }
        } catch (_) {
          /* Unsupported derived data keeps its icon. */
        }
      }
    } finally {
      _running = false;
    }
  }

  void _evict(Uint8List bytes) =>
      PaintingBinding.instance.imageCache.evict(MemoryImage(bytes));
  void _clear() {
    for (final bytes in _images.values) {
      _evict(bytes);
    }
    _images.clear();
    _attempted.clear();
  }

  @override
  void dispose() {
    _closed = true;
    _epoch++;
    _entries = [];
    _clear();
    super.dispose();
  }
}
