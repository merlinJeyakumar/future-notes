import '../models/note_import.dart';
import '../widgets/note_import_dialog.dart';
import '../models/note_list_ui_state.dart';
import '../widgets/app_settings_dialog.dart';
import 'dart:async';
import 'dart:io';
import 'dart:ui' show AppExitResponse, AppExitType;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import '../widgets/sidebar.dart';
import '../widgets/content_area.dart';
import '../viewmodels/content_viewmodel.dart';
import '../services/file_service.dart';
import '../services/encryption_service.dart';
import '../models/note_model.dart';
import '../widgets/import_confirmation_dialog.dart';
import '../widgets/export_options_dialog.dart';
import '../widgets/password_dialog.dart';
import '../services/settings_service.dart';
import '../../../core/theme/app_theme.dart';
import '../models/draft_transition.dart';
import '../widgets/draft_decision_dialog.dart';
import '../../../core/operations/operation_result.dart';
import '../../../core/operations/shutdown_sequence.dart';
import '../../../core/platform/windows_desktop_actions.dart';
import '../../../core/storage/attachment_open_cache.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    this.settings,
    this.fileService,
    this.onClose,
    this.startBackgroundServices = true,
    this.desktopActions,
    this.attachmentOpenCache,
    this.requestApplicationExit,
    this.confirmExit,
  });

  final SettingsService? settings;
  final IFileService? fileService;
  final Future<OperationResult<void>> Function()? onClose;
  final bool startBackgroundServices;
  final DesktopActions? desktopActions;
  final AttachmentOpenCache? attachmentOpenCache;
  final Future<AppExitResponse> Function()? requestApplicationExit;
  final Future<bool> Function()? confirmExit;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late final ContentViewModel _viewModel;
  late final AppLifecycleListener _lifecycle;
  Future<AppExitResponse>? _pendingExit;
  bool _isSidebarVisible = true;
  bool _shutdownStarted = false;
  ShutdownSequence? _shutdown;
  final _shutdownElapsed = Stopwatch();
  DesktopActions? _desktop;
  StreamSubscription<String>? _desktopEvents;
  bool _exitFromTray = false;
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _searchController = TextEditingController();
  final _desktopSearchFocus = FocusNode();
  final _drawerSearchFocus = FocusNode();
  final _sidebarToggleFocus = FocusNode(debugLabel: 'sidebar-toggle');
  int _navigationRequest = 0;

  void _queryChanged() => _viewModel.setSearchQuery(_searchController.text);

  Widget _buildSidebarToggle(ThemeData theme) => Container(
    height: 48,
    color: theme.appSidebar,
    alignment: Alignment.centerLeft,
    padding: const EdgeInsets.symmetric(horizontal: 8),
    child: IconButton(
      focusNode: _sidebarToggleFocus,
      tooltip: _isSidebarVisible ? 'Hide notes' : 'Show notes',
      isSelected: _isSidebarVisible,
      onPressed: () {
        setState(() => _isSidebarVisible = !_isSidebarVisible);
        // Hiding a focused search removes its node. Keep focus inside the
        // dashboard shortcut scope so Ctrl+F can reveal it again.
        _sidebarToggleFocus.requestFocus();
      },
      style: IconButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        minimumSize: const Size(48, 48),
      ),
      icon: Icon(
        Icons.view_sidebar_outlined,
        size: 18,
        color: theme.appTextSecondary,
      ),
    ),
  );

  void _focusSearch() {
    final desktop = MediaQuery.sizeOf(context).width > 800;
    if (desktop) {
      setState(() => _isSidebarVisible = true);
    } else {
      _scaffoldKey.currentState?.openDrawer();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _shutdownStarted) return;
      final focus = desktop ? _desktopSearchFocus : _drawerSearchFocus;
      if (focus.context != null) focus.requestFocus();
    });
  }

  Future<void> _handleFileSelected(
    RecentFile file,
    NoteListUiState inventory,
    bool drawer,
  ) async {
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
    _viewModel.focusNode.requestFocus();
  }

  Widget _buildSidebar({required bool drawer}) =>
      ValueListenableBuilder<NoteListUiState>(
        valueListenable: _viewModel.noteListStateNotifier,
        builder: (context, inventory, _) => Sidebar(
          listState: inventory,
          searchController: _searchController,
          searchFocusNode: drawer ? _drawerSearchFocus : _desktopSearchFocus,
          onSearchChanged: _viewModel.setSearchQuery,
          onRetrySearch: _viewModel.retrySearch,
          onFileSelected: (_) {},
          onRecentFileSelected: (file) =>
              _handleFileSelected(file, inventory, drawer),
          onOpenFolder: _handleOpenFolder,
          onDelete: _handleDelete,
          onNewNote: () => unawaited(_handleNewNote(closeDrawer: drawer)),
          onImportNote: _handleImport,
          onSettings: () => _showMasterSettings(context),
          onRefresh: _viewModel.loadRecentFiles,
          onExportPack: _handleExportPack,
        ),
      );

  @override
  void initState() {
    super.initState();
    _desktop =
        widget.desktopActions ??
        (Platform.isWindows && widget.startBackgroundServices
            ? WindowsDesktopActions()
            : null);
    _viewModel = ContentViewModel(
      fileService: widget.fileService ?? FileService(settings: widget.settings),
      settings: widget.settings,
      encryptionService: EncryptionService(),
      onDraftDecision: _showDraftDecision,
      startBackgroundServices: widget.startBackgroundServices,
      desktopActions: _desktop,
      attachmentOpenCache: widget.attachmentOpenCache,
    );
    _lifecycle = AppLifecycleListener(onExitRequested: _requestExit);
    _desktopEvents = _desktop?.events.listen((event) async {
      if (event == 'trayExit' && !_exitFromTray) {
        _exitFromTray = true;
        try {
          if (widget.requestApplicationExit != null) {
            await widget.requestApplicationExit!();
          } else {
            await ServicesBinding.instance.exitApplication(
              AppExitType.cancelable,
            );
          }
        } finally {
          _exitFromTray = false;
        }
      }
    });
    unawaited(_viewModel.initializeAttachmentCache());
    _viewModel.operationResultNotifier.addListener(_showOperationFailure);
    _searchController.addListener(_queryChanged);
  }

  Future<DraftDecision> _showDraftDecision(DraftDecisionRequest request) async {
    if (!mounted) return DraftDecision.cancel;
    final decision = await showDialog<DraftDecision>(
      context: context,
      barrierDismissible: false,
      builder: (_) => DraftDecisionDialog(request: request),
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
        final confirmed = await (widget.confirmExit?.call() ?? _confirmExit());
        if (!mounted || !confirmed) return AppExitResponse.cancel;
        final result = await _viewModel.prepareToExit();
        if (!mounted || !result.isSuccess) {
          return AppExitResponse.cancel;
        }
      }
      final close = widget.onClose;
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
        debugPrint('Storage shutdown: returning exit to Windows.');
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

  Future<bool> _confirmExit() async =>
      await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Exit Future Notes?'),
          content: const Text(
            'Exit the app completely? Unsaved changes and active attachment '
            'operations will be handled before closing.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Keep open'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Exit'),
            ),
          ],
        ),
      ) ??
      false;

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
    final result = await _viewModel.reset();
    if (!mounted || !result.isSuccess) return;
    if (closeDrawer && Navigator.canPop(context)) {
      Navigator.pop(context);
    }
    _viewModel.focusNode.requestFocus();
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
    unawaited(_desktopEvents?.cancel());
    unawaited(_desktop?.dispose());
    _lifecycle.dispose();
    _viewModel.operationResultNotifier.removeListener(_showOperationFailure);
    _viewModel.dispose();
    _searchController.dispose();
    _desktopSearchFocus.dispose();
    _drawerSearchFocus.dispose();
    _sidebarToggleFocus.dispose();
    super.dispose();
  }

  Future<void> _handleOpenFolder(RecentFile file) async {
    final fullPath = file.fullPath;
    final normalizedPath = fullPath.replaceAll(
      '/',
      '\\',
    ); // Windows consistency

    if (Platform.isWindows) {
      await Process.run('explorer.exe', ['/select,', normalizedPath]);
    } else {
      // Fallback or other platforms
      print("Show in folder not implemented for this platform");
    }
  }

  Future<void> _handleDelete(RecentFile file) async {
    if (_viewModel.usesOwnedStorage) {
      final reference = await _viewModel.reviewDeletion(file.path);
      if (!mounted || reference == null) return;
      final confirmed = await showDialog<bool>(
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

  Future<void> _handleExportPack(RecentFile file) async {
    if (_viewModel.usesOwnedStorage) {
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
        final verified = await showDialog<String>(
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
      final options = await showDialog<ExportOptions>(
        context: context,
        builder: (_) => ExportOptionsDialog(
          hasAttachments: captured.note.note.attachments.isNotEmpty,
        ),
      );
      if (!mounted || options == null) return;
      final result = await _viewModel.exportNotePack(
        format: options.format,
        password: options.password,
        fileName: file.path,
        captured: captured,
      );
      if (!mounted || result.outcome == OperationOutcome.cancelled) return;
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
    final options = await showDialog<ExportOptions>(
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

    final result = await showDialog<bool>(
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
    if (!_viewModel.ensureExtendedNoteOperations()) return;
    // Close the drawer first on mobile
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    }

    final file = await _viewModel.pickImportPackFile();
    if (file == null) return;

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
    final shouldImport = await showDialog<bool>(
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
      final result = await showDialog<OperationResult<NoteImportResult>>(
        context: context,
        barrierDismissible: false,
        builder: (_) => NoteImportDialog(
          fileName: file.name,
          jobs: _viewModel.attachmentJobsNotifier,
          cancelJob: _viewModel.cancelAttachmentJob,
          startImport: (resolveConflict) => _viewModel.importNoteFile(
            file.path!,
            archivePassword: password,
            plainText:
                !verification.isPack && file.extension?.toLowerCase() == 'txt',
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
  }

  Future<String?> _showPackPasswordDialog({bool isRequired = false}) async {
    final passwordController = TextEditingController();

    final result = await showDialog<String>(
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
    showDialog<void>(
      context: context,
      builder: (_) => AppSettingsDialog(
        settings: _viewModel.settings,
        pickLibrary: () => FilePicker.platform.getDirectoryPath(),
        openLibrary: _viewModel.switchLibrary,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // These ancestors remain present before and during closing. Replacing the
    // editor would dispose listeners still in Flutter's exit-request snapshot.
    return AbsorbPointer(
      absorbing: _shutdownStarted,
      child: ExcludeFocus(
        excluding: _shutdownStarted,
        child: _buildDashboard(context),
      ),
    );
  }

  Widget _buildDashboard(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: _viewModel,
      builder: (context, _) {
        return CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.keyF, control: true):
                _focusSearch,
            SingleActivator(LogicalKeyboardKey.keyS, control: true): () {
              if (!_shutdownStarted) {
                _viewModel.saveNote();
              }
            },
            SingleActivator(LogicalKeyboardKey.keyN, control: true): () {
              if (!_shutdownStarted) {
                unawaited(_handleNewNote());
              }
            },
          },
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isDesktop = constraints.maxWidth > 800;
              return Scaffold(
                key: _scaffoldKey,
                resizeToAvoidBottomInset: true,
                appBar: isDesktop
                    ? null
                    : AppBar(
                        backgroundColor: theme.appSidebar,
                        title: Text(
                          'Dashboard',
                          style: TextStyle(color: theme.appTextPrimary),
                        ),
                        iconTheme: IconThemeData(color: theme.appTextPrimary),
                        titleTextStyle: TextStyle(
                          color: theme.appTextPrimary,
                          fontSize: 15.552,
                        ),
                        actions: [
                          IconButton(
                            icon: const Icon(Icons.settings),
                            onPressed: () => _showMasterSettings(context),
                          ),
                        ],
                      ),
                drawer: isDesktop
                    ? null
                    : Drawer(child: _buildSidebar(drawer: true)),
                body: Stack(
                  children: [
                    Column(
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              if (isDesktop && _isSidebarVisible)
                                _buildSidebar(drawer: false),
                              Expanded(
                                child: ContentArea(viewModel: _viewModel),
                              ),
                            ],
                          ),
                        ),
                        if (isDesktop) _buildSidebarToggle(theme),
                      ],
                    ),
                    if (_viewModel.isBusy)
                      Container(
                        color: Colors.black54,
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircularProgressIndicator(
                                color: theme.colorScheme.primary,
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                "Processing...",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 13.824,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}
