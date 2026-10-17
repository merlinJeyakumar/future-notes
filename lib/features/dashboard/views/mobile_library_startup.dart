import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../../core/operations/operation_result.dart';
import '../../../core/platform/library_documents.dart';
import '../../../core/platform/mobile_library_documents.dart';
import '../../../core/platform/mobile_file_actions.dart';
import '../../../core/storage/library_admission_probe.dart';
import '../services/provider_note_files.dart';
import '../services/provider_discovery.dart';
import '../services/settings_service.dart';
import '../viewmodels/content_viewmodel.dart';
import '../models/draft_transition.dart';
import '../mobile/dashboard_screen.dart';

/// A selected folder is required. Failure never substitutes private note storage.
class MobileLibraryStartup extends StatefulWidget {
  const MobileLibraryStartup({super.key, required this.settings});
  final SettingsService settings;
  @override
  State<MobileLibraryStartup> createState() => _MobileLibraryStartupState();
}

class _MobileLibraryStartupState extends State<MobileLibraryStartup> {
  final _actions = MobileFileActions();
  late final _documents = MobileLibraryDocuments(
    kind: Platform.isAndroid
        ? LibraryLocationKind.androidTree
        : LibraryLocationKind.appleBookmark,
  );
  ProviderNoteFiles? _files;
  ProviderDiscovery? _discovery;
  final _knownLibraries = <String, String>{};
  String _locationKey(LibraryLocation location) =>
      '${location.kind.name}:${location.token}';
  String _libraryId(LibraryLocation location) => _knownLibraries.putIfAbsent(
    _locationKey(location),
    () => const Uuid().v4(),
  );
  Map<String, Object?> _selection(String id, LibraryLocation location) => {
    'version': 1,
    'id': id,
    'location': location.toJson(),
    'libraries': _knownLibraries,
  };
  String? _privateRoot;
  String? _error;
  bool _busy = true;
  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    try {
      _privateRoot = await _actions.privateRoot();
      final selected = await MobileFileActions.channel.invokeMethod<String>(
        'readLibrarySelection',
      );
      if (selected != null) {
        final json = jsonDecode(selected) as Map<String, dynamic>;
        final location = LibraryLocation.fromJson(
          Map<String, Object?>.from(json['location'] as Map),
        );
        if (json['libraries'] is Map) {
          for (final entry in (json['libraries'] as Map).entries) {
            if (entry.key is String &&
                entry.value is String &&
                RegExp(r'^[a-f0-9-]{36}$').hasMatch(entry.value as String))
              _knownLibraries[entry.key as String] = entry.value as String;
          }
        }
        _knownLibraries[_locationKey(location)] = json['id'] as String;
        await _open(location, json['id'] as String, persist: false);
      }
    } catch (error) {
      _error = error is LibraryAccessException
          ? error.message
          : 'The selected library could not be opened. Its files were retained.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _select() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final selected = await _documents.selectLocalFolder();
      if (selected == null) return;
      _privateRoot ??= await _actions.privateRoot();
      await LibraryAdmissionProbe(_documents).verify(selected);
      await _open(selected, _libraryId(selected), persist: true);
    } catch (error) {
      _error = error is LibraryAccessException
          ? error.message
          : 'This folder could not be prepared. The previous selection was retained.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open(
    LibraryLocation location,
    String id, {
    required bool persist,
  }) async {
    final candidate = ProviderNoteFiles(
      documents: _documents,
      location: location,
      libraryId: id,
      privateRoot: _privateRoot!,
    );
    try {
      await candidate.initialize();
      if (persist)
        await MobileFileActions.channel.invokeMethod<void>(
          'writeLibrarySelection',
          {'json': jsonEncode(_selection(id, location))},
        );
    } catch (_) {
      await candidate.close();
      rethrow;
    }
    if (!mounted) {
      await candidate.close();
      return;
    }
    _files = candidate;
    _discovery = ProviderDiscovery(candidate);
  }

