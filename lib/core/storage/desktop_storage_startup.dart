import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../features/dashboard/services/file_service.dart';
import '../../features/dashboard/services/macos_file_service.dart';
import '../../features/dashboard/services/settings_service.dart';
import '../operations/operation_result.dart';
import '../platform/macos_file_access.dart';
import '../theme/app_theme.dart';
import 'desktop_storage_bootstrap.dart';
import 'owned_app_services.dart';
import 'storage_environment.dart';

typedef DesktopReadyBuilder =
    Widget Function(
      SettingsService settings,
      FileService files,
      Future<OperationResult<void>> Function() close,
    );

/// Native desktop startup owns permission leases through storage shutdown.
/// Failure retains resources for cleanup/retry and never selects a legacy writer.
class DesktopStorageStartup extends StatefulWidget {
  const DesktopStorageStartup({
    super.key,
    required this.environment,
    required this.buildReady,
    this.resolvePlan,
    this.fileAccess = const MacosFileAccess(),
  });
  final StorageEnvironment environment;
  final DesktopReadyBuilder buildReady;
  final Future<DesktopStoragePlan> Function(MacosLibraryGrant?)? resolvePlan;
  final MacosFileAccess fileAccess;
  @override
  State<DesktopStorageStartup> createState() => _DesktopStorageStartupState();
}

class _DesktopStorageStartupState extends State<DesktopStorageStartup> {
  OwnedAppServices? _services;
  MacosLibraryGrant? _grant;
  DesktopLibraryAccessRequired? _accessRequired;
  bool _busy = true;
  bool _failed = false;
  bool _ready = false;
  String? _accessError;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onExitRequested: () async {
        if (_ready)
          return AppExitResponse.exit; // Dashboard owns draft decisions.
        return (await _close()).isSuccess
            ? AppExitResponse.exit
            : AppExitResponse.cancel;
      },
    );
    _start();
  }

  Future<OperationResult<void>> _close() async {
    final closed = await _services?.close();
    if (closed != null && !closed.isSuccess) return closed;
    try {
      await _grant?.close();
      return const OperationResult.success();
    } catch (_) {
      return const OperationResult.failure(
        OperationOutcome.recoveryRequired,
        'Folder access cleanup needs retry.',
      );
    }
  }

  Future<void> _start({MacosLibraryGrant? selected}) async {
    if (mounted)
      setState(() {
        _busy = true;
        _failed = false;
      });
    try {
      if (!(await _close()).isSuccess)
        throw StateError('Storage cleanup needs retry.');
      _services = null;
      _grant = null;
      final plan = widget.resolvePlan != null
          ? await widget.resolvePlan!(selected)
          : await DesktopStorageBootstrap.resolve(
              captured: widget.environment,
              selectedGrant: selected,
              access: widget.fileAccess,
            );
      _grant = plan.libraryGrant;
      if (selected != null && !identical(selected, _grant))
        await selected.close();
      final runtime = OwnedAppServices(
        environment: plan.environment,
        selectedLibraryOverride: plan.changeSelection
            ? plan.environment.dataRoot
            : null,
        afterLibraryAdmission: () async {
          await _grant?.accept();
        },
        createFiles: Platform.isMacOS
            ? (settings, owner) => MacosFileService(
                settings: settings,
                storageOwner: owner,
                initialLibrary: _grant,
              )
            : null,
      );
      _services = runtime;
      final result = await runtime.initialize();
      if (!result.isSuccess) throw StateError('Storage could not be admitted.');
      if (mounted)
        setState(() {
          _ready = true;
          _accessRequired = null;
          _accessError = null;
        });
      else {
        await _close();
      }
    } on DesktopLibraryAccessRequired catch (error) {
      await selected?.close();
      if (mounted)
        setState(() {
          _accessRequired = error;
          _accessError = _accessMessage(error.code);
          _failed = true;
        });
    } catch (_) {
      if (!identical(selected, _grant)) await selected?.close();
      if (mounted)
        setState(() {
          _accessRequired = null;
          _failed = true;
        });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _choose() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final selected = await widget.fileAccess.chooseLibrary();
      if (selected != null) {
        await _start(selected: selected);
      }
    } catch (error) {
      if (mounted)
        setState(() {
          _failed = true;
          _accessError = _accessMessage(
            error is PlatformException ? error.code : 'access_unavailable',
          );
        });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static String? _accessMessage(String code) => switch (code) {
    'permission_required' => null,
    'access_denied' =>
      'Folder access was denied. Choose your notes folder to allow access.',
    'unsupported_location' =>
      'Choose a local notes folder that allows reading and writing.',
    'entitlement_missing' || 'entitlement_unavailable' =>
      'This build is missing its signed macOS file permissions.',
    'library_changed' =>
      'The previous folder moved or changed. Choose the notes folder again.',
    _ => 'Folder access is unavailable. Choose the notes folder again.',
  };

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final runtime = _services;
    if (_ready && runtime != null) {
      return widget.buildReady(runtime.settings, runtime.files, _close);
    }
    final needsAccess = _accessRequired != null;
    return MaterialApp(
      title: 'Future Notes',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      home: Scaffold(
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    needsAccess
                        ? Icons.folder_open_outlined
                        : Icons.storage_outlined,
                    size: 36,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    needsAccess
                        ? 'Allow access to your notes folder'
                        : 'Preparing your notes',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 22),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    needsAccess
                        ? 'Choose your notes folder to restore access. Files stay in the folder you select.'
                        : _failed
                        ? 'Storage could not be prepared. No library was opened for editing.'
                        : 'Opening the selected library…',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  if (needsAccess && _accessError != null) ...[
                    Text(
                      _accessError!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (_busy)
                    const CircularProgressIndicator()
                  else
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      alignment: WrapAlignment.center,
                      children: [
                        if (needsAccess)
                          FilledButton(
                            onPressed: _choose,
                            child: const Text('Choose notes folder'),
                          ),
                        TextButton(
                          onPressed: _start,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
