import 'dart:async';
import '../../../core/operations/operation_result.dart';
import '../models/note_model.dart';
import 'background_service.dart';
import 'encryption_service.dart';
import 'note_codec.dart';
import 'provider_note_files.dart';

class ProviderDiscovery implements LibraryDiscovery {
  ProviderDiscovery(this.files);
  final ProviderNoteFiles files;
  final _snapshots = StreamController<DiscoverySnapshot>.broadcast();
  final _failures = StreamController<DiscoveryFailureEvent>.broadcast();
  final _cipher = EncryptionService();
  DiscoveryRequest? _desired;
  int _request = 0;
  bool _closed = false;
  Future<void>? _active;
  @override
  bool get isReady => !_closed;
  @override
  DiscoveryRequest? get requestedScan => _desired;
  @override
  Stream<DiscoverySnapshot> get discoveriesStream => _snapshots.stream;
  @override
  Stream<DiscoveryFailureEvent> get failuresStream => _failures.stream;
  @override
  bool isCurrent(DiscoveryRequest request) =>
      !_closed && _desired?.matches(request) == true;
  @override
  Future<void> init() async {}
  @override
  void invalidateRequests() {
    _desired = null;
  }

  @override
  void loadRecentFiles(String directoryPath) {
    final request = DiscoveryRequest(
      directoryPath,
      files.binding.generation,
      ++_request,
    );
    _desired = request;
    if (_active == null) _drain();
  }

  void _drain() {
    final request = _desired;
    if (request == null || _closed) return;
    _active = _scan(request).whenComplete(() {
      _active = null;
      if (!_closed && _desired != null && !request.matches(_desired!)) _drain();
    });
  }

  Future<void> _scan(DiscoveryRequest request) async {
    try {
      final recent = <RecentFile>[];
      for (final name in await files.getRecentFiles()) {
        if (!isCurrent(request)) return;
        final reference = await files.resolveNote(name);
        if (reference == null) continue;
        try {
          final source = await files.readResolved(reference);
          if (source == null) continue;
          final decoded = await NoteCodec.decode(
            source,
            decryptApp: _cipher.decryptAppResult,
          );
          final note = decoded.note;
          final stats = await files.getFileStats(name);
          recent.add(
            RecentFile(
              path: name,
              fullPath: reference.contentPath,
              title: note.title,
              noteId: note.id,
              isLocked: note.isLocked,
              created: DateTime.fromMillisecondsSinceEpoch(note.timestamp),
              modified: stats?.modified,
              sizeBytes: stats?.size,
            ),
          );
        } on FormatException {
          // Non-note files can coexist in a selected folder. Do not migrate them.
          continue;
        }
      }
      recent.sort(
        (a, b) => (b.modified ?? b.created ?? DateTime(1970)).compareTo(
          a.modified ?? a.created ?? DateTime(1970),
        ),
      );
      if (isCurrent(request))
        _snapshots.add(DiscoverySnapshot(request, recent, isFinal: true));
    } catch (_) {
      if (isCurrent(request))
        _failures.add(
          DiscoveryFailureEvent(
            const OperationResult.failure(
              OperationOutcome.ioFailure,
              'Selected-folder discovery failed. Check its availability and refresh.',
            ),
            request: request,
          ),
        );
    }
  }

  @override
  void dispose() {
    _closed = true;
    _desired = null;
    _snapshots.close();
    _failures.close();
  }
}