  Future<OperationResult<void>> _switch(
    ContentViewModel model,
    Future<void> Function() clearResolvedDraft,
  ) async {
    ProviderNoteFiles? candidate;
    try {
      final location = await _documents.selectLocalFolder();
      if (location == null)
        return const OperationResult.failure(
          OperationOutcome.cancelled,
          'Library switch cancelled.',
        );
      if (location.token == _files?.location.token)
        return const OperationResult.success();
      await LibraryAdmissionProbe(_documents).verify(location);
      candidate = ProviderNoteFiles(
        documents: _documents,
        location: location,
        libraryId: _libraryId(location),
        privateRoot: _privateRoot!,
      );
      await candidate.initialize();
      final permit = await model.prepareTransition(DraftTransition.library);
      if (!permit.isSuccess ||
          !model.isTransitionPermitCurrent(permit.value!)) {
        await candidate.close();
        return const OperationResult.failure(
          OperationOutcome.cancelled,
          'Library switch cancelled.',
        );
      }
      await MobileFileActions.channel.invokeMethod<void>(
        'writeLibrarySelection',
        {'json': jsonEncode(_selection(candidate.libraryId, location))},
      );
      final old = _files!;
      // Input is blocked by the dashboard during this handoff. A candidate is
      // adopted only after the native selection record is acknowledged.
      if (!mounted) {
        await candidate.close();
        return const OperationResult.failure(
          OperationOutcome.cancelled,
          'Library switch cancelled.',
        );
      }
      // If a composition or other acknowledged edit arrived during the native
      // record write, restore the selected location before consuming the permit.
      if (!model.isTransitionPermitCurrent(permit.value!)) {
        await MobileFileActions.channel.invokeMethod<void>(
          'writeLibrarySelection',
          {'json': jsonEncode(_selection(old.libraryId, old.location))},
        );
        await candidate.close();
        return const OperationResult.failure(
          OperationOutcome.conflict,
          'The draft changed during folder selection. The current library was retained.',
        );
      }
      try {
        await clearResolvedDraft();
      } catch (_) {
        await MobileFileActions.channel.invokeMethod<void>(
          'writeLibrarySelection',
          {'json': jsonEncode(_selection(old.libraryId, old.location))},
        );
        rethrow;
      }
      if (!mounted) {
        await candidate.close();
        return const OperationResult.failure(
          OperationOutcome.cancelled,
          'Library switch cancelled.',
        );
      }
      Navigator.of(context).pop(); // Close the old library's Settings route.
      setState(() {
        _files = candidate;
        _discovery = ProviderDiscovery(candidate!);
      });
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await old.close();
      });
      return const OperationResult.success();
    } catch (error) {
      await candidate?.close();
      return OperationResult.failure(
        OperationOutcome.ioFailure,
        error is LibraryAccessException
            ? error.message
            : 'The folder could not be opened. The current library was retained.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final files = _files;
    if (files != null) {
      return MobileDashboardScreen(
        key: ValueKey(files.libraryId),
        settings: widget.settings,
        fileService: files,
        attachmentActions: _actions,
        discovery: _discovery,
        recoveryLibraryId: files.libraryId,
        jobLibraryIdentity: files.binding.root,
        loadLibraryDescription: () async =>
            (await _documents.root(files.location)).name,
        changeMobileLibrary: _switch,
        onClose: () async {
          await files.close();
          return const OperationResult.success();
        },
      );
    }
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Future Notes Preview',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Choose a local-device or SD-card folder for this library.',
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text(_error!, textAlign: TextAlign.center),
                    ),
                  const SizedBox(height: 24),
                  if (_busy)
                    const CircularProgressIndicator()
                  else
                    FilledButton.icon(
                      onPressed: _select,
                      icon: const Icon(Icons.folder_open),
                      label: const Text('Choose library folder'),
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
