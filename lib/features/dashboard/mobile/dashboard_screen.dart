import '../../../core/theme/app_dialog.dart';
import '../models/note_import.dart';
import '../widgets/note_import_dialog.dart';
import '../models/note_list_ui_state.dart';
import '../models/auto_save_policy.dart';
import 'app_settings_dialog.dart';
import 'dart:async';
import 'dart:io';
import 'dart:ui' show AppExitResponse;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'sidebar.dart';
import 'job_notifications.dart';
import 'note_activity.dart';
import 'export_progress_dialog.dart';
import 'work_decision_dialog.dart';
import '../models/attachment_job.dart';
import '../widgets/android_attachment_drop_zone.dart';
import '../widgets/unfinished_work_dialog.dart';
import 'content_area.dart';
import '../widgets/note_opening_overlay.dart';
import '../viewmodels/content_viewmodel.dart';
import '../services/file_service.dart';
import '../services/background_service.dart';
import '../services/encryption_service.dart';
import '../models/note_model.dart';
import '../widgets/import_confirmation_dialog.dart';
import '../widgets/export_options_dialog.dart';
import '../widgets/password_dialog.dart';
import '../services/settings_service.dart';
import '../models/draft_transition.dart';
import '../widgets/draft_decision_dialog.dart';
import '../../../core/operations/operation_result.dart';
import '../../../core/operations/shutdown_sequence.dart';
import '../../../core/platform/attachment_file_actions.dart';
import '../../../core/platform/mobile_job_binding.dart';
import '../../../core/platform/mobile_draft_binding.dart';
import '../../../core/storage/attachment_open_cache.dart';

class MobileDashboardScreen extends StatefulWidget {
  const MobileDashboardScreen({
    super.key,
    this.settings,
    this.fileService,
    this.onClose,
    this.startBackgroundServices = true,
    this.attachmentActions,
    this.attachmentOpenCache,
    this.confirmExit,
    this.mobileLayout,
    this.discovery,
    this.recoveryLibraryId,
    this.jobLibraryIdentity,
    this.loadLibraryDescription,
    this.changeMobileLibrary,
  });

  final SettingsService? settings;
  final IFileService? fileService;
  final Future<OperationResult<void>> Function()? onClose;
  final bool startBackgroundServices;
  final AttachmentFileActions? attachmentActions;
  final AttachmentOpenCache? attachmentOpenCache;
  final Future<bool> Function()? confirmExit;

  /// Injectable for responsive widget tests; production follows the OS.
  final bool? mobileLayout;
  final LibraryDiscovery? discovery;
  final String? recoveryLibraryId;
  final String? jobLibraryIdentity;
  final Future<String> Function()? loadLibraryDescription;
  final Future<OperationResult<void>> Function(
    ContentViewModel,
    Future<void> Function(),
  )?
  changeMobileLibrary;

  @override
  State<MobileDashboardScreen> createState() => _MobileDashboardScreenState();
}

class _MobileDashboardScreenState extends State<MobileDashboardScreen> {
  late final ContentViewModel _viewModel;
  late final AppLifecycleListener _lifecycle;
  Future<AppExitResponse>? _pendingExit;
  bool _shutdownStarted = false;
  ShutdownSequence? _shutdown;
  final _shutdownElapsed = Stopwatch();
  AttachmentFileActions? _desktop;
  MobileJobBinding? _mobileJobs;
  MobileNoteActivityController? _noteActivity;
  MobileDraftBinding? _mobileDraft;
  bool _changingLibrary = false;
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _searchController = TextEditingController();
  final _drawerSearchFocus = FocusNode();
  int _navigationRequest = 0;
  bool _phoneEditor = false;
  final _exportRequests = ValueNotifier<int>(0);
  final _panelDismissals = ValueNotifier<int>(0);
  bool get _exportControlsLocked =>
      _exportRequests.value > 0 || _viewModel.hasActiveExport;

  Future<void> _duringExport(Future<void> Function() action) async {
    _exportRequests.value++;
    try {
      await action();
    } finally {
      if (mounted) _exportRequests.value--;
    }
  }

