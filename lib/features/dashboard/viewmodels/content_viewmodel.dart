import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
// import 'dart:io'; // duplicate removed
import 'package:file_picker/file_picker.dart';
import '../../../core/viewmodels/base_viewmodel.dart';
import '../services/file_service.dart';
import '../services/background_service.dart';
import '../services/encryption_service.dart';
import '../models/note_model.dart';
import 'dart:convert';
import 'package:flutter_quill/flutter_quill.dart';
// Removed invalid quill_delta import
import 'package:vsc_quill_delta_to_html/vsc_quill_delta_to_html.dart';
import 'package:flutter_quill_delta_from_html/flutter_quill_delta_from_html.dart';
import 'package:uuid/uuid.dart';
import 'package:code_text_field/code_text_field.dart';
import 'package:highlight/languages/xml.dart'; // XML handles HTML highlighting
import 'dart:typed_data';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import '../services/settings_service.dart';
import '../services/pack_service.dart';
import '../../../core/operations/operation_result.dart';
import '../models/draft_session.dart';
import '../models/draft_transition.dart';
import '../models/note_envelope.dart' show DecodedNote;
import '../services/note_codec.dart';
import '../../../core/storage/note_reference.dart';
import '../../../core/storage/owned_note_persistence.dart';
import '../../../core/storage/library_watch.dart';
import '../../../core/storage/owned_settings_persistence.dart';
import 'package:path/path.dart' as p;

typedef RecentFileFilter =
    Future<List<RecentFile>> Function(List<RecentFile> files, String query);

class ContentViewModel extends BaseViewModel {
  final IFileService _fileService;
  final IEncryptionService _encryptionService;
  final SettingsService _settings;
  final int Function() _nowMilliseconds;
  final DraftDecisionHandler? _onDraftDecision;
  final RecentFileFilter _filterRecentFiles;
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
  final BackgroundService? _backgroundService;
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
  int _activeLoads = 0;
  int _persistedCredentialGeneration = 0;
  String _observedHtml = '';
  String _observedTitle = 'New Note';
  Object? _observedRichDelta;
  NoteModel? _storedNote;
  NoteReference? _noteReference;
  String _draftNoteId = const Uuid().v4();
  int? _draftTimestamp;
  Map<String, dynamic> _retainedMetadata = {};
  NoteEnvelopeKind _envelopeKind = NoteEnvelopeKind.appEncrypted;
  Future<void> _saveTail = Future<void>.value();
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

  /// Progress notifier for long-running operations like password change/removal.
  /// Format: "status message" or null when not in progress
  final ValueNotifier<String?> progressNotifier = ValueNotifier(null);

  final Map<String, String> _sessionPasswords = {};
  final Map<String, Uint8List> _attachmentCache = {};
  bool _isLocked = false;

  bool get isLocked => _isLocked;

  String _searchQuery = "";

  List<RecentFile> get recentFiles =>
      _searchQuery.isEmpty ? _recentFiles : _filteredFiles;
  List<AttachmentModel> get attachments => _attachments;
  bool get isPasswordSet => _currentPassword != null;
  String? get currentFileName => _currentFileName;

  late final CodeController htmlController;
  bool _isHtmlMode = false;
  bool get isHtmlMode => _isHtmlMode;

  Future<void> pickAttachment() async {
    if (!ensureExtendedNoteOperations()) return;
    return _libraryTask(_pickAttachment, null);
  }

