import 'dart:async';
import 'dart:io';
import '../../../core/storage/file_operation_progress.dart';
import '../../../core/platform/android_native_cipher.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
// import 'dart:io'; // duplicate removed
import 'package:file_picker/file_picker.dart';
import '../../../core/viewmodels/base_viewmodel.dart';
import '../services/file_service.dart';
import '../services/background_service.dart';
import '../services/encryption_service.dart';
import '../models/note_model.dart';
import '../models/attachment_mention.dart';
import '../../../core/routing/fnotes_uri.dart';
import '../models/note_import.dart';
import '../services/note_import_service.dart';
import 'dart:convert';
import 'package:flutter_quill/flutter_quill.dart';
// Removed invalid quill_delta import
import 'package:vsc_quill_delta_to_html/vsc_quill_delta_to_html.dart';
import 'package:flutter_quill_delta_from_html/flutter_quill_delta_from_html.dart';
import 'package:uuid/uuid.dart';
import 'package:code_text_field/code_text_field.dart';
import 'package:highlight/languages/xml.dart'; // XML handles HTML highlighting
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import '../services/settings_service.dart';
import '../services/pack_service.dart';
import '../services/streaming_pack_service.dart';
import '../../../core/storage/external_file_export.dart';
import '../../../core/operations/operation_result.dart';
import '../models/draft_session.dart';
import '../models/save_ui_state.dart';
import '../models/note_list_ui_state.dart';
import '../models/draft_transition.dart';
import '../models/note_envelope.dart' show DecodedNote;
import '../services/note_codec.dart';
import '../services/html_source_formatter.dart';
import '../../../core/storage/note_reference.dart';
import '../../../core/storage/owned_note_persistence.dart';
import '../../../core/storage/attachment_transform_worker.dart';
import '../../../core/storage/attachment_scheduler.dart';
import '../../../core/storage/owned_write.dart';
import '../../../core/storage/attachment_performance.dart';
import '../../../core/storage/streaming_file_cipher.dart';
import '../models/attachment_job.dart';
import '../../../core/storage/library_watch.dart';
import '../../../core/storage/attachment_open_cache.dart';
import '../../../core/platform/windows_desktop_actions.dart';
import '../../../core/platform/mobile_export.dart';
import '../../../core/platform/prepared_mobile_export.dart';
import '../../../core/platform/export_filename.dart';
import '../../../core/platform/attachment_batch_export.dart';
import '../../../core/storage/owned_settings_persistence.dart';
import 'package:path/path.dart' as p;

typedef RecentFileFilter =
    Future<List<RecentFile>> Function(List<RecentFile> files, String query);

class ContentViewModel extends BaseViewModel {
  final _preparedMobileExports = PreparedMobileExportCache();
  PreparedMobileExport? preparedExportForJob(String id) =>
      _preparedMobileExports.forJob(id);
  @protected
  bool get prepareMobilePackageExport => Platform.isAndroid || Platform.isIOS;
  final IFileService _fileService;
  final IEncryptionService _encryptionService;
  final SettingsService _settings;
  final int Function() _nowMilliseconds;
  final DraftDecisionHandler? _onDraftDecision;
  final RecentFileFilter _filterRecentFiles;
  final Future<List<dynamic>> Function(String) _htmlToDelta;
  final Future<String> Function(List<dynamic>) _deltaToHtml;
  final saveStateNotifier = ValueNotifier(
    const SaveUiState(SavePhase.unsavedDraft),
  );
  final noteListStateNotifier = ValueNotifier(const NoteListUiState());
  final isConvertingNotifier = ValueNotifier(false);
  bool _saveWriting = false;
  OperationOutcome? _saveFailure;
  int? _saveFailureOwner;
  int? _saveFailureCredential;
  int _conversionRequest = 0;
  int _libraryEpoch = 0;
  String? _listError;
  String _displayedQuery = '';
  bool _isScanning = false;
  bool _isFiltering = false;
  _SearchTicket? _activeSearch;
  _SearchTicket? _pendingSearch;
  StorageBinding? _postCommitRefreshBinding;
  DiscoveryRequest? _refreshInFlight;
  bool _refreshAgain = false;
  bool _refreshDispatching = false;
  bool _committedRefreshScheduled = false;
  String? _inventoryRoot;

  String get searchQuery => _searchQuery;
  int get libraryEpoch => _libraryEpoch;
  String? get currentContentPath => _noteReference?.contentPath;
  bool get isConvertingEditor => isConvertingNotifier.value;
  EditorMode get editorMode =>
      _isHtmlMode ? EditorMode.html : EditorMode.richText;

  void _publishSaveState() {
    if (_disposed) return;
    if (_saveFailureOwner != _session.generation ||
        _saveFailureCredential != _session.credentialGeneration) {
      _saveFailure = null;
    }
    final writing = _saveWriting || _pendingSaves.isNotEmpty;
    final phase = writing
        ? SavePhase.saving
        : _saveFailure != null
        ? SavePhase.failed
        : !_session.isPersisted
        ? SavePhase.unsavedDraft
        : _session.isDirty
        ? SavePhase.dirty
        : SavePhase.saved;
    saveStateNotifier.value = SaveUiState(
      phase,
      hasChanges: _session.isDirty,
      canRetry:
          !writing && _session.canWrite && !_isLocked && _saveFailure != null,
      failure: phase == SavePhase.failed ? _saveFailure : null,
    );
  }

  OperationResult<void> _saveResult(OperationResult<void> result) {
    if (!_disposed) {
      _saveFailure =
          result.isSuccess || result.outcome == OperationOutcome.cancelled
          ? null
          : result.outcome;
      _saveFailureOwner = _session.generation;
      _saveFailureCredential = _session.credentialGeneration;
      _publishSaveState();
    }
    return result;
  }

  Future<OperationResult<void>> retrySave() => saveNote();

  void _publishNoteList() {
    if (_disposed) return;
    noteListStateNotifier.value = NoteListUiState(
      files: recentFiles,
      query: _searchQuery,
      displayedQuery: _displayedQuery,
      isScanning: _isScanning,
      isFiltering: _isFiltering,
      error: _listError,
      selectedContentPath: currentContentPath,
      selectedLockState: _isLocked
          ? NoteLockState.locked
          : isPasswordSet
          ? NoteLockState.unlocked
          : NoteLockState.unprotected,
      unlockedContentPaths: Set.unmodifiable({
        for (final file in _recentFiles)
          if (file.isLocked && _sessionPasswords.containsKey(file.path))
            file.fullPath,
      }),
      libraryEpoch: _libraryEpoch,
    );
  }

  @override
  void notifyListeners() {
    _publishSaveState();
    _publishNoteList();
    _retireTerminalOpenJobs();
    super.notifyListeners();
  }

  void _markCommittedRefresh(StorageBinding binding) {
    _postCommitRefreshBinding = binding;
  }

  void _flushCommittedRefresh() {
    if (_disposed ||
        _libraryResourcesClosing ||
        _drainingSaves ||
        _mutationsPending != 0 ||
        _committedRefreshScheduled) {
      return;
    }
    final binding = _postCommitRefreshBinding;
    if (binding == null) return;
    _postCommitRefreshBinding = null;
    _committedRefreshScheduled = true;
    scheduleMicrotask(() {
      _committedRefreshScheduled = false;
      if (!_disposed &&
          !_libraryResourcesClosing &&
          p.equals(
            _noteReference?.binding.root ?? _inventoryRoot ?? '',
            binding.root,
          )) {
        unawaited(_requestBackgroundRefresh());
      }
    });
  }

  bool _importCutover = false;
  bool get isImportCutover => _importCutover;
  bool _decisionPending = false;
  bool _librarySwitching = false;
  bool _libraryCutover = false;
  int _librarySensitiveJobs = 0;
  LibraryWatch? _libraryWatch;
  StreamSubscription<void>? _libraryWatchSubscription;
  final _retiredWatches = <LibraryWatch>{};
  final _retiredLibraries = <StorageBinding>{};
  Future<void>? _libraryResourcesClose;
  bool get isLibraryCutover => _libraryCutover;
  SettingsService get settings => _settings;

  final QuillController quillController = QuillController.basic();
  final TextEditingController titleController = TextEditingController(
    text: "New Note",
  );
  final FocusNode focusNode = FocusNode();
  final ScrollController scrollController = ScrollController();

  String? _currentPassword;
  String? _currentFileName;
  Timer? _autoSaveTimer;
  Timer? _debounceTimer; // For file watching
  Timer? _searchDebounceTimer;
  StreamSubscription? _fileWatcherSubscription;
  final LibraryDiscovery? _backgroundService;
  StreamSubscription? _backgroundFilesSubscription;
  StreamSubscription? _backgroundErrorsSubscription;
  StreamSubscription? _documentSubscription;
  DraftSession _session = DraftSession(generation: 0);
  int _nextSessionGeneration = 0;
  int _loadRequest = 0;
  int _unlockRequest = 0;
  int _listingPathRequest = 0;
  int _listingRevision = 0;
  int _searchGeneration = 0;
  bool _disposed = false;
  bool _libraryResourcesClosing = false;
  bool _publishing = false;
  bool _autoSavePaused = false;
  bool _loading = false;

  /// Note reads keep their busy guards without a dashboard-wide dimming scrim.
  bool get isOpeningNote => _loading;
  int _activeLoads = 0;
  int _persistedCredentialGeneration = 0;
  String _observedHtml = '';
  String _observedTitle = 'New Note';
  Object? _observedRichDelta;
  NoteModel? _storedNote;
  String? _retainedPlainBody;
  NoteReference? _noteReference;
  String _draftNoteId = const Uuid().v4();
  int? _draftTimestamp;
  Map<String, dynamic> _retainedMetadata = {};
  NoteEnvelopeKind _envelopeKind = NoteEnvelopeKind.appEncrypted;
  Future<void> _saveTail = Future<void>.value();
  Future<void> _mutationTail = Future.value();
  int _mutationsPending = 0;
  final _attachmentWorker = AttachmentTransformWorker();
  AttachmentOpenCache? _attachmentOpenCache;
  // A new editor session must retain the acknowledged credentials' cache key.
  // Values live only in this process and contain no passwords or key material.
  final _noteCredentialGenerations = <String, int>{};
  String _credentialIdentity(NoteReference reference) {
    final path = p.normalize(reference.contentPath);
    return Platform.isWindows ? path.toLowerCase() : path;
  }

  final DesktopActions? _desktopActions;
  final attachmentCacheNotifier = ValueNotifier<int>(0);
  final _attachmentViewerClosers = <Future<void> Function()>{};
  final _attachmentViewerPausers = <Future<void> Function()>{};
  bool _revokingAttachmentAccess = false;
  void registerAttachmentViewer(Future<void> Function() close) =>
      _attachmentViewerClosers.add(close);
  void unregisterAttachmentViewer(Future<void> Function() close) =>
      _attachmentViewerClosers.remove(close);
  void registerAttachmentPauser(Future<void> Function() pause) =>
      _attachmentViewerPausers.add(pause);
  void unregisterAttachmentPauser(Future<void> Function() pause) =>
      _attachmentViewerPausers.remove(pause);
  Future<void> pauseAttachmentViewers() async {
    for (final pause in _attachmentViewerPausers.toList()) {
      try {
        await pause();
      } catch (_) {}
    }
  }

  Future<void> _closeAttachmentViewers() async {
    for (final close in _attachmentViewerClosers.toList()) {
      try {
        await close();
      } catch (_) {}
    }
  }

  Future<void> initializeAttachmentCache() async {
    if (_attachmentOpenCache == null &&
        _desktopActions != null &&
        _usesOwnedMutations) {
      _attachmentOpenCache = AttachmentOpenCache(
        worker: _attachmentWorker,
        rootResolver: () => _desktopActions.cacheRoot(
          validationRoot: _settings.isValidationMode
              ? _settings.storageEnvironment.validationRoot
              : null,
        ),
        sourceResolver:
            (_fileService as TransactionalNoteFiles).attachmentSource,
        sourcePreparer:
            (_fileService as TransactionalNoteFiles).attachmentSource,
        performance: () => _settings.attachmentPerformance,
        sourceValidator: _fileService is AttachmentSourceSession
            ? (_fileService as AttachmentSourceSession)
                  .isAttachmentSourceCurrent
            : null,
      );
    }
    try {
      await _attachmentOpenCache?.initialize();
    } catch (_) {
      /* Open reports typed failure. */
    }
  }

  Future<DateTime?> attachmentStoredDate(String id) async {
    final reference = _noteReference;
    final files = _fileService;
    final owner = _session.generation;
    final credentials = _session.credentialGeneration;
    if (_disposed ||
        _isLocked ||
        reference == null ||
        files is! AttachmentMetadataReader ||
        !_attachments.any((a) => a.id == id)) {
      return null;
    }
    try {
      final date = await (files as AttachmentMetadataReader).attachmentModified(
        reference,
        id,
      );
      if (_disposed ||
          _isLocked ||
          owner != _session.generation ||
          credentials != _session.credentialGeneration ||
          reference.contentPath != _noteReference?.contentPath ||
          !_attachments.any((a) => a.id == id))
        return null;
      return date;
    } catch (_) {
      return null;
    }
  }

  CachedAttachmentFile? cachedAttachment(String id) {
    final reference = _noteReference;
    if (_isLocked || reference == null) return null;
    return _attachmentOpenCache?.peek(
      reference,
      id,
      _session.credentialGeneration,
    );
  }

  Future<OperationResult<CachedAttachmentFile>> openAttachment(
    AttachmentModel attachment, {
    bool system = false,
  }) async {
    if (_disposed ||
        _isLocked ||
        _revokingAttachmentAccess ||
        _noteReference == null ||
        !_attachments.any((a) => a.id == attachment.id) ||
        _deleting) {
      return const OperationResult.failure(
        OperationOutcome.rejectedInput,
        'Unlock the note before opening its attachment.',
      );
    }
    final reference = _noteReference!;
    final credential = _session.credentialGeneration;
    final generation = _session.generation;
    final password = _currentPassword;
    await initializeAttachmentCache();
    if (_disposed ||
        _isLocked ||
        _revokingAttachmentAccess ||
        generation != _session.generation ||
        credential != _session.credentialGeneration) {
      return const OperationResult.failure(
        OperationOutcome.cancelled,
        'Attachment opening cancelled.',
      );
    }
    final cache = _attachmentOpenCache;
    if (cache == null)
      return const OperationResult.failure(
        OperationOutcome.rejectedInput,
        'File-based viewing is unavailable on this target.',
      );
    final job = _newAttachmentJob(
      const Uuid().v4(),
      attachment.fileName,
      originalAttachmentId: attachment.id,
      operation: AttachmentJobOperation.open,
    );
    final result = await _trackOwnedJob(
      cache.prepare(
        reference,
        attachment,
        credential,
        password: password,
        onProgress: (phase, bytes, total) => _jobPhase(
          job,
          phase == 'Queued'
              ? AttachmentJobPhase.queued
              : phase == 'Verifying'
              ? AttachmentJobPhase.verifying
              : phase == 'Preparing' || phase == 'Checking attachment'
              ? AttachmentJobPhase.preparing
              : AttachmentJobPhase.decrypting,
          bytes: bytes,
          total: phase == 'Queued' ? null : total,
        ),
      ),
    );
    if (_disposed ||
        _isLocked ||
        generation != _session.generation ||
        credential != _session.credentialGeneration ||
        _cancelledAttachmentJobs.contains(job.progress.value.id)) {
      _jobPhase(job, AttachmentJobPhase.cancelled);
      return const OperationResult.failure(
        OperationOutcome.cancelled,
        'Attachment opening cancelled.',
      );
    }
    _jobPhase(
      job,
      result.isSuccess
          ? AttachmentJobPhase.completed
          : result.outcome == OperationOutcome.cancelled
          ? AttachmentJobPhase.cancelled
          : AttachmentJobPhase.failed,
      error: result.message,
    );
    attachmentCacheNotifier.value++;
    if (!result.isSuccess) {
      _reportResult(OperationResult.failure(result.outcome, result.message));
      return result;
    }
    if (system) {
      final opened = await _desktopActions?.openFile(result.value!.path);
      if (opened == null || !opened.isSuccess) {
        final failed = OperationResult<CachedAttachmentFile>.failure(
          opened?.outcome ?? OperationOutcome.rejectedInput,
          'No system application could open this file.',
        );
        _reportResult(OperationResult.failure(failed.outcome, failed.message));
        return failed;
      }
    }
    return result;
  }

  Future<void> _invalidateAttachmentCache(NoteReference reference) async {
    _revokingAttachmentAccess = true;
    try {
      await _preparedMobileExports.invalidate(reference.contentPath);
      await _closeAttachmentViewers();
      for (final cached
          in _attachmentOpenCache?.filesForNote(reference) ??
              <CachedAttachmentFile>[]) {
        final image = FileImage(File(cached.path));
        await image.evict();
        await ResizeImage(image, width: 120, height: 120).evict();
      }
      if (_desktopActions is RevocableAttachmentActions) {
        await (_desktopActions as RevocableAttachmentActions).revokeFiles(
          (_attachmentOpenCache?.filesForNote(reference) ?? [])
              .map((e) => e.path)
              .toList(),
        );
      }
      await _attachmentOpenCache?.invalidateNote(reference);
      if (_fileService is AttachmentSourceSession) {
        await (_fileService as AttachmentSourceSession)
            .releaseAttachmentSources(reference);
      }
      if (!_disposed) attachmentCacheNotifier.value++;
    } finally {
      _revokingAttachmentAccess = false;
    }
  }

  Future<void> closeAttachmentCache() async {
    await _preparedMobileExports.close();
    if (_noteReference != null)
      await _invalidateAttachmentCache(_noteReference!);
    await _closeAttachmentViewers();
    await _attachmentOpenCache?.close();
  }

  final ValueNotifier<List<AttachmentJobState>> attachmentJobsNotifier =
      ValueNotifier([]);
  final Map<String, FileTransformJob> _attachmentTransforms = {};
  final Map<String, File> _packageCancellationFiles = {};
  final Map<String, FileReadCancellation> _exportReadCancellations = {};
  final Map<String, Future<void> Function()> _attachmentRetries = {};
  final Set<String> _cancelledAttachmentJobs = {};
  final Set<Future<void>> _activeOwnedJobs = {};
  final Set<AttachmentJobState> _ownedJobStates = {};
  final _jobRecovery = <String, Map<String, Object?>>{};
  Map<String, Object?>? attachmentJobRecovery(String id) => _jobRecovery[id];
  final Set<AttachmentJobState> _retiredJobStates = {};
  bool _jobRetirementScheduled = false;

