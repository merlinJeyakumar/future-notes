import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'note_reference.dart';

typedef DirectoryWatchFactory =
    Stream<FileSystemEvent> Function(String path, bool recursive);

abstract interface class LibraryWatch {
  StorageBinding get binding;
  Stream<void> get changes;
  bool get failed;
  Future<void> close();
}

/// A recursive root watch plus a shallow ancestor watch. The latter survives
/// root removal and follows creation of missing path components without polling.
class NativeLibraryWatch implements LibraryWatch {
  NativeLibraryWatch._(this.binding, this._verify, this._watch, this._exists);

  static Future<NativeLibraryWatch> open(
    StorageBinding binding, {
    required Future<void> Function(String) verify,
    DirectoryWatchFactory? watch,
    Future<bool> Function(String)? exists,
  }) async {
    final owner = NativeLibraryWatch._(
      binding,
      verify,
      watch ??
          ((path, recursive) => Directory(path).watch(recursive: recursive)),
      exists ?? ((path) => Directory(path).exists()),
    );
    try {
      await owner._rebind();
      return owner;
    } catch (_) {
      await owner.close();
      rethrow;
    }
  }

  @override
  final StorageBinding binding;
  final Future<void> Function(String) _verify;
  final DirectoryWatchFactory _watch;
  final Future<bool> Function(String) _exists;
  final _changes = StreamController<void>.broadcast();
  StreamSubscription<FileSystemEvent>? _rootWatch;
  StreamSubscription<FileSystemEvent>? _ancestorWatch;
  String? _ancestor;
  bool _closed = false;
  bool _failed = false;
  bool _pending = false;
  Future<void>? _rebinding;
  Future<void>? _closing;

  @override
  Stream<void> get changes => _changes.stream;
  @override
  bool get failed => _failed;

  bool _internal(String path) => p
      .split(p.relative(path, from: binding.root))
      .any((part) => part.startsWith('.future-notes-'));

  void _error(Object error, [StackTrace? stackTrace]) {
    if (_closed) return;
    _failed = true;
    _changes.addError(const FileSystemException('Library watching failed.'));
  }

  void _event(FileSystemEvent event) {
    if (_closed) return;
    final paths = [
      event.path,
      if (event is FileSystemMoveEvent && event.destination != null)
        event.destination!,
    ];
    var topology = false;
    for (final path in paths) {
      final location = p.normalize(path);
      if (p.equals(location, binding.root) ||
          p.isWithin(location, binding.root)) {
        topology = true;
      }
      if ((p.equals(location, binding.root) ||
              p.isWithin(binding.root, location)) &&
          !_internal(location)) {
        _changes.add(null);
      }
    }
    if (topology) _requestRebind();
  }

  void _requestRebind() {
    if (_closed || _failed) return;
    _pending = true;
    if (_rebinding != null) return;
    _rebinding = (() async {
      try {
        while (_pending && !_closed) {
          _pending = false;
          await _rebind();
        }
      } catch (error) {
        _error(error);
      } finally {
        _rebinding = null;
      }
    })();
  }

  Future<void> _rebind() async {
    await _verify(binding.root);
    var ancestor = p.dirname(binding.root);
    while (!await _exists(ancestor)) {
      final parent = p.dirname(ancestor);
      if (p.equals(parent, ancestor)) {
        throw const FileSystemException('No watch ancestor.');
      }
      ancestor = parent;
    }
    if (_closed) return;
    if (_ancestor != ancestor) {
      await _ancestorWatch?.cancel();
      if (_closed) return;
      _ancestor = ancestor;
      _ancestorWatch = _watch(ancestor, false).listen(
        _event,
        onError: _error,
        onDone: () {
          _ancestor = null;
          _requestRebind();
        },
      );
    }
    final exists = await _exists(binding.root);
    if (_closed) return;
    // Reattach even when a same-named root was removed and recreated.
    await _rootWatch?.cancel();
    _rootWatch = null;
    if (_closed) return;
    if (exists) {
      _rootWatch = _watch(
        binding.root,
        true,
      ).listen(_event, onError: _error, onDone: _requestRebind);
    }
    // Covers changes in the attach gap; the VM coalesces this refresh.
    if (!_closed) _changes.add(null);
  }

  @override
  Future<void> close() => _closing ??= (() async {
    try {
      _closed = true;
      await _rebinding;
      var failed = false;
      try {
        await _rootWatch?.cancel();
        _rootWatch = null;
      } catch (_) {
        failed = true;
      }
      try {
        await _ancestorWatch?.cancel();
        _ancestorWatch = null;
      } catch (_) {
        failed = true;
      }
      await _changes.close();
      if (failed) {
        throw const FileSystemException('Library watch cleanup failed.');
      }
    } catch (_) {
      _closing = null;
      rethrow;
    }
  })();
}