  Future<T> _libraryTask<T>(Future<T> Function() action, T rejected) async {
    if (_disposed || _librarySwitching) return rejected;
    _librarySensitiveJobs++;
    try {
      return await action();
    } finally {
      _librarySensitiveJobs--;
    }
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
    if (!ensureExtendedNoteOperations()) return;
    return _libraryTask(() => _exportAttachment(attachment), null);
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

  void removeAttachment(String attachmentId) {
    if (!ensureExtendedNoteOperations()) return;
    if (_librarySwitching) return;
    if (_disposed || !_session.canWrite || _isLocked) return;
    if (!_attachments.any((a) => a.id == attachmentId)) return;
    _attachments.removeWhere((a) => a.id == attachmentId);
    attachmentsNotifier.value = List.from(_attachments);
    _attachmentCache.remove(attachmentId);
    // notifyListeners();
    _recordEdit(DraftField.attachments);
    // TODO: Physically delete the attachment file to clean up storage
  }

  // region Initialization
  ContentViewModel({
    required IFileService fileService,
    required IEncryptionService encryptionService,
    SettingsService? settings,
    bool startBackgroundServices = true,
    int Function()? nowMilliseconds,
    DraftDecisionHandler? onDraftDecision,
    BackgroundService? backgroundService,
    RecentFileFilter? filterRecentFiles,
  }) : _fileService = fileService,
       _encryptionService = encryptionService,
       _settings = settings ?? SettingsService(),
       _nowMilliseconds = nowMilliseconds ?? _systemMilliseconds,
       _onDraftDecision = onDraftDecision,
       _filterRecentFiles = filterRecentFiles ?? _defaultFilterRecentFiles,
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
    if (startBackgroundServices) _initAsync();
  }