  final _contentKey = GlobalKey();
  bool get _mobile => widget.mobileLayout ?? true;

  bool _splitLayout(double width) => _mobile
      ? MediaQuery.sizeOf(context).shortestSide >= 600 && width >= 600
      : width > 800;

  void _showPhoneNotes() {
    _panelDismissals.value++;
    FocusScope.of(context).unfocus();
    setState(() => _phoneEditor = false);
  }

  void _focusEditorAfterNavigation() {
    if (_exportControlsLocked) return;
    if (!_mobile) {
      _viewModel.focusNode.requestFocus();
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _phoneEditor && !_viewModel.isLocked)
        _viewModel.focusNode.requestFocus();
    });
  }

  void _queryChanged() => _viewModel.setSearchQuery(_searchController.text);

  void _focusSearch() {
    _showPhoneNotes();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_shutdownStarted && _drawerSearchFocus.context != null)
        _drawerSearchFocus.requestFocus();
    });
  }

  Future<void> _handleFileSelected(
    RecentFile file,
    NoteListUiState inventory,
    bool drawer,
  ) async {
    _panelDismissals.value++;
    // Returning to the retained editor is presentation-only. A different note
    // would replace the session that owns the export, so keep its existing guard.
    final export = _activeExport();
    if (export != null && _viewModel.currentContentPath != file.fullPath) {
      await _showExportProgress(existingJob: export);
      return;
    }
    final request = ++_navigationRequest;
    final result = await _viewModel.openListedNote(
      file,
      inventory.libraryEpoch,
    );
    if (!mounted ||
        request != _navigationRequest ||
        !result.isSuccess ||
        _viewModel.currentContentPath != file.fullPath) {
      return;
    }
    if (drawer && (_scaffoldKey.currentState?.isDrawerOpen ?? false)) {
      Navigator.pop(context);
    }
    if (_mobile) setState(() => _phoneEditor = true);
    _focusEditorAfterNavigation();
  }

  Widget _buildNotesList() => ValueListenableBuilder<NoteListUiState>(
    valueListenable: _viewModel.noteListStateNotifier,
    builder: (context, inventory, _) => ListenableBuilder(
      listenable: _viewModel.attachmentJobsNotifier,
      builder: (context, _) => ValueListenableBuilder<int>(
        valueListenable: _mobileJobs?.notificationCount ?? _noJobNotifications,
        builder: (context, count, _) => MobileNotesList(
          listState: inventory,
          activity: _noteActivity,
          searchController: _searchController,
          searchFocusNode: _drawerSearchFocus,
          onSearchChanged: _viewModel.setSearchQuery,
          onFileSelected: (file) => _handleFileSelected(file, inventory, false),
          onNewNote: () => unawaited(_handleNewNote()),
          onImport: _handleImport,
          notificationCount: count,
          activeJobCount: _mobileJobs?.activeCount,
          onNotifications: _showJobNotifications,
          onSettings: () => _showMasterSettings(context),
          onRefresh: _viewModel.loadRecentFiles,
          onRetrySearch: _viewModel.retrySearch,
          onDelete: _handleDelete,
          onExport: _handleExportPack,
          onExportProgress: _activeExport() == null
              ? null
              : () => unawaited(_handleEditorExport()),
        ),
      ),
    ),
  );

  final _noJobNotifications = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    _desktop = widget.attachmentActions;
    _viewModel = ContentViewModel(
      fileService: widget.fileService ?? FileService(settings: widget.settings),
      settings: widget.settings,
      encryptionService: EncryptionService(),
      onDraftDecision: _showDraftDecision,
      startBackgroundServices: widget.startBackgroundServices,
      desktopActions: _desktop,
      attachmentOpenCache: widget.attachmentOpenCache,
      backgroundService: widget.discovery,
      autoSavePolicy: AutoSavePolicy.mobile,
    );
    _lifecycle = AppLifecycleListener(
      onExitRequested: _requestExit,
      onStateChange: (state) => _viewModel.setAutomaticSavingActive(
        state == AppLifecycleState.resumed,
      ),
    );
    final library = widget.jobLibraryIdentity;
    if (library != null) {
      _noteActivity = MobileNoteActivityController(
        jobs: _viewModel.attachmentJobsNotifier,
        library: library,
        ownerOf: (id) =>
            NoteJobOwner.fromRecovery(_viewModel.attachmentJobRecovery(id)),
      );
    }
    if ((Platform.isAndroid || Platform.isIOS) &&
        widget.startBackgroundServices) {
      _mobileJobs = MobileJobBinding(
        _viewModel,
        onNotification: (id) => unawaited(_openJobNotification(id)),
      );
    }
    unawaited(_viewModel.initializeAttachmentCache());
    _viewModel.operationResultNotifier.addListener(_showOperationFailure);
    _searchController.addListener(_queryChanged);
    if ((Platform.isAndroid || Platform.isIOS) &&
        widget.recoveryLibraryId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _mobileDraft = MobileDraftBinding(
          model: _viewModel,
          library: widget.recoveryLibraryId!,
          context: () => context,
          onRecovered: () {
            if (mounted) setState(() => _phoneEditor = true);
          },
        );
      });
    }
  }

  bool _jobNotificationOpen = false;

  AttachmentJobState? _activeExport({String? id}) {
    for (final state in _viewModel.attachmentJobsNotifier.value) {
      final job = state.progress.value;
      if (job.active &&
          job.operation == AttachmentJobOperation.export &&
          (id == null || job.id == id))
        return state;
    }
    return null;
  }

  Future<void> _openJobNotification(String id) async {
    final jobs = _mobileJobs;
    if (jobs == null || _jobNotificationOpen) return;
    await jobs.interrupted;
    await WidgetsBinding.instance.endOfFrame;
    await _mobileDraft?.restored;
    if (!mounted) return;
    if (jobs.retained.value.any((record) => record['id'] == id)) {
      await _showInterruptedJob(id);
    } else {
      await _showJobNotifications(selectedId: id);
    }
  }

  Future<void> _showJobNotifications({String? selectedId}) async {
    final jobs = _mobileJobs;
    if (jobs == null || _jobNotificationOpen) return;
    _panelDismissals.value++;
    final export = selectedId == null ? null : _activeExport(id: selectedId);
    if (export != null) {
      await _showExportProgress(existingJob: export);
      return;
    }
    _jobNotificationOpen = true;
    String? selected;
    try {
      selected = await showAppDialog<String>(
        context: context,
        builder: (_) => MobileJobNotifications(
          jobs: jobs,
          model: _viewModel,
          selectedId: selectedId,
        ),
      );
    } finally {
      _jobNotificationOpen = false;
    }
    if (mounted && selected != null) {
      final export = _activeExport(id: selected);
      if (export != null) {
        await _showExportProgress(existingJob: export);
      } else {
        await _showInterruptedJob(selected);
      }
    }
  }

  Future<void> _showInterruptedJob(String id) async {
    _panelDismissals.value++;
    final jobs = _mobileJobs;
    if (jobs == null || _jobNotificationOpen) return;
    await jobs.interrupted;
    await _mobileDraft?.restored;
    if (!mounted || !jobs.retained.value.any((record) => record['id'] == id))
      return;
    _jobNotificationOpen = true;
    try {
      await showAppDialog<void>(
        context: context,
        builder: (_) => UnfinishedWorkDialog(
          jobs: jobs,
          jobId: id,
          model: _viewModel,
          onOpenNote: () {
            if (mounted) {
              setState(() => _phoneEditor = true);
              _focusEditorAfterNavigation();
            }
          },
        ),
      );
    } finally {
      _jobNotificationOpen = false;
    }
  }

  Future<DraftDecision> _showDraftDecision(DraftDecisionRequest request) async {
    if (!mounted) return DraftDecision.cancel;
    final decision = await showAppDialog<DraftDecision>(
      context: context,
      barrierDismissible: false,
      builder: (_) => request.kind == DraftDecisionKind.activeAttachments
          ? MobileWorkDecisionDialog(
              model: _viewModel,
              transition: request.transition,
            )
          : DraftDecisionDialog(request: request),
    );
    return mounted ? decision ?? DraftDecision.cancel : DraftDecision.cancel;
  }

  void _showOperationFailure() {
    if (!mounted) return;
    final result = _viewModel.operationResultNotifier.value;
    if (result == null ||
        result.isSuccess ||
        result.outcome == OperationOutcome.cancelled) {
      return;
    }
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(
          result.message ?? 'The operation could not be completed.',
        ),
      ),
    );
  }

  Future<AppExitResponse> _requestExit() async {
    if (_pendingExit != null) return _pendingExit!;
    final operation = _resolveExit();
    _pendingExit = operation;
    try {
      return await operation;
    } finally {
      _pendingExit = null;
    }
  }

  Future<AppExitResponse> _resolveExit() async {
    try {
      if (!_shutdownStarted) {
        // The transition coordinator prompts only for work that needs a
        // decision. A saved, idle app can proceed directly to orderly cleanup.
        final confirmed =
            await (widget.confirmExit?.call() ?? Future.value(true));
        if (!mounted || !confirmed) return AppExitResponse.cancel;
        final result = await _viewModel.prepareToExit();
        if (!mounted || !result.isSuccess) {
          return AppExitResponse.cancel;
        }
      }
      final close = widget.onClose;
      await _mobileDraft?.clear();
      await _viewModel.closeAttachmentCache();
      if (close == null) {
        return AppExitResponse.exit;
      }
      // Keep the editor mounted but non-writable, including after partial
      // cleanup. Flutter's current exit snapshot still owns its listeners.
      FocusManager.instance.primaryFocus?.unfocus();
      setState(() => _shutdownStarted = true);
      final shutdown = _shutdown ??= ShutdownSequence(
        closeWatchers: _viewModel.closeLibraryResources,
        closeStorage: close,
        onPhase: _onShutdownPhase,
      );
      final closed = await shutdown.closeForExit(
        onSlow: () {
          if (mounted) {
            _showShutdownNotice(
              'Closing is taking longer than expected. '
              'The window will close when cleanup finishes.',
            );
          }
        },
      );
      if (closed.isSuccess) {
        debugPrint('Storage shutdown: mobile cleanup complete.');
        return AppExitResponse.exit;
      }
    } catch (_) {
      // Retain owned handles for a subsequent orderly close attempt.
    }
    if (mounted) {
      _showShutdownNotice(
        'Storage cleanup is incomplete. Close the window again to retry.',
      );
    }
    return AppExitResponse.cancel;
  }

  void _showShutdownNotice(String message) {
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(message)));
  }

  void _onShutdownPhase(ShutdownPhase phase) {
    _shutdownElapsed.start();
    debugPrint(
      'Storage shutdown: ${phase.name} '
      'at ${_shutdownElapsed.elapsedMilliseconds} ms',
    );
    if (phase == ShutdownPhase.complete || phase == ShutdownPhase.failed) {
      _shutdownElapsed.stop();
    }
  }

  Future<void> _handleNewNote({bool closeDrawer = false}) async {
    _panelDismissals.value++;
    final result = await _viewModel.reset();
    if (!mounted || !result.isSuccess) return;
    if (closeDrawer && Navigator.canPop(context)) {
      Navigator.pop(context);
    }
    if (_mobile) setState(() => _phoneEditor = true);
    _focusEditorAfterNavigation();
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(
        content: Text(
          'New draft ready. Edit it, then select Save to create the note.',
        ),
      ),
    );
  }

  @override
  void dispose() {
    _exportRequests.dispose();
    _panelDismissals.dispose();
    _mobileDraft?.dispose();
    _mobileJobs?.dispose();
    _noteActivity?.dispose();
    _noJobNotifications.dispose();
    unawaited(_desktop?.dispose());
    _lifecycle.dispose();
    _viewModel.operationResultNotifier.removeListener(_showOperationFailure);
    _viewModel.dispose();
    _searchController.dispose();
    _drawerSearchFocus.dispose();
    super.dispose();
  }

  Future<void> _handleDelete(RecentFile file) async {
    if (_viewModel.usesOwnedStorage) {
      final reference = await _viewModel.reviewDeletion(file.path);
      if (!mounted || reference == null) return;
      final confirmed = await showAppDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Delete Note?'),
          content: const Text(
            'Permanently remove this note and its app-managed recovery copies?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Delete'),
            ),
          ],
        ),
      );
      if (mounted && confirmed == true) {
        await _viewModel.deleteReviewedNote(reference);
      }
      return;
    }
    if (!_viewModel.ensureExtendedNoteOperations()) return;
    _viewModel.deleteNote(file.path);
  }

  Future<OperationResult<void>?> _showExportProgress({
    String? noteTitle,
    Future<OperationResult<void>> Function()? start,
    AttachmentJobState? existingJob,
  }) async {
    if (_jobNotificationOpen || !mounted) return null;
    _panelDismissals.value++;
    _jobNotificationOpen = true;
    return showMobileExportProgress(
      context: context,
      model: _viewModel,
      noteTitle: noteTitle,
      start: start,
      existingJob: existingJob,
      onHidden: () => _jobNotificationOpen = false,
    );
  }

  Future<void> _handleEditorExport() => _duringExport(_exportFromEditor);

  Future<void> _exportFromEditor() async {
    final export = _activeExport();
    if (export != null) {
      await _showExportProgress(existingJob: export);
      return;
    }
    if (!_viewModel.ensureExtendedNoteOperations()) return;
    final owner = _viewModel.draftSession.generation;
    if (_viewModel.currentFileName == null) {
      final save = await showAppDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Save before exporting?'),
          content: const Text(
            'Save this new note, then choose its export options.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save & Export'),
            ),
          ],
        ),
      );
      if (!mounted ||
          save != true ||
          owner != _viewModel.draftSession.generation)
        return;
      final saved = await _viewModel.saveNote(allowEmptyFirstSave: true);
      if (!mounted ||
          !saved.isSuccess ||
          owner != _viewModel.draftSession.generation)
        return;
    }
    final name = _viewModel.currentFileName;
    final path = _viewModel.currentContentPath;
    if (name == null || path == null || !mounted) return;
    await _handleExportPack(
      RecentFile(
        path: name,
        fullPath: path,
        title: _viewModel.titleController.text,
      ),
    );
  }

  Future<void> _handleExportPack(RecentFile file) async {
    final export = _activeExport();
    if (export != null) {
      await _showExportProgress(existingJob: export);
      return;
    }
    // Retain the exported note's editor before the worker pins its session.
    // Returning from the list then needs no reload, cancellation or second owner.
    final loaded = await _viewModel.loadNote(file.path);
    if (!mounted || !loaded.isSuccess) return;
    await _duringExport(() => _exportPack(file));
  }

  Future<void> _exportPack(RecentFile file) async {
    if (_viewModel.usesOwnedStorage) {
      final export = _activeExport();
      if (export != null) {
        await _showExportProgress(existingJob: export);
        return;
      }
      final review = await _viewModel.captureNoteForExport(file.path);
      if (!mounted) return;
      if (!review.isSuccess) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(review.message ?? 'Export unavailable.')),
        );
        return;
      }
      final captured = review.value!;
      if (!_viewModel.exportHasVerifiedCredential(captured)) {
        final verified = await showAppDialog<String>(
          context: context,
          builder: (_) => PasswordDialog(
            title: 'Verify password for export',
            description:
                'Confirm this note password before exporting its encrypted contents.',
            onVerifyCurrent: (password) =>
                _viewModel.verifyExportCredential(captured, password),
            onConfirm: (_) {},
          ),
        );
        if (!mounted || verified == null) return;
      }
      final options = await showAppDialog<ExportOptions>(
        context: context,
        builder: (_) => ExportOptionsDialog(
          hasAttachments: captured.note.note.attachments.isNotEmpty,
        ),
      );
      if (!mounted || options == null) return;
      final result = await _showExportProgress(
        noteTitle: file.title,
        start: () => _viewModel.exportNotePack(
          format: options.format,
          password: options.password,
          fileName: file.path,
          captured: captured,
        ),
      );
      if (!mounted ||
          result == null ||
          result.outcome == OperationOutcome.cancelled)
        return;
      if (_jobNotificationOpen)
        return; // Result is visible in its retained dialog.
      if (result.isSuccess && ModalRoute.of(context)?.isCurrent == true) {
        final ready = _viewModel.attachmentJobsNotifier.value
            .where(
              (state) =>
                  _viewModel.preparedExportForJob(state.progress.value.id) !=
                  null,
            )
            .lastOrNull;
        if (ready != null) {
          await _showExportProgress(noteTitle: file.title, existingJob: ready);
          return;
        }
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.isSuccess
                ? 'Complete note package exported.'
                : result.message ?? 'Export failed.',
          ),
        ),
      );
      return;
    }
    if (!_viewModel.ensureExtendedNoteOperations()) return;
    // Close the sidebar first on mobile
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    }

    // First load the note so we have access to attachments and metadata
    final loaded = await _viewModel.loadNote(file.path);

    if (!mounted) return;
    if (!loaded.isSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            loaded.message ?? 'The requested note could not be opened.',
          ),
        ),
      );
      return;
    }

    // If note is locked, require password to export
    if (_viewModel.isLocked) {
      final unlocked = await _showUnlockForExportDialog();
      if (!unlocked) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Cannot export: incorrect file password or cancelled',
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
    }

    if (!mounted) return;

    // Show export options dialog
    final options = await showAppDialog<ExportOptions>(
      context: context,
      builder: (context) => ExportOptionsDialog(
        hasAttachments: _viewModel.attachments.isNotEmpty,
      ),
    );

    if (options == null) return;

    if (!mounted) return;

    // Show loading indicator
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            ),
            SizedBox(width: 12),
            Text('Preparing export...'),
          ],
        ),
        duration: Duration(seconds: 30),
      ),
    );

    try {
      // Export runs in background (uses compute internally)
      await _viewModel.exportNotePack(
        format: options.format,
        password: options.password,
      );

      if (!mounted) return;

      // Hide loading and show success
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Export ready! Share sheet will appear.'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Export failed: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<bool> _showUnlockForExportDialog() async {
    final passwordController = TextEditingController();
    String? errorText;

    final result = await showAppDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: const Color(0xFF161E2D),
          title: const Text(
            'Unlock to Export',
            style: TextStyle(color: Colors.white),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'This note is password protected. Enter the password to export.',
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: passwordController,
                autofocus: true,
                obscureText: true,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Password',
                  labelStyle: const TextStyle(color: Colors.grey),
                  filled: true,
                  fillColor: const Color(0xFF1E293B),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFF334155)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFF334155)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Colors.blueAccent),
                  ),
                  errorText: errorText,
                  errorStyle: const TextStyle(color: Colors.redAccent),
                ),
                onSubmitted: (value) async {
                  final success = await _viewModel.unlockNote(value);
                  if (success) {
                    Navigator.pop(context, true);
                  } else {
                    setState(() => errorText = 'Incorrect password');
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final success = await _viewModel.unlockNote(
                  passwordController.text,
                );
                if (success) {
                  Navigator.pop(context, true);
                } else {
                  setState(() => errorText = 'Incorrect password');
                }
              },
              child: const Text('Unlock'),
            ),
          ],
        ),
      ),
    );
    // Don't dispose controller here - it may still be referenced during rebuild
    // It will be garbage collected automatically
    return result ?? false;
  }

  Future<void> _handleImport() async {
    _panelDismissals.value++;
    if (!_viewModel.ensureExtendedNoteOperations()) return;
    // Close the drawer first on mobile
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    }

    final file = await _viewModel.pickImportPackFile();
    if (file == null) return;
    try {
      if (!mounted) return;

      // Verify the file
      final verification = await _viewModel.verifyImportFile(file);

      if (!mounted) return;

      if (!verification.isValid) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Invalid file: ${verification.message}'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // Show confirmation dialog
      final shouldImport = await showAppDialog<bool>(
        context: context,
        builder: (context) => ImportConfirmationDialog(
          fileName: file.name,
          fileType: verification.message,
          previewInfo: verification.previewInfo,
        ),
      );

      if (shouldImport != true) return;

      if (!mounted) return;

      if (_viewModel.usesOwnedStorage) {
        String? password;
        if (verification.isPack) {
          password = await _showPackPasswordDialog(
            isRequired: verification.isPackEncrypted,
          );
          if (password == null || !mounted) return;
        }
        final result = await showAppDialog<OperationResult<NoteImportResult>>(
          context: context,
          barrierDismissible: false,
          builder: (_) => NoteImportDialog(
            fileName: file.name,
            detailedProgress: true,
            jobs: _viewModel.attachmentJobsNotifier,
            cancelJob: _viewModel.cancelAttachmentJob,
            startImport: (resolveConflict) => _viewModel.importNoteFile(
              file.path!,
              archivePassword: password,
              plainText:
                  !verification.isPack &&
                  file.extension?.toLowerCase() == 'txt',
              resolveConflict: resolveConflict,
            ),
          ),
        );
        if (!mounted || result == null) return;
        if (result.isSuccess &&
            result.value!.disposition != NoteImportDisposition.ignored) {
          await _viewModel.loadNote(result.value!.fileName);
        }
        return;
      }

      String? importedNoteId;
      String? errorMessage;

      if (verification.isPack) {
        // Handle pack file import - always ask for optional archive password
        final password = await _showPackPasswordDialog(
          isRequired: verification.isPackEncrypted,
        );

        // If password is required and user cancelled, abort
        if (password == null) {
          return;
        }

        // Import runs in background (uses compute internally)
        importedNoteId = await _viewModel.importNotePack(
          file.path!,
          archivePassword: password,
        );

        if (importedNoteId == null) {
          // Determine error reason
          if (password.isNotEmpty) {
            errorMessage = 'Import failed - incorrect archive password';
          } else {
            errorMessage = 'Import failed - archive may be password protected';
          }
        }
      } else {
        // Handle regular file import
        final result = await _viewModel.performImport(file);
        importedNoteId = result.isSuccess ? result.value ?? 'success' : null;
        if (!result.isSuccess) errorMessage = result.message;
      }

      if (!mounted) return;

      // Show result message
      if (importedNoteId != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('File imported successfully!'),
            backgroundColor: Colors.green,
          ),
        );

        // Load the imported file if we have a real ID
        if (importedNoteId != 'success') {
          await _viewModel.loadNote(importedNoteId);
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage ?? 'Import failed'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      try {
        await _viewModel.releaseImportSelection(file);
      } catch (_) {
        /* Provider close also retires source leases. */
      }
    }
  }

  Future<String?> _showPackPasswordDialog({bool isRequired = false}) async {
    final passwordController = TextEditingController();

    final result = await showAppDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF161E2D),
        title: Text(
          isRequired ? 'Enter Archive Password' : 'Archive Password (Optional)',
          style: const TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              isRequired
                  ? 'This archive is password protected. Enter the password to import.'
                  : 'If this archive has a password, enter it below. Leave empty if no password.',
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: passwordController,
              autofocus: true,
              obscureText: true,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Archive Password',
                hintText: isRequired ? null : 'Leave empty if no password',
                hintStyle: const TextStyle(color: Colors.grey),
                labelStyle: const TextStyle(color: Colors.grey),
                filled: true,
                fillColor: const Color(0xFF1E293B),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFF334155)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFF334155)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Colors.blueAccent),
                ),
              ),
              onSubmitted: (value) => Navigator.pop(context, value),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('Cancel'),
          ),
          if (!isRequired)
            TextButton(
              onPressed: () => Navigator.pop(context, ''),
              child: const Text('Skip'),
            ),
          FilledButton(
            onPressed: () => Navigator.pop(context, passwordController.text),
            child: const Text('Import'),
          ),
        ],
      ),
    );

    // Don't dispose controller here - it will be garbage collected
    // Null means Cancel; an empty string is an explicit no-password import.
    return result;
  }

  void _showMasterSettings(BuildContext context) {
    _panelDismissals.value++;
    showAppDialog<void>(
      context: context,
      builder: (_) => AppSettingsDialog(
        settings: _viewModel.settings,
        pickLibrary: () => FilePicker.platform.getDirectoryPath(),
        openLibrary: _viewModel.switchLibrary,
        loadLibraryPath: widget.loadLibraryDescription,
        changeLibrary: widget.changeMobileLibrary == null
            ? null
            : () async {
                setState(() => _changingLibrary = true);
                try {
                  return await widget.changeMobileLibrary!(
                    _viewModel,
                    () async {
                      await _mobileDraft?.retireResolvedDraft();
                    },
                  );
                } finally {
                  if (mounted) setState(() => _changingLibrary = false);
                }
              },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // These ancestors remain present before and during closing. Replacing the
    // editor would dispose listeners still in Flutter's exit-request snapshot.
    return AbsorbPointer(
      absorbing: _shutdownStarted || _changingLibrary,
      child: ExcludeFocus(
        excluding: _shutdownStarted,
        child: AndroidAttachmentDropZone(
          model: _viewModel,
          exportRequests: _exportRequests,
          child: _buildDashboard(context),
        ),
      ),
    );
  }

  Widget _buildDashboard(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      _viewModel,
      _viewModel.isLockedNotifier,
      _viewModel.attachmentJobsNotifier,
    ]),
    builder: (context, _) => CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyF, control: true):
            _focusSearch,
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): () {
          if (!_shutdownStarted && !_exportControlsLocked)
            _viewModel.saveNote();
        },
        const SingleActivator(LogicalKeyboardKey.keyN, control: true): () {
          if (!_shutdownStarted && !_exportControlsLocked)
            unawaited(_handleNewNote());
        },
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final split = _splitLayout(constraints.maxWidth);
          final editor = ExcludeFocus(
            excluding: !split && !_phoneEditor,
            child: TickerMode(
              enabled: split || _phoneEditor,
              child: MobileContentArea(
                key: _contentKey,
                viewModel: _viewModel,
                jobNotificationCount: _mobileJobs?.notificationCount,
                activeJobCount: _mobileJobs?.activeCount,
                onJobNotifications: _showJobNotifications,
                onExport: _handleEditorExport,
                exportRequests: _exportRequests,
                dismissPanels: _panelDismissals,
                onBack: split ? null : _showPhoneNotes,
              ),
            ),
          );
          return PopScope(
            canPop: split || !_phoneEditor,
            onPopInvokedWithResult: (didPop, result) {
              if (!didPop && !split && _phoneEditor) _showPhoneNotes();
            },
            child: Scaffold(
              key: _scaffoldKey,
              resizeToAvoidBottomInset: true,
              body: SafeArea(
                child: Stack(
                  children: [
                    if (split)
                      Row(
                        children: [
                          SizedBox(width: 320, child: _buildNotesList()),
                          const VerticalDivider(width: 1),
                          Expanded(child: editor),
                        ],
                      )
                    else
                      IndexedStack(
                        index: _phoneEditor ? 1 : 0,
                        children: [
                          ExcludeFocus(
                            excluding: _phoneEditor,
                            child: TickerMode(
                              enabled: !_phoneEditor,
                              child: _buildNotesList(),
                            ),
                          ),
                          editor,
                        ],
                      ),
                    if (_viewModel.isBusy && _viewModel.isOpeningNote)
                      const Positioned.fill(child: NoteOpeningOverlay())
                    else if (_viewModel.isBusy)
                      const Positioned.fill(
                        child: ColoredBox(
                          color: Color(0x66000000),
                          child: Center(child: CircularProgressIndicator()),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
}
