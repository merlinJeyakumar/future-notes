import 'dart:async';
import '../../../core/operations/operation_result.dart';
import '../../../core/platform/library_documents.dart';
import '../../../core/platform/mobile_diagnostics.dart';
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
    var stage =
        1; // enumerate, recognize/resolve, decode, confirm folder access
    try {
      final recent = <RecentFile>[];
      var unreadable = 0;
      for (final entry in await files.discoveryCandidates()) {
        if (!isCurrent(request)) return;
        stage = 2;
        try {
          final candidate = await files.inspectDiscoveryCandidate(entry);
          if (candidate == null) continue;
          final reference = candidate.reference;
          stage = 3;
          final source = await files.readResolved(reference);
          if (source == null) throw const FormatException('Note disappeared.');
          final decoded = await NoteCodec.decode(
            source,
            decryptApp: _cipher.decryptAppResult,
          );
          final note = decoded.note;
          final metadata = candidate.metadata;
          recent.add(
            RecentFile(
              path: entry.name,
              fullPath: reference.contentPath,
              title: note.title,
              noteId: note.id,
              isLocked: note.isLocked,
              created: DateTime.fromMillisecondsSinceEpoch(note.timestamp),
              modified: metadata.modifiedMillis == null
                  ? null
                  : DateTime.fromMillisecondsSinceEpoch(
                      metadata.modifiedMillis!,
                    ),
              sizeBytes: metadata.length,
            ),
          );
        } catch (error) {
          if (error is LibraryAccessException &&
              const {
                'unsupported_provider',
                'wrong_backend',
              }.contains(error.code)) {
            rethrow;
          }
          // One damaged/unreadable entry must not hide the rest of the library.
          // Unrelated files that passed only the conservative header probe are
          // ignored. Recognizable entry failures are diagnostic-only; confirm
          // folder access below before publishing the remaining valid notes.
          if (error is! FormatException ||
              entry.isDirectory ||
              entry.name.startsWith('note_') ||
              entry.name.endsWith('.enc')) {
            unreadable++;
            _diagnose(stage, error);
          }
        }
      }
      if (unreadable > 0) {
        stage = 4;
        // A provider-wide outage must not acknowledge an empty/partial scan.
        await files.documents.root(files.location);
      }
      recent.sort(
        (a, b) => (b.modified ?? b.created ?? DateTime(1970)).compareTo(
          a.modified ?? a.created ?? DateTime(1970),
        ),
      );
      if (isCurrent(request)) {
        _snapshots.add(DiscoverySnapshot(request, recent, isFinal: true));
      }
    } catch (error) {
      _diagnose(stage, error);
      if (isCurrent(request)) {
        _failures.add(
          DiscoveryFailureEvent(
            OperationResult.failure(
              OperationOutcome.ioFailure,
              error is LibraryAccessException &&
                      error.code == 'permission_revoked'
                  ? 'Folder permission is unavailable. Select the folder again in Settings.'
                  : 'Selected folder could not be read. Previous results are retained. Check its availability and retry.',
            ),
            request: request,
          ),
        );
      }
    }
  }

  void _diagnose(int stage, Object error) {
    const reasons = [
      'permission_revoked',
      'missing_document',
      'metadata_limit',
      'ambiguous_names',
      'revision_changed',
      'short_read',
      'document_io',
    ];
    final index = error is LibraryAccessException
        ? reasons.indexOf(error.code)
        : -1;
    final reason = error is FormatException
        ? 1
        : index < 0
        ? 0
        : index + 2;
    MobileDiagnostics.record(MobileDiagnostic.discoveryFailed, {
      'stage': stage,
      'reason': reason,
    });
  }

  @override
  void dispose() {
    _closed = true;
    _desired = null;
    _snapshots.close();
    _failures.close();
  }
}
