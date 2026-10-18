import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../../core/operations/operation_result.dart';
import '../services/settings_service.dart';
import '../../../core/storage/attachment_performance.dart';
import '../../../core/storage/attachment_scheduler.dart';

class AppSettingsDialog extends StatefulWidget {
  const AppSettingsDialog({
    super.key,
    required this.settings,
    required this.pickLibrary,
    required this.openLibrary,
    this.loadVersion,
  });
  final SettingsService settings;
  final Future<String?> Function() pickLibrary;
  final Future<OperationResult<void>> Function(String) openLibrary;
  final Future<String> Function()? loadVersion;
  @override
  State<AppSettingsDialog> createState() => _AppSettingsDialogState();
}

class _AppSettingsDialogState extends State<AppSettingsDialog> {
  late Future<String> _libraryPath;
  late final Future<String> _version;
  final _pending = <String>{};
  String? _error;
  double? _targetPreview;
  @override
  void initState() {
    super.initState();
    _libraryPath = widget.settings.getUserDataPath();
    _version = widget.loadVersion?.call() ?? _loadVersion();
  }

  Future<String> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    return 'Future Notes ${info.version}${info.buildNumber.isEmpty ? '' : '+${info.buildNumber}'}';
  }

  Future<void> _write(String key, Future<void> Function() action) async {
    if (!_pending.add(key)) return;
    setState(() => _error = null);
    try {
      await action();
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Settings could not be saved. The previous value was retained.',
        );
      }
    } finally {
      _pending.remove(key);
      if (mounted) setState(() {});
    }
  }

  Future<void> _openLibrary() => _write('library', () async {
    final directory = await widget.pickLibrary();
    if (!mounted || directory == null) return;
    final result = await widget.openLibrary(directory);
    if (!mounted) return;
    // The acknowledged settings location is authoritative even when a switch
    // reports a retained late edit or deferred old-library cleanup.
    _libraryPath = widget.settings.getUserDataPath();
    if (!result.isSuccess) {
      _error = result.message ?? 'The library could not be opened.';
    }
  });

  @override
  Widget build(BuildContext context) {
    final settings = widget.settings;
    return AlertDialog(
      title: const Text('App settings'),
      scrollable: true,
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const ListTile(
              title: Text('Closing the app'),
              subtitle: Text(
                'Close asks for confirmation, then exits Future Notes.',
              ),
            ),
            ListTile(
              title: const Text('Theme'),
              subtitle: DropdownButton<ThemeMode>(
                value: settings.themeMode,
                isExpanded: true,
                items: ThemeMode.values
                    .map(
                      (mode) =>
                          DropdownMenuItem(value: mode, child: Text(mode.name)),
                    )
                    .toList(),
                onChanged: _pending.contains('theme')
                    ? null
                    : (value) {
                        if (value != null) {
                          _write('theme', () => settings.setThemeMode(value));
                        }
                      },
              ),
            ),
            ListTile(
              title: const Text('File compression'),
              subtitle: DropdownButton<CompressionLevel>(
                value: settings.compressionLevel,
                isExpanded: true,
                items: CompressionLevel.values
                    .map(
                      (level) => DropdownMenuItem(
                        value: level,
                        child: Text(level.name),
                      ),
                    )
                    .toList(),
                onChanged: _pending.contains('compression')
                    ? null
                    : (value) {
                        if (value != null) {
                          _write(
                            'compression',
                            () => settings.setCompressionLevel(value),
                          );
                        }
                      },
              ),
            ),
            if (!kIsWeb && !Platform.isAndroid && !Platform.isIOS) ...[
              const Divider(),
              _attachmentPerformance(),
              const Divider(),
              const Text(
                'Current library',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              FutureBuilder<String>(
                future: _libraryPath,
                builder: (context, snapshot) => SelectableText(
                  snapshot.hasError
                      ? 'Library location unavailable'
                      : snapshot.data ?? 'Loading…',
                ),
              ),
              TextButton.icon(
                onPressed: _pending.contains('library') ? null : _openLibrary,
                icon: const Icon(Icons.folder_open),
                label: Text(
                  _pending.contains('library')
                      ? 'Opening library…'
                      : 'Open another library',
                ),
              ),
            ],
            if (_error != null)
              Semantics(
                liveRegion: true,
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const Divider(),
            const Text('About', style: TextStyle(fontWeight: FontWeight.w600)),
            FutureBuilder<String>(
              future: _version,
              builder: (context, snapshot) => Text(
                snapshot.hasError
                    ? 'Future Notes · version unavailable'
                    : snapshot.data ?? 'Future Notes',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _attachmentPerformance() {
    final current = widget.settings.attachmentPerformance;
    final pending = _pending.contains('performance');
    Future<void> save(AttachmentPerformance value) => _write(
      'performance',
      () => widget.settings.setAttachmentPerformance(value),
    );
    Widget limit(
      String label,
      int value,
      List<int> options,
      String Function(int) text,
      AttachmentPerformance Function(int) candidate,
    ) => DropdownButtonFormField<int>(
      key: ValueKey('$label:$value:$pending'),
      decoration: InputDecoration(labelText: label),
      initialValue: value,
      items: ({0, ...options, value}.toList()..sort())
          .map(
            (v) => DropdownMenuItem(
              value: v,
              child: Text(v == 0 ? 'Automatic' : text(v)),
            ),
          )
          .toList(),
      onChanged: pending
          ? null
          : (v) {
              if (v != null) save(candidate(v));
            },
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Attachment performance',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        const Text(
          'Automatically adapts to this computer and other running apps. Additional files queue while processing continues.',
        ),
        const SizedBox(height: 8),
        Text(
          'Available-capacity target: ${(_targetPreview ?? current.targetPercent.toDouble()).round()}%',
        ),
        Slider(
          key: const ValueKey('attachment-capacity-target'),
          min: 10,
          max: 90,
          divisions: 16,
          value: _targetPreview ?? current.targetPercent.toDouble(),
          label:
              '${(_targetPreview ?? current.targetPercent.toDouble()).round()}%',
          onChanged: pending ? null : (v) => setState(() => _targetPreview = v),
          onChangeEnd: pending
              ? null
              : (v) async {
                  await save(current.copyWith(targetPercent: v.round()));
                  if (mounted) setState(() => _targetPreview = null);
                },
        ),
        const Text(
          'Default 70%. A scheduling target, not an OS hard cap; memory is a ceiling, not an allocation goal.',
        ),
        ValueListenableBuilder<AttachmentBudget?>(
          valueListenable: AttachmentScheduler.shared.status,
          builder: (context, budget, _) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              budget == null
                  ? 'CPU and available memory are detected when work starts.'
                  : '${budget.capacity.processors} logical processors · ${(budget.capacity.availableBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GiB available\n${budget.active} active · ${budget.queued} queued${budget.capacity.detected ? '' : ' · conservative monitoring fallback'}',
            ),
          ),
        ),
        ExpansionTile(
          title: const Text('Advanced configuration'),
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: 8),
          children: [
            limit(
              'Maximum parallel files',
              current.maxParallel,
              [1, 2, 4, 8, 16, 32, 64, 128, 256],
              (v) => '$v files',
              (v) => current.copyWith(maxParallel: v),
            ),
            const SizedBox(height: 12),
            limit(
              'Preparation working-memory budget',
              current.memoryMiB,
              [64, 128, 256, 512, 1024, 2048, 4096, 8192],
              (v) => '$v MiB',
              (v) => current.copyWith(memoryMiB: v),
            ),
            const SizedBox(height: 6),
            SwitchListTile(
              key: const ValueKey('check-before-open'),
              title: const Text(
                'Check encrypted files before opening/exporting',
              ),
              subtitle: const Text(
                'Optional full source hash scan. Off by default.',
              ),
              value: current.checkBeforeOpen,
              onChanged: pending
                  ? null
                  : (v) => save(current.copyWith(checkBeforeOpen: v)),
            ),
            SwitchListTile(
              key: const ValueKey('verify-after-open'),
              title: const Text('Verify decrypted output'),
              subtitle: const Text(
                'Optional plaintext readback for previews and Share / Save attachments. Off by default.',
              ),
              value: current.verifyAfterOpen,
              onChanged: pending
                  ? null
                  : (v) => save(current.copyWith(verifyAfterOpen: v)),
            ),
            SwitchListTile(
              key: const ValueKey('validate-exported-backup'),
              title: const Text('Validate exported backups'),
              subtitle: const Text(
                'Optional full-package read-back before sharing. Off by default.',
              ),
              value: current.validateExportedBackup,
              onChanged: pending
                  ? null
                  : (v) => save(current.copyWith(validateExportedBackup: v)),
            ),
            SwitchListTile(
              key: const ValueKey('verify-large-file-writes'),
              title: const Text('Extra verification after large writes'),
              subtitle: const Text(
                'Optional encryption and publication read-back. Off by default.',
              ),
              value: current.verifyLargeFileWrites,
              onChanged: pending
                  ? null
                  : (v) => save(current.copyWith(verifyLargeFileWrites: v)),
            ),
            const Text(
              'Attachment metadata is validated when loading/unlocking the note. Required file-safety, length and padding checks always apply.',
            ),
            const Text(
              'Each worker reserves an estimated 64 MiB scheduling allowance and streams 1 MiB windows. Lower limits apply as memory becomes busy.',
            ),
            TextButton(
              onPressed: pending
                  ? null
                  : () => save(AttachmentPerformance.defaults),
              child: const Text('Reset performance defaults'),
            ),
          ],
        ),
        const Text(
          'Optional checks do not change encryption formats. Basic safety and recovery journals remain active.',
        ),
      ],
    );
  }
}