  void _retireTerminalOpenJobs() {
    if (_disposed) return;
    final latest = <String, AttachmentJobState>{};
    for (final job in attachmentJobsNotifier.value) {
      final state = job.progress.value;
      if (state.operation == AttachmentJobOperation.open) {
        latest['${state.owner}/${state.originalAttachmentId}'] = job;
      }
    }
    final retiring = attachmentJobsNotifier.value.where((job) {
      final state = job.progress.value;
      return !state.active &&
          state.operation == AttachmentJobOperation.open &&
          (state.owner != _session.generation ||
              !identical(
                latest['${state.owner}/${state.originalAttachmentId}'],
                job,
              ));
    }).toSet();
    if (retiring.isEmpty) return;
    attachmentJobsNotifier.value = List.unmodifiable(
      attachmentJobsNotifier.value.where((job) => !retiring.contains(job)),
    );
    for (final job in retiring) {
      _ownedJobStates.remove(job);
      _cancelledAttachmentJobs.remove(job.progress.value.id);
      _retiredJobStates.add(job);
    }
    if (_jobRetirementScheduled) return;
    _jobRetirementScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _jobRetirementScheduled = false;
      for (final job in _retiredJobStates.toList()) {
        job.dispose();
      }
      _retiredJobStates.clear();
    });
  }

  bool _bulkAttachmentJob = false;
  int _attachmentAdds = 0;
  final _attachmentAddCompletions = <String, Completer<void>>{};
  bool _deleting = false;
  bool _deletingCurrent = false;
  bool get isDeletingCurrent => _deletingCurrent;
  final ValueNotifier<List<NoteReference>> pendingDeletionsNotifier =
      ValueNotifier([]);
  bool get _usesOwnedMutations =>
      _fileService is TransactionalNoteFiles &&
      (_fileService as TransactionalNoteFiles).usesOwnedStorage;
  bool get usesOwnedStorage => _usesOwnedMutations;
  bool get hasActiveExport => attachmentJobsNotifier.value.any(
    (state) =>
        state.progress.value.active &&
        state.progress.value.operation == AttachmentJobOperation.export,
  );

  // Export scan policy follows the actual native host, not a UI theme override.
  @protected
  bool get mobileAttachmentExportPolicy => Platform.isAndroid || Platform.isIOS;
  bool get hasAttachmentJobs =>
      attachmentJobsNotifier.value.any((j) => j.progress.value.active);

  Future<T> _mutate<T>(Future<T> Function() action) {
    final queued = _mutationsPending != 0;
    _mutationsPending++;
    // An idle queue starts in the caller's zone rather than joining a completed
    // future from a different zone (notably Flutter's fake-async test harness).
    final result = queued
        ? _mutationTail.then((_) => action())
        : Future<T>.sync(action);
    _mutationTail = result.then<void>(
      (_) {
        _mutationsPending--;
        _flushCommittedRefresh();
      },
      onError: (Object _, StackTrace __) {
        _mutationsPending--;
        _flushCommittedRefresh();
      },
    );
    return result;
  }

  Future<T> _trackOwnedJob<T>(Future<T> future) {
    final settled = future.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    _activeOwnedJobs.add(settled);
    settled.then((_) => _activeOwnedJobs.remove(settled));
    return future;
  }

  Future<OperationResult<void>> _resolveOwnerJobs(
    DraftTransition transition,
  ) async {
    if (!hasAttachmentJobs) return const OperationResult.success();
    final accepted = _activeOwnedJobs.toList();
    if (attachmentJobsNotifier.value.any(
      (job) => job.progress.value.phase == AttachmentJobPhase.finalizing,
    )) {
      if (transition == DraftTransition.exit) {
        final finishing = attachmentJobsNotifier.value
            .where(
              (job) =>
                  job.progress.value.phase == AttachmentJobPhase.finalizing,
            )
            .toList();
        final joins = finishing
            .map(
              (job) => _attachmentAddCompletions[job.progress.value.id]?.future,
            )
            .toList();
        if (joins.every((join) => join != null)) {
          await Future.wait(joins.cast<Future<void>>());
          return _resolveOwnerJobs(transition);
        }
        await Future.wait(accepted);
        return const OperationResult.success();
      }
      return const OperationResult.failure(
        OperationOutcome.conflict,
        'Finishing attachment commit. Wait before continuing.',
      );
    }
    final decision = await _askDraftDecision(
      DraftDecisionRequest(DraftDecisionKind.activeAttachments, transition),
    );
    if (decision != DraftDecision.discard) return _cancelledResult();
    // A commit can begin while the decision dialog is open.
    if (attachmentJobsNotifier.value.any(
      (job) => job.progress.value.phase == AttachmentJobPhase.finalizing,
    )) {
      if (transition != DraftTransition.exit) {
        return const OperationResult.failure(
          OperationOutcome.conflict,
          'Finishing attachment commit. Wait before continuing.',
        );
      }
      final finishing = attachmentJobsNotifier.value
          .where(
            (job) => job.progress.value.phase == AttachmentJobPhase.finalizing,
          )
          .toList();
      final joins = finishing
          .map(
            (job) => _attachmentAddCompletions[job.progress.value.id]?.future,
          )
          .toList();
      if (joins.every((join) => join != null)) {
        await Future.wait(joins.cast<Future<void>>());
        return _resolveOwnerJobs(transition);
      }
      await Future.wait(accepted);
      return const OperationResult.success();
    }
    final cancelling = attachmentJobsNotifier.value
        .where(_latchCancellation)
        .toList();
    await Future.wait(cancelling.map(_signalCancellation));
    await Future.wait(accepted);
    return const OperationResult.success();
  }

  final List<_PendingSave> _pendingSaves = [];
  bool _drainingSaves = false;
  final ValueNotifier<OperationResult<void>?> operationResultNotifier =
      ValueNotifier(null);

  DraftSession get draftSession => _session;
  bool get hasUnsavedChanges => _session.isDirty;
  List<RecentFile> _recentFiles = [];
  List<RecentFile> _filteredFiles = [];
  List<AttachmentModel> _attachments = [];

  final ValueNotifier<List<AttachmentModel>> attachmentsNotifier =
      ValueNotifier([]);
  final ValueNotifier<bool> isLockedNotifier = ValueNotifier(false);
  final ValueNotifier<bool> isAutoSavingNotifier = ValueNotifier(false);
  final ValueNotifier<bool> isSavingNotifier = ValueNotifier(false);

  /// Progress notifier for long-running operations like password change/removal.
  /// Format: "status message" or null when not in progress
  final ValueNotifier<String?> progressNotifier = ValueNotifier(null);

  final Map<String, String> _sessionPasswords = {};
  final Map<String, Uint8List> _attachmentCache = {};
  final Map<String, Future<Uint8List?>> _previewReads = {};
  bool _isLocked = false;

  bool get isLocked => _isLocked;

  String _searchQuery = "";

  List<RecentFile> get recentFiles =>
      _searchQuery.isEmpty ? _recentFiles : _filteredFiles;
  List<AttachmentModel> get attachments => _attachments;
  bool get isPasswordSet => _currentPassword != null;
  String? get currentFileName => _currentFileName;
  DateTime? get currentNoteDate {
    final timestamp = _storedNote?.timestamp;
    if (timestamp == null) return null;
    try {
      return DateTime.fromMillisecondsSinceEpoch(timestamp);
    } catch (_) {
      return null;
    }
  }

  late final CodeController htmlController;
  bool _isHtmlMode = false;
  bool get isHtmlMode => _isHtmlMode;

  final _nativeDropOwner = const Uuid().v4();
  bool _dropBatchActive = false;
  bool get canAcceptAttachmentDrop =>
      _usesOwnedMutations &&
      !_disposed &&
      !_isLocked &&
      _session.canWrite &&
      !_dropBatchActive &&
      !_bulkAttachmentJob &&
      !_librarySwitching &&
      !_libraryResourcesClosing &&
      !_importCutover &&
      !_deleting;

  Future<OperationResult<void>> attachDroppedFiles(
    List<String> paths, {
    bool waitForCompletion = true,
  }) async {
    if (paths.isEmpty) return _cancelledResult();
    if (!canAcceptAttachmentDrop) {
      return _reportResult(
        const OperationResult.failure(
          OperationOutcome.conflict,
          'Unlock the note and finish its active operation before attaching files.',
        ),
      );
    }
    final owner = _session.generation;
    final credential = _session.credentialGeneration;
    final captured = List<String>.of(paths);
    var admitted = false;
    _dropBatchActive = true;
    notifyListeners();
    try {
      return await _libraryTask(() async {
        bool ownsDrop() =>
            !_disposed &&
            owner == _session.generation &&
            credential == _session.credentialGeneration &&
            !_isLocked &&
            _session.canWrite &&
            !_libraryResourcesClosing &&
            !_importCutover;
        try {
          // Validate the batch before prompting for first Save or starting work.
          // Sources remain file-backed; the existing worker rechecks each source.
          final accepted = <String>{};
          for (final path in captured) {
            if (!p.isAbsolute(path) ||
                await FileSystemEntity.type(path, followLinks: false) !=
                    FileSystemEntityType.file ||
                await File(path).length() > 10 * 1024 * 1024 * 1024) {
              return _reportResult(
                const OperationResult.failure(
                  OperationOutcome.rejectedInput,
                  'Drop regular files up to 10 GiB each. Folders and unavailable files cannot be attached.',
                ),
              );
            }
            if (!ownsDrop()) return _cancelledResult();
            accepted.add(p.normalize(path));
          }
          if (!_session.isPersisted) {
            final decision = await _askDraftDecision(
              const DraftDecisionRequest(
                DraftDecisionKind.firstAttachment,
                DraftTransition.navigation,
              ),
            );
            if (!ownsDrop() || decision != DraftDecision.save) {
              return _cancelledResult();
            }
            final saved = await saveNote(allowEmptyFirstSave: true);
            if (!saved.isSuccess) return saved;
          }
          final work = <Future<OperationResult<void>>>[];
          for (final path in accepted) {
            if (!ownsDrop()) return _cancelledResult();
            work.add(addOwnedAttachment(path, p.basename(path)));
          }
          // Intake ends after admission, not after encryption/publication.
          _dropBatchActive = false;
          admitted = true;
          if (!_disposed) notifyListeners();
          Future<OperationResult<void>> finish() async {
            final results = await Future.wait(work);
            for (final result in results) {
              if (!result.isSuccess) return _reportResult(result);
            }
            return const OperationResult<void>.success();
          }

          final completed = finish();
          if (waitForCompletion) return completed;
          unawaited(completed);
          return const OperationResult<void>.success();
        } catch (_) {
          return _reportResult(
            const OperationResult.failure(
              OperationOutcome.ioFailure,
              'Dropped files could not be attached. Completed attachments and the draft were retained.',
            ),
          );
        }
      }, _cancelledResult());
    } finally {
      if (!admitted) _dropBatchActive = false;
      if (!_disposed) notifyListeners();
    }
  }

  String? get mobileDropTarget => canAcceptAttachmentDrop
      ? '$_nativeDropOwner:${_session.generation}:${_session.credentialGeneration}:${_noteReference?.binding.root ?? "new"}'
      : null;

  Future<OperationResult<void>> attachNativeDroppedSources(
    List<Map<Object?, Object?>> sources,
    String target,
  ) async {
    final files = _fileService;
    final adopted = <PlatformFile>[];
    if (files is! NativeDropSourceOwner || files is! PickedSourceOwner)
      return _cancelledResult();
    try {
      for (final source in sources) {
        adopted.add(
          (files as NativeDropSourceOwner).adoptDroppedSource(source),
        );
      }
      if (target != mobileDropTarget || !canAcceptAttachmentDrop)
        return _cancelledResult();
      final owner = _session.generation;
      final credential = _session.credentialGeneration;
      bool owns() =>
          !_disposed &&
          owner == _session.generation &&
          credential == _session.credentialGeneration &&
          !_isLocked &&
          _session.canWrite &&
          !_librarySwitching;
      if (adopted.any(
        (f) => f.path == null || f.size > 10 * 1024 * 1024 * 1024,
      ))
        return const OperationResult.failure(
          OperationOutcome.rejectedInput,
          'Attach regular files up to 10 GiB each.',
        );
      if (!_session.isPersisted) {
        final decision = await _askDraftDecision(
          const DraftDecisionRequest(
            DraftDecisionKind.firstAttachment,
            DraftTransition.navigation,
          ),
        );
        if (!owns() || decision != DraftDecision.save)
          return _cancelledResult();
        final saved = await saveNote(allowEmptyFirstSave: true);
        if (!saved.isSuccess) return saved;
      }
      if (!owns()) return _cancelledResult();
      for (final file in adopted.toList()) {
        if (!owns()) break;
        final pending = addOwnedAttachment(file.path!, file.name);
        adopted.remove(file);
        unawaited(
          pending
              .then(_reportResult)
              .whenComplete(
                () => (files as PickedSourceOwner).releasePickedSource(
                  file.path!,
                ),
              ),
        );
      }
      return const OperationResult.success();
    } finally {
      for (final file in adopted) {
        await (files as PickedSourceOwner).releasePickedSource(file.path!);
      }
    }
  }

  bool interruptedJobBelongs(Map<String, dynamic> record) {
    final recovery = record['recovery'];
    return recovery is Map &&
        recovery['library'] == _noteReference?.binding.root;
  }

  Future<bool> interruptedJobInLibrary(Map<String, dynamic> record) async {
    final recovery = record['recovery'];
    return recovery is Map &&
        recovery['library'] == await _fileService.getUserDataPath();
  }

  bool canRetryInterrupted(Map<String, dynamic> record) {
    final recovery = record['recovery'];
    return record['operation'] == 'add' &&
        recovery is Map &&
        interruptedJobBelongs(record) &&
        recovery['target'] == _currentFileName &&
        !_isLocked &&
        _session.canWrite &&
        _session.isPersisted &&
        !attachmentJobsNotifier.value.any(
          (job) =>
              job.progress.value.id == record['id'] &&
              job.progress.value.active,
        );
  }

  Future<OperationResult<void>> openInterruptedNote(
    Map<String, dynamic> record,
  ) async {
    if (!await interruptedJobInLibrary(record))
      return const OperationResult.failure(
        OperationOutcome.conflict,
        'Select the original library first.',
      );
    final recovery = Map<String, dynamic>.from(record['recovery'] as Map);
    final target = recovery['target'];
    if (target is! String)
      return const OperationResult.failure(
        OperationOutcome.rejectedInput,
        'This operation has no captured note.',
      );
    return loadNote(target);
  }

  Future<OperationResult<void>> retryInterruptedAttachment(
    Map<String, dynamic> record,
  ) async {
    if (!canRetryInterrupted(record) || _fileService is! PickedSourceRecovery)
      return const OperationResult.failure(
        OperationOutcome.conflict,
        'Open and unlock the original note before retrying.',
      );
    final recovery = Map<String, dynamic>.from(record['recovery'] as Map);
    final id = recovery['attachment'];
    if (id is! String || !RegExp(r'^[a-f0-9-]{36}$').hasMatch(id))
      return const OperationResult.failure(
        OperationOutcome.rejectedInput,
        'The interrupted attachment identity is unavailable.',
      );
    // A killed process may already have published the acknowledged generation.
    if (_attachments.any((a) => a.id == id)) {
      await discardInterruptedSource(record);
      return const OperationResult.success();
    }
    final owner = _session.generation;
    final credential = _session.credentialGeneration;
    PlatformFile? source;
    try {
      try {
        if (recovery['input'] is Map)
          source = await (_fileService as PickedSourceRecovery)
              .reopenPickedSource(
                Map<String, Object?>.from(recovery['input'] as Map),
              );
      } catch (_) {
        /* Transient drop grants require explicit reselection. */
      }
      source ??= (await _fileService.pickFile())?.files.single;
      if (source == null) return _cancelledResult();
      if (_disposed ||
          owner != _session.generation ||
          credential != _session.credentialGeneration ||
          _isLocked)
        return _cancelledResult();
      if (source.size != recovery['length'])
        return const OperationResult.failure(
          OperationOutcome.conflict,
          'The input length changed. The interrupted record was retained.',
        );
      if (_fileService is InterruptedStagingOwner &&
          recovery['staging'] is String) {
        await (_fileService as InterruptedStagingOwner)
            .discardInterruptedStaging(recovery['staging'] as String, id);
      }
      if (_disposed ||
          owner != _session.generation ||
          credential != _session.credentialGeneration ||
          _isLocked)
        return _cancelledResult();
      return await addOwnedAttachment(
        source.path!,
        recovery['fileName'] as String? ?? source.name,
        expectedHash: recovery['plaintextHash'] as String?,
        expectedModified: recovery['modified'] as int?,
        recoveryAttachmentId: id,
      );
    } catch (_) {
      return const OperationResult.failure(
        OperationOutcome.ioFailure,
        'The original input is unavailable or changed. Its recovery record was retained.',
      );
    } finally {
      if (source?.path != null)
        await (_fileService as PickedSourceOwner).releasePickedSource(
          source!.path!,
        );
    }
  }

  Future<void> discardInterruptedSource(Map<String, dynamic> record) async {
    final recovery = record['recovery'];
    if (_fileService is InterruptedStagingOwner &&
        recovery is Map &&
        recovery['staging'] is String &&
        recovery['attachment'] is String) {
      await (_fileService as InterruptedStagingOwner).discardInterruptedStaging(
        recovery['staging'] as String,
        recovery['attachment'] as String,
      );
    }
    if (_fileService is PickedSourceRecovery &&
        recovery is Map &&
        recovery['input'] is Map) {
      await (_fileService as PickedSourceRecovery).forgetPickedSource(
        Map<String, Object?>.from(recovery['input'] as Map),
      );
    }
  }

  Future<void> pickAttachment() async {
    if (_dropBatchActive) return;
    if (_usesOwnedMutations) {
      return _libraryTask(_pickOwnedAttachment, null);
    }
    if (!ensureExtendedNoteOperations()) return;
    return _libraryTask(_pickAttachment, null);
  }

  Future<T> _libraryTask<T>(Future<T> Function() action, T rejected) async {
    if (_disposed || _librarySwitching || _deleting) return rejected;
    _librarySensitiveJobs++;
    try {
      return await action();
    } finally {
      _librarySensitiveJobs--;
    }
  }

  Future<void> _pickOwnedAttachment() async {
    if (_disposed || !_session.canWrite || _isLocked) return;
    final owner = _session.generation;
    if (!_session.isPersisted) {
      final decision = await _askDraftDecision(
        const DraftDecisionRequest(
          DraftDecisionKind.firstAttachment,
          DraftTransition.navigation,
        ),
      );
      if (decision != DraftDecision.save || owner != _session.generation) {
        return;
      }
      if (!(await saveNote(allowEmptyFirstSave: true)).isSuccess) return;
    }
    final selection = await _fileService.pickFile();
    if (selection == null) return;
    if (_disposed || owner != _session.generation) {
      if (_fileService is PickedSourceOwner) {
        for (final source in selection.files) {
          if (source.path != null)
            await (_fileService as PickedSourceOwner).releasePickedSource(
              source.path!,
            );
        }
      }
      return;
    }
    final selected = selection.files.single;
    final path = selected.path;
    if (path == null) return;
    // Allow another selection immediately while admitted files prepare.
    unawaited(
      addOwnedAttachment(path, selected.name).then(_reportResult).whenComplete(
        () async {
          if (_fileService is PickedSourceOwner)
            await (_fileService as PickedSourceOwner).releasePickedSource(path);
        },
      ),
    );
  }

  AttachmentJobState _newAttachmentJob(
    String id,
    String fileName, {
    bool batch = false,
    String? originalAttachmentId,
    List<String> attachmentIds = const [],
    bool captureRecoveryOwner = true,
    AttachmentJobOperation operation = AttachmentJobOperation.add,
  }) {
    final job = AttachmentJobState(
      AttachmentJobSnapshot(
        id: id,
        owner: _session.generation,
        fileName: fileName,
        phase: AttachmentJobPhase.queued,
        batch: batch,
        originalAttachmentId: originalAttachmentId,
        attachmentIds: List.unmodifiable(attachmentIds),
        operation: batch && operation == AttachmentJobOperation.add
            ? AttachmentJobOperation.protection
            : operation,
      ),
    );
    if (captureRecoveryOwner && _noteReference != null) {
      final reference = _noteReference!;
      _jobRecovery[id] = {
        'version': 1,
        'target': reference.fileName,
        'library': reference.binding.root,
        'fileName': fileName,
      };
    }
    _ownedJobStates.add(job);
    attachmentJobsNotifier.value = [...attachmentJobsNotifier.value, job];
    _retireTerminalOpenJobs();
    return job;
  }

  void _jobPhase(
    AttachmentJobState job,
    AttachmentJobPhase phase, {
    int bytes = 0,
    int? total,
    String? error,
    String? detail,
    String? originalAttachmentId,
    FileOperationProgress? fileProgress,
  }) {
    if (_disposed || !_ownedJobStates.contains(job)) return;
    final previous = job.progress.value;
    if (!previous.active) return;
    if ((previous.phase == AttachmentJobPhase.cancelling ||
            previous.phase == AttachmentJobPhase.finalizing) &&
        previous.phase != phase &&
        ![
          AttachmentJobPhase.completed,
          AttachmentJobPhase.cancelled,
          AttachmentJobPhase.failed,
        ].contains(phase)) {
      return;
    }
    job.update(
      AttachmentJobSnapshot(
        id: previous.id,
        owner: previous.owner,
        fileName: previous.fileName,
        phase: phase,
        bytes: bytes,
        total: total,
        error: error,
        detail: detail,
        batch: previous.batch,
        originalAttachmentId:
            originalAttachmentId ?? previous.originalAttachmentId,
        attachmentIds: previous.attachmentIds,
        operation: previous.operation,
        fileProgress: fileProgress,
      ),
    );
    if (!job.progress.value.active && previous.active) {
      attachmentJobsNotifier.value = List.of(attachmentJobsNotifier.value);
    }
  }

  Future<void> cancelAttachmentJob(String id) async {
    final jobs = attachmentJobsNotifier.value.where(
      (j) => j.progress.value.id == id,
    );
    if (jobs.isEmpty) return;
    final job = jobs.first;
    final group = job.progress.value.batch
        ? attachmentJobsNotifier.value
              .where(
                (j) =>
                    j.progress.value.batch &&
                    j.progress.value.owner == job.progress.value.owner,
              )
              .toList()
        : [job];
    if (group.any(
      (j) => j.progress.value.phase == AttachmentJobPhase.finalizing,
    )) {
      return;
    }
    final cancelling = group.where(_latchCancellation).toList();
    await Future.wait(cancelling.map(_signalCancellation));
  }

  bool _latchCancellation(AttachmentJobState job) {
    final state = job.progress.value;
    if (!state.cancellable || !_ownedJobStates.contains(job)) return false;
    _cancelledAttachmentJobs.add(state.id);
    _jobPhase(
      job,
      AttachmentJobPhase.cancelling,
      bytes: state.bytes,
      total: state.total,
    );
    return true;
  }

  bool _tryBeginFinalization(Iterable<AttachmentJobState> jobs) {
    final group = jobs.toList();
    if (_disposed ||
        group.any(
          (job) =>
              job.progress.value.owner != _session.generation ||
              !job.progress.value.cancellable ||
              _cancelledAttachmentJobs.contains(job.progress.value.id),
        )) {
      return false;
    }
    for (final job in group) {
      _jobPhase(job, AttachmentJobPhase.finalizing);
    }
    return true;
  }

  Future<void> _signalCancellation(AttachmentJobState job) async {
    final state = job.progress.value;
    final id = state.id;
    _exportReadCancellations[id]?.cancel();
    if (state.operation == AttachmentJobOperation.open) {
      final reference = _noteReference;
      final attachment = state.originalAttachmentId;
      if (reference != null && attachment != null)
        await _attachmentOpenCache?.cancel(
          reference,
          attachment,
          _session.credentialGeneration,
        );
      return;
    }
    await _packageCancellationFiles[id]?.writeAsString('cancel', flush: true);
    await _attachmentTransforms[id]?.cancel();
  }

  Future<void> retryAttachmentJob(String id) async {
    final retry = _attachmentRetries[id];
    if (retry == null) return;
    final state = attachmentJobsNotifier.value
        .where((j) => j.progress.value.id == id)
        .firstOrNull
        ?.progress
        .value;
    if (_isLocked || state?.owner != _session.generation) return;
    try {
      await retry();
      removePendingAttachmentJob(id);
    } catch (_) {
      _reportResult(
        const OperationResult.failure(
          OperationOutcome.ioFailure,
          'The original input is unavailable. Select the file again; the note was retained.',
        ),
      );
    }
  }

  void removePendingAttachmentJob(String id) {
    final current = attachmentJobsNotifier.value;
    final match = current.where((job) => job.progress.value.id == id).toList();
    if (match.isEmpty || match.first.progress.value.active) return;
    attachmentJobsNotifier.value = current
        .where((job) => job.progress.value.id != id)
        .toList();
    _attachmentRetries.remove(id);
    // A card may still own the notifier until its next build.
  }

  Future<OperationResult<CipherFileResult>> _transformAttachment(
    AttachmentJobState job,
    StreamingFileSource source,
    String destination, {
    required bool decrypt,
    String? oldPassword,
    String? newPassword,
    bool? verifyWrites,
    OwnedWriteTarget? ownedTarget,
  }) async {
    final id = job.progress.value.id;
    if (_cancelledAttachmentJobs.contains(id)) {
      return const OperationResult.failure(
        OperationOutcome.cancelled,
        'Attachment preparation cancelled.',
      );
    }
    final transform = _attachmentWorker.submit(
      FileTransformRequest(
        source: source,
        destination: destination,
        decryptSource: decrypt,
        encryptDestination: true,
        sourcePassword: oldPassword,
        destinationPassword: newPassword,
        verifyOutput:
            verifyWrites ??
            _settings.attachmentPerformance.verifyLargeFileWrites,
        ownedTarget: ownedTarget ?? OwnedWriteTarget.forPath(destination),
      ),
      onStarted: () => _jobPhase(job, AttachmentJobPhase.preparing),
      onProgress: (phase, bytes, total) => _jobPhase(
        job,
        switch (phase) {
          'Decrypting' => AttachmentJobPhase.decrypting,
          'Verifying' => AttachmentJobPhase.verifying,
          _ => AttachmentJobPhase.encrypting,
        },
        bytes: bytes,
        total: total,
      ),
    );
    _attachmentTransforms[id] = transform;
    try {
      return await transform.result;
    } finally {
      _attachmentTransforms.remove(id);
    }
  }

  NoteSnapshot _generationSnapshot(
    List<AttachmentModel> attachments,
    String? password, {
    required bool changesProtection,
    Map<String, dynamic>? metadata,
  }) {
    _observeRichEdit();
    final reuseBody =
        !changesProtection &&
        _storedNote != null &&
        !_session.dirtyFields.contains(DraftField.body);
    return NoteSnapshot(
      sessionGeneration: _session.generation,
      editRevision: _session.editRevision + 1,
      credentialGeneration: _session.credentialGeneration,
      fileName: _currentFileName,
      reference: _noteReference,
      noteId: _storedNote?.id ?? _draftNoteId,
      title: titleController.text,
      body: reuseBody
          ? _storedNote!.content
          : (changesProtection &&
                    !_session.dirtyFields.contains(DraftField.body) &&
                    _retainedPlainBody != null
                ? _retainedPlainBody!
                : (_isHtmlMode
                      ? htmlController.text
                      : jsonEncode(
                          quillController.document.toDelta().toJson(),
                        ))),
      timestamp:
          _storedNote?.timestamp ?? (_draftTimestamp ??= _nowMilliseconds()),
      password: password,
      envelopeKind: _envelopeKind,
      metadata: metadata ?? _retainedMetadata,
      attachments: attachments,
      reuseStoredBody: reuseBody,
      attachmentsChanged: true,
    );
  }

  Future<OperationResult<void>> addOwnedAttachment(
    String path,
    String fileName, {
    String? expectedHash,
    int? expectedModified,
    String? recoveryAttachmentId,
  }) => _trackOwnedJob(
    _runOwnedAttachment(
      path,
      fileName,
      expectedHash: expectedHash,
      expectedModified: expectedModified,
      recoveryAttachmentId: recoveryAttachmentId,
    ),
  );

  Future<OperationResult<void>> _runOwnedAttachment(
    String path,
    String fileName, {
    String? expectedHash,
    int? expectedModified,
    String? recoveryAttachmentId,
  }) async {
    if (!_usesOwnedMutations ||
        _disposed ||
        !_session.canWrite ||
        _isLocked ||
        !_session.isPersisted ||
        _deleting ||
        _librarySwitching ||
        _libraryResourcesClosing ||
        _bulkAttachmentJob ||
        _attachmentAdds >= AttachmentScheduler.maxQueued) {
      return const OperationResult.failure(
        OperationOutcome.conflict,
        'Save the note and finish its active operation first.',
      );
    }
    if (recoveryAttachmentId != null) {
      if (attachmentJobsNotifier.value.any(
        (job) =>
            job.progress.value.id == recoveryAttachmentId &&
            job.progress.value.active,
      ))
        return const OperationResult.failure(
          OperationOutcome.conflict,
          'This attachment is already being retried.',
        );
      removePendingAttachmentJob(recoveryAttachmentId);
      _cancelledAttachmentJobs.remove(recoveryAttachmentId);
    }
    _attachmentAdds++;
    final owner = _session.generation;
    final credential = _session.credentialGeneration;
    final password = _currentPassword;
    final id = recoveryAttachmentId ?? const Uuid().v4();
    if (_attachments.any((a) => a.id == id)) {
      _attachmentAdds--;
      return const OperationResult.success();
    }
    final job = _newAttachmentJob(id, fileName);
    final completed = Completer<void>();
    _attachmentAddCompletions[id] = completed;
    final performance = _settings.attachmentPerformance;
    final reference = _noteReference!;
    final files = _fileService as TransactionalNoteFiles;
    Directory? operation;
    OperationResult<void> result;
    try {
      final sourceStat = await File(path).stat();
      if (_fileService is AttachmentStagingCapacity)
        await (_fileService as AttachmentStagingCapacity).checkStagingCapacity(
          sourceStat.size,
        );
      final source = StreamingFileSource(
        path,
        sourceStat.size,
        sha256Hex: expectedHash,
        modifiedMicros: expectedModified,
      );
      _jobRecovery[id] = {
        'version': 1,
        'fileName': fileName,
        'state': 'retryFromSource',
        'target': reference.fileName,
        'library': reference.binding.root,
        'attachment': id,
        'length': sourceStat.size,
        'modified': sourceStat.modified.microsecondsSinceEpoch,
        'passwordRequired': password != null,
        if (_fileService is PickedSourceRecovery)
          'input': (_fileService as PickedSourceRecovery).pickedSourceIdentity(
            path,
          ),
      };
      if (_cancelledAttachmentJobs.contains(id) ||
          owner != _session.generation) {
        throw const FileJobCancelled();
      }
      operation = await files.createOperationDirectory(reference);
      _jobRecovery[id]!['staging'] = p.basename(operation.path);
      final target = files is AttachmentCandidateOwner
          ? await (files as AttachmentCandidateOwner).createAttachmentCandidate(
              reference,
              id,
              operation,
              source.length + 32,
            )
          : OwnedWriteTarget.forPath(p.join(operation.path, '$id.med'));
      final staged = target.path;
      final transformed = await _transformAttachment(
        job,
        source,
        staged,
        decrypt: false,
        ownedTarget: target,
        verifyWrites: performance.verifyLargeFileWrites,
        newPassword: password,
      );
      if (!transformed.isSuccess) {
        result = OperationResult.failure(
          transformed.outcome,
          transformed.message,
        );
      } else {
        _jobRecovery[id]!['plaintextHash'] = transformed.value!.plaintextHash;
        result = await _mutate(() async {
          if (_disposed ||
              owner != _session.generation ||
              credential != _session.credentialGeneration ||
              _isLocked ||
              _noteReference == null ||
              !p.equals(reference.contentPath, _noteReference!.contentPath) ||
              _cancelledAttachmentJobs.contains(id)) {
            return _cancelledResult();
          }
          if (!_tryBeginFinalization([job])) return _cancelledResult();
          final attachment = AttachmentModel(
            id: id,
            fileName: fileName,
            size: source.length,
            mimeType: 'application/octet-stream',
          );
          return _saveSnapshot(
            _generationSnapshot(
              [..._attachments, attachment],
              password,
              changesProtection: false,
            ),
            true,
            generationChange: true,
            onProgress: (phase, bytes, total) => _jobPhase(
              job,
              AttachmentJobPhase.finalizing,
              detail: phase,
              bytes: bytes,
              total: total,
            ),
            prepared: [
              PreparedAttachmentFile(
                id,
                StreamingFileSource(
                  staged,
                  transformed.value!.length,
                  receipt: transformed.value!.receipt,
                ),
              ),
            ],
          );
        });
      }
    } on FileJobCancelled {
      result = _cancelledResult();
    } catch (_) {
      result = const OperationResult.failure(
        OperationOutcome.ioFailure,
        'Attachment preparation failed; the note was retained.',
      );
    } finally {
      if (operation != null) {
        try {
          await files.removeOperationDirectory(operation);
        } catch (_) {
          /* Retain operation sources for manual cleanup. */
        }
      }
      _attachmentAdds--;
    }
    _jobPhase(
      job,
      result.isSuccess
          ? AttachmentJobPhase.completed
          : result.outcome == OperationOutcome.cancelled
          ? AttachmentJobPhase.cancelled
          : AttachmentJobPhase.failed,
      error: result.message,
    );
    if (!result.isSuccess && result.outcome != OperationOutcome.cancelled) {
      _attachmentRetries[id] = () async {
        final recovery = _jobRecovery[id];
        final input = recovery?['input'];
        if (_fileService is PickedSourceRecovery && input is Map) {
          final source = await (_fileService as PickedSourceRecovery)
              .reopenPickedSource(Map<String, Object?>.from(input));
          try {
            if (source.size != recovery!['length'])
              throw const FormatException('Input length changed.');
            _reportResult(
              await addOwnedAttachment(
                source.path!,
                fileName,
                expectedHash: recovery['plaintextHash'] as String?,
                expectedModified: recovery['modified'] as int?,
              ),
            );
          } finally {
            await (_fileService as PickedSourceOwner).releasePickedSource(
              source.path!,
            );
          }
        } else {
          _reportResult(await addOwnedAttachment(path, fileName));
        }
      };
    }
    if ((result.isSuccess || result.outcome == OperationOutcome.cancelled) &&
        _fileService is PickedSourceRecovery &&
        _jobRecovery[id]?['input'] is Map) {
      try {
        await (_fileService as PickedSourceRecovery).forgetPickedSource(
          Map<String, Object?>.from(_jobRecovery[id]!['input'] as Map),
        );
      } catch (_) {
        /* A retained read grant can be revoked later. */
      }
    }
    _attachmentAddCompletions.remove(id);
    completed.complete();
    return result;
  }

  Future<OperationResult<void>> _changeOwnedProtection(
    String? password, {
    String? verifiedOldPassword,
  }) => _trackOwnedJob(
    _runOwnedProtection(password, verifiedOldPassword: verifiedOldPassword),
  );

  Future<OperationResult<void>> _runOwnedProtection(
    String? password, {
    String? verifiedOldPassword,
  }) async {
    if (_disposed ||
        !_session.canWrite ||
        _isLocked ||
        _bulkAttachmentJob ||
        _deleting ||
        hasAttachmentJobs) {
      return const OperationResult.failure(
        OperationOutcome.conflict,
        'Finish the active note operation first.',
      );
    }
    if (verifiedOldPassword != null && !verifyPassword(verifiedOldPassword)) {
      return const OperationResult.failure(
        OperationOutcome.rejectedInput,
        'Incorrect current password.',
      );
    }
    if (!_session.isPersisted) {
      // A never-saved draft still requires explicit Save; no files exist yet.
      _currentPassword = password;
      _recordEdit(DraftField.protection);
      notifyListeners();
      return const OperationResult.success();
    }
    final performance = _settings.attachmentPerformance;
    _bulkAttachmentJob = true;
    final generation = _session.generation;
    final credential = _session.credentialGeneration;
    final previousPassword = _currentPassword;
    final original = List<AttachmentModel>.of(_attachments);
    final reference = _noteReference!;
    final files = _fileService as TransactionalNoteFiles;
    final prepared = <PreparedAttachmentFile>[];
    final replacement = <AttachmentModel>[];
    final jobs = <AttachmentJobState>[
      _newAttachmentJob(const Uuid().v4(), 'Note protection', batch: true),
      for (final attachment in original)
        _newAttachmentJob(
          const Uuid().v4(),
          attachment.fileName,
          batch: true,
          originalAttachmentId: attachment.id,
        ),
    ];
    Directory? operation;
    OperationResult<void> result = const OperationResult.success();
    try {
      operation = await files.createOperationDirectory(reference);
      _jobPhase(jobs.first, AttachmentJobPhase.preparing);
      for (
        var attachmentIndex = 0;
        attachmentIndex < original.length;
        attachmentIndex++
      ) {
        final attachment = original[attachmentIndex];
        if (jobs.any(
          (job) => _cancelledAttachmentJobs.contains(job.progress.value.id),
        )) {
          result = _cancelledResult();
          break;
        }
        final job = jobs[attachmentIndex + 1];
        final id = job.progress.value.id;
        _jobPhase(job, AttachmentJobPhase.preparing);
        final source = await files.attachmentSource(
          _noteReference ?? reference,
          attachment.id,
          verifyContent: performance.checkBeforeOpen,
        );
        var target = files is AttachmentCandidateOwner
            ? await (files as AttachmentCandidateOwner)
                  .createAttachmentCandidate(
                    reference,
                    id,
                    operation,
                    source.length + 32,
                  )
            : OwnedWriteTarget.forPath(p.join(operation.path, '$id.med'));
        var staged = target.path;
        var transform = await _transformAttachment(
          job,
          source,
          staged,
          decrypt: true,
          ownedTarget: target,
          verifyWrites: performance.verifyLargeFileWrites,
          oldPassword: previousPassword,
          newPassword: password,
        );
        if (!transform.isSuccess &&
            transform.outcome == OperationOutcome.rejectedInput &&
            previousPassword != null) {
          // Legacy mixed-key attachments can use the app key. A retry owns a
          // fresh output; valid padding alone is never called authentication.
          target = files is AttachmentCandidateOwner
              ? await (files as AttachmentCandidateOwner)
                    .createAttachmentCandidate(
                      reference,
                      id,
                      operation,
                      source.length + 32,
                    )
              : OwnedWriteTarget.forPath(
                  p.join(operation.path, '$id.fallback.med'),
                );
          staged = target.path;
          transform = await _transformAttachment(
            job,
            source,
            staged,
            decrypt: true,
            ownedTarget: target,
            verifyWrites: performance.verifyLargeFileWrites,
            newPassword: password,
          );
        }
        if (!transform.isSuccess) {
          result = OperationResult.failure(
            transform.outcome,
            transform.message,
          );
          break;
        }
        prepared.add(
          PreparedAttachmentFile(
            id,
            StreamingFileSource(
              staged,
              transform.value!.length,
              receipt: transform.value!.receipt,
            ),
          ),
        );
        replacement.add(
          AttachmentModel(
            id: id,
            fileName: attachment.fileName,
            size: attachment.size,
            mimeType: attachment.mimeType,
            mentionId: attachment.mentionId,
          ),
        );
      }
      if (result.isSuccess) {
        result = await _mutate(() async {
          if (_disposed ||
              generation != _session.generation ||
              credential != _session.credentialGeneration ||
              jobs.any(
                (job) =>
                    _cancelledAttachmentJobs.contains(job.progress.value.id),
              )) {
            return _cancelledResult();
          }
          if (!_tryBeginFinalization(jobs)) return _cancelledResult();
          for (var i = 0; i < replacement.length; i++) {
            final latest = _attachments.where((a) => a.id == original[i].id);
            if (latest.length == 1 &&
                latest.single.mentionId != replacement[i].mentionId) {
              final a = replacement[i];
              replacement[i] = AttachmentModel(
                id: a.id,
                fileName: a.fileName,
                size: a.size,
                mimeType: a.mimeType,
                mentionId: latest.single.mentionId,
              );
            }
          }
          final metadata = <String, dynamic>{..._retainedMetadata};
          final oldFields = metadata['attachments'];
          if (oldFields is List &&
              oldFields.isNotEmpty &&
              oldFields.first is String &&
              !replacement.any((a) => a.mentionId != null)) {
            metadata['attachments'] = replacement.map((a) => a.id).toList();
          } else {
            final byId = <String, Map<String, dynamic>>{};
            if (oldFields is List) {
              for (final fields in oldFields) {
                if (fields is Map<String, dynamic> && fields['id'] is String) {
                  byId[fields['id'] as String] = fields;
                }
              }
            }
            metadata['attachments'] = [
              for (var i = 0; i < replacement.length; i++)
                {...?byId[original[i].id], ...replacement[i].toJson()},
            ];
          }
          return _saveSnapshot(
            _generationSnapshot(
              replacement,
              password,
              changesProtection: true,
              metadata: metadata,
            ),
            true,
            generationChange: true,
            changesProtection: true,
            prepared: prepared,
          );
        });
      }
    } catch (_) {
      result = const OperationResult.failure(
        OperationOutcome.ioFailure,
        'Protection change failed; the old credentials and attachments were retained.',
      );
    } finally {
      if (operation != null) {
        try {
          await files.removeOperationDirectory(operation);
        } catch (_) {
          /* Retain operation sources for manual cleanup. */
        }
      }
      _bulkAttachmentJob = false;
    }
    for (final job in jobs) {
      _jobPhase(
        job,
        result.isSuccess
            ? AttachmentJobPhase.completed
            : result.outcome == OperationOutcome.cancelled
            ? AttachmentJobPhase.cancelled
            : AttachmentJobPhase.failed,
        error: result.message,
      );
    }
    return _reportResult(result);
  }

  Future<void> _pickAttachment() async {
    if (_disposed || !_session.canWrite || _isLocked) return;
    final owner = _session.generation;
    if (!_session.isPersisted) {
      if (_onDraftDecision == null) {
        _reportResult(
          const OperationResult.failure(
            OperationOutcome.rejectedInput,
            'Save this new note before adding an attachment.',
          ),
        );
        return;
      }
      final decision = await _askDraftDecision(
        const DraftDecisionRequest(
          DraftDecisionKind.firstAttachment,
          DraftTransition.navigation,
        ),
      );
      if (_disposed || owner != _session.generation) return;
      if (decision != DraftDecision.save) return;
      final saved = await saveNote();
      if (!saved.isSuccess || _disposed || owner != _session.generation) return;
    }
    final result = await _fileService.pickFile(allowedExtensions: null);
    if (_disposed || owner != _session.generation || _isLocked) return;

    if (result != null && result.files.single.path != null) {
      // Don't block UI with setBusy

      final path = result.files.single.path!;
      final originalFile = File(path);
      final fileName = result.files.single.name;
      final tempId = const Uuid().v4();
      final ext = fileName.split('.').last.toLowerCase();

      // 1. Add Placeholder
      final placeholder = AttachmentModel(
        id: tempId,
        fileName: fileName,
        size: 0,
        mimeType: 'application/octet-stream', // Unknown pending
        isLoading: true,
      );
      _attachments.add(placeholder);
      attachmentsNotifier.value = List.from(_attachments);
      // notifyListeners(); // Removed to reduce rebuilds

      // Prepare Note ID
      String noteId;
      if (_currentFileName != null) {
        if (_currentFileName!.startsWith('note_')) {
          noteId = _currentFileName!.replaceFirst('note_', '');
        } else {
          noteId = const Uuid().v4();
          _currentFileName = "note_$noteId";
        }
      } else {
        noteId = const Uuid().v4();
        _currentFileName = "note_$noteId";
      }

      try {
        // 2. Check Size
        int size = await originalFile.length();
        if (size > 10 * 1024 * 1024 * 1024) {
          _attachments.removeWhere((a) => a.id == tempId);
          attachmentsNotifier.value = List.from(_attachments);
          // notifyListeners();
          print("File too large > 10GB");
          return;
        }

        // 3. Compress
        Uint8List bytes;
        final settings = _settings;
        final isImage = ['jpg', 'jpeg', 'png', 'webp', 'heic'].contains(ext);

        if (isImage && settings.compressionLevel != CompressionLevel.none) {
          int quality = 85;
          int minWidth = 1920;
          int minHeight = 1080;
          if (settings.compressionLevel == CompressionLevel.high) {
            quality = 50;
            minWidth = 1024;
            minHeight = 768;
          } else if (settings.compressionLevel == CompressionLevel.medium) {
            quality = 70;
            minWidth = 1280;
            minHeight = 720;
          }
          final compressed = await FlutterImageCompress.compressWithFile(
            path,
            quality: quality,
            minWidth: minWidth,
            minHeight: minHeight,
          );
          if (compressed != null) {
            bytes = compressed;
            size = bytes.length;
          } else {
            bytes = await originalFile.readAsBytes();
          }
        } else {
          bytes = await originalFile.readAsBytes();
        }

        // 4. Encrypt (Background via Service)
        final encryptedBytes = await _encryptionService.encryptBinary(
          bytes,
          password: _currentPassword,
        );

        // 5. Save
        final attachmentId = await _fileService.saveAttachment(
          encryptedBytes,
          noteId,
        );

        // 6. Update List (Replace placeholder)
        final index = _attachments.indexWhere((a) => a.id == tempId);
        if (index != -1) {
          _attachments[index] = AttachmentModel(
            id: attachmentId,
            fileName: fileName,
            size: size,
            mimeType: isImage ? 'image/$ext' : 'application/octet-stream',
            isLoading: false,
          );
          attachmentsNotifier.value = List.from(_attachments);
          // notifyListeners();
        }

        _recordEdit(DraftField.attachments);
      } catch (e) {
        print("Error adding attachment: $e");
        // Remove placeholder on error
        _attachments.removeWhere((a) => a.id == tempId);
        attachmentsNotifier.value = List.from(_attachments);
        // notifyListeners();
      }
    }
  }

  Future<void> exportAttachment(AttachmentModel attachment) async {
    if (_usesOwnedMutations) {
      _reportResult(await _trackOwnedJob(_exportOwnedAttachment(attachment)));
      return;
    }
    if (!ensureExtendedNoteOperations()) return;
    return _libraryTask(() => _exportAttachment(attachment), null);
  }

  Future<OperationResult<void>> exportAttachments(
    Iterable<String> ids, {
    required AttachmentBatchExport output,
  }) => _trackOwnedJob(_exportOwnedAttachments(ids.toSet(), output));

  Future<OperationResult<void>> _exportOwnedAttachments(
    Set<String> ids,
    AttachmentBatchExport output,
  ) async {
    if (!_usesOwnedMutations || ids.isEmpty) return _cancelledResult();
    final ready = await _resolveOwnerJobs(DraftTransition.navigation);
    if (!ready.isSuccess) return ready;
    if (_disposed ||
        _isLocked ||
        _noteReference == null ||
        _deleting ||
        _bulkAttachmentJob ||
        !ids.every((id) => _attachments.any((a) => a.id == id)))
      return _cancelledResult();
    final owner = _session.generation;
    final credentials = _session.credentialGeneration;
    final path = currentContentPath;
    final performance = _settings.attachmentPerformance;
    final selected = _attachments.where((a) => ids.contains(a.id)).toList();
    _bulkAttachmentJob = true;
    final job = _newAttachmentJob(
      const Uuid().v4(),
      '${selected.length} attachments',
      batch: true,
      attachmentIds: selected.map((a) => a.id).toList(),
      operation: AttachmentJobOperation.export,
    );
    final allocated = <String>[];
    OperationResult<void> result = _cancelledResult();
    bool current() =>
        !_disposed &&
        !_isLocked &&
        owner == _session.generation &&
        credentials == _session.credentialGeneration &&
        path == currentContentPath &&
        !_cancelledAttachmentJobs.contains(job.progress.value.id);
    try {
      result = const OperationResult.success();
      for (var i = 0; i < selected.length; i++) {
        if (!current()) {
          result = _cancelledResult();
          break;
        }
        result = await _exportOwnedAttachment(
          selected[i],
          batchJob: job,
          policy: performance,
          batchOutput: output,
          allocated: allocated,
          batchDetail:
              'File ${i + 1} of ${selected.length} · ${selected[i].fileName}',
        );
        if (!result.isSuccess) break;
      }
      if (result.isSuccess) {
        if (!current() || !_tryBeginFinalization([job])) {
          result = _cancelledResult();
        } else {
          final accepted = await output.publish(List.unmodifiable(allocated));
          result = accepted
              ? const OperationResult.success()
              : _cancelledResult();
        }
      }
    } catch (_) {
      result = const OperationResult.failure(
        OperationOutcome.ioFailure,
        'Selected attachments could not be exported. The originals were retained.',
      );
    } finally {
      try {
        await output.cleanup(allocated);
      } catch (_) {
        result = const OperationResult.failure(
          OperationOutcome.ioFailure,
          'Export temporary-file cleanup needs retry. The originals were retained.',
        );
      }
      _bulkAttachmentJob = false;
      _exportReadCancellations.remove(job.progress.value.id);
    }
    _jobPhase(
      job,
      result.isSuccess
          ? AttachmentJobPhase.completed
          : result.outcome == OperationOutcome.cancelled
          ? AttachmentJobPhase.cancelled
          : AttachmentJobPhase.failed,
      error: result.message,
    );
    return _reportResult(result);
  }

  Future<OperationResult<void>> _exportOwnedAttachment(
    AttachmentModel attachment, {
    AttachmentJobState? batchJob,
    AttachmentBatchExport? batchOutput,
    List<String>? allocated,
    String? batchDetail,
    AttachmentPerformance? policy,
  }) async {
    if (batchJob == null) {
      final ready = await _resolveOwnerJobs(DraftTransition.navigation);
      if (!ready.isSuccess) return ready;
    }
    if ((batchJob == null && _bulkAttachmentJob) ||
        _disposed ||
        _isLocked ||
        _noteReference == null ||
        _deleting) {
      return _cancelledResult();
    }
    if (batchJob == null) _bulkAttachmentJob = true;
    final job =
        batchJob ??
        _newAttachmentJob(
          const Uuid().v4(),
          attachment.fileName,
          originalAttachmentId: attachment.id,
          operation: AttachmentJobOperation.export,
        );
    _jobPhase(
      job,
      AttachmentJobPhase.queued,
      originalAttachmentId: attachment.id,
      detail: batchDetail,
    );
    final files = _fileService as TransactionalNoteFiles;
    final readCancellation = _exportReadCancellations.putIfAbsent(
      job.progress.value.id,
      FileReadCancellation.new,
    );
    final mobile = mobileAttachmentExportPolicy;
    final performance = policy ?? _settings.attachmentPerformance;
    final checks = performance.exportChecks(mobile: mobile);
    String? candidate;
    OperationResult<void> result;
    try {
      final source = await files.attachmentSource(
        _noteReference!,
        attachment.id,
        cancellation: readCancellation,
        verifyContent: checks.checkSource,
        onProgress: (phase, bytes, total) => _jobPhase(
          job,
          AttachmentJobPhase.preparing,
          bytes: bytes,
          total: total,
          detail: batchDetail,
        ),
      );
      final destination = batchOutput != null
          ? await batchOutput.destination(attachment.fileName)
          : Platform.isAndroid || Platform.isIOS
          ? await MobileExport.destination(attachment.fileName)
          : await FilePicker.platform.saveFile(
              dialogTitle: 'Save Attachment',
              fileName: attachment.fileName,
            );
      if (destination == null) {
        result = const OperationResult.failure(
          OperationOutcome.cancelled,
          'Export cancelled.',
        );
      } else {
        allocated?.add(destination);
        await _verifyExportDestination(destination);
        final expected = await ExternalFileExport.reviewOwned(
          destination,
          verifyReadback: performance.verifyLargeFileWrites,
        );
        candidate = ExternalFileExport.candidatePath(destination);
        final id = job.progress.value.id;
        if (_cancelledAttachmentJobs.contains(id) ||
            readCancellation.cancelled ||
            _disposed ||
            _isLocked)
          throw const FileJobCancelled();
        final transform = _attachmentWorker.submit(
          FileTransformRequest(
            source: source,
            destination: candidate,
            decryptSource: true,
            encryptDestination: false,
            sourcePassword: _currentPassword,
            verifyOutput: checks.verifyOutput,
            ownedTarget: OwnedWriteTarget.forPath(candidate),
            requireWholeSource: mobile,
            expectedPlaintextBytes: mobile && attachment.size > 0
                ? attachment.size
                : null,
          ),
          onProgress: (phase, bytes, total) => _jobPhase(
            job,
            phase == 'Verifying'
                ? AttachmentJobPhase.verifying
                : AttachmentJobPhase.decrypting,
            bytes: bytes,
            total: total,
            detail: batchDetail,
          ),
        );
        _attachmentTransforms[id] = transform;
        var transformed = await transform.result;
        _attachmentTransforms.remove(id);
        if (!transformed.isSuccess &&
            transformed.outcome == OperationOutcome.rejectedInput &&
            _currentPassword != null &&
            !_cancelledAttachmentJobs.contains(id)) {
          candidate = ExternalFileExport.candidatePath(destination);
          final fallback = _attachmentWorker.submit(
            FileTransformRequest(
              source: source,
              destination: candidate,
              decryptSource: true,
              encryptDestination: false,
              verifyOutput: checks.verifyOutput,
              ownedTarget: OwnedWriteTarget.forPath(candidate),
              requireWholeSource: mobile,
              expectedPlaintextBytes: mobile && attachment.size > 0
                  ? attachment.size
                  : null,
            ),
            onProgress: (phase, bytes, total) => _jobPhase(
              job,
              phase == 'Verifying'
                  ? AttachmentJobPhase.verifying
                  : AttachmentJobPhase.decrypting,
              bytes: bytes,
              total: total,
              detail: batchDetail,
            ),
          );
          _attachmentTransforms[id] = fallback;
          transformed = await fallback.result;
          _attachmentTransforms.remove(id);
        }
        if (!transformed.isSuccess) {
          result = OperationResult.failure(
            transformed.outcome,
            transformed.message,
          );
        } else if (_cancelledAttachmentJobs.contains(id)) {
          result = _cancelledResult();
        } else if (batchJob == null && !_tryBeginFinalization([job])) {
          result = _cancelledResult();
        } else {
          result = await ExternalFileExport.publishOwned(
            receipt: transformed.value!.receipt!,
            destination: destination,
            expected: expected,
          );
          if (batchJob == null &&
              result.isSuccess &&
              (Platform.isAndroid || Platform.isIOS))
            await MobileExport.share(destination);
        }
      }
    } on FileJobCancelled {
      result = _cancelledResult();
    } catch (_) {
      result =
          readCancellation.cancelled ||
              _cancelledAttachmentJobs.contains(job.progress.value.id)
          ? _cancelledResult()
          : const OperationResult.failure(
              OperationOutcome.ioFailure,
              'Attachment export failed; the source was retained.',
            );
    } finally {
      if (candidate != null && await File(candidate).exists()) {
        try {
          await File(candidate).delete();
        } catch (_) {
          /* Retain owned export candidate. */
        }
      }
      if (batchJob == null) {
        _bulkAttachmentJob = false;
        _exportReadCancellations.remove(job.progress.value.id);
      }
    }
    if (batchJob == null)
      _jobPhase(
        job,
        result.isSuccess
            ? AttachmentJobPhase.completed
            : result.outcome == OperationOutcome.cancelled
            ? AttachmentJobPhase.cancelled
            : AttachmentJobPhase.failed,
        error: result.message,
      );
    return result;
  }

  Future<void> _exportAttachment(AttachmentModel attachment) async {
    // 1. Pick location first
    final String? outputFile = await FilePicker.platform.saveFile(
      dialogTitle: 'Save Attachment',
      fileName: attachment.fileName,
      lockParentWindow: true,
    );

    if (outputFile == null) return;

    // 2. Process and Save
    setBusy(true);
    try {
      final data = await readAttachment(attachment.id);
      if (data != null) {
        final file = File(outputFile);
        await file.writeAsBytes(data);
      }
    } catch (e) {
      print("Error saving attachment: $e");
    } finally {
      setBusy(false);
    }
  }

  Future<void> _verifyExportDestination(String destination) async {
    if (!p.isAbsolute(destination) || p.split(destination).contains('..')) {
      throw const FormatException(
        'An absolute export destination is required.',
      );
    }
    final settings = await _settings.getSettingsFilePath();
    if (p.equals(settings, destination))
      throw const FormatException(
        'Export cannot replace application settings.',
      );
    final roots = <String>{
      await _fileService.getUserDataPath(),
      p.dirname(settings),
      if (_settings.storageEnvironment.dataRoot != null)
        _settings.storageEnvironment.dataRoot!,
      if (_noteReference != null) _noteReference!.binding.root,
    };
    for (final root in roots) {
      if (!p.isWithin(root, destination)) continue;
      final relative = p.split(p.relative(destination, from: root));
      if (relative.any((part) => part.startsWith('.future-notes-')) ||
          (relative.first.startsWith('note_') && relative.length > 1) ||
          (relative.length == 1 &&
              p.extension(destination).toLowerCase() == '.enc')) {
        throw const FormatException(
          'Choose an export destination outside managed note objects.',
        );
      }
    }
  }

  Future<OperationResult<void>> removeAttachment(String attachmentId) {
    return removeAttachments([attachmentId]);
  }

  Future<OperationResult<void>> removeAttachments(
    Iterable<String> attachmentIds,
  ) {
    final ids = attachmentIds.toSet();
    if (ids.isEmpty) return Future.value(_cancelledResult());
    if (_usesOwnedMutations) {
      if (_disposed ||
          !_session.canWrite ||
          _isLocked ||
          hasAttachmentJobs ||
          _deleting) {
        return Future.value(_cancelledResult());
      }
      final generation = _session.generation;
      return _libraryTask(
        () => _mutate(() async {
          if (_disposed ||
              generation != _session.generation ||
              !_session.canWrite ||
              _isLocked ||
              hasAttachmentJobs ||
              _deleting ||
              !ids.every((id) => _attachments.any((a) => a.id == id)))
            return _cancelledResult();
          final result = await _saveSnapshot(
            _generationSnapshot(
              _attachments.where((a) => !ids.contains(a.id)).toList(),
              _currentPassword,
              changesProtection: false,
            ),
            true,
            generationChange: true,
          );
          return _reportResult(result);
        }),
        _cancelledResult(),
      );
    }
    if (!ensureExtendedNoteOperations() ||
        _librarySwitching ||
        _disposed ||
        !_session.canWrite ||
        _isLocked ||
        !ids.every((id) => _attachments.any((a) => a.id == id)))
      return Future.value(_cancelledResult());
    _attachments.removeWhere((a) => ids.contains(a.id));
    attachmentsNotifier.value = List.from(_attachments);
    for (final id in ids) {
      _attachmentCache.remove(id);
    }
    // notifyListeners();
    _recordEdit(DraftField.attachments);
    return Future.value(const OperationResult.success());
  }

  // region Initialization
  ContentViewModel({
    required IFileService fileService,
    required IEncryptionService encryptionService,
    SettingsService? settings,
    bool startBackgroundServices = true,
    int Function()? nowMilliseconds,
    DraftDecisionHandler? onDraftDecision,
    LibraryDiscovery? backgroundService,
    RecentFileFilter? filterRecentFiles,
    Future<List<dynamic>> Function(String)? htmlToDelta,
    Future<String> Function(List<dynamic>)? deltaToHtml,
    AttachmentOpenCache? attachmentOpenCache,
    DesktopActions? desktopActions,
  }) : _fileService = fileService,
       _encryptionService = encryptionService,
       _settings = settings ?? SettingsService(),
       _nowMilliseconds = nowMilliseconds ?? _systemMilliseconds,
       _onDraftDecision = onDraftDecision,
       _filterRecentFiles = filterRecentFiles ?? _defaultFilterRecentFiles,
       _htmlToDelta =
           htmlToDelta ?? ((html) => compute(_htmlToDeltaTask, html)),
       _deltaToHtml =
           deltaToHtml ?? ((delta) => compute(_deltaToHtmlTask, delta)),
       _attachmentOpenCache = attachmentOpenCache,
       _desktopActions = desktopActions,
       _backgroundService = startBackgroundServices
           ? backgroundService ??
                 BackgroundService(
                   environment:
                       (settings ?? SettingsService()).storageEnvironment,
                 )
           : null {
    // Initialize CodeController with syntax highlighting
    htmlController = CodeController(
      language: xml, // Highlighting for XML/HTML
    );

    // Ensure settings are loaded before loading files
    _bindDocument();
    htmlController.addListener(_onHtmlChanged);
    titleController.addListener(_onTitleChanged);
    _settings.attachmentPerformanceNotifier.addListener(
      _configureAttachmentPerformance,
    );
    _configureAttachmentPerformance();
    if (startBackgroundServices) _initAsync();
  }

  static int _systemMilliseconds() => DateTime.now().millisecondsSinceEpoch;

  void _configureAttachmentPerformance() =>
      AttachmentScheduler.shared.configure(_settings.attachmentPerformance);

  void _bindDocument() {
    _documentSubscription?.cancel();
    final document = quillController.document;
    _observedRichDelta = document.toDelta();
    _documentSubscription = document.changes.listen((_) {
      if (!_disposed &&
          !_publishing &&
          !_isHtmlMode &&
          identical(document, quillController.document)) {
        _observeRichEdit();
      }
    });
  }

  void _replaceDocument(Document document) {
    _documentSubscription?.cancel();
    final previous = quillController.document;
    quillController.document = document;
    _bindDocument();
    if (!identical(previous, document)) previous.close();
  }

  void _observeRichEdit() {
    if (_disposed || _publishing || _isHtmlMode) return;
    final delta = quillController.document.toDelta();
    if (delta == _observedRichDelta) return;
    _observedRichDelta = delta;
    _recordEdit(DraftField.body);
  }

  void _onHtmlChanged() {
    final text = htmlController.text;
    if (text == _observedHtml) return;
    _observedHtml = text;
    if (!_publishing && _isHtmlMode) _recordEdit(DraftField.body);
  }

  void _onTitleChanged() {
    final text = titleController.text;
    if (text == _observedTitle) return;
    _observedTitle = text;
    if (!_publishing) _recordEdit(DraftField.title);
  }

  void _recordEdit(DraftField field) {
    if (_disposed || _publishing || !_session.canWrite) return;
    _session = _session.edited(field);
    _autoSavePaused = false;
    _scheduleAutoSave();
    _publishSaveState();
  }

  AttachmentMentionQuery? attachmentMentionQuery() {
    if (_disposed ||
        _isLocked ||
        !_session.canWrite ||
        isConvertingEditor ||
        _librarySwitching ||
        _importCutover ||
        _deleting) {
      return null;
    }
    if (_isHtmlMode) {
      final value = htmlController.value;
      if (!value.selection.isCollapsed ||
          !value.composing.isCollapsed ||
          !htmlAllowsAttachmentMention(value.text, value.selection.start)) {
        return null;
      }
      final end = value.selection.start;
      if (end <= 0) return null;
      final start = value.text.lastIndexOf('\n', end == 0 ? 0 : end - 1) + 1;
      final query = AttachmentMentionQuery.find(
        value.text.substring(start, end),
        end - start,
        offset: start,
      );
      return query != null &&
              htmlAllowsAttachmentMention(value.text, query.start)
          ? query
          : null;
    }
    final selection = quillController.selection;
    if (!selection.isCollapsed ||
        selection.start < 0 ||
        selection.start >= quillController.document.length) {
      return null;
    }
    final line = quillController.document.queryChild(selection.start);
    final node = line.node;
    if (node == null ||
        quillController.getSelectionStyle().attributes['link']?.value != null) {
      return null;
    }
    final query = AttachmentMentionQuery.find(
      node.toPlainText(),
      line.offset,
      offset: selection.start - line.offset,
    );
    if (query != null &&
        quillController.document
                .collectStyle(query.start, 1)
                .attributes['link']
                ?.value !=
            null) {
      return null;
    }
    return query;
  }

  OperationResult<AttachmentModel> resolveInternalLink(String url) {
    final target = FnotesTarget.parse(url);
    if (target == null) {
      return const OperationResult.failure(
        OperationOutcome.rejectedInput,
        'Invalid internal link.',
      );
    }
    if (target.resource != FnotesResource.attachment) {
      return const OperationResult.failure(
        OperationOutcome.rejectedInput,
        'Unsupported internal link.',
      );
    }
    final matches = _attachments
        .where((a) => !a.isLoading && a.mentionIdentity == target.id)
        .toList();
    if (_isLocked || matches.length != 1) {
      return const OperationResult.failure(
        OperationOutcome.rejectedInput,
        'Attachment unavailable.',
      );
    }
    return OperationResult.success(matches.single);
  }

  OperationResult<void> insertAttachmentMention({
    required String attachmentId,
    required AttachmentMentionQuery query,
    required int owner,
    required EditorMode mode,
  }) {
    final current = attachmentMentionQuery();
    final matches = _attachments
        .where((a) => a.id == attachmentId && !a.isLoading)
        .toList();
    if (owner != _session.generation ||
        mode != editorMode ||
        current == null ||
        current.start != query.start ||
        current.end != query.end ||
        current.text != query.text ||
        matches.length != 1) {
      return const OperationResult.failure(
        OperationOutcome.cancelled,
        'Mention no longer available.',
      );
    }
    final attachment = matches.single;
    if (_attachments
            .where((a) => a.mentionIdentity == attachment.mentionIdentity)
            .length !=
        1) {
      return const OperationResult.failure(
        OperationOutcome.rejectedInput,
        'Attachment reference is ambiguous.',
      );
    }
    final url = FnotesTarget.attachment(attachment.mentionIdentity);
    final label = '@${attachment.fileName}';
    _publishing = true;
    try {
      if (_isHtmlMode) {
        final text =
            '<a href="$url">${const HtmlEscape(HtmlEscapeMode.element).convert(label)}</a> ';
        final value = htmlController.value;
        htmlController.value = value.copyWith(
          text: value.text.replaceRange(query.start, query.end, text),
          selection: TextSelection.collapsed(offset: query.start + text.length),
          composing: TextRange.empty,
        );
        _observedHtml = htmlController.text;
      } else {
        final controller = quillController;
        final attributes = controller.getSelectionStyle().attributes;
        final style = <String, dynamic>{
          for (final e in attributes.entries)
            if (e.value.scope == AttributeScope.inline && e.key != 'link')
              e.key: e.value.value,
        };
        final delta = controller.document.toDelta().slice(0, 0)
          ..retain(query.start)
          ..insert(label, {...style, 'link': url})
          ..insert(' ', style)
          ..delete(query.end - query.start);
        // Isolate this replacement from adjacent typing in Quill's history.
        controller.document.history.lastRecorded = 0;
        controller.compose(
          delta,
          TextSelection.collapsed(offset: query.start + label.length + 1),
          ChangeSource.local,
        );
        controller.document.history.lastRecorded = 0;
        controller.updateSelection(
          TextSelection.collapsed(offset: query.start + label.length + 1),
          ChangeSource.local,
        );
        _observedRichDelta = controller.document.toDelta();
      }
      if (attachment.mentionId == null) {
        _attachments = [
          for (final a in _attachments)
            if (a.id == attachment.id)
              AttachmentModel(
                id: a.id,
                fileName: a.fileName,
                size: a.size,
                mimeType: a.mimeType,
                mentionId: a.id,
              )
            else
              a,
        ];
      }
    } finally {
      _publishing = false;
    }
    _recordEdit(DraftField.body);
    _recordEdit(DraftField.attachments);
    attachmentsNotifier.value = List.of(_attachments);
    return const OperationResult.success();
  }

  Future<void> handleLinkClick(String url) async {
    if (FnotesTarget.isInternal(url)) {
      return; // Never pass internal resources to an external launcher.
    }
    if (url.startsWith('note://')) {
      final noteId = url.replaceFirst('note://', '');
      // Find file with this noteId
      // We need to match noteId to filename.
      // Current assumption: filename is "note_$noteId".

      // Check recent files for "note_$noteId"
      final targetName = "note_$noteId";
      await loadNote(targetName);
    } else {
      // Standard URL
      // Default launch?
      // We can use launchUrl from url_launcher
      // But user needs to import it?
      // For now print
      print("External Link Clicked: $url");
    }
  }

  Future<void> toggleEditorMode() async {
    await setEditorMode(_isHtmlMode ? EditorMode.richText : EditorMode.html);
  }

  Future<OperationResult<void>> formatHtml({
    bool expandTextBlocks = false,
  }) async {
    if (_disposed ||
        !_isHtmlMode ||
        _isLocked ||
        !_session.canWrite ||
        _librarySwitching ||
        _importCutover ||
        _deleting ||
        _libraryResourcesClosing) {
      return _cancelledResult();
    }
    if (isConvertingEditor) {
      return const OperationResult.failure(
        OperationOutcome.conflict,
        'Editor conversion is already running.',
      );
    }
    final owner = _session.generation;
    final revision = _session.editRevision;
    final source = htmlController.text;
    final selection = htmlController.selection;
    isConvertingNotifier.value = true;
    try {
      final formatted = await compute(
        expandTextBlocks ? formatExpandedHtmlSource : formatHtmlSource,
        source,
      );
      if (_disposed ||
          owner != _session.generation ||
          revision != _session.editRevision ||
          !_isHtmlMode ||
          _isLocked ||
          !_session.canWrite ||
          _libraryResourcesClosing) {
        return _cancelledResult();
      }
      if (formatted != source) {
        htmlController.value = TextEditingValue(
          text: formatted,
          selection: TextSelection(
            baseOffset: selection.baseOffset.clamp(0, formatted.length),
            extentOffset: selection.extentOffset.clamp(0, formatted.length),
          ),
        );
      }
      return const OperationResult.success();
    } catch (_) {
      if (_disposed || owner != _session.generation) return _cancelledResult();
      return _reportResult(
        const OperationResult.failure(
          OperationOutcome.rejectedInput,
          'HTML could not be formatted. Complete its tags first; the source was retained.',
        ),
      );
    } finally {
      if (!_disposed) isConvertingNotifier.value = false;
    }
  }

  Future<OperationResult<void>> setEditorMode(EditorMode target) =>
      _libraryTask(() => _setEditorMode(target), _cancelledResult());

  Future<OperationResult<void>> _setEditorMode(EditorMode target) async {
    if (_disposed || _importCutover || !_session.canWrite || _isLocked) {
      return _cancelledResult();
    }
    if (target == editorMode) return const OperationResult.success();
    if (isConvertingEditor) {
      return const OperationResult.failure(
        OperationOutcome.conflict,
        'Editor conversion is already running.',
      );
    }
    _observeRichEdit();
    final owner = _session.generation;
    final revision = _session.editRevision;
    final request = ++_conversionRequest;
    final source = editorMode;
    isConvertingNotifier.value = true;
    try {
      if (target == EditorMode.richText) {
        final delta = await _htmlToDelta(htmlController.text);
        if (_disposed ||
            owner != _session.generation ||
            revision != _session.editRevision ||
            request != _conversionRequest ||
            source != editorMode) {
          return _cancelledResult();
        }
        final document = Document.fromJson(delta);
        _publishing = true;
        try {
          _replaceDocument(document);
          _isHtmlMode = false;
        } finally {
          _publishing = false;
        }
      } else {
        final html = await _deltaToHtml(
          quillController.document.toDelta().toJson(),
        );
        _observeRichEdit();
        if (_disposed ||
            owner != _session.generation ||
            revision != _session.editRevision ||
            request != _conversionRequest ||
            source != editorMode) {
          return _cancelledResult();
        }
        _publishing = true;
        try {
          htmlController.text = html;
          _isHtmlMode = true;
        } finally {
          _publishing = false;
        }
      }
      _recordEdit(DraftField.body);
      notifyListeners();
      return const OperationResult.success();
    } catch (_) {
      if (_disposed || owner != _session.generation) return _cancelledResult();
      return _reportResult(
        const OperationResult.failure(
          OperationOutcome.rejectedInput,
          'Editor conversion failed; the draft was retained.',
        ),
      );
    } finally {
      if (!_disposed && request == _conversionRequest) {
        isConvertingNotifier.value = false;
      }
    }
  }

  Future<void> _initFileWatcher() async {
    final background = _backgroundService;
    if (background == null || _disposed || _libraryResourcesClosing) {
      return;
    }
    await background.init();
    if (_disposed || _libraryResourcesClosing) {
      return;
    }
    _backgroundFilesSubscription = background.discoveriesStream.listen((
      snapshot,
    ) {
      if (_disposed || !background.isCurrent(snapshot.request)) {
        return;
      }
      _recentFiles = snapshot.files;
      _inventoryRoot = snapshot.request.directoryPath;
      _listingRevision++;
      _listError = null;
      _isScanning = !snapshot.isFinal || _refreshAgain;
      _restartSearch();
      _publishNoteList();
      if (snapshot.isFinal) _finishBackgroundRefresh(snapshot.request);
    });
    _backgroundErrorsSubscription = background.failuresStream.listen((failure) {
      if (_disposed ||
          _libraryResourcesClosing ||
          (failure.request != null &&
              !background.isCurrent(failure.request!))) {
        return;
      }
      _listError =
          failure.result.message ?? 'Library discovery failed. Retry refresh.';
      _isScanning = false;
      _publishNoteList();
      if (failure.request != null) {
        _finishBackgroundRefresh(failure.request!);
      } else {
        _refreshInFlight = null;
        _refreshAgain = false;
      }
    });

    if (_fileService is LibraryFileService && !kIsWeb) {
      final libraries = _fileService as LibraryFileService;
      await _bindLibraryWatch(await libraries.currentLibrary());
      return;
    }
    _fileWatcherSubscription = _fileService.watchRecentFiles().listen(
      (_) {
        if (_disposed) return;
        // Debounce reload
        if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
        _debounceTimer = Timer(const Duration(seconds: 2), () {
          loadRecentFiles();
        });
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!_disposed) {
          _reportResult(
            const OperationResult.failure(
              OperationOutcome.ioFailure,
              'Library watching failed. Retry refresh.',
            ),
          );
        }
      },
    );
  }

  StreamSubscription<void> _listenLibraryWatch(LibraryWatch watch) =>
      watch.changes.listen(
        (_) {
          if (_disposed ||
              _libraryResourcesClosing ||
              !identical(_libraryWatch, watch)) {
            return;
          }
          _debounceTimer?.cancel();
          _debounceTimer = Timer(
            const Duration(seconds: 2),
            () => unawaited(_requestBackgroundRefresh()),
          );
        },
        onError: (Object error, StackTrace stackTrace) {
          if (!_disposed && identical(_libraryWatch, watch)) {
            _reportResult(
              const OperationResult.failure(
                OperationOutcome.ioFailure,
                'Library watching failed. Retry refresh.',
              ),
            );
          }
        },
      );

  Future<void> _closeLibraryWatch(LibraryWatch watch) async {
    _retiredWatches.add(watch);
    await watch.close();
    _retiredWatches.remove(watch);
  }

  Future<void> _bindLibraryWatch(StorageBinding binding) async {
    if (_libraryResourcesClosing) {
      return;
    }
    final libraries = _fileService as LibraryFileService;
    final previous = _libraryWatch;
    if (previous != null &&
        p.equals(previous.binding.root, binding.root) &&
        !previous.failed) {
      return;
    }
    final request = _listingPathRequest;
    final next = await libraries.openLibraryWatch(binding);
    if (_disposed ||
        _libraryResourcesClosing ||
        request != _listingPathRequest ||
        _librarySwitching) {
      await _closeLibraryWatch(next);
      return;
    }
    final subscription = _listenLibraryWatch(next);
    if (next.failed) {
      await subscription.cancel();
      await _closeLibraryWatch(next);
      throw const FileSystemException('Library watching failed.');
    }
    final oldSubscription = _libraryWatchSubscription;
    _libraryWatch = next;
    _libraryWatchSubscription = subscription;
    await oldSubscription?.cancel();
    if (previous != null) await _closeLibraryWatch(previous);
  }

  /// Settings commit is the publication boundary. Preparation never consumes
  /// Discard; an unexpected edit during commit retains its exact old reference.
  Future<OperationResult<void>> switchLibrary(String root) async {
    final jobs = await _resolveOwnerJobs(DraftTransition.library);
    if (!jobs.isSuccess) return _reportResult(jobs);
    if (_disposed ||
        _libraryResourcesClosing ||
        _librarySwitching ||
        _deleting ||
        _librarySensitiveJobs != 0 ||
        _activeLoads != 0 ||
        _decisionPending) {
      return _reportResult(
        const OperationResult.failure(
          OperationOutcome.conflict,
          'Finish the active note operation before opening another library.',
        ),
      );
    }
    if (_fileService is! LibraryFileService) {
      return _reportResult(
        const OperationResult.failure(
          OperationOutcome.rejectedInput,
          'Library switching awaits recoverable persistence validation for this storage.',
        ),
      );
    }
    final service = _fileService as LibraryFileService;
    if (!service.supportsLibrarySwitch ||
        !_settings.supportsRecoverableLibrarySwitch) {
      return _reportResult(
        const OperationResult.failure(
          OperationOutcome.rejectedInput,
          'Library switching awaits recoverable persistence validation for this storage.',
        ),
      );
    }
    if (!p.isAbsolute(root) || p.split(root).contains('..')) {
      return _reportResult(
        const OperationResult.failure(
          OperationOutcome.rejectedInput,
          'Choose an absolute library folder.',
        ),
      );
    }
    _librarySwitching = true;
    LibraryWatch? candidateWatch;
    StreamSubscription<void>? candidateSubscription;
    StorageBinding? candidate;
    StorageBinding? previous;
    var committed = false;
    var cleanupFailed = false;
    final wasReadOnly = quillController.readOnly;
    Future<OperationResult<void>> perform() async {
      try {
        await _settings.init();
        final original = await service.currentLibrary();
        previous = original;
        if (p.equals(original.root, p.normalize(root))) {
          return const OperationResult.success();
        }
        await _saveTail;
        final resolved = await prepareTransition(DraftTransition.library);
        if (!resolved.isSuccess) {
          return _reportResult(_transitionFailure(resolved));
        }
        final next = await service.prepareLibrary(root);
        candidate = next;
        final prepared = await service.openLibraryWatch(next);
        candidateWatch = prepared;
        _retiredWatches.add(prepared);
        candidateSubscription = _listenLibraryWatch(prepared);
        var fallback =
            _noteReference ?? await _fileService.newNoteReference(_draftNoteId);
        await _saveTail;
        fallback = _noteReference ?? fallback;
        if (!isTransitionPermitCurrent(resolved.value!) ||
            prepared.failed ||
            _librarySensitiveJobs != 0) {
          return _reportResult(
            const OperationResult.failure(
              OperationOutcome.conflict,
              'The draft or candidate library changed; the previous library was retained.',
            ),
          );
        }
        _libraryCutover = true;
        _cancelAutoSave();
        quillController.readOnly = true;
        notifyListeners();
        await _settings.commitLibraryPath(
          next.root,
          expectedRoot: original.root,
          canCommit: () =>
              isTransitionPermitCurrent(resolved.value!) && !prepared.failed,
        );
        committed = true;
        service.publishLibrary(next);
        _listingPathRequest++;
        _backgroundService?.invalidateRequests();
        final oldWatch = _libraryWatch;
        final oldSubscription = _libraryWatchSubscription;
        if (oldWatch != null) _retiredWatches.add(oldWatch);
        _retiredLibraries.add(original);
        _libraryWatch = candidateWatch;
        _libraryWatchSubscription = candidateSubscription;
        _retiredWatches.remove(prepared);
        candidateWatch = null;
        candidateSubscription = null;
        final unchanged = isTransitionPermitCurrent(resolved.value!);
        if (!_disposed) {
          _libraryEpoch++;
          _inventoryRoot = next.root;
          _refreshInFlight = null;
          _refreshAgain = false;
          _postCommitRefreshBinding = null;
          _listError = null;
          _recentFiles = const [];
          _filteredFiles = const [];
          _displayedQuery = '';
          _listingRevision++;
          _restartSearch();
          _sessionPasswords.clear();
          if (unchanged) {
            _resetDraft();
          } else {
            _noteReference = fallback;
          }
        }
        await oldSubscription?.cancel();
        if (oldWatch != null) await _closeLibraryWatch(oldWatch);
        if (_disposed) {
          await _libraryWatchSubscription?.cancel();
          if (_libraryWatch != null) await _closeLibraryWatch(_libraryWatch!);
          _libraryWatch = null;
          _libraryWatchSubscription = null;
        }
        if (unchanged || _disposed) {
          _retiredLibraries.add(original);
          await service.releaseLibrary(original);
          _retiredLibraries.remove(original);
        } else {
          _retiredLibraries.add(original);
        }
        if (!_disposed) {
          await loadRecentFiles();
          if (_libraryWatch?.failed ?? false) {
            return _reportResult(
              const OperationResult.failure(
                OperationOutcome.ioFailure,
                'The new library opened; watching failed. Retry refresh.',
              ),
            );
          }
          if (!unchanged) {
            return _reportResult(
              const OperationResult.failure(
                OperationOutcome.conflict,
                'The new library opened; a late edit was retained in the previous library draft. Save it before continuing.',
              ),
            );
          }
        }
        return _reportResult(const OperationResult.success());
      } on SettingsPersistenceFailure catch (failure) {
        return _reportResult(
          OperationResult.failure(
            failure.outcome,
            'Library settings could not be committed; the previous library and draft were retained.',
          ),
        );
      } on NotePersistenceFailure catch (failure) {
        return _reportResult(
          OperationResult.failure(
            failure.outcome,
            committed
                ? 'The new library opened; previous-library cleanup is pending.'
                : 'Library preparation failed; the previous library and draft were retained.',
          ),
        );
      } catch (_) {
        return _reportResult(
          OperationResult.failure(
            committed
                ? OperationOutcome.recoveryRequired
                : OperationOutcome.ioFailure,
            committed
                ? 'The new library opened; cleanup or refresh is pending.'
                : 'Library preparation failed; the previous library and draft were retained.',
          ),
        );
      }
    }

    final result = await perform();
    try {
      try {
        await candidateSubscription?.cancel();
      } catch (_) {
        cleanupFailed = true;
      }
      try {
        final abandonedWatch = candidateWatch;
        if (abandonedWatch != null) await _closeLibraryWatch(abandonedWatch);
      } catch (_) {
        cleanupFailed = true;
      }
      try {
        final abandoned = candidate;
        final old = previous;
        if (!committed &&
            abandoned != null &&
            old != null &&
            !p.equals(abandoned.root, old.root)) {
          _retiredLibraries.add(abandoned);
          await service.releaseLibrary(abandoned);
          _retiredLibraries.remove(abandoned);
        }
      } catch (_) {
        cleanupFailed = true;
      }
    } finally {
      _libraryCutover = false;
      _librarySwitching = false;
      if (!_disposed) {
        quillController.readOnly = wasReadOnly;
        if (_session.isDirty) _scheduleAutoSave();
        notifyListeners();
      }
    }
    if (cleanupFailed) {
      return _reportResult(
        const OperationResult.failure(
          OperationOutcome.recoveryRequired,
          'The previous library was retained; candidate cleanup is pending.',
        ),
      );
    }
    return result;
  }

  Future<void> _initAsync() async {
    // Wait for settings to load so custom data path is available
    try {
      await _settings.init();
      if (_disposed) return;
      if (_usesOwnedMutations) {
        final pending = await (_fileService as TransactionalNoteFiles)
            .pendingDeletions();
        if (_disposed) return;
        pendingDeletionsNotifier.value = pending;
      }
      await _initFileWatcher();
      if (_disposed) return;
      await loadRecentFiles();
    } catch (_) {
      if (!_disposed) {
        operationResultNotifier.value = const OperationResult.failure(
          OperationOutcome.ioFailure,
          'Library initialization failed.',
        );
      }
    }
  }
  // endregion

  // region File Loading
  Future<void> _requestBackgroundRefresh() async {
    if (_disposed || _libraryResourcesClosing || _backgroundService == null)
      return;
    if (_refreshInFlight != null || _refreshDispatching) {
      _refreshAgain = true;
      _isScanning = true;
      _publishNoteList();
      return;
    }
    _refreshDispatching = true;
    try {
      await loadRecentFiles();
    } finally {
      _refreshDispatching = false;
    }
  }

  void _finishBackgroundRefresh(DiscoveryRequest request) {
    if (_refreshInFlight != null && !_refreshInFlight!.matches(request)) return;
    _refreshInFlight = null;
    if (_refreshAgain && !_disposed && !_libraryResourcesClosing) {
      _refreshAgain = false;
      scheduleMicrotask(() => unawaited(_requestBackgroundRefresh()));
    }
  }

  Future<void> loadRecentFiles() async {
    if (_disposed || _libraryResourcesClosing || _backgroundService == null) {
      return;
    }
    final request = ++_listingPathRequest;
    _backgroundService.invalidateRequests();
    _refreshAgain = false;
    _refreshInFlight = null;
    _listError = null;
    _isScanning = true;
    _publishNoteList();
    try {
      final path = await _fileService.getUserDataPath();
      if (path.isEmpty || _disposed || request != _listingPathRequest) return;
      if (_inventoryRoot != null && !p.equals(_inventoryRoot!, path)) {
        _libraryEpoch++;
        _recentFiles = const [];
        _filteredFiles = const [];
        _displayedQuery = '';
        _listingRevision++;
        _restartSearch();
      }
      _inventoryRoot = path;
      if (_fileService is LibraryFileService && !_librarySwitching && !kIsWeb) {
        await _bindLibraryWatch(StorageBinding(path, request));
        if (_disposed || request != _listingPathRequest) return;
      }
      _backgroundService.loadRecentFiles(path);
      _refreshInFlight = _backgroundService.requestedScan;
      _publishNoteList();
    } catch (_) {
      if (!_disposed && request == _listingPathRequest) {
        _listError = 'Library discovery failed. Retry refresh.';
        _isScanning = false;
        _publishNoteList();
      }
    }
  }

  /// Explicit cleanup retry; never release the root of a retained draft.
  Future<OperationResult<void>> retryLibraryCleanup() async {
    if (_disposed ||
        _librarySwitching ||
        _librarySensitiveJobs != 0 ||
        _drainingSaves ||
        _activeLoads != 0) {
      return const OperationResult.failure(
        OperationOutcome.conflict,
        'Finish the active operation before cleanup.',
      );
    }
    try {
      for (final watch in _retiredWatches.toList()) {
        await _closeLibraryWatch(watch);
      }
      if (_fileService is LibraryFileService) {
        final libraries = _fileService as LibraryFileService;
        final active = await libraries.currentLibrary();
        for (final binding in _retiredLibraries.toList()) {
          if (p.equals(binding.root, active.root) ||
              p.equals(binding.root, _noteReference?.binding.root ?? '')) {
            continue;
          }
          await libraries.releaseLibrary(binding);
          _retiredLibraries.remove(binding);
        }
      }
      return const OperationResult.success();
    } catch (_) {
      return _reportResult(
        const OperationResult.failure(
          OperationOutcome.recoveryRequired,
          'Library cleanup is still pending.',
        ),
      );
    }
  }

  Future<void> closeLibraryResources() =>
      _libraryResourcesClose ??= _closeLibraryResources();

  Future<void> _closeLibraryResources() async {
    _libraryResourcesClosing = true;
    try {
      // Quiesce read-only work before releasing watchers or writer roots. The
      // close UI is already non-writable; a queued refresh must not restart it.
      _debounceTimer?.cancel();
      _searchDebounceTimer?.cancel();
      _listingPathRequest++;
      _searchGeneration++;
      _backgroundService?.invalidateRequests();
      await _fileWatcherSubscription?.cancel();
      _fileWatcherSubscription = null;
      await _backgroundFilesSubscription?.cancel();
      _backgroundFilesSubscription = null;
      await _backgroundErrorsSubscription?.cancel();
      _backgroundErrorsSubscription = null;
      _backgroundService?.dispose();
      final active = _libraryWatch;
      if (active != null) _retiredWatches.add(active);
      _libraryWatch = null;
      await _libraryWatchSubscription?.cancel();
      _libraryWatchSubscription = null;
      for (final watch in {..._retiredWatches, if (active != null) active}) {
        await _closeLibraryWatch(watch);
      }
    } catch (_) {
      _libraryResourcesClose = null;
      rethrow;
    }
  }

  Future<OperationResult<void>> openListedNote(RecentFile file, int epoch) =>
      loadNote(
        file.path,
        expectedRoot: _inventoryRoot,
        expectedContentPath: file.fullPath,
        expectedLibraryEpoch: epoch,
      );

  Future<OperationResult<void>> loadNote(
    String fileName, {
    String? expectedRoot,
    String? expectedContentPath,
    int? expectedLibraryEpoch,
  }) async {
    bool expected(NoteReference? reference) =>
        (expectedLibraryEpoch == null ||
            expectedLibraryEpoch == _libraryEpoch) &&
        (expectedRoot == null ||
            (reference != null &&
                p.equals(expectedRoot, reference.binding.root))) &&
        (expectedContentPath == null ||
            (reference != null &&
                p.equals(expectedContentPath, reference.contentPath)));
    if (expectedLibraryEpoch != null && expectedLibraryEpoch != _libraryEpoch) {
      return _cancelledResult();
    }
    if (_disposed) {
      return const OperationResult.failure(
        OperationOutcome.cancelled,
        'Editor was closed.',
      );
    }
    if (fileName == _currentFileName &&
        !_loading &&
        _session.access != DraftAccess.unsupported &&
        expected(_noteReference)) {
      return const OperationResult.success();
    }
    final request = ++_loadRequest;
    final resolved = await prepareTransition(DraftTransition.navigation);
    if (!resolved.isSuccess) return _reportResult(_transitionFailure(resolved));
    if (_disposed || request != _loadRequest) return _cancelledResult();
    final owner = _session.generation;
    _activeLoads++;
    _loading = true;
    setBusy(true);
    try {
      final reference = await _fileService.resolveNote(fileName);
      if (!expected(reference)) return _cancelledResult();
      if (_disposed ||
          request != _loadRequest ||
          owner != _session.generation) {
        return _cancelledResult();
      }
      final content = reference == null
          ? null
          : await _fileService.readResolved(reference);
      if (_disposed ||
          request != _loadRequest ||
          owner != _session.generation) {
        return _cancelledResult();
      }
      if (content == null) {
        return _reportResult(
          const OperationResult.failure(
            OperationOutcome.ioFailure,
            'The selected note could not be read.',
          ),
        );
      }
      final prospective = await _decodeNote(content);
      final note = prospective.note;
      if (!expected(reference)) return _cancelledResult();
      final resolvedReference = reference!.withModelId(note.id);
      String? password;
      String? plainBody;
      var locked = note.isLocked;
      late Document document;
      if (locked) {
        final cached = _sessionPasswords[fileName];
        if (cached != null) {
          final decrypted = await _encryptionService.decryptResult(
            note.content,
            password: cached,
          );
          if (decrypted.isSuccess) {
            plainBody = decrypted.value!;
            document = _prepareDocument(decrypted.value!);
            password = cached;
            locked = false;
          } else {
            document = Document();
          }
        } else {
          document = Document();
        }
      } else {
        plainBody = note.content;
        document = _prepareDocument(note.content);
      }
      if (locked) await _invalidateAttachmentCache(resolvedReference);
      // Edits made while reading must remain owned by the previous draft.
      if (_disposed ||
          request != _loadRequest ||
          owner != _session.generation ||
          !isTransitionPermitCurrent(resolved.value!)) {
        document.close();
        return _cancelledResult();
      }
      _cancelAutoSave();
      _unlockRequest++;
      _publishing = true;
      try {
        if (!expected(resolvedReference)) {
          document.close();
          return _cancelledResult();
        }
        _currentFileName = fileName;
        _currentPassword = password;
        _storedNote = note;
        _retainedPlainBody = plainBody;
        _noteReference = resolvedReference;
        _retainedMetadata = prospective.metadata;
        _envelopeKind = prospective.kind;
        final credentials =
            _noteCredentialGenerations[_credentialIdentity(
              resolvedReference,
            )] ??
            0;
        _persistedCredentialGeneration = credentials;
        _session = DraftSession(
          generation: ++_nextSessionGeneration,
          access: locked ? DraftAccess.locked : DraftAccess.editable,
          persistedRevision: 0,
          credentialGeneration: credentials,
        );
        _isLocked = locked;
        _isHtmlMode = false;
        _attachments = List.from(note.attachments);
        _attachmentCache.clear();
        _replaceDocument(document);
        htmlController.clear();
        titleController.text = note.title;
        if (locked) _sessionPasswords.remove(fileName);
        isLockedNotifier.value = locked;
        attachmentsNotifier.value = List.unmodifiable(_attachments);
      } finally {
        _publishing = false;
      }
      notifyListeners();
      return _reportResult(const OperationResult.success());
    } on NotePersistenceFailure catch (failure) {
      if (_disposed ||
          request != _loadRequest ||
          owner != _session.generation) {
        return _cancelledResult();
      }
      return _reportResult(
        OperationResult.failure(
          failure.outcome,
          'Note loading failed; the previous draft was retained.',
        ),
      );
    } on FormatException {
      if (_disposed ||
          request != _loadRequest ||
          owner != _session.generation) {
        return _cancelledResult();
      }
      return _reportResult(
        const OperationResult.failure(
          OperationOutcome.rejectedInput,
          'Unsupported or damaged note; the previous draft was retained.',
        ),
      );
    } catch (_) {
      if (_disposed ||
          request != _loadRequest ||
          owner != _session.generation) {
        return _cancelledResult();
      }
      return _reportResult(
        const OperationResult.failure(
          OperationOutcome.ioFailure,
          'Note loading failed; the previous draft was retained.',
        ),
      );
    } finally {
      _activeLoads--;
      if (!_disposed) {
        _loading = _activeLoads > 0;
        if (!_loading) setBusy(false);
      }
    }
  }

  Future<DecodedNote> _decodeNote(String content) => NoteCodec.decode(
    content,
    decryptApp: _encryptionService.decryptAppResult,
  );
  Future<DraftDecision> _askDraftDecision(DraftDecisionRequest request) async {
    if (_disposed || _decisionPending || _onDraftDecision == null) {
      return DraftDecision.cancel;
    }
    _decisionPending = true;
    try {
      return await _onDraftDecision(request);
    } catch (_) {
      return DraftDecision.cancel;
    } finally {
      _decisionPending = false;
    }
  }

  OperationResult<void> _transitionFailure(
    OperationResult<DraftTransitionPermit> result,
  ) => OperationResult.failure(result.outcome, result.message);

  bool isTransitionPermitCurrent(DraftTransitionPermit permit) {
    _observeRichEdit();
    return !_disposed &&
        permit.generation == _session.generation &&
        permit.revision == _session.editRevision &&
        (permit.discardChanges || !_session.isDirty);
  }

  Future<OperationResult<DraftTransitionPermit>> prepareTransition(
    DraftTransition transition,
  ) async {
    // Metadata removal and other queued publications must settle before a
    // navigation decision captures its revision. Preparation is outside this
    // queue and has its own explicit Cancel & wait decision below.
    if (_mutationsPending != 0) await _mutationTail;
    final jobs = await _resolveOwnerJobs(transition);
    if (!jobs.isSuccess) {
      return OperationResult.failure(jobs.outcome, jobs.message);
    }
    if (_librarySwitching &&
        (transition != DraftTransition.library || _libraryCutover)) {
      return const OperationResult.failure(
        OperationOutcome.conflict,
        'Library switching is in progress.',
      );
    }
    _observeRichEdit();
    if (_disposed) {
      return const OperationResult.failure(
        OperationOutcome.cancelled,
        'Editor was closed.',
      );
    }
    final owner = _session.generation;
    var firstSaveApproved = false;
    while (true) {
      _observeRichEdit();
      if (_disposed || owner != _session.generation) {
        return const OperationResult.failure(
          OperationOutcome.cancelled,
          'The selected draft changed.',
        );
      }
      if (!_session.isDirty) {
        return OperationResult.success(
          DraftTransitionPermit(
            generation: owner,
            revision: _session.editRevision,
          ),
        );
      }
      if (!_session.isPersisted && !firstSaveApproved) {
        if (_onDraftDecision == null) {
          return const OperationResult.failure(
            OperationOutcome.rejectedInput,
            'Save or explicitly discard this new draft before continuing.',
          );
        }
        final revision = _session.editRevision;
        final decision = await _askDraftDecision(
          DraftDecisionRequest(DraftDecisionKind.firstSave, transition),
        );
        _observeRichEdit();
        if (_disposed ||
            owner != _session.generation ||
            revision != _session.editRevision) {
          return const OperationResult.failure(
            OperationOutcome.conflict,
            'The draft changed during the decision.',
          );
        }
        if (decision == DraftDecision.discard) {
          return OperationResult.success(
            DraftTransitionPermit(
              generation: owner,
              revision: revision,
              discardChanges: true,
            ),
          );
        }
        if (decision != DraftDecision.save) {
          return const OperationResult.failure(
            OperationOutcome.cancelled,
            'The transition was cancelled.',
          );
        }
        firstSaveApproved = true;
      }
      final saved = await saveNote();
      if (_disposed || owner != _session.generation) {
        return const OperationResult.failure(
          OperationOutcome.cancelled,
          'The selected draft changed.',
        );
      }
      if (saved.isSuccess) continue; // Flush edits made during the commit too.
      if (_onDraftDecision == null) {
        return OperationResult.failure(saved.outcome, saved.message);
      }
      _cancelAutoSave();
      final revision = _session.editRevision;
      final decision = await _askDraftDecision(
        DraftDecisionRequest(
          DraftDecisionKind.saveFailure,
          transition,
          failureMessage: saved.message,
        ),
      );
      _observeRichEdit();
      if (_disposed ||
          owner != _session.generation ||
          revision != _session.editRevision) {
        return const OperationResult.failure(
          OperationOutcome.conflict,
          'The draft changed during the decision.',
        );
      }
      if (decision == DraftDecision.discard) {
        return OperationResult.success(
          DraftTransitionPermit(
            generation: owner,
            revision: revision,
            discardChanges: true,
          ),
        );
      }
      if (decision != DraftDecision.retry) {
        return const OperationResult.failure(
          OperationOutcome.cancelled,
          'Save failed; the draft was retained.',
        );
      }
    }
  }

  Future<OperationResult<void>> prepareToExit() async {
    await _saveTail;
    final resolved = await prepareTransition(DraftTransition.exit);
    if (!resolved.isSuccess) return _reportResult(_transitionFailure(resolved));
    if (!isTransitionPermitCurrent(resolved.value!)) return _cancelledResult();
    _cancelAutoSave();
    return const OperationResult.success();
  }

  OperationResult<void> _reportResult(OperationResult<void> result) {
    if (!_disposed) operationResultNotifier.value = result;
    return result;
  }

  OperationResult<void> _cancelledResult() => const OperationResult.failure(
    OperationOutcome.cancelled,
    'A newer editor operation owns this request.',
  );

  bool get supportsExtendedNoteOperations =>
      _fileService is! NoteMutationPolicy ||
      (_fileService as NoteMutationPolicy).supportsExtendedNoteOperations;

  /// Reject before dialogs, draft changes, file selection or service I/O.
  bool ensureExtendedNoteOperations() {
    if (supportsExtendedNoteOperations) return true;
    _reportResult(
      const OperationResult.failure(
        OperationOutcome.rejectedInput,
        'Attachments, password changes, import, export and Delete are temporarily '
        'unavailable in this storage preview. Your draft was retained.',
      ),
    );
    return false;
  }
  // endregion

  // region Password & Locking
  Future<OperationResult<void>> setPassword(String password) {
    if (_usesOwnedMutations) {
      return _libraryTask(
        () => _changeOwnedProtection(password),
        _cancelledResult(),
      );
    }
    if (!ensureExtendedNoteOperations() ||
        _librarySwitching ||
        _disposed ||
        !_session.canWrite ||
        _isLocked) {
      return Future.value(_cancelledResult());
    }
    _currentPassword = password;
    _recordEdit(DraftField.protection);
    notifyListeners();
    return Future.value(const OperationResult.success());
  }

  Future<OperationResult<void>> clearPassword() {
    if (_usesOwnedMutations) {
      return _libraryTask(
        () => _changeOwnedProtection(null),
        _cancelledResult(),
      );
    }
    if (!ensureExtendedNoteOperations() ||
        _librarySwitching ||
        _disposed ||
        !_session.canWrite ||
        _isLocked) {
      return Future.value(_cancelledResult());
    }
    _currentPassword = null;
    _recordEdit(DraftField.protection);
    notifyListeners();
    return Future.value(const OperationResult.success());
  }

  /// Removes password protection from the current note.
  /// Decrypts all attachments and saves the note without encryption.
  /// If [password] is provided, it will be used instead of the stored password.
  Future<bool> removePassword({String? password}) async {
    if (_usesOwnedMutations) {
      return (await _libraryTask(
        () => _changeOwnedProtection(null, verifiedOldPassword: password),
        _cancelledResult(),
      )).isSuccess;
    }
    if (!ensureExtendedNoteOperations()) return false;
    return _libraryTask(() => _removePassword(password: password), false);
  }

  Future<bool> _removePassword({String? password}) async {
    final effectivePassword = password ?? _currentPassword;
    if (effectivePassword == null || _currentFileName == null) return false;

    // Extract noteId from _currentFileName
    String noteId;
    if (_currentFileName!.startsWith('note_')) {
      noteId = _currentFileName!.replaceFirst('note_', '');
      if (noteId.contains('.')) {
        noteId = noteId.split('.').first;
      }
    } else {
      noteId = const Uuid().v4();
    }

    setBusy(true);
    try {
      final totalSteps =
          _attachments.length + 2; // content + attachments + saving
      int currentStep = 0;

      // Report starting
      progressNotifier.value = 'Decrypting content...';
      currentStep++;

      // 1. Decrypt all attachments and save them unencrypted
      final List<AttachmentModel> newAttachments = [];
      for (int i = 0; i < _attachments.length; i++) {
        final attachment = _attachments[i];
        final percent = ((currentStep / totalSteps) * 100).round();
        progressNotifier.value =
            'Decrypting $percent% (${attachment.fileName})';

        // Yield to event loop to keep UI responsive
        await Future.delayed(Duration.zero);

        final encryptedData = await _fileService.readAttachment(
          noteId,
          attachment.id,
        );
        if (encryptedData != null) {
          final decryptedData = await _encryptionService.decryptBinary(
            encryptedData,
            password: effectivePassword,
          );
          if (decryptedData.isNotEmpty) {
            // Re-encrypt with app key (no user password) and save with new ID
            final reEncryptedData = await _encryptionService.encryptBinary(
              decryptedData,
              password: null, // App key only, no user password
            );
            final newId = await _fileService.saveAttachment(
              reEncryptedData,
              noteId,
            );
            newAttachments.add(
              AttachmentModel(
                id: newId,
                fileName: attachment.fileName,
                size: attachment.size,
                mimeType: attachment.mimeType,
                mentionId: attachment.mentionId,
                isLoading: false,
              ),
            );
          } else {
            // Decryption failed, keep original
            newAttachments.add(attachment);
          }
        } else {
          // No data found, keep original
          newAttachments.add(attachment);
        }
        currentStep++;
      }

      // 2. Update attachments list
      _attachments = newAttachments;
      attachmentsNotifier.value = List.from(_attachments);

      // 3. Clear password (content is already in memory unencrypted)
      _currentPassword = null;
      _sessionPasswords.remove(_currentFileName!);
      _recordEdit(DraftField.attachments);
      _recordEdit(DraftField.protection);

      // 4. Save the note (will save without encryption since password is null)
      progressNotifier.value = 'Saving note...';
      final saved = await saveNote();
      if (!saved.isSuccess) return false;

      progressNotifier.value = null; // Clear progress
      notifyListeners();
      return true;
    } catch (e) {
      print("Error removing password: $e");
      progressNotifier.value = null;
      return false;
    } finally {
      setBusy(false);
      progressNotifier.value = null;
    }
  }

  Future<bool> unlockNote(
    String password, {
    bool readOnlyExport = false,
  }) async {
    return _libraryTask(
      () => _unlockNote(password, readOnlyExport: readOnlyExport),
      false,
    );
  }

  Future<bool> _unlockNote(
    String password, {
    bool readOnlyExport = false,
  }) async {
    if (_disposed || _currentFileName == null || _storedNote == null) {
      return false;
    }
    if (!_isLocked) return _currentPassword == password;
    final owner = _session.generation;
    final request = ++_unlockRequest;
    try {
      NoteCodec.validateAttachmentDeclarations(_retainedMetadata);
      final decryptedContent = await _encryptionService.decryptResult(
        _storedNote!.content,
        password: password,
      );
      if (!decryptedContent.isSuccess) return false;
      final document = _prepareDocument(decryptedContent.value!);
      if (_disposed ||
          owner != _session.generation ||
          request != _unlockRequest ||
          !_isLocked) {
        document.close();
        return false;
      }
      // Read-only access may reveal the same locked draft while its export
      // retains ownership. No other active operation may cross this boundary.
      final activeJobs = attachmentJobsNotifier.value
          .map((state) => state.progress.value)
          .where((job) => job.active)
          .toList();
      final keepExportOwner =
          readOnlyExport &&
          activeJobs.isNotEmpty &&
          activeJobs.every(
            (job) =>
                job.owner == owner &&
                job.operation == AttachmentJobOperation.export,
          );
      if (readOnlyExport && hasActiveExport && !keepExportOwner) {
        document.close();
        return false;
      }
      _publishing = true;
      try {
        _currentPassword = password;
        _sessionPasswords[_currentFileName!] = password;
        _retainedPlainBody = decryptedContent.value!;
        _session = DraftSession(
          generation: keepExportOwner ? owner : ++_nextSessionGeneration,
          persistedRevision: _session.persistedRevision,
          editRevision: _session.editRevision,
          credentialGeneration: _session.credentialGeneration,
        );
        _isLocked = false;
        _replaceDocument(document);
        if (keepExportOwner) quillController.readOnly = true;
        isLockedNotifier.value = false;
      } finally {
        _publishing = false;
      }
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Password confirmation never reloads or replaces an editable document.
  Future<bool> verifyStoredPassword(String password) async {
    if (_disposed || _storedNote == null) return false;
    if (!_isLocked) return verifyPassword(password);
    final owner = _session.generation;
    try {
      final decrypted = await _encryptionService.decryptResult(
        _storedNote!.content,
        password: password,
      );
      if (!decrypted.isSuccess) return false;
      _prepareDocument(decrypted.value!).close();
      return !_disposed && owner == _session.generation;
    } catch (_) {
      return false;
    }
  }

  bool verifyPassword(String password) {
    return _currentPassword == password;
  }

  Future<OperationResult<void>> manualLock() async {
    if (_disposed || _currentPassword == null) {
      return _reportResult(
        const OperationResult.failure(
          OperationOutcome.rejectedInput,
          'Save a protected note before locking.',
        ),
      );
    }
    final owner = _session.generation;
    final resolved = await prepareTransition(DraftTransition.lock);
    if (!resolved.isSuccess) return _reportResult(_transitionFailure(resolved));
    if (_disposed ||
        owner != _session.generation ||
        !isTransitionPermitCurrent(resolved.value!)) {
      return _cancelledResult();
    }
    if (resolved.value!.discardChanges && !_session.isPersisted) {
      return reset(discardChanges: true);
    }
    if (resolved.value!.discardChanges && _storedNote?.isLocked != true) {
      return _reportResult(
        const OperationResult.failure(
          OperationOutcome.rejectedInput,
          'The stored note is not protected; the draft was retained.',
        ),
      );
    }
    _cancelAutoSave();
    _loadRequest++;
    _unlockRequest++;
    if (_noteReference != null)
      await _invalidateAttachmentCache(_noteReference!);
    if (_disposed || owner != _session.generation) return _cancelledResult();
    _loading = false;
    _publishing = true;
    try {
      _sessionPasswords.remove(_currentFileName);
      _currentPassword = null;
      _retainedPlainBody = null;
      _isLocked = true;
      _session = DraftSession(
        generation: ++_nextSessionGeneration,
        access: DraftAccess.locked,
        editRevision: _session.editRevision,
        persistedRevision: _session.persistedRevision,
        credentialGeneration: _session.credentialGeneration,
      );
      _replaceDocument(Document());
      htmlController.clear();
      _attachmentCache.clear();
      if (resolved.value!.discardChanges && _storedNote != null) {
        titleController.text = _storedNote!.title;
        _attachments = List.from(_storedNote!.attachments);
        attachmentsNotifier.value = List.unmodifiable(_attachments);
      }
      isLockedNotifier.value = true;
    } finally {
      _publishing = false;
    }
    notifyListeners();
    return _reportResult(const OperationResult.success());
  }

  /// Changes the password for the current note only.
  /// If [oldPassword] is provided, it will be used instead of the stored password.
  Future<String> changePassword(
    String newPassword, {
    String? oldPassword,
  }) async {
    if (_usesOwnedMutations) {
      if (_currentPassword == null) return 'Error: No active password';
      final result = await _libraryTask(
        () => _changeOwnedProtection(
          newPassword,
          verifiedOldPassword: oldPassword,
        ),
        _cancelledResult(),
      );
      _reportResult(result);
      return result.isSuccess
          ? 'Password changed successfully'
          : result.message ?? 'Password change failed.';
    }
    if (!ensureExtendedNoteOperations()) {
      return 'Password changes are unavailable in this storage preview.';
    }
    return _libraryTask(
      () => _changePassword(newPassword, oldPassword: oldPassword),
      'Library switching is in progress.',
    );
  }

  Future<OperationResult<void>> changePasswordResult(
    String password, {
    String? oldPassword,
  }) async {
    if (_usesOwnedMutations) {
      if (_currentPassword == null) {
        return _reportResult(
          const OperationResult.failure(
            OperationOutcome.rejectedInput,
            'No active password.',
          ),
        );
      }
      return _reportResult(
        await _libraryTask(
          () => _changeOwnedProtection(
            password,
            verifiedOldPassword: oldPassword,
          ),
          _cancelledResult(),
        ),
      );
    }
    final message = await changePassword(password, oldPassword: oldPassword);
    return message == 'Password changed successfully'
        ? const OperationResult.success()
        : OperationResult.failure(OperationOutcome.ioFailure, message);
  }

  Future<String> _changePassword(
    String newPassword, {
    String? oldPassword,
  }) async {
    final effectiveOldPassword = oldPassword ?? _currentPassword;
    if (effectiveOldPassword == null) return "Error: No active password";
    if (_currentFileName == null) return "Error: No file selected";

    // Extract noteId from currentFileName
    String noteId;
    if (_currentFileName!.startsWith('note_')) {
      noteId = _currentFileName!.replaceFirst('note_', '');
      if (noteId.contains('.')) {
        noteId = noteId.split('.').first;
      }
    } else {
      noteId = const Uuid().v4();
    }

    setBusy(true);
    try {
      // 1. Get content from editor (already decrypted in memory)
      progressNotifier.value = 'Re-encrypting content...';
      await Future.delayed(Duration.zero);

      String contentToSave = "";
      if (_isHtmlMode) {
        contentToSave = htmlController.text;
      } else {
        final delta = quillController.document.toDelta();
        contentToSave = jsonEncode(delta.toJson());
      }

      // Re-encrypt content with new password
      final newEncryptedContent = await _encryptionService.encrypt(
        contentToSave,
        password: newPassword,
      );

      // 2. Re-encrypt all attachments
      final List<AttachmentModel> newAttachments = [];
      final totalAttach = _attachments.length;

      for (int i = 0; i < _attachments.length; i++) {
        final attachment = _attachments[i];
        progressNotifier.value =
            'Re-encrypting attachment ${i + 1}/$totalAttach...';
        await Future.delayed(Duration.zero);

        final encryptedData = await _fileService.readAttachment(
          noteId,
          attachment.id,
        );
        if (encryptedData != null) {
          final decryptedData = await _encryptionService.decryptBinary(
            encryptedData,
            password: effectiveOldPassword,
          );
          if (decryptedData.isNotEmpty) {
            final newEncryptedData = await _encryptionService.encryptBinary(
              decryptedData,
              password: newPassword,
            );
            final newId = await _fileService.saveAttachment(
              newEncryptedData,
              noteId,
            );
            newAttachments.add(
              AttachmentModel(
                id: newId,
                fileName: attachment.fileName,
                size: attachment.size,
                mimeType: attachment.mimeType,
                mentionId: attachment.mentionId,
                isLoading: false,
              ),
            );
          } else {
            newAttachments.add(attachment);
          }
        } else {
          newAttachments.add(attachment);
        }
      }

      // 3. Update internal state
      _attachments = newAttachments;
      attachmentsNotifier.value = List.from(_attachments);
      _currentPassword = newPassword;
      _sessionPasswords[_currentFileName!] = newPassword;
      _recordEdit(DraftField.attachments);
      _recordEdit(DraftField.protection);

      // 4. Build and save the note
      progressNotifier.value = 'Saving...';
      final note = NoteModel(
        id: noteId,
        title: titleController.text,
        content: newEncryptedContent,
        isLocked: true,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        attachments: newAttachments,
      );

      final jsonString = json.encode(note.toJson());
      final appEncrypted = await _encryptionService.encryptApp(jsonString);

      if (_currentFileName!.startsWith('note_')) {
        await _fileService.saveNoteContent(noteId, appEncrypted);
      } else {
        await _fileService.saveFile(appEncrypted, _currentFileName!);
      }

      print("Password changed for: $_currentFileName");
      return "Password changed successfully";
    } catch (e) {
      print("Error changing password: $e");
      return "Error: $e";
    } finally {
      setBusy(false);
      progressNotifier.value = null;
    }
  }

  void setSearchQuery(String query) {
    if (_disposed || query == _searchQuery) return;
    if (_searchQuery.isEmpty && query.isNotEmpty) _filteredFiles = _recentFiles;
    _searchQuery = query;
    _listError = null;
    _restartSearch();
  }

  void clearSearch() => setSearchQuery('');
  void retrySearch() {
    _listError = null;
    _restartSearch();
  }

  void _restartSearch() {
    _searchDebounceTimer?.cancel();
    final generation = ++_searchGeneration;
    _pendingSearch = null;
    if (_searchQuery.isEmpty) {
      _displayedQuery = '';
      _isFiltering = false;
      _publishNoteList();
      return;
    }
    _isFiltering = true;
    _publishNoteList();
    final query = _searchQuery;
    final listing = _listingRevision;
    final epoch = _libraryEpoch;
    _searchDebounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (!_ownsSearch(generation, listing, query) || epoch != _libraryEpoch)
        return;
      _pendingSearch = _SearchTicket(
        generation,
        listing,
        epoch,
        query,
        _recentFiles,
      );
      _pumpSearch();
    });
  }

  void _pumpSearch() {
    if (_disposed || _libraryResourcesClosing || _activeSearch != null) return;
    final ticket = _pendingSearch;
    _pendingSearch = null;
    if (ticket == null ||
        !_ownsSearch(ticket.generation, ticket.listing, ticket.query) ||
        ticket.epoch != _libraryEpoch) {
      return;
    }
    _activeSearch = ticket;
    unawaited(_runSearch(ticket));
  }

  Future<void> _runSearch(_SearchTicket ticket) async {
    bool owns() =>
        ticket.epoch == _libraryEpoch &&
        _ownsSearch(ticket.generation, ticket.listing, ticket.query);
    try {
      final results = await _filterRecentFiles(ticket.files, ticket.query);
      if (owns()) {
        _filteredFiles = List.unmodifiable(results);
        _displayedQuery = ticket.query;
        _isFiltering = false;
        _listError = null;
        _publishNoteList();
      }
    } catch (_) {
      if (owns()) {
        _isFiltering = false;
        _listError = 'Note search failed. Retry search.';
        _publishNoteList();
      }
    } finally {
      if (identical(_activeSearch, ticket)) _activeSearch = null;
      _pumpSearch();
    }
  }

  bool _ownsSearch(int generation, int listing, String query) =>
      !_disposed &&
      !_libraryResourcesClosing &&
      generation == _searchGeneration &&
      listing == _listingRevision &&
      query == _searchQuery;

  static Future<List<RecentFile>> _defaultFilterRecentFiles(
    List<RecentFile> files,
    String query,
  ) => compute(_filterFiles, {'files': files, 'query': query});
  static List<RecentFile> _filterFiles(Map<String, dynamic> params) {
    final List<RecentFile> files = params['files'];
    final String query = params['query'].toString().toLowerCase();

    return files.where((file) {
      final title = file.title.toLowerCase();
      return title.contains(query);
    }).toList();
  }

  // endregion

  // region Saving
  Future<OperationResult<void>> saveNote({
    bool isAutoSave = false,
    bool allowEmptyFirstSave = false,
  }) {
    if (_importCutover) {
      return Future.value(
        const OperationResult.failure(
          OperationOutcome.conflict,
          'Import replacement is finishing.',
        ),
      );
    }
    if (_deleting) {
      return Future.value(
        const OperationResult.failure(
          OperationOutcome.conflict,
          'Permanent deletion is in progress.',
        ),
      );
    }
    if (_libraryCutover) {
      return Future.value(
        const OperationResult.failure(
          OperationOutcome.conflict,
          'Library switching is finishing.',
        ),
      );
    }
    if (_disposed || !_session.canWrite || _isLocked) {
      return Future.value(
        _saveResult(
          const OperationResult.failure(
            OperationOutcome.rejectedInput,
            'This session cannot be saved.',
          ),
        ),
      );
    }
    if (isAutoSave && !_session.isPersisted) {
      return Future.value(
        const OperationResult.failure(
          OperationOutcome.rejectedInput,
          'A new draft requires its first explicit Save.',
        ),
      );
    }
    // Quill emits document events asynchronously. Observe the actual current
    // Delta before capture so typing followed immediately by Save is included.
    _observeRichEdit();
    if (!_session.isDirty &&
        !(allowEmptyFirstSave && !isAutoSave && !_session.isPersisted)) {
      return Future.value(
        _saveResult(
          _session.isPersisted
              ? const OperationResult.success()
              : const OperationResult.failure(
                  OperationOutcome.rejectedInput,
                  'The new draft is empty.',
                ),
        ),
      );
    }
    // Capture body, title, finalized objects, identity and credentials before
    // queueing or awaiting encryption. In-flight edits remain a later revision.
    final reuseBody =
        _storedNote != null &&
        !_session.dirtyFields.contains(DraftField.body) &&
        _session.credentialGeneration == _persistedCredentialGeneration;
    final queued = _pendingSaves.isEmpty ? null : _pendingSaves.last;
    if (queued != null &&
        queued.snapshot.sessionGeneration == _session.generation &&
        queued.snapshot.credentialGeneration == _session.credentialGeneration &&
        queued.snapshot.noteId == (_storedNote?.id ?? _draftNoteId) &&
        queued.snapshot.editRevision == _session.editRevision &&
        (queued.snapshot.reference == null ||
            queued.snapshot.reference!.contentPath ==
                _noteReference?.contentPath)) {
      queued.isAutoSave = queued.isAutoSave && isAutoSave;
      return queued.result.future;
    }
    late final NoteSnapshot snapshot;
    try {
      snapshot = NoteSnapshot(
        sessionGeneration: _session.generation,
        editRevision: _session.editRevision,
        credentialGeneration: _session.credentialGeneration,
        fileName: _currentFileName,
        reference: _noteReference,
        noteId: _storedNote?.id ?? _draftNoteId,
        title: titleController.text,
        body: reuseBody
            ? _storedNote!.content
            : (_isHtmlMode
                  ? htmlController.text
                  : jsonEncode(quillController.document.toDelta().toJson())),
        timestamp:
            _storedNote?.timestamp ?? (_draftTimestamp ??= _nowMilliseconds()),
        password: _currentPassword,
        envelopeKind: _envelopeKind,
        metadata: _retainedMetadata,
        attachments: _attachments.where((a) => !a.isLoading).toList(),
        reuseStoredBody: reuseBody,
        attachmentsChanged:
            _storedNote == null ||
            _session.dirtyFields.contains(DraftField.attachments),
      );
    } catch (_) {
      return Future.value(
        _saveResult(
          const OperationResult.failure(
            OperationOutcome.rejectedInput,
            'The draft could not be encoded; it was retained.',
          ),
        ),
      );
    }
    // Replace only work that has not begun. Active encryption/commit owns its
    // immutable snapshot; pending callers share the latest revision's outcome.
    for (final pending in _pendingSaves.toList()) {
      if (!_ownsSnapshot(pending.snapshot)) {
        _pendingSaves.remove(pending);
        pending.result.complete(_cancelledResult());
      }
    }
    final last = _pendingSaves.isEmpty ? null : _pendingSaves.last;
    final _PendingSave pending;
    if (last != null && last.accepts(snapshot)) {
      pending = last;
      if (snapshot.editRevision >= pending.snapshot.editRevision) {
        pending.snapshot = snapshot;
      }
      // A queued explicit Save remains explicit when an automatic request joins.
      pending.isAutoSave = pending.isAutoSave && isAutoSave;
    } else {
      pending = _PendingSave(snapshot, isAutoSave);
      _pendingSaves.add(pending);
    }
    if (!_drainingSaves) {
      _drainingSaves = true;
      _saveTail = Future<void>.microtask(_drainSaveQueue);
    }
    _publishSaveState();
    return pending.result.future;
  }

  Future<void> _drainSaveQueue() async {
    try {
      while (_pendingSaves.isNotEmpty) {
        final pending = _pendingSaves.removeAt(0);
        OperationResult<void> result;
        try {
          result = await _mutate(
            () => _saveSnapshot(pending.snapshot, pending.isAutoSave),
          );
        } catch (_) {
          // Settle every accepted caller even if an unexpected callback fails.
          if (_ownsSnapshot(pending.snapshot)) {
            _autoSavePaused = true;
            _saveResult(
              const OperationResult.failure(
                OperationOutcome.ioFailure,
                'Save failed; the draft was retained. Retry Save.',
              ),
            );
          }
          result = const OperationResult.failure(
            OperationOutcome.ioFailure,
            'Save failed; the draft was retained. Retry Save.',
          );
        }
        pending.result.complete(result);
      }
    } finally {
      _drainingSaves = false;
      _publishSaveState();
      _flushCommittedRefresh();
    }
  }

  bool _ownsSnapshot(NoteSnapshot snapshot) =>
      !_disposed &&
      _session.canWrite &&
      !_isLocked &&
      snapshot.sessionGeneration == _session.generation &&
      snapshot.credentialGeneration == _session.credentialGeneration;

  Future<OperationResult<void>> _saveSnapshot(
    NoteSnapshot snapshot,
    bool isAutoSave, {
    List<PreparedAttachmentFile> prepared = const [],
    bool generationChange = false,
    bool changesProtection = false,
    FileByteProgress? onProgress,
  }) async {
    if (!_ownsSnapshot(snapshot)) return _cancelledResult();
    if (_persistedCredentialGeneration == snapshot.credentialGeneration &&
        _session.persistedRevision != null &&
        _session.persistedRevision! >= snapshot.editRevision) {
      // This queued request is already covered by our own acknowledged write.
      return _saveResult(const OperationResult.success());
    }
    if (!isAutoSave && !_usesOwnedMutations) setBusy(true);
    _saveWriting = true;
    _saveFailure = null;
    isSavingNotifier.value = true;
    _publishSaveState();
    if (isAutoSave) isAutoSavingNotifier.value = true;
    try {
      var reference =
          snapshot.reference ??
          (_noteReference?.modelId == snapshot.noteId
              ? _noteReference!
              : await _fileService.newNoteReference(snapshot.noteId));
      final acknowledged = _noteReference;
      // Earlier saves in this same session can advance the storage revision
      // after this immutable edit snapshot was captured. Rebase only onto our
      // own acknowledged commit of the identical object, never a fresh read.
      if (reference.storageRevision != null &&
          acknowledged != null &&
          acknowledged.modelId == snapshot.noteId &&
          acknowledged.contentPath == reference.contentPath &&
          acknowledged.binding.root == reference.binding.root &&
          acknowledged.storageOwner?.generation ==
              reference.storageOwner?.generation &&
          acknowledged.storageOwner?.identity ==
              reference.storageOwner?.identity) {
        reference = acknowledged;
      }
      var body = snapshot.body;
      if (!snapshot.reuseStoredBody && snapshot.password != null) {
        body = await _encryptionService.encrypt(
          body,
          password: snapshot.password,
        );
      }
      final metadata = <String, dynamic>{
        ...snapshot.metadata,
        'id': snapshot.noteId,
        'title': snapshot.title,
        'content': body,
        'isLocked': snapshot.password != null,
        'timestamp': snapshot.timestamp,
      };
      if (snapshot.attachmentsChanged) {
        final original = snapshot.metadata['attachments'];
        final legacy =
            original is List && original.isNotEmpty && original.first is String;
        if (legacy && !snapshot.attachments.any((a) => a.mentionId != null)) {
          metadata['attachments'] = snapshot.attachments
              .map((a) => a.id)
              .toList();
        } else {
          final byId = <String, Map<String, dynamic>>{};
          if (original is List) {
            for (final entry in original) {
              if (entry is Map<String, dynamic> && entry['id'] is String) {
                byId[entry['id'] as String] = entry;
              }
            }
          }
          metadata['attachments'] = snapshot.attachments
              .map((a) => {...?byId[a.id], ...a.toJson()})
              .toList();
        }
      }
      final json = jsonEncode(metadata);
      final encoded = snapshot.envelopeKind == NoteEnvelopeKind.legacyJson
          ? json
          : await _encryptionService.encryptApp(json);
      if (!_ownsSnapshot(snapshot)) return _cancelledResult();
      if (generationChange &&
          (changesProtection ||
              _attachments.any(
                (a) => !snapshot.attachments.any((next) => next.id == a.id),
              ))) {
        await _invalidateAttachmentCache(reference);
        if (!_ownsSnapshot(snapshot)) return _cancelledResult();
      }
      final committedReference = generationChange
          ? await (_fileService as TransactionalNoteFiles).commitGeneration(
              reference,
              encoded,
              prepared,
              onProgress: onProgress,
            )
          : await _fileService.writeResolved(reference, encoded);
      if (!_ownsSnapshot(snapshot)) return _cancelledResult();
      _currentFileName = committedReference.fileName;
      _noteReference = committedReference.withModelId(snapshot.noteId);
      _storedNote = NoteModel.fromJson(metadata);
      if (!snapshot.reuseStoredBody) _retainedPlainBody = snapshot.body;
      _retainedMetadata = metadata;
      _persistedCredentialGeneration = snapshot.credentialGeneration;
      if (generationChange) {
        final sameRevision = _session.editRevision == snapshot.editRevision - 1;
        _session = DraftSession(
          generation: _session.generation,
          editRevision: _session.editRevision + 1,
          persistedRevision: snapshot.editRevision,
          credentialGeneration:
              _session.credentialGeneration + (changesProtection ? 1 : 0),
          dirtyFields: sameRevision ? const {} : _session.dirtyFields,
        );
        _persistedCredentialGeneration = _session.credentialGeneration;
        _attachments = List.of(snapshot.attachments);
        _currentPassword = snapshot.password;
        attachmentsNotifier.value = List.of(_attachments);
        _attachmentCache.clear();
        isLockedNotifier.value = _isLocked;
      } else {
        _session = _session.acknowledged(snapshot.editRevision);
      }
      _noteCredentialGenerations[_credentialIdentity(_noteReference!)] =
          _session.credentialGeneration;
      if (snapshot.password != null) {
        _sessionPasswords[reference.fileName] = snapshot.password!;
      } else {
        _sessionPasswords.remove(reference.fileName);
      }
      _autoSavePaused = false;
      if (generationChange) notifyListeners();
      if (_session.isDirty) {
        _scheduleAutoSave();
      } else {
        _cancelAutoSave();
      }
      _markCommittedRefresh(committedReference.binding);
      _saveWriting = false;
      _publishNoteList();
      return _saveResult(const OperationResult.success());
    } on NotePersistenceFailure catch (failure) {
      if (!_ownsSnapshot(snapshot)) return _cancelledResult();
      _autoSavePaused = true;
      return _saveResult(
        OperationResult.failure(
          failure.outcome,
          'Save failed; the draft was retained. Retry Save.',
        ),
      );
    } catch (_) {
      if (!_ownsSnapshot(snapshot)) return _cancelledResult();
      _autoSavePaused = true;
      return _saveResult(
        const OperationResult.failure(
          OperationOutcome.ioFailure,
          'Save failed; the draft was retained. Retry Save.',
        ),
      );
    } finally {
      if (!_disposed) {
        if (!isAutoSave && !_usesOwnedMutations) setBusy(false);
        _saveWriting = false;
        isSavingNotifier.value = false;
        _publishSaveState();
        if (isAutoSave) isAutoSavingNotifier.value = false;
      }
    }
  }

  Future<void> deleteNote(String fileName) async {
    if (_usesOwnedMutations) {
      final reference = await reviewDeletion(fileName);
      if (reference != null) await deleteReviewedNote(reference);
      return;
    }
    if (!ensureExtendedNoteOperations()) return;
    return _libraryTask(() => _deleteNote(fileName), null);
  }

  Future<NoteReference?> reviewDeletion(String fileName) async {
    if (!_usesOwnedMutations) return null;
    for (final reference in pendingDeletionsNotifier.value) {
      if (reference.fileName == fileName) return reference;
    }
    final ready = await _resolveOwnerJobs(DraftTransition.navigation);
    if (!ready.isSuccess) {
      _reportResult(ready);
      return null;
    }
    try {
      final reference = await _fileService.resolveNote(fileName);
      if (reference == null) return null;
      final content = await _fileService.readResolved(reference);
      if (content == null) return null;
      final decoded = await _decodeNote(content);
      return reference.withModelId(decoded.note.id);
    } catch (_) {
      _reportResult(
        const OperationResult.failure(
          OperationOutcome.ioFailure,
          'The note could not be reviewed for deletion.',
        ),
      );
      return null;
    }
  }

  Future<OperationResult<void>> deleteReviewedNote(
    NoteReference reference,
  ) async {
    if (!_usesOwnedMutations ||
        _disposed ||
        _deleting ||
        hasAttachmentJobs ||
        _librarySwitching ||
        _libraryResourcesClosing) {
      return _cancelledResult();
    }
    _deleting = true;
    await _invalidateAttachmentCache(reference);
    final selected =
        _noteReference?.contentPath == reference.contentPath &&
        _noteReference?.binding.root == reference.binding.root;
    _deletingCurrent = selected;
    final wasReadOnly = quillController.readOnly;
    if (selected) quillController.readOnly = true;
    notifyListeners();
    if (selected) _cancelAutoSave();
    final result = await _mutate(() async {
      try {
        final deleted = await (_fileService as TransactionalNoteFiles)
            .deleteResolved(reference);
        if (!_disposed) {
          final retained = pendingDeletionsNotifier.value
              .where((r) => r.contentPath != reference.contentPath)
              .toList();
          if (deleted.outcome == OperationOutcome.recoveryRequired ||
              (!deleted.isSuccess &&
                  pendingDeletionsNotifier.value.any(
                    (r) => r.contentPath == reference.contentPath,
                  ))) {
            retained.add(reference);
          }
          pendingDeletionsNotifier.value = retained;
        }
        if (selected && !_disposed) {
          if (deleted.isSuccess) {
            _resetDraft();
          } else if (deleted.outcome == OperationOutcome.recoveryRequired) {
            _session = DraftSession(
              generation: _session.generation,
              access: DraftAccess.deleted,
              editRevision: _session.editRevision,
              persistedRevision: _session.persistedRevision,
              credentialGeneration: _session.credentialGeneration,
              dirtyFields: _session.dirtyFields,
            );
            notifyListeners();
          }
        }
        if (!_disposed) await loadRecentFiles();
        final progress = deleted.value;
        if (deleted.isSuccess) return const OperationResult<void>.success();
        return OperationResult<void>.failure(
          deleted.outcome,
          progress == null
              ? deleted.message
              : 'Permanent deletion incomplete: ${progress.removed.length} objects removed, ${progress.pending.length} cleanup items pending. Retry Delete.',
        );
      } catch (_) {
        return const OperationResult<void>.failure(
          OperationOutcome.ioFailure,
          'Delete failed; no successful removal is claimed.',
        );
      }
    });
    _deleting = false;
    _deletingCurrent = false;
    if (!_disposed) {
      quillController.readOnly = selected
          ? (!_session.canWrite || _isLocked)
          : wasReadOnly;
      if (_session.isDirty && _session.canWrite) _scheduleAutoSave();
      notifyListeners();
    }
    return _reportResult(
      result.isSuccess ? const OperationResult.success() : result,
    );
  }

  Future<void> _deleteNote(String fileName) async {
    await _fileService.deleteFile(fileName);
    if (_currentFileName == fileName) {
      await reset(discardChanges: true);
    }
    await loadRecentFiles();
  }
  // endregion

  // region Import & Export
  Future<void> releaseImportSelection(PlatformFile file) async {
    if (_fileService is! PickedSourceOwner || file.path == null) return;
    final identity = _fileService is PickedSourceRecovery
        ? (_fileService as PickedSourceRecovery).pickedSourceIdentity(
            file.path!,
          )
        : null;
    await (_fileService as PickedSourceOwner).releasePickedSource(file.path!);
    if (identity != null)
      await (_fileService as PickedSourceRecovery).forgetPickedSource(identity);
  }

  Future<PlatformFile?> pickImportFile() async {
    final result = await _fileService.pickFile(
      allowedExtensions: ['txt', 'enc'],
    );
    return result?.files.single;
  }

  Future<ImportVerificationResult> verifyImportFile(PlatformFile file) async {
    if (_usesOwnedMutations) {
      final path = file.path;
      if (path == null) {
        return ImportVerificationResult(
          isValid: false,
          message: 'A native file is required.',
        );
      }
      try {
        final input = await File(path).open();
        Uint8List header;
        try {
          header = await input.read(6);
        } finally {
          await input.close();
        }
        final binary =
            header.length >= 6 &&
            header[0] == 0x4e &&
            header[1] == 0x4f &&
            header[2] == 0x54 &&
            header[3] == 0x45;
        final zip =
            header.length >= 4 && header[0] == 0x50 && header[1] == 0x4b;
        final suffix = p.extension(file.name).toLowerCase();
        if (binary || zip) {
          return ImportVerificationResult(
            isValid: true,
            message: binary ? 'Binary Note Package' : 'ZIP Note Package',
            isPack: true,
            isPackEncrypted: binary && header[5] == 1,
          );
        }
        if (!['.txt', '.enc'].contains(suffix) ||
            await File(path).length() > StreamingPackService.metadataLimit) {
          return ImportVerificationResult(
            isValid: false,
            message: 'Unsupported file or oversized note metadata.',
          );
        }
        return ImportVerificationResult(
          isValid: true,
          message: suffix == '.txt' ? 'Plain text note' : 'Encrypted note',
        );
      } catch (_) {
        return ImportVerificationResult(
          isValid: false,
          message: 'The import source could not be read.',
        );
      }
    }
    if (file.path == null) {
      return ImportVerificationResult(
        isValid: false,
        message: "File path not found",
      );
    }

    try {
      final fileObj = File(file.path!);
      final ext = file.name.split('.').last.toLowerCase();

      // Handle pack files (binary data)
      if (ext == 'fnote' || ext == 'zip') {
        final data = await fileObj.readAsBytes();
        final packService = PackService(_encryptionService);

        if (ext == 'fnote') {
          if (packService.isPack(data)) {
            final isEncrypted = packService.isEncrypted(data);
            return ImportVerificationResult(
              isValid: true,
              message: "Note Pack File",
              previewInfo:
                  "Format: Binary Pack (.fnote)\nEncrypted: ${isEncrypted ? 'Yes (password required)' : 'No'}",
              isPack: true,
              isPackEncrypted: isEncrypted,
            );
          } else {
            return ImportVerificationResult(
              isValid: false,
              message: "Invalid pack file format",
            );
          }
        } else if (ext == 'zip') {
          if (packService.isZip(data)) {
            return ImportVerificationResult(
              isValid: true,
              message: "ZIP Archive",
              previewInfo: "Format: ZIP Archive\nSize: ${data.length} bytes",
              isPack: true,
              isPackEncrypted: false, // We can't easily detect this for ZIP
            );
          } else {
            return ImportVerificationResult(
              isValid: false,
              message: "Invalid ZIP file",
            );
          }
        }
      }

      // Handle text-based files
      final content = await fileObj.readAsString();

      if (ext == 'enc') {
        try {
          final decoded = await _decodeNote(content);
          final note = decoded.note;
          return ImportVerificationResult(
            isValid: true,
            message: decoded.kind == NoteEnvelopeKind.appEncrypted
                ? 'Valid Encrypted Note'
                : 'Valid Legacy Note',
            previewInfo:
                'Title: ${note.title}\nDate: ${DateTime.fromMillisecondsSinceEpoch(note.timestamp)}',
          );
        } catch (_) {
          return ImportVerificationResult(
            isValid: false,
            message: "Invalid Encryption or Corrupt File",
          );
        }
      } else if (ext == 'txt') {
        // Valid text file
        return ImportVerificationResult(
          isValid: true,
          message: "Plain Text File",
          previewInfo:
              "Size: ${await fileObj.length()} bytes\nPreview: ${content.length > 50 ? content.substring(0, 50) + '...' : content}",
        );
      }

      return ImportVerificationResult(
        isValid: false,
        message: "Unsupported format",
      );
    } catch (e) {
      return ImportVerificationResult(
        isValid: false,
        message: "Error reading file: $e",
      );
    }
  }

  Future<OperationResult<String>> performImport(PlatformFile file) async {
    if (_usesOwnedMutations) {
      if (file.path == null) {
        return const OperationResult.failure(
          OperationOutcome.rejectedInput,
          'A native file is required.',
        );
      }
      return importOwnedFile(
        file.path!,
        plainText: p.extension(file.name).toLowerCase() == '.txt',
      );
    }
    if (!ensureExtendedNoteOperations()) {
      return const OperationResult.failure(
        OperationOutcome.rejectedInput,
        'Import unavailable.',
      );
    }
    await _libraryTask(() => _performImport(file), null);
    return const OperationResult.success();
  }

  Future<void> _performImport(PlatformFile file) async {
    final importedName = await _fileService.importFile(file);
    if (importedName != null) {
      await loadRecentFiles();
    }
  }

  /// Export the current note as a pack file (binary or zip) with optional archive password
  /// Note: Content is packed as-is (preserving original encryption), archive password is separate
  Future<OperationResult<void>> exportNotePack({
    required ExportFormat format,
    String? password,
    String? fileName,
    NoteExportCapture? captured,
  }) async {
    if (_usesOwnedMutations) {
      return _trackOwnedJob(
        _exportOwnedPackage(
          format: format,
          password: password,
          fileName: fileName,
          captured: captured,
        ),
      );
    }
    if (!ensureExtendedNoteOperations()) {
      return const OperationResult.failure(
        OperationOutcome.rejectedInput,
        'Export unavailable.',
      );
    }
    await _libraryTask(
      () => _exportNotePack(format: format, password: password),
      null,
    );
    return const OperationResult.success();
  }

  Future<void> _exportNotePack({
    required ExportFormat format,
    String? password,
  }) async {
    final reference = _noteReference;
    final owner = _session.generation;
    if (reference == null) return;

    setBusy(true);
    try {
      // 1. Get current note data (encrypted)
      final content = await _fileService.readResolved(reference);
      if (content == null) {
        setBusy(false);
        return;
      }

      final decoded = await _decodeNote(content);
      if (_disposed || owner != _session.generation) return;
      final note = decoded.note;

      // 2. Keep the note content as-is (don't decrypt file password protected content)
      // The note.isLocked flag indicates if the CONTENT is password protected
      final exportNote = NoteModel(
        id: note.id,
        title: note.title,
        content: note.content, // Keep encrypted content as-is
        isLocked: note.isLocked, // Preserve lock status
        timestamp: note.timestamp,
        attachments: note.attachments,
      );

      // 3. Gather all attachment data AS-IS (encrypted)
      final attachmentData = <String, Uint8List>{};
      String noteId = note.id;

      for (final attachment in note.attachments) {
        final encryptedBytes = await _fileService.readAttachment(
          noteId,
          attachment.id,
        );
        if (encryptedBytes != null) {
          // Keep attachments encrypted as-is
          attachmentData[attachment.id] = encryptedBytes;
        }
      }

      // 4. Create pack (archive password is separate from file password)
      final packService = PackService(_encryptionService);
      Uint8List packData;
      String extension;

      if (format == ExportFormat.zip) {
        packData = await packService.createZipPack(
          exportNote,
          attachmentData,
          password: password, // This is ARCHIVE password
          noteMetadata: decoded.metadata,
        );
        extension = 'zip';
      } else {
        packData = await packService.createPack(
          exportNote,
          attachmentData,
          password: password, // This is ARCHIVE password
          noteMetadata: decoded.metadata,
        );
        extension = 'fnote';
      }

      // 5. Save or share based on platform
      final safeTitle = note.title.replaceAll(RegExp(r'[^\w\s-]'), '').trim();
      final fileName = '${safeTitle.isEmpty ? "note" : safeTitle}.$extension';

      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        // Desktop: use file picker to save
        final outputPath = await FilePicker.platform.saveFile(
          dialogTitle: 'Save Note Package',
          fileName: fileName,
          type: FileType.custom,
          allowedExtensions: [extension],
        );

        if (outputPath != null) {
          final file = File(outputPath);
          await file.writeAsBytes(packData);
        }
      } else {
        // Mobile: use share sheet
        final tempDir = await getTemporaryDirectory();
        final tempFile = File('${tempDir.path}/$fileName');
        await tempFile.writeAsBytes(packData);
        await Share.shareXFiles([XFile(tempFile.path)], text: note.title);
      }
    } catch (e) {
      print('Error exporting note pack: $e');
    } finally {
      setBusy(false);
    }
  }

  Future<OperationResult<void>> _exportOwnedPackage({
    required ExportFormat format,
    String? password,
    String? fileName,
    String? destination,
    NoteExportCapture? captured,
  }) async {
    final performance = _settings.attachmentPerformance;
    final ready = await _resolveOwnerJobs(DraftTransition.navigation);
    if (!ready.isSuccess) return ready;
    if (_bulkAttachmentJob || _librarySwitching || _disposed || _deleting) {
      return _cancelledResult();
    }
    if (captured == null &&
        (fileName == null || fileName == _currentFileName)) {
      final transition = await prepareTransition(DraftTransition.navigation);
      if (!transition.isSuccess) return _transitionFailure(transition);
    }
    final owner = _session.generation;
    _bulkAttachmentJob = true;
    final files = _fileService as TransactionalNoteFiles;
    final job = _newAttachmentJob(
      const Uuid().v4(),
      'Export package',
      operation: AttachmentJobOperation.export,
      captureRecoveryOwner: false,
    );
    final id = job.progress.value.id;
    final readCancellation = FileReadCancellation();
    _exportReadCancellations[id] = readCancellation;
    void checkCancellation() {
      if (_disposed ||
          owner != _session.generation ||
          readCancellation.cancelled ||
          _cancelledAttachmentJobs.contains(id)) {
        throw const FileJobCancelled();
      }
    }

    Directory? operation;
    String? candidate;
    String? privateExport;
    OperationResult<void> result;
    try {
      checkCancellation();
      _jobPhase(job, AttachmentJobPhase.preparing, detail: 'Preparing export');
      final reference =
          captured?.reference ??
          (fileName == null || fileName == _currentFileName
              ? _noteReference
              : await _fileService.resolveNote(fileName));
      checkCancellation();
      if (reference == null) {
        throw const FormatException('Save the note before exporting.');
      }
      _jobRecovery[id] = {
        'version': 1,
        'target': reference.fileName,
        'library': reference.binding.root,
        'fileName': job.progress.value.fileName,
      };
      attachmentJobsNotifier.value = List.of(attachmentJobsNotifier.value);
      final content = await _fileService.readResolved(reference);
      checkCancellation();
      if (content == null) {
        throw const FormatException('The captured note is unavailable.');
      }
      final decoded = await _decodeNote(content);
      checkCancellation();
      final resolved = reference.withModelId(decoded.note.id);
      final attachments = <String, StreamingFileSource>{};
      final checks = performance.exportChecks(
        mobile: mobileAttachmentExportPolicy,
      );
      final validateBackup = performance.validateBackupExport(
        mobile: mobileAttachmentExportPolicy,
      );
      var attachmentIndex = 0;
      for (final attachment in decoded.note.attachments) {
        checkCancellation();
        attachmentIndex++;
        final detail = checks.checkSource
            ? 'Checking export attachments ($attachmentIndex/${decoded.note.attachments.length})'
            : 'Preparing export files ($attachmentIndex/${decoded.note.attachments.length})';
        _jobPhase(job, AttachmentJobPhase.preparing, detail: detail);
        attachments[attachment.id] = await files.attachmentSource(
          resolved,
          attachment.id,
          cancellation: readCancellation,
          verifyContent: checks.checkSource,
          onProgress: (_, bytes, total) => _jobPhase(
            job,
            AttachmentJobPhase.preparing,
            bytes: bytes,
            total: total,
            detail: detail,
          ),
        );
        checkCancellation();
      }
      final extension = format == ExportFormat.binary ? 'fnote' : 'zip';
      final mobileDestination =
          destination == null && prepareMobilePackageExport;
      final cacheKey = _preparedMobileExports.key([
        resolved.binding.root,
        resolved.contentPath,
        decoded.metadata,
        format.name,
        checks.checkSource,
        checks.verifyOutput,
        validateBackup,
        performance.verifyLargeFileWrites,
        for (final entry in attachments.entries)
          [
            entry.key,
            entry.value.length,
            entry.value.modifiedMicros,
            entry.value.sha256Hex,
          ],
      ], password);
      if (mobileDestination) {
        final cached = await _preparedMobileExports.find(
          resolved.contentPath,
          cacheKey,
        );
        checkCancellation();
        if (cached != null) {
          _preparedMobileExports.reuse(id, cached);
          _jobPhase(
            job,
            AttachmentJobPhase.completed,
            bytes: cached.length,
            total: cached.length,
            detail: 'Using prepared export',
          );
          return _reportResult(const OperationResult.success());
        }
      }
      if (destination == null) {
        _jobPhase(
          job,
          AttachmentJobPhase.preparing,
          detail: mobileDestination
              ? 'Preparing export file'
              : 'Choose export destination',
        );
      }
      destination ??= mobileDestination
          ? await MobileExport.destination(
              noteExportFileName(decoded.note.title, extension),
            )
          : await FilePicker.platform.saveFile(
              dialogTitle: 'Save Note Package',
              fileName: 'note.$extension',
              type: FileType.custom,
              allowedExtensions: [extension],
            );
      if (mobileDestination) privateExport = destination;
      checkCancellation();
      if (destination == null) {
        result = const OperationResult.failure(
          OperationOutcome.cancelled,
          'Export cancelled.',
        );
      } else {
        await _verifyExportDestination(destination);
        final expected = await ExternalFileExport.reviewOwned(
          destination,
          verifyReadback: performance.verifyLargeFileWrites,
        );
        operation = await files.createOperationDirectory(resolved);
        final cancellation = File(p.join(operation.path, 'cancel'));
        _packageCancellationFiles[id] = cancellation;
        checkCancellation();
        candidate = ExternalFileExport.candidatePath(destination);
        _jobPhase(
          job,
          AttachmentJobPhase.preparing,
          detail: 'Writing export package',
        );
        final receipt = await StreamingPackService().exportPackage(
          verifyWrites: performance.verifyLargeFileWrites,
          metadata: decoded.metadata,
          attachments: attachments,
          format: format,
          destination: candidate,
          operationDirectory: operation.path,
          password: password,
          cancellationFile: cancellation.path,
          onProgress: (progress) => _jobPhase(
            job,
            progress.phase == PackageExportPhase.encrypting
                ? AttachmentJobPhase.encrypting
                : progress.phase == PackageExportPhase.verifyingEncryption
                ? AttachmentJobPhase.verifying
                : AttachmentJobPhase.preparing,
            bytes: progress.bytes,
            total: progress.total,
            detail: '${progress.label} · ${progress.fileName}',
          ),
        );
        if (_disposed ||
            owner != _session.generation ||
            _cancelledAttachmentJobs.contains(id)) {
          result = _cancelledResult();
        } else {
          if (validateBackup) {
            _jobPhase(
              job,
              AttachmentJobPhase.verifying,
              detail: 'Validating exported backup',
            );
            // Optional full readback; bounded writes, source revision checks,
            // flush/close and safe destination publication always remain.
            await StreamingPackService().importPackage(
              source: candidate,
              operationDirectory: operation.path,
              password: password,
              cancellationFile: cancellation.path,
            );
          }
          if (_cancelledAttachmentJobs.contains(id)) {
            result = _cancelledResult();
          } else if (!_tryBeginFinalization([job])) {
            result = _cancelledResult();
          } else {
            result = await ExternalFileExport.publishOwned(
              receipt: receipt,
              destination: destination,
              expected: expected,
            );
            if (result.isSuccess && mobileDestination) {
              await _preparedMobileExports.remember(
                job: id,
                note: resolved.contentPath,
                key: cacheKey,
                path: destination,
              );
            }
          }
        }
      }
    } on FileJobCancelled {
      result = const OperationResult.failure(
        OperationOutcome.cancelled,
        'Export cancelled.',
      );
    } on NotePersistenceFailure catch (failure) {
      result = OperationResult.failure(
        readCancellation.cancelled
            ? OperationOutcome.cancelled
            : failure.outcome,
        readCancellation.cancelled
            ? 'Export cancelled.'
            : 'Export failed; no complete backup is claimed.',
      );
    } on FormatException catch (failure) {
      result = OperationResult.failure(
        OperationOutcome.rejectedInput,
        failure.message,
      );
    } catch (_) {
      result = const OperationResult.failure(
        OperationOutcome.ioFailure,
        'Export failed; no complete backup is claimed.',
      );
    } finally {
      _exportReadCancellations.remove(id);
      _packageCancellationFiles.remove(id);
      if (privateExport != null && _preparedMobileExports.forJob(id) == null) {
        try {
          await MobileExport.discardAll([privateExport]);
        } catch (_) {
          /* Startup retries orphan cleanup. */
        }
      }
      if (candidate != null && await File(candidate).exists()) {
        try {
          await File(candidate).delete();
        } catch (_) {
          /* Retain owned candidate. */
        }
      }
      if (operation != null) {
        try {
          await files.removeOperationDirectory(operation);
        } catch (_) {
          /* Retain operation. */
        }
      }
      _bulkAttachmentJob = false;
    }
    _jobPhase(
      job,
      result.isSuccess
          ? AttachmentJobPhase.completed
          : result.outcome == OperationOutcome.cancelled
          ? AttachmentJobPhase.cancelled
          : AttachmentJobPhase.failed,
      error: result.message,
    );
    return _reportResult(result);
  }

  Future<OperationResult<void>> exportOwnedPackageTo(
    String destination, {
    required ExportFormat format,
    String? password,
    String? fileName,
  }) => _trackOwnedJob(
    _exportOwnedPackage(
      format: format,
      password: password,
      fileName: fileName,
      destination: destination,
    ),
  );

  Future<OperationResult<NoteImportResult>> importNoteFile(
    String source, {
    String? archivePassword,
    bool plainText = false,
    ResolveNoteImportConflict? resolveConflict,
  }) => _trackOwnedJob(
    _importOwnedFile(
      source,
      archivePassword: archivePassword,
      plainText: plainText,
      resolveConflict: resolveConflict,
    ),
  );

  /// Compatibility adapter for callers that only need the resolved filename.
  Future<OperationResult<String>> importOwnedFile(
    String source, {
    String? archivePassword,
    bool plainText = false,
    ResolveNoteImportConflict? resolveConflict,
  }) async {
    final result = await importNoteFile(
      source,
      archivePassword: archivePassword,
      plainText: plainText,
      resolveConflict: resolveConflict,
    );
    return result.isSuccess
        ? OperationResult.success(result.value!.fileName)
        : OperationResult.failure(result.outcome, result.message);
  }

  Future<OperationResult<NoteExportCapture>> captureNoteForExport(
    String fileName,
  ) async {
    if (fileName == _currentFileName) {
      final transition = await prepareTransition(DraftTransition.navigation);
      if (!transition.isSuccess) {
        return OperationResult.failure(transition.outcome, transition.message);
      }
    }
    try {
      final reference = await _fileService.resolveNote(fileName);
      if (reference == null) throw const FormatException('Note unavailable.');
      final content = await _fileService.readResolved(reference);
      if (content == null) throw const FormatException('Note unavailable.');
      final decoded = await _decodeNote(content);
      return OperationResult.success(
        NoteExportCapture(reference.withModelId(decoded.note.id), decoded),
      );
    } catch (_) {
      return const OperationResult.failure(
        OperationOutcome.ioFailure,
        'The note could not be captured for export.',
      );
    }
  }

  bool exportHasVerifiedCredential(NoteExportCapture capture) =>
      !capture.note.note.isLocked ||
      (!_isLocked &&
          _currentPassword != null &&
          _noteReference?.contentPath == capture.reference.contentPath &&
          _noteReference?.binding.root == capture.reference.binding.root);

  Future<bool> verifyExportCredential(
    NoteExportCapture capture,
    String password,
  ) async {
    final result = await _encryptionService.decryptResult(
      capture.note.note.content,
      password: password,
    );
    if (!result.isSuccess) return false;
    try {
      _prepareDocument(result.value!).close();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<OperationResult<NoteImportResult>> _importOwnedFile(
    String source, {
    String? archivePassword,
    bool plainText = false,
    ResolveNoteImportConflict? resolveConflict,
  }) async {
    final performance = _settings.attachmentPerformance;
    final ready = await _resolveOwnerJobs(DraftTransition.navigation);
    if (!ready.isSuccess) {
      return OperationResult.failure(ready.outcome, ready.message);
    }
    if (!_usesOwnedMutations ||
        _disposed ||
        _bulkAttachmentJob ||
        _librarySwitching ||
        _deleting) {
      return const OperationResult.failure(
        OperationOutcome.conflict,
        'Finish the active note operation first.',
      );
    }
    final transition = await prepareTransition(DraftTransition.navigation);
    if (!transition.isSuccess) {
      return OperationResult.failure(transition.outcome, transition.message);
    }
    _bulkAttachmentJob = true;
    final owner = _session.generation;
    final files = _fileService as TransactionalNoteFiles;
    final job = _newAttachmentJob(
      const Uuid().v4(),
      'Import package',
      operation: AttachmentJobOperation.import,
    );
    final jobId = job.progress.value.id;
    Directory? operation;
    OperationResult<NoteImportResult> result;
    Document? replacementDocument;
    NoteReference? acknowledged;
    final previousReadOnly = quillController.readOnly;
    try {
      final storageId = const Uuid().v4();
      final freshReference = await _fileService.newNoteReference(storageId);
      var reference = freshReference;
      operation = await files.createOperationDirectory(reference);
      final cancellation = File(p.join(operation.path, 'cancel'));
      _packageCancellationFiles[jobId] = cancellation;
      if (_cancelledAttachmentJobs.contains(jobId)) {
        throw const FileJobCancelled();
      }
      _jobPhase(job, AttachmentJobPhase.preparing);
      FilePackResult imported;
      final sourceName = _fileService is PickedSourceOwner
          ? (_fileService as PickedSourceOwner).sourceDisplayName(source) ??
                source
          : source;
      final extension = p.extension(sourceName).toLowerCase();
      if (plainText || extension == '.enc') {
        if (await File(source).length() > StreamingPackService.metadataLimit) {
          throw const FormatException('Imported note metadata exceeds limit.');
        }
        final text = await File(source).readAsString();
        DecodedNote decoded;
        if (plainText) {
          decoded = NoteCodec.decodeMetadata(
            jsonEncode({
              'id': const Uuid().v4(),
              'title': p.basenameWithoutExtension(sourceName),
              'content': jsonEncode([
                {'insert': text.endsWith('\n') ? text : '$text\n'},
              ]),
              'timestamp': _nowMilliseconds(),
              'isLocked': false,
              'attachments': [],
            }),
          );
        } else {
          decoded = await _decodeNote(text);
        }
        if (decoded.note.attachments.isNotEmpty) {
          throw const FormatException(
            'Loose note import is incomplete: attachments are missing.',
          );
        }
        imported = FilePackResult(decoded, const {});
      } else {
        imported = await StreamingPackService().importPackage(
          source: source,
          operationDirectory: operation.path,
          password: archivePassword,
          verifyWrites: performance.verifyLargeFileWrites,
          cancellationFile: cancellation.path,
          onProgress: (progress) => _jobPhase(
            job,
            progress.phase == PackageImportPhase.decrypting
                ? AttachmentJobPhase.decrypting
                : AttachmentJobPhase.preparing,
            bytes: progress.bytes,
            total: progress.total,
            detail:
                '${progress.label} · File ${progress.fileIndex} of ${progress.fileCount}\n${progress.fileName}',
          ),
        );
      }
      if (!imported.note.note.isLocked) {
        _prepareDocument(imported.note.note.content).close();
      } else {
        final parts = imported.note.note.content.split(':');
        if (parts.length > 2 ||
            (parts.length == 2 && base64Decode(parts.first).length != 16)) {
          throw const FormatException(
            'Imported protected body has invalid framing.',
          );
        }
        final body = base64Decode(parts.last);
        if (body.isEmpty || body.length % 16 != 0) {
          throw const FormatException('Imported protected body is incomplete.');
        }
      }
      // Validate ciphertext framing before duplicate decisions or publication.
      for (final attachment in imported.note.note.attachments) {
        final payload = imported.attachments[attachment.id];
        if (payload == null ||
            payload.length < 32 ||
            (payload.length - 16) % 16 != 0) {
          throw const FormatException(
            'Imported attachment ciphertext is incomplete.',
          );
        }
      }
      var noteId = imported.note.note.id;
      var createDuplicate = false;
      _jobPhase(
        job,
        AttachmentJobPhase.preparing,
        detail: 'Looking for a matching note',
      );
      final importService = NoteImportService(_fileService, _encryptionService);
      final existing = await importService.find(noteId, reference.binding);
      if (existing != null) {
        reference = existing.reference;
        if (resolveConflict == null) {
          _jobPhase(
            job,
            AttachmentJobPhase.failed,
            error: 'Choose Duplicate, Back up & Replace, or Ignore.',
          );
          return const OperationResult.failure(
            OperationOutcome.conflict,
            'This note already exists. Choose Duplicate, Back up & Replace, or Ignore.',
          );
        }
        _jobPhase(
          job,
          AttachmentJobPhase.preparing,
          detail: 'Choose how to import this note',
        );
        final decision = await resolveConflict(
          NoteImportConflict(
            reference,
            existing.decoded.note.title,
            existing.decoded.note.isLocked,
          ),
        );
        if (_disposed ||
            owner != _session.generation ||
            _cancelledAttachmentJobs.contains(jobId)) {
          _jobPhase(job, AttachmentJobPhase.cancelled);
          return const OperationResult.failure(
            OperationOutcome.cancelled,
            'Import cancelled.',
          );
        }
        if (decision == NoteImportDecision.ignore) {
          _jobPhase(job, AttachmentJobPhase.completed);
          return OperationResult.success(
            NoteImportResult(NoteImportDisposition.ignored, reference.fileName),
          );
        }
        if (decision == NoteImportDecision.duplicate) {
          createDuplicate = true;
          noteId = storageId;
          reference = freshReference;
        } else {
          // Keep predecessor availability checks without reading/hashing its
          // payloads. Publication retains the old objects and journals the
          // predecessor envelope; imported attachments receive fresh IDs.
          for (final attachment in existing.decoded.note.attachments) {
            await files.attachmentSource(
              reference,
              attachment.id,
              verifyContent: false,
            );
          }
        }
      }
      final replacing = existing != null && !createDuplicate;
      final replacementKind =
          existing?.decoded.kind ?? NoteEnvelopeKind.appEncrypted;
      final selected =
          replacing &&
          _noteReference?.contentPath == reference.contentPath &&
          _noteReference?.binding.root == reference.binding.root;
      if (selected) {
        replacementDocument = imported.note.note.isLocked
            ? Document()
            : _prepareDocument(imported.note.note.content);
      }
      final prepared = <PreparedAttachmentFile>[];
      final models = <AttachmentModel>[];
      final oldFields = imported.note.metadata['attachments'];
      final preserved = <String, Map<String, dynamic>>{};
      if (oldFields is List) {
        for (final fields in oldFields) {
          if (fields is Map<String, dynamic> && fields['id'] is String) {
            preserved[fields['id'] as String] = fields;
          }
        }
      }
      final newFields = <Map<String, dynamic>>[];
      for (final attachment in imported.note.note.attachments) {
        final payload = imported.attachments[attachment.id];
        if (payload == null ||
            payload.length < 32 ||
            (payload.length - 16) % 16 != 0) {
          throw const FormatException(
            'Imported attachment ciphertext is incomplete.',
          );
        }
        final id = const Uuid().v4();
        prepared.add(
          PreparedAttachmentFile(id, payload, fileName: attachment.fileName),
        );
        final model = AttachmentModel(
          id: id,
          fileName: attachment.fileName,
          size: attachment.size,
          mimeType: attachment.mimeType,
          mentionId: attachment.mentionId,
        );
        models.add(model);
        newFields.add(
          preserved.containsKey(attachment.id)
              ? {...preserved[attachment.id]!, 'id': id}
              : model.toJson(),
        );
      }
      final metadata = <String, dynamic>{
        ...imported.note.metadata,
        'id': noteId,
        'attachments':
            oldFields is List &&
                oldFields.isNotEmpty &&
                oldFields.first is String
            ? models.map((a) => a.id).toList()
            : newFields,
      };
      final json = jsonEncode(metadata);
      final encoded =
          replacing && replacementKind == NoteEnvelopeKind.legacyJson
          ? json
          : await _encryptionService.encryptApp(json);
      var nativeSaved = false;
      if (!kIsWeb &&
          Platform.isAndroid &&
          AndroidNativeCipher.ready &&
          _fileService is AttachmentCandidateOwner &&
          prepared.isNotEmpty) {
        final candidates = _fileService as AttachmentCandidateOwner;
        final first = await candidates.createAttachmentCandidate(
          reference,
          prepared.first.id,
          operation,
          prepared.first.source.length,
        );
        // Unsupported direct sinks keep the existing single-transfer fallback.
        // Never copy to another private intermediate just to copy it again.
        if (first.sink != null) {
          final allBytes = prepared.fold<int>(0, (n, a) => n + a.source.length);
          var saved = 0;
          for (var i = 0; i < prepared.length; i++) {
            if (_cancelledAttachmentJobs.contains(jobId))
              throw const FileJobCancelled();
            final item = prepared[i];
            final target = i == 0
                ? first
                : await candidates.createAttachmentCandidate(
                    reference,
                    item.id,
                    operation,
                    item.source.length,
                  );
            if (target.sink == null) {
              throw const FormatException(
                'The selected provider stopped supporting direct writes.',
              );
            }
            void progress(String phase, int bytes, int total) {
              final current = bytes.clamp(0, item.source.length);
              final state = FileOperationProgress(
                stage: phase == 'Verifying'
                    ? 'Verifying saved file'
                    : 'Saving encrypted files',
                fileName: item.fileName ?? item.id,
                fileIndex: i + 1,
                fileCount: prepared.length,
                bytes: current,
                total: item.source.length,
                overallBytes: saved + current,
                overallTotal: allBytes,
              );
              _jobPhase(
                job,
                AttachmentJobPhase.preparing,
                bytes: state.overallBytes,
                total: state.overallTotal,
                detail:
                    '${state.stage} · File ${state.fileIndex} of ${state.fileCount}\n${state.fileName}',
                fileProgress: state,
              );
            }

            progress('Saving encrypted files', 0, item.source.length);
            final transfer = _attachmentWorker.submit(
              FileTransformRequest(
                source: StreamingFileSource(
                  item.source.path,
                  item.source.length,
                  offset: item.source.offset,
                  sha256Hex:
                      item.source.receipt?.sha256Hex ?? item.source.sha256Hex,
                  modifiedMicros:
                      item.source.receipt?.modifiedMicros ??
                      item.source.modifiedMicros,
                ),
                destination: target.path,
                decryptSource: false,
                encryptDestination: false,
                verifyOutput: performance.verifyLargeFileWrites,
                maxPlaintextBytes: StreamingFileCipher.maxAttachmentBytes + 32,
                expectedPlaintextBytes: item.source.length,
                requireWholeSource: true,
                ownedTarget: target,
              ),
              onProgress: progress,
            );
            _attachmentTransforms[jobId] = transfer;
            OperationResult<CipherFileResult> transferred;
            try {
              transferred = await transfer.result;
            } finally {
              _attachmentTransforms.remove(jobId);
            }
            if (!transferred.isSuccess) {
              if (transferred.outcome == OperationOutcome.cancelled)
                throw const FileJobCancelled();
              throw const FormatException(
                'The encrypted attachment could not be saved.',
              );
            }
            final receipt = transferred.value!.receipt;
            if (receipt == null)
              throw const FormatException(
                'The saved attachment has no write receipt.',
              );
            prepared[i] = PreparedAttachmentFile(
              item.id,
              StreamingFileSource(
                target.path,
                transferred.value!.length,
                receipt: receipt,
              ),
              fileName: item.fileName,
            );
            progress(
              'Saving encrypted files',
              item.source.length,
              item.source.length,
            );
            saved += item.source.length;
          }
          nativeSaved = true;
        }
      }
      result = await _mutate(() async {
        if (_disposed ||
            owner != _session.generation ||
            _cancelledAttachmentJobs.contains(jobId)) {
          return const OperationResult<NoteImportResult>.failure(
            OperationOutcome.cancelled,
            'Import cancelled.',
          );
        }
        _observeRichEdit();
        if (!isTransitionPermitCurrent(transition.value!)) {
          return const OperationResult<NoteImportResult>.failure(
            OperationOutcome.conflict,
            'The draft changed during import; it was retained.',
          );
        }
        final current = await importService.find(noteId, reference.binding);
        if ((!replacing && current != null) ||
            (replacing &&
                (current == null ||
                    current.reference.contentPath != reference.contentPath ||
                    !reference.storageRevision!.matches(
                      current.reference.storageRevision!,
                    )))) {
          return const OperationResult<NoteImportResult>.failure(
            OperationOutcome.conflict,
            'The library changed during confirmation. Import again.',
          );
        }
        // No await between the final draft check and making the selected editor
        // read-only. Autosaves cannot recreate the replaced generation.
        _observeRichEdit();
        if (_disposed ||
            owner != _session.generation ||
            !isTransitionPermitCurrent(transition.value!)) {
          return const OperationResult<NoteImportResult>.failure(
            OperationOutcome.conflict,
            'The draft changed during import; it was retained.',
          );
        }
        if (!_tryBeginFinalization([job])) {
          return const OperationResult<NoteImportResult>.failure(
            OperationOutcome.cancelled,
            'Import cancelled.',
          );
        }
        if (selected) {
          _importCutover = true;
          _conversionRequest++;
          isConvertingNotifier.value = false;
          _cancelAutoSave();
          quillController.readOnly = true;
          notifyListeners();
        }
        var hasFileProgress = false;
        final committed = await files.commitGeneration(
          reference,
          encoded,
          prepared,
          onFileProgress: (progress) {
            hasFileProgress = true;
            if (nativeSaved) {
              _jobPhase(
                job,
                AttachmentJobPhase.finalizing,
                detail:
                    'Finishing import\nSaving note details and recovery information',
                fileProgress: FileOperationProgress(
                  stage: 'Finishing import',
                  fileName: 'Note details',
                  fileIndex: prepared.length,
                  fileCount: prepared.length,
                  bytes: 0,
                  total: 0,
                  overallBytes: 0,
                  overallTotal: 0,
                ),
              );
              return;
            }
            _jobPhase(
              job,
              AttachmentJobPhase.finalizing,
              bytes: progress.total == 0 ? 0 : progress.overallBytes,
              total: progress.total == 0 ? null : progress.overallTotal,
              detail: progress.total == 0
                  ? 'Finishing import\nSaving note details and recovery information'
                  : '${progress.stage} · File ${progress.fileIndex} of ${progress.fileCount}\n${progress.fileName}',
              fileProgress: progress,
            );
          },
          onProgress: (phase, bytes, total) {
            if (!hasFileProgress) {
              _jobPhase(
                job,
                AttachmentJobPhase.finalizing,
                bytes: bytes,
                total: total,
                detail: phase,
              );
            }
          },
        );
        acknowledged = committed.withModelId(noteId);
        _markCommittedRefresh(committed.binding);
        if (replacing) {
          await _invalidateAttachmentCache(reference);
          _sessionPasswords.remove(reference.fileName);
        }
        if (selected && !_disposed) {
          _observeRichEdit();
          if (!isTransitionPermitCurrent(transition.value!)) {
            return OperationResult<NoteImportResult>.partial(
              OperationOutcome.recoveryRequired,
              'The imported version was committed, but newer draft edits were retained.',
              NoteImportResult(
                NoteImportDisposition.replaced,
                committed.fileName,
              ),
            );
          }
          _publishImportedReplacement(
            committed.withModelId(noteId),
            metadata,
            replacementKind,
            replacementDocument!,
          );
          replacementDocument = null;
        }
        return OperationResult<NoteImportResult>.success(
          NoteImportResult(
            createDuplicate
                ? NoteImportDisposition.duplicated
                : replacing
                ? NoteImportDisposition.replaced
                : NoteImportDisposition.created,
            committed.fileName,
          ),
        );
      });
    } on NotePersistenceFailure catch (failure) {
      result = OperationResult.failure(
        failure.outcome,
        'Import failed; the existing note and recovery copies were retained.',
      );
    } on FileJobCancelled {
      result = const OperationResult.failure(
        OperationOutcome.cancelled,
        'Import cancelled.',
      );
    } on FormatException catch (failure) {
      result = OperationResult.failure(
        OperationOutcome.rejectedInput,
        failure.message,
      );
    } catch (_) {
      result = const OperationResult.failure(
        OperationOutcome.ioFailure,
        'Import failed; no existing note was overwritten.',
      );
    } finally {
      _packageCancellationFiles.remove(jobId);
      if (_fileService is PickedSourceOwner) {
        try {
          await (_fileService as PickedSourceOwner).releasePickedSource(source);
        } catch (_) {}
      }
      if (operation != null) {
        try {
          await files.removeOperationDirectory(operation);
        } catch (_) {
          /* Retain operation. */
        }
      }
      _bulkAttachmentJob = false;
      replacementDocument?.close();
      if (!_disposed && _importCutover) {
        _importCutover = false;
        quillController.readOnly = previousReadOnly;
        notifyListeners();
      }
    }
    if (!result.isSuccess && acknowledged != null) {
      // A publication receipt is authoritative even if cache/viewer cleanup
      // failed afterward. Never report this as an untouched original.
      if (!_disposed &&
          _noteReference?.contentPath == acknowledged!.contentPath) {
        _session = DraftSession(
          generation: _session.generation,
          access: DraftAccess.unsupported,
          editRevision: _session.editRevision,
          persistedRevision: _session.persistedRevision,
          credentialGeneration: _session.credentialGeneration,
          dirtyFields: _session.dirtyFields,
        );
        quillController.readOnly = true;
        _sessionPasswords.remove(acknowledged!.fileName);
        notifyListeners();
      }
      result = OperationResult.partial(
        OperationOutcome.recoveryRequired,
        'The imported version was committed and backed up, but the editor could not be refreshed. Your draft was retained; reopen before editing.',
        NoteImportResult(
          NoteImportDisposition.replaced,
          acknowledged!.fileName,
        ),
      );
    }
    _jobPhase(
      job,
      result.isSuccess
          ? AttachmentJobPhase.completed
          : result.outcome == OperationOutcome.cancelled
          ? AttachmentJobPhase.cancelled
          : AttachmentJobPhase.failed,
      error: result.message,
    );
    return result;
  }

  void _publishImportedReplacement(
    NoteReference reference,
    Map<String, dynamic> metadata,
    NoteEnvelopeKind kind,
    Document document,
  ) {
    final note = NoteModel.fromJson(metadata);
    _publishing = true;
    try {
      _unlockRequest++;
      _loadRequest++;
      _currentFileName = reference.fileName;
      _noteReference = reference;
      _currentPassword = null;
      _storedNote = note;
      _retainedMetadata = metadata;
      _retainedPlainBody = note.isLocked ? null : note.content;
      _envelopeKind = kind;
      _noteCredentialGenerations.remove(_credentialIdentity(reference));
      _persistedCredentialGeneration = 0;
      _session = DraftSession(
        generation: ++_nextSessionGeneration,
        access: note.isLocked ? DraftAccess.locked : DraftAccess.editable,
        persistedRevision: 0,
      );
      _isLocked = note.isLocked;
      _isHtmlMode = false;
      _attachments = List.of(note.attachments);
      _attachmentCache.clear();
      _replaceDocument(document);
      htmlController.clear();
      titleController.text = note.title;
      isLockedNotifier.value = _isLocked;
      attachmentsNotifier.value = List.unmodifiable(_attachments);
    } finally {
      _publishing = false;
    }
    notifyListeners();
  }

  /// Import a note pack file (.fnote or .zip)
  /// Returns the noteId on success, null on failure
  /// archivePassword: password to decrypt the archive itself
  /// Content inside is preserved as-is (with original file password encryption if any)
  Future<String?> importNotePack(
    String filePath, {
    String? archivePassword,
  }) async {
    if (_usesOwnedMutations) {
      final result = await _trackOwnedJob(
        importOwnedFile(filePath, archivePassword: archivePassword),
      );
      if (!result.isSuccess) {
        _reportResult(OperationResult.failure(result.outcome, result.message));
      }
      return result.isSuccess ? result.value : null;
    }
    if (!ensureExtendedNoteOperations()) return null;
    return _libraryTask(
      () => _importNotePack(filePath, archivePassword: archivePassword),
      null,
    );
  }

  Future<String?> _importNotePack(
    String filePath, {
    String? archivePassword,
  }) async {
    setBusy(true);
    try {
      final file = File(filePath);
      final data = await file.readAsBytes();

      final packService = PackService(_encryptionService);
      PackResult? result;

      if (packService.isPack(data)) {
        // Binary pack - use archive password to decrypt the pack
        result = await packService.extractPack(data, password: archivePassword);
      } else if (packService.isZip(data)) {
        // ZIP pack - use archive password to decrypt the pack
        result = await packService.extractZipPack(
          data,
          password: archivePassword,
        );
      }

      if (result == null) {
        setBusy(false);
        return null;
      }

      // Save the imported note
      final noteId = const Uuid().v4();

      // Save attachments AS-IS (they're already encrypted with file password)
      final newAttachments = <AttachmentModel>[];
      for (final entry in result.attachments.entries) {
        // Save the encrypted attachment data directly (no re-encryption)
        final attachmentId = await _fileService.saveAttachment(
          entry.value, // Already encrypted with file password
          noteId,
        );

        // Find original attachment model for metadata
        final original = result.note.attachments.firstWhere(
          (a) => a.id == entry.key,
          orElse: () => AttachmentModel(id: entry.key, fileName: 'attachment'),
        );

        newAttachments.add(
          AttachmentModel(
            id: attachmentId,
            fileName: original.fileName,
            size: entry.value.length,
            mimeType: original.mimeType,
            mentionId: original.mentionId,
          ),
        );
      }

      // Create the imported note with original content (encrypted with file password if any)
      final importedNote = NoteModel(
        id: noteId,
        title: result.note.title,
        content: result
            .note
            .content, // Keep content as-is (may be encrypted with file password)
        isLocked: result.note.isLocked, // Preserve original lock status
        timestamp: DateTime.now().millisecondsSinceEpoch,
        attachments: newAttachments,
      );

      final jsonString = json.encode(importedNote.toJson());
      final appEncrypted = await _encryptionService.encryptApp(jsonString);
      await _fileService.saveNoteContent(noteId, appEncrypted);

      await loadRecentFiles();
      setBusy(false);
      return "note_$noteId";
    } catch (e) {
      print('Error importing note pack: $e');
      setBusy(false);
      return null;
    }
  }

  /// Check if a file is an encrypted pack (needs password)
  Future<bool> isPackEncrypted(String filePath) async {
    try {
      final file = File(filePath);
      final input = await file.open();
      final Uint8List data;
      try {
        data = await input.read(6);
      } finally {
        await input.close();
      }
      final packService = PackService(_encryptionService);

      if (packService.isPack(data)) {
        return packService.isEncrypted(data);
      }
      // For ZIP, we try to extract without password first
      // If it fails, it might be encrypted
      return false;
    } catch (e) {
      return false;
    }
  }

  /// Pick a pack file for import
  Future<PlatformFile?> pickImportPackFile() async {
    final result = await _fileService.pickFile(
      allowedExtensions: ['txt', 'enc', 'fnote', 'zip'],
    );
    return result?.files.single;
  }
  // endregion

  // region Helpers
  Document _prepareDocument(String content) {
    final probe = content.trim();
    if (probe.startsWith('[') || probe.startsWith('{')) {
      try {
        final json = jsonDecode(content);
        if (json is! List) {
          throw const FormatException('Unsupported body schema.');
        }
        return Document.fromJson(json);
      } catch (_) {
        throw const FormatException('Invalid structured body.');
      }
    }
    if (probe.startsWith('<')) {
      try {
        return Document.fromDelta(HtmlToDelta().convert(content));
      } catch (_) {
        throw const FormatException('Invalid HTML body.');
      }
    }
    // Probe using trimmed text, but preserve the original boundary whitespace.
    return Document()..insert(0, content);
  }

  Future<OperationResult<void>> reset({bool discardChanges = false}) async {
    if (_librarySwitching) {
      return _reportResult(
        const OperationResult.failure(
          OperationOutcome.conflict,
          'Library switching is in progress.',
        ),
      );
    }
    final owner = _session.generation;
    if (!discardChanges) {
      final resolved = await prepareTransition(DraftTransition.newNote);
      if (!resolved.isSuccess) {
        return _reportResult(_transitionFailure(resolved));
      }
      if (_disposed ||
          owner != _session.generation ||
          !isTransitionPermitCurrent(resolved.value!)) {
        return _cancelledResult();
      }
    }
    if (_disposed) return _cancelledResult();
    _resetDraft();
    return _reportResult(const OperationResult.success());
  }

  void _resetDraft() {
    _retainedPlainBody = null;
    _cancelAutoSave();
    _loadRequest++;
    _unlockRequest++;
    _publishing = true;
    try {
      _currentFileName = null;
      _currentPassword = null;
      _storedNote = null;
      _noteReference = null;
      _draftNoteId = const Uuid().v4();
      _draftTimestamp = null;
      _retainedMetadata = {};
      _envelopeKind = NoteEnvelopeKind.appEncrypted;
      _persistedCredentialGeneration = 0;
      _session = DraftSession(generation: ++_nextSessionGeneration);
      _isLocked = false;
      _isHtmlMode = false;
      _attachments = [];
      _replaceDocument(Document());
      htmlController.clear();
      titleController.text = 'New Note';
      _attachmentCache.clear();
      isLockedNotifier.value = false;
      attachmentsNotifier.value = const [];
    } finally {
      _publishing = false;
    }
    notifyListeners();
  }

  /// Private recovery captures are separate from Save and never create a note.
  /// Passwords remain in memory; protected recovery bodies are password-wrapped
  /// before entering the platform-authenticated recovery journal.
  Future<Map<String, dynamic>?> capturePrivateRecoveryDraft() async {
    _observeRichEdit();
    if (_disposed || _isLocked || !_session.isDirty || !_session.canWrite)
      return null;
    final generation = _session.generation;
    final revision = _session.editRevision;
    final credential = _session.credentialGeneration;
    var body =
        !_session.dirtyFields.contains(DraftField.body) &&
            _retainedPlainBody != null
        ? _retainedPlainBody!
        : _isHtmlMode
        ? htmlController.text
        : jsonEncode(quillController.document.toDelta().toJson());
    final password = _currentPassword;
    final value = <String, dynamic>{
      'version': 1,
      'id': _storedNote?.id ?? _draftNoteId,
      'fileName': _currentFileName,
      'title': titleController.text,
      'timestamp':
          _storedNote?.timestamp ?? (_draftTimestamp ??= _nowMilliseconds()),
      'html': _isHtmlMode,
      'protected': password != null,
      'metadata': Map<String, dynamic>.from(_retainedMetadata),
      'attachments': _attachments
          .where((a) => !a.isLoading)
          .map((a) => a.toJson())
          .toList(),
      'fields': _session.dirtyFields.map((e) => e.name).toList(),
      if (_noteReference?.storageRevision case final base?)
        'base': {
          'length': base.length,
          'sha256': base.sha256Hex,
          'modified': base.modifiedMicros,
        },
    };
    if (password != null)
      body = await _encryptionService.encrypt(body, password: password);
    if (_disposed ||
        generation != _session.generation ||
        revision != _session.editRevision ||
        credential != _session.credentialGeneration ||
        _isLocked)
      return null;
    value['body'] = body;
    return value;
  }

  Future<bool> verifyPrivateRecoveryPassword(
    Map<String, dynamic> draft,
    String password,
  ) async {
    if (draft['protected'] != true) return true;
    final decoded = await _encryptionService.decryptResult(
      draft['body'] as String,
      password: password,
    );
    if (!decoded.isSuccess) return false;
    try {
      _prepareDocument(decoded.value!).close();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<OperationResult<void>> recoverPrivateDraft(
    Map<String, dynamic> draft, {
    String? password,
  }) async {
    Document? prepared;
    try {
      if (_disposed ||
          _session.isDirty ||
          draft['version'] != 1 ||
          draft['id'] is! String ||
          (draft['id'] as String).isEmpty)
        return _cancelledResult();
      final fileName = draft['fileName'] as String?;
      final base = draft['base'] as Map?;
      if (fileName != null) {
        final existing = await _fileService.resolveNote(fileName);
        if (existing == null ||
            base == null ||
            existing.storageRevision?.sha256Hex != base['sha256'] ||
            existing.storageRevision?.length != base['length']) {
          return const OperationResult.failure(
            OperationOutcome.conflict,
            'This note changed after the recovery draft. Its current version was preserved.',
          );
        }
      }
      var body = draft['body'] as String;
      if (draft['protected'] == true) {
        if (password == null)
          return const OperationResult.failure(
            OperationOutcome.rejectedInput,
            'Unlock the protected recovery draft first.',
          );
        final decoded = await _encryptionService.decryptResult(
          body,
          password: password,
        );
        if (!decoded.isSuccess)
          return const OperationResult.failure(
            OperationOutcome.rejectedInput,
            'The recovery password was not accepted.',
          );
        body = decoded.value!;
      }
      prepared = _prepareDocument(body);
      if (fileName != null) {
        final opened = await loadNote(fileName);
        if (!opened.isSuccess) return opened;
        if (_isLocked && (password == null || !await unlockNote(password)))
          return const OperationResult.failure(
            OperationOutcome.rejectedInput,
            'Unlock the existing note before recovery.',
          );
        if (_noteReference?.storageRevision?.sha256Hex != base!['sha256'] ||
            _noteReference?.storageRevision?.length != base['length']) {
          return const OperationResult.failure(
            OperationOutcome.conflict,
            'The note changed during recovery. No recovery edits were applied.',
          );
        }
      } else {
        _resetDraft();
        _draftNoteId = draft['id'] as String;
        _draftTimestamp = draft['timestamp'] as int;
      }
      if (_disposed) return _cancelledResult();
      _cancelAutoSave();
      _publishing = true;
      try {
        _retainedMetadata = Map<String, dynamic>.from(draft['metadata'] as Map);
        _retainedPlainBody = body;
        _currentPassword = draft['protected'] == true ? password : null;
        _isLocked = false;
        _isHtmlMode = draft['html'] == true;
        _replaceDocument(prepared);
        prepared = null;
        htmlController.text = _isHtmlMode ? body : '';
        titleController.text = draft['title'] as String;
        _attachments = (draft['attachments'] as List)
            .map(
              (e) =>
                  AttachmentModel.fromJson(Map<String, dynamic>.from(e as Map)),
            )
            .toList();
        final fields = (draft['fields'] as List)
            .cast<String>()
            .map(DraftField.values.byName)
            .toSet();
        _session = DraftSession(
          generation: ++_nextSessionGeneration,
          editRevision: 1,
          persistedRevision: fileName == null ? null : 0,
          credentialGeneration: _session.credentialGeneration,
          dirtyFields: fields.isEmpty ? {DraftField.body} : fields,
        );
        isLockedNotifier.value = false;
        attachmentsNotifier.value = List.unmodifiable(_attachments);
      } finally {
        _publishing = false;
      }
      _publishSaveState();
      notifyListeners();
      _scheduleAutoSave(); // Existing first-Save guard still protects new drafts.
      return const OperationResult.success();
    } catch (_) {
      return const OperationResult.failure(
        OperationOutcome.recoveryRequired,
        'The private draft could not be restored. Recovery material was retained.',
      );
    } finally {
      prepared?.close();
    }
  }

  // region Lifecycle
  @override
  void dispose() {
    _jobRecovery.clear();
    _settings.attachmentPerformanceNotifier.removeListener(
      _configureAttachmentPerformance,
    );
    unawaited(closeAttachmentCache());
    attachmentCacheNotifier.dispose();
    pendingDeletionsNotifier.dispose();
    for (final transform in _attachmentTransforms.values) {
      unawaited(transform.cancel());
    }
    unawaited(_attachmentWorker.close());
    for (final job in _ownedJobStates) {
      job.dispose();
    }
    for (final job in _retiredJobStates) {
      job.dispose();
    }
    _retiredJobStates.clear();
    attachmentJobsNotifier.dispose();
    _disposed = true;
    _postCommitRefreshBinding = null;
    _pendingSearch = null;
    _conversionRequest++;
    saveStateNotifier.dispose();
    noteListStateNotifier.dispose();
    isConvertingNotifier.dispose();
    _listingPathRequest++;
    _searchGeneration++;
    for (final pending in _pendingSaves) {
      pending.result.complete(_cancelledResult());
    }
    _pendingSaves.clear();
    _loadRequest++;
    _unlockRequest++;
    _autoSaveTimer?.cancel();
    _debounceTimer?.cancel();
    _searchDebounceTimer?.cancel();
    _fileWatcherSubscription?.cancel();
    closeLibraryResources().catchError((Object error) {});
    _documentSubscription?.cancel();
    _backgroundFilesSubscription?.cancel();
    _backgroundErrorsSubscription?.cancel();
    quillController.dispose();
    titleController.dispose();
    htmlController.dispose();
    focusNode.dispose();
    scrollController.dispose();
    _backgroundService?.dispose();
    attachmentsNotifier.dispose();
    isLockedNotifier.dispose();
    isAutoSavingNotifier.dispose();
    isSavingNotifier.dispose();
    progressNotifier.dispose();
    operationResultNotifier.dispose();
    super.dispose();
  }
  // endregion

  void onTextChanged() {
    _recordEdit(DraftField.body);
  }

  void _scheduleAutoSave() {
    _cancelAutoSave();
    if (_disposed ||
        !_session.isPersisted ||
        !_session.canWrite ||
        _isLocked ||
        !_session.isDirty ||
        _autoSavePaused) {
      return;
    }
    final owner = _session.generation;
    _autoSaveTimer = Timer(const Duration(seconds: 2), () async {
      if (_disposed ||
          owner != _session.generation ||
          !_session.canWrite ||
          _isLocked ||
          _autoSavePaused) {
        return;
      }
      await saveNote(isAutoSave: true);
    });
  }

  void _cancelAutoSave() => _autoSaveTimer?.cancel();

  Future<Uint8List?> readAttachment(String attachmentId) {
    final key =
        '${_session.generation}:${_session.credentialGeneration}:$attachmentId';
    final existing = _previewReads[key];
    if (existing != null) return existing;
    late final Future<Uint8List?> reading;
    reading = _readAttachmentPreview(attachmentId).whenComplete(() {
      if (identical(_previewReads[key], reading)) _previewReads.remove(key);
    });
    _previewReads[key] = reading;
    return reading;
  }

  Future<Uint8List?> _readAttachmentPreview(String attachmentId) async {
    if (_disposed || _isLocked) return null;
    final owner = _session.generation;
    final password = _currentPassword;
    if (_currentFileName == null ||
        (!_usesOwnedMutations && !_currentFileName!.startsWith('note_'))) {
      return null;
    }
    final noteId = _currentFileName!.replaceFirst('note_', '');

    if (_attachmentCache.containsKey(attachmentId)) {
      return _attachmentCache[attachmentId];
    }

    Uint8List? encryptedBytes;
    if (_usesOwnedMutations) {
      final reference = _noteReference;
      if (reference == null) return null;
      try {
        final source = await (_fileService as TransactionalNoteFiles)
            .attachmentSource(reference, attachmentId);
        // Large attachments remain stored/exportable and use file cards.
        if (source.length > 8 * 1024 * 1024 + 32) return null;
        final input = await File(source.path).open();
        try {
          encryptedBytes = await input.read(8 * 1024 * 1024 + 33);
        } finally {
          await input.close();
        }
        if (encryptedBytes.length != source.length) return null;
        if (source.sha256Hex != null &&
            await compute(_previewHash, encryptedBytes) != source.sha256Hex) {
          return null;
        }
      } catch (_) {
        return null;
      }
    } else {
      encryptedBytes = await _fileService.readAttachment(noteId, attachmentId);
    }
    if (encryptedBytes == null) return null;

    final decrypted = await _encryptionService.decryptBinaryResult(
      encryptedBytes,
      password: password,
    );
    if (_disposed ||
        _isLocked ||
        owner != _session.generation ||
        password != _currentPassword) {
      return null;
    }
    if (!decrypted.isSuccess) return null;
    _attachmentCache[attachmentId] = decrypted.value!;
    var cacheBytes = _attachmentCache.values.fold<int>(
      0,
      (n, bytes) => n + bytes.length,
    );
    while (cacheBytes > 32 * 1024 * 1024 && _attachmentCache.isNotEmpty) {
      final oldest = _attachmentCache.keys.first;
      cacheBytes -= _attachmentCache.remove(oldest)!.length;
    }
    return decrypted.value!;
  }

  // endregion
}

String _previewHash(Uint8List bytes) => crypto.sha256.convert(bytes).toString();

/// One not-yet-started Save. Coalescing cannot cross a session, credential or
/// captured-object boundary. The active Save is removed from this collection.
class _PendingSave {
  _PendingSave(this.snapshot, this.isAutoSave);

  NoteSnapshot snapshot;
  bool isAutoSave;
  final result = Completer<OperationResult<void>>();

  bool accepts(NoteSnapshot candidate) {
    if (snapshot.sessionGeneration != candidate.sessionGeneration ||
        snapshot.credentialGeneration != candidate.credentialGeneration ||
        snapshot.noteId != candidate.noteId) {
      return false;
    }
    final before = snapshot.reference;
    final after = candidate.reference;
    return before == null ||
        after == null ||
        (before.contentPath == after.contentPath &&
            before.binding.root == after.binding.root &&
            before.storageOwner?.identity == after.storageOwner?.identity &&
            before.storageOwner?.generation == after.storageOwner?.generation);
  }
}

class ImportVerificationResult {
  final bool isValid;
  final String message;
  final String? previewInfo;
  final bool isPack;
  final bool isPackEncrypted;

  ImportVerificationResult({
    required this.isValid,
    required this.message,
    this.previewInfo,
    this.isPack = false,
    this.isPackEncrypted = false,
  });
}

class NoteExportCapture {
  const NoteExportCapture(this.reference, this.note);
  final NoteReference reference;
  final DecodedNote note;
}

Future<List<dynamic>> _htmlToDeltaTask(String html) async {
  final delta = HtmlToDelta().convert(html);
  return delta.toJson();
}

Future<String> _deltaToHtmlTask(List<dynamic> deltaJson) async {
  final options = ConverterOptions.forEmail();
  options.sanitizerOptions.urlSanitizer = FnotesTarget.sanitize;
  final converter = QuillDeltaToHtmlConverter(
    deltaJson.cast<Map<String, dynamic>>(),
    options,
  );
  return formatHtmlSource(converter.convert());
}

class _SearchTicket {
  const _SearchTicket(
    this.generation,
    this.listing,
    this.epoch,
    this.query,
    this.files,
  );
  final int generation;
  final int listing;
  final int epoch;
  final String query;
  final List<RecentFile> files;
}
