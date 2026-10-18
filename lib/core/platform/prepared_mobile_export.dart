import 'dart:io';
import 'dart:math';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'mobile_export.dart';

class PreparedMobileExport {
  const PreparedMobileExport({
    required this.path,
    required this.note,
    required this.key,
    required this.length,
    required this.modifiedMicros,
  });
  final String path, note, key;
  final int length, modifiedMicros;
  Future<bool> isCurrent() async {
    final stat = await File(path).stat();
    return stat.type == FileSystemEntityType.file &&
        stat.size == length &&
        stat.modified.microsecondsSinceEpoch == modifiedMicros &&
        await File(path).resolveSymbolicLinks() == path;
  }
}

/// Session-only package reuse. Keys never persist passwords or password hashes.
/// Metadata/source fingerprints identify a snapshot without payload rescans.
class PreparedMobileExportCache {
  final _secret = List<int>.generate(32, (_) => Random.secure().nextInt(256));
  final _notes = <String, PreparedMobileExport>{};
  final _jobs = <String, PreparedMobileExport>{};
  String key(Object snapshot, String? password) => Hmac(
    sha256,
    _secret,
  ).convert(utf8.encode(jsonEncode([snapshot, password]))).toString();
  PreparedMobileExport? forJob(String job) => _jobs[job];
  Future<PreparedMobileExport?> find(String note, String key) async {
    final cached = _notes[note];
    if (cached == null || cached.key != key) return null;
    if (!await cached.isCurrent()) {
      await invalidate(note);
      return null;
    }
    return cached;
  }

  void reuse(String job, PreparedMobileExport file) {
    _jobs[job] = file;
  }

  Future<void> remember({
    required String job,
    required String note,
    required String key,
    required String path,
  }) async {
    final stat = await File(path).stat();
    if (stat.type != FileSystemEntityType.file)
      throw StateError('Export unavailable.');
    await invalidate(note);
    final file = PreparedMobileExport(
      path: path,
      note: note,
      key: key,
      length: stat.size,
      modifiedMicros: stat.modified.microsecondsSinceEpoch,
    );
    _notes[note] = file;
    _jobs[job] = file;
  }

  Future<void> invalidate(String note) async {
    final old = _notes.remove(note);
    _jobs.removeWhere((_, file) => file.note == note);
    if (old != null) await MobileExport.discardAll([old.path]);
  }

  Future<void> close() async {
    final paths = _notes.values.map((file) => file.path).toList();
    _notes.clear();
    _jobs.clear();
    await MobileExport.discardAll(paths);
  }
}