  static int _systemMilliseconds() => DateTime.now().millisecondsSinceEpoch;

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
  }

  Future<void> handleLinkClick(String url) async {
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
    return _libraryTask(_toggleEditorMode, null);
  }

  Future<void> _toggleEditorMode() async {
    if (_disposed || !_session.canWrite || _isLocked) return;
    _observeRichEdit();
    final owner = _session.generation;
    final revision = _session.editRevision;
    setBusy(true);
    try {
      if (_isHtmlMode) {
        final html = htmlController.text;
        final deltaList = await compute(_htmlToDeltaTask, html);
        if (_disposed ||
            owner != _session.generation ||
            revision != _session.editRevision)
          return;
        final document = Document.fromJson(deltaList);
        _publishing = true;
        try {
          _replaceDocument(document);
          _isHtmlMode = false;
        } finally {
          _publishing = false;
        }
      } else {
        final delta = quillController.document.toDelta();
        final html = await compute(_deltaToHtmlTask, delta.toJson());
        _observeRichEdit();
        if (_disposed ||
            owner != _session.generation ||
            revision != _session.editRevision)
          return;
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
    } catch (_) {
      _reportResult(
        const OperationResult.failure(
          OperationOutcome.rejectedInput,
          'Editor conversion failed; the draft was retained.',
        ),
      );
    } finally {
      if (!_disposed) setBusy(false);
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
      _listingRevision++;
      _restartSearch();
      notifyListeners();
    });
    _backgroundErrorsSubscription = background.errorsStream.listen((failure) {
      if (!_disposed) _reportResult(failure);
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
          _debounceTimer = Timer(const Duration(seconds: 2), loadRecentFiles);
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
    if (_disposed ||
        _libraryResourcesClosing ||
        _librarySwitching ||
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
          _recentFiles = [];
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
  Future<void> loadRecentFiles() async {
    if (_disposed || _libraryResourcesClosing || _backgroundService == null) {
      return;
    }
    final request = ++_listingPathRequest;
    _backgroundService.invalidateRequests();
    try {
      final path = await _fileService.getUserDataPath();
      if (path.isNotEmpty && !_disposed && request == _listingPathRequest) {
        if (_fileService is LibraryFileService &&
            !_librarySwitching &&
            !kIsWeb) {
          await _bindLibraryWatch(StorageBinding(path, request));
          if (_disposed || request != _listingPathRequest) return;
        }
        _backgroundService.loadRecentFiles(path);
      }
    } on BackgroundServiceFailure catch (failure) {
      if (!_disposed && request == _listingPathRequest) {
        _reportResult(
          OperationResult.failure(
            failure.outcome,
            'Library discovery is unavailable. Retry refresh.',
          ),
        );
      }
    } catch (_) {
      if (!_disposed && request == _listingPathRequest) {
        _reportResult(
          const OperationResult.failure(
            OperationOutcome.ioFailure,
            'Library discovery failed. Retry refresh.',
          ),
        );
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

  Future<OperationResult<void>> loadNote(String fileName) async {
    if (_disposed)
      return const OperationResult.failure(
        OperationOutcome.cancelled,
        'Editor was closed.',
      );
    if (fileName == _currentFileName && !_loading) {
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
      if (content == null)
        return _reportResult(
          const OperationResult.failure(
            OperationOutcome.ioFailure,
            'The selected note could not be read.',
          ),
        );
      final prospective = await _decodeNote(content);
      final note = prospective.note;
      final resolvedReference = reference!.withModelId(note.id);
      String? password;
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
        document = _prepareDocument(note.content);
      }
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
        _currentFileName = fileName;
        _currentPassword = password;
        _storedNote = note;
        _noteReference = resolvedReference;
        _retainedMetadata = prospective.metadata;
        _envelopeKind = prospective.kind;
        _persistedCredentialGeneration = 0;
        _session = DraftSession(
          generation: ++_nextSessionGeneration,
          access: locked ? DraftAccess.locked : DraftAccess.editable,
          persistedRevision: 0,
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
      if (_disposed || request != _loadRequest || owner != _session.generation)
        return _cancelledResult();
      return _reportResult(
        const OperationResult.failure(
          OperationOutcome.rejectedInput,
          'Unsupported or damaged note; the previous draft was retained.',
        ),
      );
    } catch (_) {
      if (_disposed || request != _loadRequest || owner != _session.generation)
        return _cancelledResult();
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
  void setPassword(String password) {
    if (!ensureExtendedNoteOperations()) return;
    if (_librarySwitching) return;
    if (_disposed || !_session.canWrite || _isLocked) return;
    _currentPassword = password;
    _recordEdit(DraftField.protection);
    notifyListeners();
  }

  void clearPassword() {
    if (!ensureExtendedNoteOperations()) return;
    if (_librarySwitching) return;
    if (_disposed || !_session.canWrite || _isLocked) return;
    _currentPassword = null;
    _recordEdit(DraftField.protection);
    notifyListeners();
  }

  /// Removes password protection from the current note.
  /// Decrypts all attachments and saves the note without encryption.
  /// If [password] is provided, it will be used instead of the stored password.
  Future<bool> removePassword({String? password}) async {
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

  Future<bool> unlockNote(String password) async {
    return _libraryTask(() => _unlockNote(password), false);
  }

  Future<bool> _unlockNote(String password) async {
    if (_disposed || _currentFileName == null || _storedNote == null)
      return false;
    if (!_isLocked) return _currentPassword == password;
    final owner = _session.generation;
    final request = ++_unlockRequest;
    try {
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
      _publishing = true;
      try {
        _currentPassword = password;
        _sessionPasswords[_currentFileName!] = password;
        _session = DraftSession(
          generation: ++_nextSessionGeneration,
          persistedRevision: _session.persistedRevision,
          editRevision: _session.editRevision,
          credentialGeneration: _session.credentialGeneration,
        );
        _isLocked = false;
        _replaceDocument(document);
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
        !isTransitionPermitCurrent(resolved.value!))
      return _cancelledResult();
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
    _loading = false;
    _publishing = true;
    try {
      _sessionPasswords.remove(_currentFileName);
      _currentPassword = null;
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
    if (!ensureExtendedNoteOperations())
      return 'Password changes are unavailable in this storage preview.';
    return _libraryTask(
      () => _changePassword(newPassword, oldPassword: oldPassword),
      'Library switching is in progress.',
    );
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
    if (_disposed || query == _searchQuery) {
      return;
    }
    _searchQuery = query;
    _restartSearch();
    notifyListeners();
  }

  void _restartSearch() {
    _searchDebounceTimer?.cancel();
    final generation = ++_searchGeneration;
    _filteredFiles = const [];
    if (_searchQuery.isEmpty) {
      return;
    }
    final query = _searchQuery;
    final listing = _listingRevision;
    final files = List<RecentFile>.unmodifiable(_recentFiles);
    _searchDebounceTimer = Timer(const Duration(milliseconds: 300), () async {
      if (!_ownsSearch(generation, listing, query)) {
        return;
      }
      try {
        final results = await _filterRecentFiles(files, query);
        if (!_ownsSearch(generation, listing, query)) {
          return;
        }
        _filteredFiles = List<RecentFile>.unmodifiable(results);
        notifyListeners();
      } catch (_) {
        if (_ownsSearch(generation, listing, query)) {
          _reportResult(
            const OperationResult.failure(
              OperationOutcome.ioFailure,
              'Note search failed. Retry search.',
            ),
          );
        }
      }
    });
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
  Future<OperationResult<void>> saveNote({bool isAutoSave = false}) {
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
        _reportResult(
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
    if (!_session.isDirty) {
      return Future.value(
        _reportResult(
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
        _reportResult(
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
    return pending.result.future;
  }

  Future<void> _drainSaveQueue() async {
    try {
      while (_pendingSaves.isNotEmpty) {
        final pending = _pendingSaves.removeAt(0);
        OperationResult<void> result;
        try {
          result = await _saveSnapshot(pending.snapshot, pending.isAutoSave);
        } catch (_) {
          // Settle every accepted caller even if an unexpected callback fails.
          if (_ownsSnapshot(pending.snapshot)) _autoSavePaused = true;
          result = const OperationResult.failure(
            OperationOutcome.ioFailure,
            'Save failed; the draft was retained. Retry Save.',
          );
        }
        pending.result.complete(result);
      }
    } finally {
      _drainingSaves = false;
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
    bool isAutoSave,
  ) async {
    if (!_ownsSnapshot(snapshot)) return _cancelledResult();
    if (_persistedCredentialGeneration == snapshot.credentialGeneration &&
        _session.persistedRevision != null &&
        _session.persistedRevision! >= snapshot.editRevision) {
      // This queued request is already covered by our own acknowledged write.
      return _reportResult(const OperationResult.success());
    }
    if (!isAutoSave) setBusy(true);
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
        if (legacy) {
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
      final committedReference = await _fileService.writeResolved(
        reference,
        encoded,
      );
      if (!_ownsSnapshot(snapshot)) return _cancelledResult();
      _currentFileName = committedReference.fileName;
      _noteReference = committedReference.withModelId(snapshot.noteId);
      _storedNote = NoteModel.fromJson(metadata);
      _retainedMetadata = metadata;
      _persistedCredentialGeneration = snapshot.credentialGeneration;
      _session = _session.acknowledged(snapshot.editRevision);
      if (snapshot.password != null) {
        _sessionPasswords[reference.fileName] = snapshot.password!;
      } else {
        _sessionPasswords.remove(reference.fileName);
      }
      _autoSavePaused = false;
      if (_session.isDirty) {
        _scheduleAutoSave();
      } else {
        _cancelAutoSave();
      }
      await loadRecentFiles();
      return _reportResult(const OperationResult.success());
    } on NotePersistenceFailure catch (failure) {
      if (!_ownsSnapshot(snapshot)) return _cancelledResult();
      _autoSavePaused = true;
      return _reportResult(
        OperationResult.failure(
          failure.outcome,
          'Save failed; the draft was retained. Retry Save.',
        ),
      );
    } catch (_) {
      if (!_ownsSnapshot(snapshot)) return _cancelledResult();
      _autoSavePaused = true;
      return _reportResult(
        const OperationResult.failure(
          OperationOutcome.ioFailure,
          'Save failed; the draft was retained. Retry Save.',
        ),
      );
    } finally {
      if (!_disposed) {
        if (!isAutoSave) setBusy(false);
        if (isAutoSave) isAutoSavingNotifier.value = false;
      }
    }
  }

  Future<void> deleteNote(String fileName) async {
    if (!ensureExtendedNoteOperations()) return;
    return _libraryTask(() => _deleteNote(fileName), null);
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
  Future<PlatformFile?> pickImportFile() async {
    final result = await _fileService.pickFile(
      allowedExtensions: ['txt', 'enc'],
    );
    return result?.files.single;
  }

  Future<ImportVerificationResult> verifyImportFile(PlatformFile file) async {
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

  Future<void> performImport(PlatformFile file) async {
    if (!ensureExtendedNoteOperations()) return;
    return _libraryTask(() => _performImport(file), null);
  }

  Future<void> _performImport(PlatformFile file) async {
    final importedName = await _fileService.importFile(file);
    if (importedName != null) {
      await loadRecentFiles();
    }
  }

  /// Export the current note as a pack file (binary or zip) with optional archive password
  /// Note: Content is packed as-is (preserving original encryption), archive password is separate
  Future<void> exportNotePack({
    required ExportFormat format,
    String? password,
  }) async {
    if (!ensureExtendedNoteOperations()) return;
    return _libraryTask(
      () => _exportNotePack(format: format, password: password),
      null,
    );
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

  /// Import a note pack file (.fnote or .zip)
  /// Returns the noteId on success, null on failure
  /// archivePassword: password to decrypt the archive itself
  /// Content inside is preserved as-is (with original file password encryption if any)
  Future<String?> importNotePack(
    String filePath, {
    String? archivePassword,
  }) async {
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
      final data = await file.readAsBytes();
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
        if (json is! List)
          throw const FormatException('Unsupported body schema.');
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
      if (!resolved.isSuccess)
        return _reportResult(_transitionFailure(resolved));
      if (_disposed ||
          owner != _session.generation ||
          !isTransitionPermitCurrent(resolved.value!))
        return _cancelledResult();
    }
    if (_disposed) return _cancelledResult();
    _resetDraft();
    return _reportResult(const OperationResult.success());
  }

  void _resetDraft() {
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

  // region Lifecycle
  @override
  void dispose() {
    _disposed = true;
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
        _autoSavePaused)
      return;
    final owner = _session.generation;
    _autoSaveTimer = Timer(const Duration(seconds: 2), () async {
      if (_disposed ||
          owner != _session.generation ||
          !_session.canWrite ||
          _isLocked ||
          _autoSavePaused)
        return;
      await saveNote(isAutoSave: true);
    });
  }

  void _cancelAutoSave() => _autoSaveTimer?.cancel();

  Future<Uint8List?> readAttachment(String attachmentId) async {
    if (_disposed || _isLocked) return null;
    final owner = _session.generation;
    final password = _currentPassword;
    if (_currentFileName == null || !_currentFileName!.startsWith('note_'))
      return null;
    final noteId = _currentFileName!.replaceFirst('note_', '');

    if (_attachmentCache.containsKey(attachmentId)) {
      return _attachmentCache[attachmentId];
    }

    final encryptedBytes = await _fileService.readAttachment(
      noteId,
      attachmentId,
    );
    if (encryptedBytes == null) return null;

    final decrypted = await _encryptionService.decryptBinaryResult(
      encryptedBytes,
      password: password,
    );
    if (_disposed ||
        _isLocked ||
        owner != _session.generation ||
        password != _currentPassword)
      return null;
    if (!decrypted.isSuccess) return null;
    _attachmentCache[attachmentId] = decrypted.value!;
    return decrypted.value!;
  }

  // endregion
}

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

Future<List<dynamic>> _htmlToDeltaTask(String html) async {
  final delta = HtmlToDelta().convert(html);
  return delta.toJson();
}

Future<String> _deltaToHtmlTask(List<dynamic> deltaJson) async {
  final converter = QuillDeltaToHtmlConverter(
    deltaJson.cast<Map<String, dynamic>>(),
    ConverterOptions.forEmail(),
  );
  return converter.convert();
}
